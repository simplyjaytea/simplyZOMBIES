extends Control
# The inventory layer. The survivor body panel (equipment slots + injuries) is drawn here;
# every carried container is its own ContainerWindow child -- draggable by its title bar,
# pinnable so its contents stay on screen during play. Rules unchanged from the first
# version of this screen: reads InventoryView snapshots, proposes Commands, the sim decides
# fit and depth, and no numbers except stack counts (docs/10 -- counting discrete objects
# is not uncertainty being collapsed).
#
# All item drag state lives here, in one place. Windows forward presses and releases as
# layer-local points because Godot's mouse focus pins events to the control that took the
# press: a drag that starts in one bag must be droppable in another, on an equipment slot,
# or nowhere, and only the layer can see all of those at once.

const SimInventory = preload("res://sim/modules/inventory.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const UiText = preload("res://ui/text.gd")
const Palette = preload("res://presentation/palette.gd")
const Paperdoll = preload("res://ui/paperdoll.gd")
const Chrome = preload("res://ui/chrome.gd")
const UiPrefs = preload("res://ui/prefs.gd")
const ContainerWindow = preload("res://ui/container_window.gd")

# PartState 0..3 as words. Same four grades the paperdoll tints, never a number.
const PART_STATE_WORDS: Array[String] = ["unhurt", "hurt", "badly hurt", "unusable"]

const CELL: int = 68
const PAD: int = 28
const BODY_W: float = 1096.0
const BODY_H: float = 780.0

# Equipment slot geometry, in one place -- the boxes you can click and the boxes you can
# see must be the same set of rects.
const SLOT_W: float = float(CELL) * 3.0
const SLOT_H: float = float(CELL)
# Twelve slots, six a side, in body order top to bottom: what covers your head down the
# left, what covers your trunk and legs down the right, weapons at the bottom of each.
const SLOT_PLACEMENTS: Array[Dictionary] = [
	{"slot": "head", "x": 48.0, "y": 86.0},
	{"slot": "eyes", "x": 48.0, "y": 206.0},
	{"slot": "face", "x": 48.0, "y": 326.0},
	{"slot": "gloves", "x": 48.0, "y": 446.0},
	{"slot": "belt", "x": 48.0, "y": 566.0},
	{"slot": "primary", "x": 48.0, "y": 686.0},
	{"slot": "vest", "x": 880.0, "y": 86.0},
	{"slot": "torso", "x": 880.0, "y": 206.0},
	{"slot": "legs", "x": 880.0, "y": 326.0},
	{"slot": "feet", "x": 880.0, "y": 446.0},
	{"slot": "back", "x": 880.0, "y": 566.0},
	{"slot": "secondary", "x": 880.0, "y": 686.0},
]


static func slot_rect(body_x: float, body_y: float, placement: Dictionary) -> Rect2:
	return Rect2(Vector2(body_x + float(placement["x"]), body_y + float(placement["y"])), Vector2(SLOT_W, SLOT_H))


var _world: Variant = null
var _actor: int = -1
var _view: Dictionary = {}
var _open: bool = false

var _drag_item: int = -1
var _drag_rotated: bool = false
var _drag_from_container: int = -1
var _drag_dims: Vector2i = Vector2i.ONE

# Clickable words under the condition readout, built by _draw and read by _press_at:
# {rect, verb}. Derived every draw and never stored, which is work_panel.gd's rule and the
# reason the word you can see and the word you can click cannot drift apart.
var _hit: Array[Dictionary] = []

var _paperdoll: Control = null
var _ghost: Control = null
var _windows: Dictionary = {} # container id -> ContainerWindow
var _default_cursor: Vector2 = Vector2.ZERO
var _default_col_w: float = 0.0


class Ghost:
	extends Control
	# Inner classes do not see the outer script's constants, so the chrome is preloaded
	# again here rather than reached for implicitly.
	const GhostChrome = preload("res://ui/chrome.gd")
	const GHOST_CELL: int = 68

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
	_paperdoll.custom_minimum_size = Vector2(520, 520)
	_paperdoll.visible = false
	add_child(_paperdoll)
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
	for win in _windows.values():
		(win as Control).set("layer_open", open)
		(win as Control).visible = open or bool((win as Control).get("pinned"))
		(win as Control).queue_redraw()
	if _paperdoll != null:
		_paperdoll.visible = open
	_sync_size()
	queue_redraw()


func has_pinned() -> bool:
	for win in _windows.values():
		if bool((win as Control).get("pinned")):
			return true
	return false


# Settings changed; everything that reads an opacity redraws.
func refresh_style() -> void:
	queue_redraw()
	for win in _windows.values():
		(win as Control).queue_redraw()


func set_world(world: Variant, actor: int) -> void:
	_world = world
	_actor = actor
	_view = SimInventory.inventory_view(world, actor) if world != null else {}
	_sync_size()
	if world != null and _paperdoll != null:
		var cv: Dictionary = SimCondition.view(world, actor)
		if not cv.is_empty():
			_paperdoll.call("set_view", cv)
	_sync_windows()
	queue_redraw()


func rotate() -> void:
	if _drag_item != -1:
		_drag_rotated = not _drag_rotated
		if _ghost != null:
			_ghost.queue_redraw()


# ---- windows ----

func _sync_windows() -> void:
	var seen: Dictionary = {}
	_default_cursor = Vector2(float(PAD) + BODY_W + 24.0, float(PAD))
	_default_col_w = 0.0
	# Quick-access containers: the pockets, and anything worn on the belt or vest. The back
	# slot is deliberately absent -- a backpack needs the inventory open.
	var quick_ids: Dictionary = {_actor: true}
	for entry in _view.get("slots", []) as Array:
		var sd: Dictionary = entry as Dictionary
		if String(sd.get("slot", "")) in ["belt", "vest"]:
			var sit: Variant = sd.get("item")
			if sit is Dictionary:
				quick_ids[int((sit as Dictionary).get("item", -1))] = true
	for cont in _view.get("containers", []) as Array:
		var c: Dictionary = cont as Dictionary
		var cid: int = int(c.get("container", -1))
		seen[cid] = true
		var label: String = String(c.get("label", ""))
		var win: Variant = _windows.get(cid)
		if win == null:
			var w := ContainerWindow.new()
			w.on_press = _press_at
			w.on_release = _release_at
			w.on_rightclick = _right_at
			w.on_pin_toggle = _on_window_pinned
			w.set("pinned", UiPrefs.window_pinned(label))
			add_child(w)
			_windows[cid] = w
			win = w
			w.configure(cid, label, int(c.get("w", 0)), int(c.get("h", 0)), c.get("items", []) as Array)
			var stored: Variant = UiPrefs.window_pos(label)
			w.position = (stored as Vector2) if stored is Vector2 else _alloc_default(w.size)
		else:
			(win as Control).call("configure", cid, label, int(c.get("w", 0)), int(c.get("h", 0)), c.get("items", []) as Array)
		(win as Control).set("layer_open", _open)
		(win as Control).set("drag_exclude", _drag_item)
		(win as Control).set("quick", quick_ids.has(cid))
		(win as Control).visible = _open or bool((win as Control).get("pinned"))
	for cid in _windows.keys().duplicate():
		if not seen.has(cid):
			(_windows[cid] as Control).queue_free()
			_windows.erase(cid)
	if _ghost != null:
		move_child(_ghost, get_child_count() - 1)


# First-seen windows flow into columns right of the body panel; a moved window's position
# is the player's and persists in prefs instead. Windows are not all created in one pass --
# pockets exist before a pack is ever equipped -- so a default position must also dodge the
# rects existing windows already hold, or the second pass stacks a new window exactly on
# top of an old one (which is how the pockets spent a session hidden under a hiking pack).
func _alloc_default(win_size: Vector2) -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	var at: Vector2 = _default_cursor
	var col_x: float = _default_cursor.x
	var col_w: float = _default_col_w
	for _attempt in range(64):
		if at.y + win_size.y > view.y - float(PAD) and at.y > float(PAD):
			col_x += col_w + 24.0
			at = Vector2(col_x, float(PAD))
			col_w = 0.0
		var candidate := Rect2(Vector2(minf(at.x, maxf(0.0, view.x - win_size.x - 8.0)), at.y), win_size)
		var clash: Rect2 = Rect2()
		var found: bool = false
		for win in _windows.values():
			var w: Control = win as Control
			if Rect2(w.position, w.size).grow(8.0).intersects(candidate):
				clash = Rect2(w.position, w.size)
				found = true
				break
		if not found:
			_default_cursor = Vector2(col_x, at.y + win_size.y + 24.0)
			_default_col_w = maxf(col_w, win_size.x)
			return candidate.position
		at.y = clash.position.y + clash.size.y + 24.0
		col_w = maxf(col_w, win_size.x)
	# No clash-free spot exists (a wide loadout genuinely fills the screen). Bottom-right
	# is the least-bad overlap -- never over the body panel's slots -- and every window is
	# draggable from wherever it lands.
	var view2: Vector2 = get_viewport_rect().size
	return Vector2(maxf(0.0, view2.x - win_size.x - 16.0), maxf(float(PAD), view2.y - win_size.y - 16.0))


func _on_window_pinned(_win: Control) -> void:
	queue_redraw()


# ---- shared hit handling (layer body + forwarded from windows) ----

func _gui_input(event: InputEvent) -> void:
	if not _open or _world == null or _view.is_empty():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
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
	# Words first, and for work_panel.gd's reason: they sit inside the body panel the slot and
	# grid maths also cover, so whichever target is more specific has to win. `_hit` is empty
	# whenever the screen is closed, so this needs no `_open` guard of its own.
	for h in _hit:
		if (h["rect"] as Rect2).has_point(p):
			# Through the queue like every other player act, and with no patient named: the
			# intake defaults it to the player (treatment.gd's `infection.respond` arm), which
			# is the same "one key, one obvious target" rule the T key already follows.
			_world.commands.push({"type": "infection.respond", "verb": String(h.get("verb", ""))})
			return
	var body_x: float = float(PAD)
	var body_y: float = float(PAD)
	# equipment slot pick: lift the item out of the slot (only on the open screen -- the
	# slots are not drawn during play)
	if _open:
		var slots: Array = _view.get("slots", []) as Array
		for pl in SLOT_PLACEMENTS:
			if slot_rect(body_x, body_y, pl).has_point(p):
				for entry in slots:
					var d: Dictionary = entry as Dictionary
					if String(d.get("slot", "")) == String(pl["slot"]):
						var it: Variant = d.get("item")
						if it is Dictionary:
							# The item, not just the slot: a slot name on its own does not say
							# whose coat this is, and inventory.intake used to act on everybody's.
							_begin_drag(int((it as Dictionary).get("item", -1)), -2, false, Vector2i(1, 1))
							_world.commands.push({"type": "item.unequip", "slot": String(pl["slot"]), "item": int((it as Dictionary).get("item", -1))})
						return
				return
	# grid pick inside any interactive window (open screen, or a pinned quick-access pouch)
	for win in _windows.values():
		var w: Control = win as Control
		if not w.visible or not bool(w.call("interactive")):
			continue
		var cell: Variant = w.call("cell_from_layer", p)
		if cell == null:
			continue
		var cx: int = (cell as Vector2i).x
		var cy: int = (cell as Vector2i).y
		for it in w.get("items") as Array:
			var d: Dictionary = it as Dictionary
			var rx: int = int(d.get("x", 0))
			var ry: int = int(d.get("y", 0))
			var rw: int = int(d.get("w", 1))
			var rh: int = int(d.get("h", 1))
			if cx >= rx and cx < rx + rw and cy >= ry and cy < ry + rh:
				var dims := Vector2i(rw, rh)
				var rotated: bool = bool(d.get("rotated", false))
				if rotated:
					dims = Vector2i(rh, rw)
				_begin_drag(int(d.get("item", -1)), int(w.get("container_id")), rotated, dims)
				return
		return


func _release_at(p: Vector2) -> void:
	if _drag_item == -1 or _world == null:
		return
	var item: int = _drag_item
	var rotated: bool = _drag_rotated
	_cancel_drag()
	var body_x: float = float(PAD)
	var body_y: float = float(PAD)
	if _open:
		for pl in SLOT_PLACEMENTS:
			if slot_rect(body_x, body_y, pl).has_point(p):
				_world.commands.push({"type": "item.equip", "item": item, "slot": String(pl["slot"])})
				queue_redraw()
				return
	for win in _windows.values():
		var w: Control = win as Control
		if not w.visible or not bool(w.call("interactive")):
			continue
		var cell: Variant = w.call("cell_from_layer", p)
		if cell == null:
			continue
		# propose move; sim decides (depth, fit, cycle)
		_world.commands.push({"type": "item.move", "item": item, "container": int(w.get("container_id")), "x": (cell as Vector2i).x, "y": (cell as Vector2i).y, "rotated": rotated})
		queue_redraw()
		return
	# dropped outside: no op (keeps in original container until a command lands)
	queue_redraw()


func _right_at(p: Vector2) -> void:
	if _drag_item != -1:
		rotate()
		return
	for win in _windows.values():
		var w: Control = win as Control
		if not w.visible or not bool(w.call("interactive")):
			continue
		var cell: Variant = w.call("cell_from_layer", p)
		if cell == null:
			continue
		var cx: int = (cell as Vector2i).x
		var cy: int = (cell as Vector2i).y
		for it in w.get("items") as Array:
			var d: Dictionary = it as Dictionary
			var rx: int = int(d.get("x", 0))
			var ry: int = int(d.get("y", 0))
			var rw: int = int(d.get("w", 1))
			var rh: int = int(d.get("h", 1))
			if cx >= rx and cx < rx + rw and cy >= ry and cy < ry + rh:
				_world.commands.push({"type": "item.use", "item": int(d.get("item", -1))})
				return
		return


func _begin_drag(item: int, from_container: int, rotated: bool, dims: Vector2i) -> void:
	_drag_item = item
	_drag_from_container = from_container
	_drag_rotated = rotated
	_drag_dims = dims
	for win in _windows.values():
		(win as Control).set("drag_exclude", _drag_item)
		(win as Control).queue_redraw()
	queue_redraw()


func _cancel_drag() -> void:
	_drag_item = -1
	_drag_from_container = -1
	_drag_rotated = false
	for win in _windows.values():
		(win as Control).set("drag_exclude", -1)
		(win as Control).queue_redraw()
	if _ghost != null:
		_ghost.queue_redraw()


# ---- drawing ----

func _draw() -> void:
	# Cleared before the early returns, not inside the body: a closed screen has no clickable
	# words, and rects left over from the last frame it was open would still be hit-testable.
	_hit.clear()
	if not _open:
		return
	var view: Vector2 = get_viewport_rect().size
	var dim: Color = Chrome.FIELD
	dim.a = 0.82
	draw_rect(Rect2(Vector2.ZERO, view), dim)
	var alpha: float = UiPrefs.opacity("inventory_opacity")
	var font: Font = Chrome.font()
	if _view.is_empty():
		draw_string(font, Vector2(float(PAD), float(PAD) + 32.0), "no inventory", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Chrome.TEXT_DIM)
		return
	var body_x: float = float(PAD)
	var body_y: float = float(PAD)
	var body := Rect2(Vector2(body_x, body_y), Vector2(BODY_W, BODY_H))
	Chrome.panel(self, body, alpha)
	Chrome.header(self, body, "survivor", alpha)
	# One screen (the owner's call, 2026-08-19): the doll carries injuries and armour, the
	# slots flank it, and anything wrong with the body reads as prose below the figure.
	_paperdoll.position = Vector2(body_x + BODY_W / 2.0 - 260.0, body_y + 84.0)
	_paperdoll.visible = true
	var by_slot: Dictionary = {}
	for entry in _view.get("slots", []) as Array:
		var d: Dictionary = entry as Dictionary
		by_slot[String(d.get("slot", ""))] = d.get("item")
	for pl in SLOT_PLACEMENTS:
		var box: Rect2 = slot_rect(body_x, body_y, pl)
		var it: Variant = by_slot.get(String(pl["slot"]))
		draw_rect(box, Chrome.SLOT_EMPTY)
		draw_rect(box, Chrome.PANEL_EDGE, false, 2.0)
		if it is Dictionary:
			Chrome.item_plate(self, Rect2(box.position + Vector2(4, 4), box.size - Vector2(8, 8)), alpha)
			var item_name: String = UiText.fit(font, String((it as Dictionary).get("name", "")), 20, SLOT_W - 24.0)
			draw_string(font, box.position + Vector2(12, 40), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT)
		else:
			draw_string(font, box.position + Vector2(12, 40), String(pl["slot"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT_DIM)
	# The condition readout: only the parts with something to say, as prose under the doll.
	# Same read model as the doll's tints and the HUD -- states and words, never a number
	# (docs/01 clause 4; check_ban_health_bar.gd).
	var lines: Array = _condition_lines()
	var ly: float = body_y + 620.0
	if lines.is_empty():
		draw_string(font, Vector2(body_x + BODY_W / 2.0 - 60.0, ly), "no injuries", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Chrome.TEXT_DIM)
	else:
		for line in lines:
			var d2: Dictionary = line as Dictionary
			var text: String = String(d2["text"])
			var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(font, Vector2(body_x + BODY_W / 2.0 - tw / 2.0, ly), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, d2["colour"] as Color)
			ly += 28.0
	_draw_responses(font, body_x, ly + 10.0)
	# how to work the screen, in one dim line under the body panel
	var hint: String = "drag a bag by its title · pin keeps it on screen — pinned belt and vest pouches stay usable in play · right-click rotates"
	draw_string(font, Vector2(body_x, body_y + BODY_H + 30.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Chrome.TEXT_DIM)


# What you could do about an infection, under the body it is in. One clickable word per offered
# response, in work_panel.gd's idiom exactly: the sim decides what is on offer
# (`SimTreatment.response_view`), a response you can afford is simply *there* in the accent colour,
# and one you cannot is absent rather than greyed with a reason beside it. Amber is chrome.gd's one
# colour for the thing that matters, and on this screen an answer to a fever is that thing.
#
# No numbers reach here and none could: the view carries a verb and a sentence, which is the same
# contract the condition readout above it has (docs/01 clause 4, check_ban_health_bar.gd).
func _draw_responses(font: Font, body_x: float, y: float) -> void:
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
	var at: float = body_x + BODY_W / 2.0 - total / 2.0
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
		# One tag for the wound, not three: an open wound is "bleeding", a dressed one is
		# named by its dressing, and a wound that is neither is just "wound".
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
