extends Control
# The inventory sheet. One fixed layout, since the owner's 2026-09-08 call (docs/30, "The
# inventory sheet"), re-dressed and re-laid since their 2026-10-19 call to keep the Tarkov-style
# grid and redo its look (docs/23, "The inventory, redone"): a title bar across the top; the body,
# its twelve slots and its condition on the left; the bag grids in the middle, in one lane -- or in
# two, what you carry beside the box you are standing at, so source and destination are on screen
# together; a fast list of everything in reach and the inspect pane down the right; and the belt
# and pockets as a quick strip along the bottom. The look is `ui/locker.gd`'s Salvage Locker.
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
const SimItems = preload("res://sim/modules/items.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimStockpile = preload("res://sim/modules/stockpile.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const UiText = preload("res://ui/text.gd")
const Palette = preload("res://presentation/palette.gd")
const Paperdoll = preload("res://ui/paperdoll.gd")
const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")
const Hud = preload("res://ui/hud.gd")
const UiPrefs = preload("res://ui/prefs.gd")
const BagGrid = preload("res://ui/bag_grid.gd")
const InspectPane = preload("res://ui/inspect_pane.gd")
const ItemMenu = preload("res://ui/item_menu.gd")
const QuickStrip = preload("res://ui/quick_strip.gd")
const Motion = preload("res://ui/motion.gd")
const ItemPicture = preload("res://ui/item_picture.gd")
const Appearance = preload("res://presentation/appearance.gd")
const NavBar = preload("res://ui/nav_bar.gd")
const CarePane = preload("res://ui/care_pane.gd")

# A tab on the navigation bar was clicked: the screen it names, or "" for the close control.
# main.gd's `_show_screen` answers, the same door Tab, J and K go through.
signal navigate(screen: String)

# PartState 0..3 as words. Same four grades the paperdoll tints, never a number.
const PART_STATE_WORDS: Array[String] = ["unhurt", "hurt", "badly hurt", "unusable"]

const PAD: float = 16.0
const GAP: float = 16.0
const STRIP_H: float = 84.0
# The title bar: the sheet's name, whose body it is, the keys, and the line a refused move speaks
# on. Shorter on a small window, where its title steps down a rung of the type ladder.
const TOP_H: float = 56.0
const TOP_H_COMPACT: float = 48.0
const TITLE_SIZE: int = 50
const TITLE_SIZE_COMPACT: int = 30
const HINT_SIZE: int = 20
const BODY_W: float = 464.0
const BODY_W_COMPACT: float = 344.0
const RIGHT_W: float = 440.0
const RIGHT_W_COMPACT: float = 360.0
# Below either of these the sheet takes its compact arrangement: the 2x chart, no words under the
# slots, fewer condition rows, and the right column giving way to a second bag lane while a box is
# open. Not a smaller copy of the big one -- every cell and picture stays the size it is.
const FULL_WIDTH: float = 1600.0
const FULL_HEIGHT: float = 900.0

# Equipment slot geometry, in one place -- the boxes you can click and the boxes you can see must
# be the same set of rects. A slot is one bag cell square, so a thing worn and the same thing in a
# pack are the same picture in the same well.
const SLOT_W: float = 60.0
const SLOT_H: float = 60.0
const SLOT_STEP: float = 84.0
const SLOT_STEP_COMPACT: float = 62.0
const SLOT_INSET: float = 16.0
const SLOT_WORD_SIZE: int = 20
# The chart is 64 x 160 art pixels and drawn at a whole-number scale: 3x on a full window, the
# world's own 2x on a compact one, plus a row under it for the stance word.
const DOLL_W: float = 192.0
const DOLL_H: float = 506.0
const DOLL_W_COMPACT: float = 128.0
const DOLL_H_COMPACT: float = 346.0
const CONDITION_ROWS: int = 5
const CONDITION_ROWS_COMPACT: int = 3
# Twelve slots, six a side, in body order top to bottom: what covers your head down the left,
# what covers your trunk and legs down the right, weapons at the bottom of each.
const LEFT_SLOTS: Array[String] = ["head", "eyes", "face", "gloves", "belt", "primary"]
const RIGHT_SLOTS: Array[String] = ["vest", "torso", "legs", "feet", "back", "secondary"]

# The bag column, in the order it is drawn. Pockets first because they are always there; then what
# is worn, outermost-reachable first. Anything else -- a toolbox inside the pack -- appears only
# once the player has opened it, which is what the `open` verb is for.
const COLUMN_SLOTS: Array[String] = ["belt", "vest", "back"]
# Between two bags in a lane, across and down.
const BAG_GAP: float = 8.0

# The list: one row per thing in reach, and the chips that narrow it. A chip names kinds by the
# content class every item already has -- the plate tints are the same split -- so filtering is a
# question the screen can answer without knowing anything the player does not.
# How much of the right column the list takes; the inspect pane below gets the rest, and needs the
# larger part -- a weapon's fitted slots run six lines under its sentence.
const LIST_SHARE: float = 0.42
const LIST_ROW: float = 40.0
const LIST_NAME_SIZE: int = 25
const LIST_NOTE_SIZE: int = 20
const LIST_ICON: float = 36.0
const FILTERS: Array = [
	["all", []],
	["use", ["consumable"]],
	["arms", ["weapon.melee", "weapon.ranged"]],
	["wear", ["armor", "container"]],
	["tools", ["tool"]],
	["parts", ["attachment", "material"]],
]

# How long a notice -- "no room in the cupboard" -- stays on the title bar, on the wall clock.
const NOTICE_MS: int = 3200

var _world: Variant = null
var _actor: int = -1
var _view: Dictionary = {}
var _open: bool = false

var _drag_item: int = -1
var _drag_rotated: bool = false
var _drag_dims: Vector2i = Vector2i.ONE

# What the inspect pane is talking about, and the plate that wears the ring.
var _selected: int = -1
# The selected plate's focus pulse (`ui/motion.gd`): which item it last started on, when on the wall
# clock, and which frame the last draw left on screen -- so a new selection starts the breath from
# its rest frame, and `_process` redraws the columns only when the frame turns over.
var _pulse_item: int = -1
var _pulse_since_ms: int = 0
# The last thing the player picked up, and when on the wall clock: the quick strip's item_ping.
# -1 for none. Set by `ping`, which `main.gd` calls off the drained `item.pickedUp` events.
var _ping_item: int = -1
var _ping_since_ms: int = 0
var _pulse_frame: int = -1
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
# recomputing the layout, so a click and a plate cannot disagree about where a bag is. Filled from
# `_column_places()`, the one arithmetic, which the pointer (`cursor_at`) reads directly because it
# is asked between frames and by a gate that never draws.
var _placed: Array[Dictionary] = []
var _scroll: float = 0.0
var _condition_scroll: int = 0
# The list: which chip is in force (an index into FILTERS) and how many rows it is scrolled.
var _filter: int = 0
var _list_scroll: int = 0
# What the title bar is saying, whether it is a refusal, and since when on the wall clock.
var _notice: String = ""
var _notice_bad: bool = false
var _notice_ms: int = 0

var _paperdoll: Control = null
var _ghost: Control = null
# The body part picked on the figure, "" for none: while it is set and no item is, the inspect pane
# is the part's care pane (ui/care_pane.gd). Presentation state only, like `_selected`.
var _part: String = ""
# The name field (docs/33 item 24): the item being named, -1 while the field is shut, what is typed
# so far, and where the caret stands in it. Presentation state only: nothing reaches the sim until
# Enter sends `item.name`. While it is open `input_map.gd` hands it every key (`name_key`), so W
# types a letter and does not walk anybody.
var _naming: int = -1
var _name_text: String = ""
var _name_caret: int = 0
# What the title bar says while the field is open, in place of the sheet's own hint.
const NAME_HINT: String = "type a name · Enter keeps it · Esc leaves it as it was"
# Set by main.gd while Colony or Skills is up: the strip is field HUD, and the field HUD is put away
# under every screen about people, not left lit under their wash.
var strip_hidden: bool = false

# The bag column is drawn into its own clipped child rather than straight onto the sheet: a deep
# loadout is taller than the screen, and without a clip the last bag paints over the quick strip.
# Input stays with the sheet -- the child ignores the mouse -- so every rect in `_placed` is still
# in sheet coordinates and the hit test needs no second frame of reference.
var _column_layer: Control = null
# The transfer window: the box you are standing at, beside your pockets, drawn while the sheet is
# *closed* so a loot stop never leaves the district. Its own Control and not part of the sheet,
# because the sheet ignores the mouse when closed and a Control that stopped the mouse over the
# whole screen would eat the click that swings your axe. This one is exactly the size of the
# window, so everything outside it still reaches the world.
var _loot_layer: Control = null
var _loot: Dictionary = {}
# Where the two grids and the word were drawn this frame, in window-local coordinates.
var _loot_placed: Array[Dictionary] = []
var _loot_hit: Array[Dictionary] = []


class LootWindow:
	extends Control
	# Stops the mouse over its own rect and nowhere else, and hands both halves back to the sheet:
	# the drawing, because that is where the layout lives, and the input, because that is where
	# the drag state lives. Godot pins mouse focus to whichever control took the press until the
	# button comes up, and both grids are inside this one control, so a drag from the cupboard to
	# a pocket begins and ends in the same node and needs no forwarding at all -- which is exactly
	# what the pinnable bag windows this overhaul deleted could not manage.

	var panel: Control = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		if panel != null:
			panel.call("_draw_loot_into", self)

	func _gui_input(event: InputEvent) -> void:
		if panel != null:
			panel.call("_loot_input", event)
			panel.call("_loot_point", event)


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
	# The held item, under the pointer: its own plate and picture at the size it has in a bag, and
	# over the cells it would land on, whether the sim would take it there.

	var panel: Control = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if panel == null or int(panel.get("_drag_item")) == -1:
			return
		# Under the plate, so the verdict on the cells is behind the thing you are holding.
		panel.call("_draw_drop_hint_into", self)
		panel.call("_draw_ghost_into", self, get_local_mouse_position())


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_size()
	_paperdoll = Paperdoll.new()
	_paperdoll.custom_minimum_size = Vector2(DOLL_W, DOLL_H)
	_paperdoll.size = Vector2(DOLL_W, DOLL_H)
	_paperdoll.visible = false
	# The figure is drawn by its own Control but clicked through the sheet: the sheet owns every
	# press (`_press_at`) and asks the figure which part is under it (`_part_under`).
	_paperdoll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paperdoll)
	var loot := LootWindow.new()
	loot.panel = self
	loot.visible = false
	_loot_layer = loot
	add_child(_loot_layer)
	var columns := Columns.new()
	columns.panel = self
	_column_layer = columns
	_column_layer.visible = _open
	add_child(_column_layer)
	var g := Ghost.new()
	g.panel = self
	_ghost = g
	add_child(_ghost)


func _process(_delta: float) -> void:
	if _drag_item != -1 and _ghost != null:
		_ghost.queue_redraw()
	# The selected plate's pulse: a columns redraw only while it is live and its frame has turned
	# over, or once to settle it on its rest frame when reduced motion is thrown mid-breath.
	if _open and _selected != -1 and _pulse_item == _selected and _column_layer != null:
		var elapsed: float = _pulse_elapsed()
		var still: bool = Motion.reduced()
		if Motion.frame_of(Motion.PULSE_ID, elapsed, still) != _pulse_frame and (Motion.is_live(Motion.PULSE_ID, elapsed, still) or still):
			_column_layer.queue_redraw()
	# A notice clears itself off the title bar.
	if _open and not _notice.is_empty() and Time.get_ticks_msec() - _notice_ms > NOTICE_MS:
		_notice = ""
		queue_redraw()


# Wall-clock seconds the selected plate has worn its pulse. Never the sim's tick: the sheet is open
# on a paused game as often as a running one.
func _pulse_elapsed() -> float:
	return float(Time.get_ticks_msec() - _pulse_since_ms) / 1000.0


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
		_end_naming()
		_cancel_drag()
		_close_menu()
		_notice = ""
		_part = ""
	if _paperdoll != null:
		_paperdoll.visible = open
	if _column_layer != null:
		_column_layer.visible = open
	_sync_size()
	queue_redraw()


# Settings changed; everything that reads an opacity redraws.
func refresh_style() -> void:
	queue_redraw()


# The player picked `item` up: the strip pings the slot it landed in, or its lead when it went
# into a bag. A second pick-up restarts the ping on the newer item.
func ping(item: int) -> void:
	_ping_item = item
	_ping_since_ms = Time.get_ticks_msec()
	queue_redraw()


# `{item, frame}` while the ping is still playing, {} once it has -- a one-shot that has reached
# its held last frame is finished, and the strip goes back to plain.
func _ping_view() -> Dictionary:
	if _ping_item == -1:
		return {}
	var elapsed: float = float(Time.get_ticks_msec() - _ping_since_ms) / 1000.0
	var still: bool = Motion.reduced()
	if elapsed > Motion.period_of("item_ping") * 2.0:
		_ping_item = -1
		return {}
	return {"item": _ping_item, "frame": Motion.frame_of("item_ping", elapsed, still)}


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
	if _column_layer != null and _open:
		_column_layer.queue_redraw()


func rotate() -> void:
	if _drag_item != -1:
		_drag_rotated = not _drag_rotated
		if _ghost != null:
			_ghost.queue_redraw()


# Say something on the title bar for a few seconds: a quick move that went through, or why one
# did not.
func _say(text: String, bad: bool) -> void:
	_notice = text
	_notice_bad = bad
	_notice_ms = Time.get_ticks_msec()
	queue_redraw()


# The container the survivor is standing at, or {} for none. Fed every refresh by main.gd, not
# only while the sheet is open: the whole point of the window is that it works during play.
const LOOT_PAD: float = 12.0
const LOOT_GAP: float = 12.0
const LOOT_FOOT: float = 48.0
# Where the window may not start above, as a share of the screen's height (the HUD's prose columns
# end about there), and the foot it falls back to when it cannot also clear the action bar.
const LOOT_CLEAR_TOP: float = 0.3
const LOOT_LOW: float = 150.0
# The window's one clickable word; the draw and the pointer measure the same string.
const LOOT_WORD: String = "take all that fits"
# The stockpile's grid in the window (slice S4): the sim lays the pile out into as many cells as the
# screen gives it, nearest first, and says when something seen did not fit. The bounds keep the
# window a window: never narrower than a cupboard's few cells, never so tall it covers the HUD's
# prose or drops over the action bar. At 1280x720 that is eight by three; at 1920x1080, ten by six.
const STORES_COLS_MIN: int = 4
const STORES_COLS_MAX: int = 10
const STORES_ROWS_MIN: int = 2
const STORES_ROWS_MAX: int = 6
const STORES_SHEET_COLS: int = 7
# The share of the screen's width the whole window may take, pockets included.
const STORES_WIDE_SHARE: float = 0.62
# The stockpile grid's header note: where its things are, and when the pile holds more than the grid.
const STORES_NOTE: String = "in sight"
const STORES_MORE: String = "and more besides"
func set_loot(view: Dictionary) -> void:
	_loot = view if view is Dictionary else {}
	if _loot_layer == null:
		return
	# Hidden while the sheet is open: the cupboard is a column on the sheet then, and two pictures
	# of one box on one screen is the confusion the fixed layout exists to end.
	var show: bool = not _loot.is_empty() and not _open
	_loot_layer.visible = show
	if not show:
		return
	var box: Vector2 = BagGrid.size_of(int(_loot.get("w", 0)), int(_loot.get("h", 0)))
	var mine: Dictionary = _pockets()
	var pockets: Vector2 = BagGrid.size_of(int(mine.get("w", 0)), int(mine.get("h", 0)))
	var wide: float = LOOT_PAD * 2.0 + box.x + LOOT_GAP + pockets.x
	var tall: float = LOOT_PAD * 2.0 + maxf(box.y, pockets.y) + LOOT_FOOT
	var view_size: Vector2 = get_viewport_rect().size
	_loot_layer.size = Vector2(wide, tall)
	# Centred horizontally and set low, clear of the HUD's two prose columns at the top -- and, since
	# the Salvage Locker, clear of the action bar too where the screen has the height for both: its
	# foot is the HUD's own margin, strip clearance and bar height above the bottom, plus one gap.
	# A short screen (720) cannot clear both, and the prose columns are what the window must not
	# cover, so there it sits where it always sat, its foot over the top of the bar.
	var foot: float = Hud.MARGIN + Hud.STRIP_CLEARANCE + Hud.BAR_H + LOOT_GAP
	var top: float = view_size.y - tall - foot
	if top < view_size.y * LOOT_CLEAR_TOP:
		top = view_size.y - tall - LOOT_LOW
	_loot_layer.position = (Vector2(roundf((view_size.x - wide) / 2.0), roundf(top)) / Locker.PX).round() * Locker.PX
	_loot_layer.queue_redraw()


func loot_open() -> bool:
	return _loot_layer != null and _loot_layer.visible


## How many cells the window's stockpile grid gets at this screen size: as wide as fits beside the
## pockets in STORES_WIDE_SHARE of the width, and as tall as keeps the window's top clear of the HUD's
## prose columns with its foot over the action bar -- the same two lines `set_loot` places it by.
## main.gd hands this to `SimStockpile.stores_view`.
func loot_capacity() -> Vector2i:
	var view_size: Vector2 = get_viewport_rect().size
	var mine: Dictionary = _pockets()
	var pockets: Vector2 = BagGrid.size_of(int(mine.get("w", 0)), int(mine.get("h", 0)))
	var spare_w: float = view_size.x * STORES_WIDE_SHARE - LOOT_PAD * 2.0 - LOOT_GAP - pockets.x - BagGrid.PAD * 2.0
	var cols: int = clampi(floori(spare_w / float(BagGrid.CELL)), STORES_COLS_MIN, STORES_COLS_MAX)
	var foot: float = Hud.MARGIN + Hud.STRIP_CLEARANCE + Hud.BAR_H + LOOT_GAP
	# Never so tall that `set_loot` has to drop it over the action bar: a sentence cut in half under
	# the window reads as broken. What does not fit says so ("and more besides") and is on the sheet.
	var spare_h: float = view_size.y * (1.0 - LOOT_CLEAR_TOP) - foot - LOOT_PAD * 2.0 - LOOT_FOOT - BagGrid.HEAD - BagGrid.PAD
	var rows: int = clampi(floori(spare_h / float(BagGrid.CELL)), STORES_ROWS_MIN, STORES_ROWS_MAX)
	return Vector2i(cols, rows)


# Whether a column, or the window's box, is the stockpile rather than a container entity.
static func _is_stores(column: Dictionary) -> bool:
	return int(column.get("container", -1)) == SimStockpile.STORES


# Whether `item` is listed in `column`.
static func _lists(column: Dictionary, item: int) -> bool:
	for entry in column.get("items", []) as Array:
		if int((entry as Dictionary).get("item", -1)) == item:
			return true
	return false


# The one door a dropped or sent item goes through. Between two of your own bags, or into or out of
# a cupboard, it is the `item.move` it always was. Out of the stockpile it is `stockpile.take` (to
# the cell it was dropped on, when `cell` names one); into it, `stockpile.put`, which lays it on a
# tile by S3's rule, so the cell it was dropped on means nothing. The sim decides every one.
func _send(item: int, column: Dictionary, cell: Variant, rotated: bool) -> void:
	if _world == null or item < 0:
		return
	var here: Dictionary = _open_here()
	var from_stores: bool = _is_stores(here) and _lists(here, item)
	if _is_stores(column):
		if not from_stores:
			_world.commands.push({"type": SimStockpile.PUT_COMMAND, "item": item})
		return
	if from_stores:
		var take: Dictionary = {"type": SimStockpile.TAKE_COMMAND, "item": item}
		if cell is Vector2i:
			take["container"] = int(column.get("container", -1))
			take["x"] = (cell as Vector2i).x
			take["y"] = (cell as Vector2i).y
			take["rotated"] = rotated
		_world.commands.push(take)
		return
	if cell is Vector2i:
		_world.commands.push({"type": "item.move", "item": item, "container": int(column.get("container", -1)), "x": (cell as Vector2i).x, "y": (cell as Vector2i).y, "rotated": rotated})


func _pockets() -> Dictionary:
	for entry in _view.get("containers", []) as Array:
		if int((entry as Dictionary)["container"]) == _actor:
			return entry as Dictionary
	return {"container": _actor, "label": "pockets", "w": 0, "h": 0, "items": []}


func _draw_loot_into(ci: CanvasItem) -> void:
	_loot_placed.clear()
	_loot_hit.clear()
	if _loot.is_empty():
		return
	var alpha: float = UiPrefs.opacity("inventory_opacity")
	var rect := Rect2(Vector2.ZERO, (_loot_layer as Control).size)
	Locker.panel(ci, rect, alpha)
	_loot_placed = _loot_places()
	BagGrid.draw_bag(ci, _loot_placed[0]["at"] as Vector2, _loot, alpha, _drag_item, _loot_note(), _world)
	BagGrid.draw_bag(ci, _loot_placed[1]["at"] as Vector2, _loot_placed[1]["column"] as Dictionary, alpha, _drag_item, "on you", _world)
	# One clickable word, in work_panel.gd's idiom, and the sentence that says what it will and
	# will not do -- *that fits* is half the verb, because the grid has already told you the axe
	# will not go in. Since the Salvage Locker it is a stamped button rather than amber prose.
	Locker.button(ci, _loot_word_rect(), LOOT_WORD, true, alpha)
	_loot_hit.append({"rect": _loot_word_rect(), "verb": "takeAll"})
	var font: Font = Chrome.font()
	var hint: String = "drag between them · ctrl-click sends · Esc closes"
	var hw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
	ci.draw_string(font, Vector2(rect.size.x - hw - LOOT_PAD - Locker.PX * 2.0, rect.size.y - LOOT_PAD - 10.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE, Locker.TEXT_DIM)


# The box's header note: "here" for a cupboard; for the stockpile, that these are the things in
# sight, or that the pile holds more than the grid.
func _loot_note() -> String:
	if not _is_stores(_loot):
		return "here"
	return STORES_MORE if bool(_loot.get("more", false)) else STORES_NOTE


func _loot_input(event: InputEvent) -> void:
	if _world == null or _loot.is_empty() or not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		for h in _loot_hit:
			if (h["rect"] as Rect2).has_point(mb.position):
				if _is_stores(_loot):
					_world.commands.push({"type": SimStockpile.TAKE_COMMAND, "all": true})
				else:
					_world.commands.push({"type": "container.takeAll"})
				(_loot_layer as Control).accept_event()
				return
		var found: Variant = _loot_item_under(mb.position)
		if found is Dictionary:
			var d: Dictionary = found as Dictionary
			if mb.ctrl_pressed:
				_quick_move(int(d.get("item", -1)))
				(_loot_layer as Control).queue_redraw()
				(_loot_layer as Control).accept_event()
				return
			var dims := Vector2i(int(d.get("w", 1)), int(d.get("h", 1)))
			if bool(d.get("rotated", false)):
				dims = Vector2i(dims.y, dims.x)
			_begin_drag(int(d.get("item", -1)), bool(d.get("rotated", false)), dims)
		(_loot_layer as Control).accept_event()
	elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		if _drag_item != -1:
			var item: int = _drag_item
			var rotated: bool = _drag_rotated
			_cancel_drag()
			for placed in _loot_placed:
				var cell: Variant = BagGrid.cell_at(placed["at"] as Vector2, placed["column"] as Dictionary, mb.position)
				if cell == null:
					continue
				_send(item, placed["column"] as Dictionary, cell, rotated)
				break
		(_loot_layer as Control).accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _drag_item != -1:
			rotate()
		(_loot_layer as Control).accept_event()


# The window's two grids, the box and your pockets, as {at, column} in window-local coordinates --
# the one arithmetic the draw and the pointer share.
func _loot_places() -> Array[Dictionary]:
	var box_size: Vector2 = BagGrid.size_of(int(_loot.get("w", 0)), int(_loot.get("h", 0)))
	return [
		{"at": Vector2(LOOT_PAD, LOOT_PAD), "column": _loot},
		{"at": Vector2(LOOT_PAD + box_size.x + LOOT_GAP, LOOT_PAD), "column": _pockets()},
	]


func _loot_word_rect() -> Rect2:
	var tall: float = (_loot_layer as Control).size.y if _loot_layer != null else 0.0
	var w: float = Locker.label_width(LOOT_WORD, Locker.LABEL_SIZE)
	return Rect2(Vector2(LOOT_PAD, tall - LOOT_PAD - 32.0), Vector2(w, 32.0))


# Which pointer the kit dresses the mouse in over the transfer window, at `p` in the window's own
# frame: while an item is held, what `_drop_verdict` says of dropping it there; otherwise the hand
# over an item or the take-all word, the arrow elsewhere.
func loot_cursor_at(p: Vector2) -> int:
	if _drag_item != -1:
		return int(_drop_verdict(_loot_places(), p).get("shape", Input.CURSOR_MOVE))
	if _loot.is_empty():
		return Input.CURSOR_ARROW
	if _loot_word_rect().has_point(p):
		return Input.CURSOR_POINTING_HAND
	for placed in _loot_places():
		var cell: Variant = BagGrid.cell_at(placed["at"] as Vector2, placed["column"] as Dictionary, p)
		if cell != null and BagGrid.item_at(placed["column"] as Dictionary, cell as Vector2i) is Dictionary:
			return Input.CURSOR_POINTING_HAND
	return Input.CURSOR_ARROW


# Called by the window after every event it hands over, so the pointer follows the state the
# event just left -- a press that lifts an item turns the hand into the move at once.
func _loot_point(event: InputEvent) -> void:
	if _loot_layer != null and event is InputEventMouse:
		(_loot_layer as Control).mouse_default_cursor_shape = loot_cursor_at((event as InputEventMouse).position) as Control.CursorShape


func _loot_item_under(p: Vector2) -> Variant:
	for placed in _loot_placed:
		var cell: Variant = BagGrid.cell_at(placed["at"] as Vector2, placed["column"] as Dictionary, p)
		if cell == null:
			continue
		return BagGrid.item_at(placed["column"] as Dictionary, cell as Vector2i)
	return null


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


# --- quick transfer -----------------------------------------------------------------------------
#
# Ctrl-click, or the inspect pane's button: send an item across without dragging it. From what you
# carry to the box you are standing at, or from the box to the first of your bags with room, in the
# column's own order. The place is found by asking `SimInventory.can_place` cell by cell -- the
# sim's verdict, never a second copy of the fit rules -- and the move goes through the queue like a
# drag would. Nothing is repacked; an item that fits nowhere stays put and the title bar says so.

# Where a quick move of `item` would go: the containers to try, in order.
func _quick_targets(item: int) -> Array:
	var here: Dictionary = _open_here()
	var in_here: bool = false
	for entry in here.get("items", []) as Array:
		if int((entry as Dictionary).get("item", -1)) == item:
			in_here = true
	if not in_here:
		return [here] if not here.is_empty() else []
	var out: Array = []
	for column in _columns():
		var d: Dictionary = column as Dictionary
		if int(d.get("container", -1)) != int(here.get("container", -2)) and int(d.get("container", -1)) != item:
			out.append(d)
	return out


func _quick_move(item: int) -> bool:
	if _world == null or item < 0:
		return false
	var name: String = _name_of(item)
	# Onto the stockpile there are no cells to ask about: it goes down on a tile by the sim's rule.
	# Off it, the cell is found below like any other, and `_send` makes it a `stockpile.take`.
	var here: Dictionary = _open_here()
	if _is_stores(here) and not _lists(here, item):
		_send(item, here, null, false)
		_say("%s onto the stockpile" % name, false)
		return true
	var targets: Array = _quick_targets(item)
	if targets.is_empty():
		_say("nothing open to send %s to" % name, true)
		return false
	for target in targets:
		var d: Dictionary = target as Dictionary
		var box: int = int(d.get("container", -1))
		for rotated in [false, true]:
			for y in int(d.get("h", 0)):
				for x in int(d.get("w", 0)):
					if bool(SimInventory.can_place(_world, item, box, x, y, rotated).get("ok", false)):
						_send(item, d, Vector2i(x, y), rotated)
						_say("%s into the %s" % [name, String(d.get("label", ""))], false)
						return true
	_say("no room for %s in the %s" % [name, String((targets[0] as Dictionary).get("label", ""))], true)
	return false


func _name_of(item: int) -> String:
	for entry in _open_here().get("items", []) as Array:
		if int((entry as Dictionary).get("item", -1)) == item:
			return String((entry as Dictionary).get("name", "it"))
	for column in _columns():
		for entry in (column as Dictionary).get("items", []) as Array:
			if int((entry as Dictionary).get("item", -1)) == item:
				return String((entry as Dictionary).get("name", "it"))
	return "it"


# --- layout -----------------------------------------------------------------------------

func _compact() -> bool:
	var view: Vector2 = get_viewport_rect().size
	return view.x < FULL_WIDTH or view.y < FULL_HEIGHT


func _top_h() -> float:
	return TOP_H_COMPACT if _compact() else TOP_H


func _top_rect() -> Rect2:
	return Rect2(Vector2(PAD, PAD), Vector2(get_viewport_rect().size.x - PAD * 2.0, _top_h()))


func _content_top() -> float:
	return PAD + _top_h() + GAP


# The height the three working columns share: from under the title bar to over the quick strip.
func _tall() -> float:
	return get_viewport_rect().size.y - _content_top() - GAP - STRIP_H - PAD


func _body_rect() -> Rect2:
	return Rect2(Vector2(PAD, _content_top()), Vector2(BODY_W_COMPACT if _compact() else BODY_W, _tall()))


# The narrowest a bag lane can be: the widest carried bag, the frame pack's seven cells.
func _lane_min() -> float:
	return BagGrid.size_of(7, 1).x


# Whether the right column gives way to a second bag lane: only on a window too narrow to have the
# list, the inspect pane and two lanes at once, and only while a box is open -- source and
# destination on screen together matters more than the words about one item while you pack.
func _right_hidden() -> bool:
	if _open_here().is_empty() or _world == null:
		return false
	var view: Vector2 = get_viewport_rect().size
	var body: Rect2 = _body_rect()
	var right_w: float = RIGHT_W_COMPACT if _compact() else RIGHT_W
	var room: float = view.x - PAD - right_w - GAP - (body.end.x + GAP)
	return room < _lane_min() * 2.0 + GAP


func _right_rect() -> Rect2:
	if _right_hidden():
		return Rect2()
	var view: Vector2 = get_viewport_rect().size
	var wide: float = RIGHT_W_COMPACT if _compact() else RIGHT_W
	return Rect2(Vector2(view.x - PAD - wide, _content_top()), Vector2(wide, _tall()))


# The list takes the top half of the right column and the inspect pane the rest.
func _list_rect() -> Rect2:
	var right: Rect2 = _right_rect()
	if not right.has_area():
		return Rect2()
	var tall: float = roundf(right.size.y * LIST_SHARE / Locker.PX) * Locker.PX
	# A picked part's care can need more than the inspect half: the list gives up rows to it, down to
	# its header, the chips and one row, so every refusal it can reads instead of being cut off at
	# 1280x720. The floor is measured from where the chips really end (they wrap to two lines in the
	# narrow column): a floor of two bare rows once left the list no row at all under its chips, and
	# it said "nothing in reach" over an item that was.
	if _showing_part():
		var need: float = CarePane.height_for(_care_view(), right.size.x - CarePane.PAD * 2.0)
		var floor_h: float = _rows_offset(right.size.x) + LIST_ROW + Locker.PX * 4.0
		tall = maxf(floor_h, minf(tall, right.size.y - GAP - need))
		tall = floorf(tall / Locker.PX) * Locker.PX
	return Rect2(right.position, Vector2(right.size.x, tall))


func _inspect_rect() -> Rect2:
	var right: Rect2 = _right_rect()
	if not right.has_area():
		return Rect2()
	var list: Rect2 = _list_rect()
	var top: float = list.end.y + GAP
	return Rect2(Vector2(right.position.x, top), Vector2(right.size.x, right.end.y - top))


func _column_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size
	var body: Rect2 = _body_rect()
	var right: Rect2 = _right_rect()
	var x: float = body.end.x + GAP
	var end: float = (right.position.x - GAP) if right.has_area() else (view.x - PAD)
	return Rect2(Vector2(x, _content_top()), Vector2(maxf(200.0, end - x), _tall()))


# The lanes the bags are laid in: [{rect, columns}]. Two when a box is open and there is room --
# what you carry on the left, the box on the right -- otherwise one, in the column's own order.
func _lanes() -> Array[Dictionary]:
	var area: Rect2 = _column_rect()
	var all: Array = _columns()
	var here: Dictionary = _open_here() if _world != null else {}
	if not here.is_empty() and area.size.x >= _lane_min() * 2.0 + GAP and not all.is_empty():
		var half: float = floorf((area.size.x - GAP) / 2.0 / Locker.PX) * Locker.PX
		var mine: Array = all.slice(1)
		return [
			{"rect": Rect2(area.position, Vector2(half, area.size.y)), "columns": mine},
			{"rect": Rect2(Vector2(area.end.x - half, area.position.y), Vector2(half, area.size.y)), "columns": [all[0]]},
		]
	return [{"rect": area, "columns": all}]


static func slot_rect(body: Rect2, side: int, index: int) -> Rect2:
	var compact: bool = body.size.x < BODY_W
	var step: float = SLOT_STEP_COMPACT if compact else SLOT_STEP
	var x: float = body.position.x + SLOT_INSET if side == 0 else body.end.x - SLOT_INSET - SLOT_W
	return Rect2(Vector2(x, body.position.y + Locker.HEAD_H + 8.0 + step * float(index)), Vector2(SLOT_W, SLOT_H))


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
	# What you are standing at goes first, above what you are carrying: it is the thing you opened
	# the screen for, and it is the only column that is not yours. `inventory_view` never mentions
	# it -- a cupboard is not a reachable container of the survivor's -- so it comes from the
	# container module's own view.
	if _world != null and not _open_here().is_empty():
		out.append(_open_here())
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


# The container the survivor is standing at, as a column. Pulled fresh rather than cached, because
# the whole thing changes every time something moves in or out of it.
#
# The stockpile when no cupboard is open (slice S4), laid out for wherever it is drawn: the sheet's
# column when the sheet is up, the window's grid when it is not. Kept for the tick it was read on,
# because a frame asks for it a dozen times and the pile changes only when the sim steps.
var _stores_key: Array = []
var _stores_memo: Dictionary = {}


func _open_here() -> Dictionary:
	if _world == null or _actor < 0:
		return {}
	var box: Dictionary = SimContainers.open_view(_world, _actor)
	if not box.is_empty():
		return box
	# With the sheet shut, the window's own feed is this exact view (main.gd lays it out at
	# `loot_capacity`), so it is read rather than laid out a second time.
	if not _open and _is_stores(_loot):
		return _loot
	var cap: Vector2i = _sheet_capacity() if _open else loot_capacity()
	var key: Array = [int(_world.tick), _actor, cap, _open]
	if key != _stores_key:
		_stores_key = key
		_stores_memo = SimStockpile.stores_view(_world, _actor, cap.x, cap.y)
	return _stores_memo


# The stockpile's column on the sheet: as wide as a lane's narrowest (`_lane_min`, seven cells), so it
# fits the box's lane at every size the sheet lays out at, and a fixed height (the lane scrolls). A
# constant, not a measure of the column rect: that rect asks `_open_here` whether a box is open.
func _sheet_capacity() -> Vector2i:
	return Vector2i(STORES_SHEET_COLS, STORES_ROWS_MAX)


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
	if _selected != -1 and _world != null and not SimInventory.owns(_world, _actor, _selected) and not _in_here(_selected):
		_selected = -1
	if _menu_item != -1 and _world != null and not SimInventory.owns(_world, _actor, _menu_item):
		_close_menu()


# Whether `item` is in the box the survivor is standing at: selectable and inspectable, and sent
# back with a quick move, though none of the carried verbs apply to it.
func _in_here(item: int) -> bool:
	for entry in _open_here().get("items", []) as Array:
		if int((entry as Dictionary).get("item", -1)) == item:
			return true
	return false


# --- the list ---------------------------------------------------------------------------

# Every item in every column on the sheet, as the list shows it: {item, name, baseId, count, where,
# class, view}, in the chip's kind, sorted by name and then by where it is. The same item views
# the grids draw, so a row and a plate are the same thing.
func _list_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kinds: Array = (FILTERS[clampi(_filter, 0, FILTERS.size() - 1)] as Array)[1] as Array
	for column in _columns():
		var c: Dictionary = column as Dictionary
		var where: String = String(c.get("label", ""))
		for entry in c.get("items", []) as Array:
			var d: Dictionary = entry as Dictionary
			var cls: String = BagGrid.class_of(_world, String(d.get("baseId", "")))
			if not kinds.is_empty() and not kinds.has(cls):
				continue
			out.append({"item": int(d.get("item", -1)), "name": String(d.get("name", "")), "baseId": String(d.get("baseId", "")), "count": int(d.get("count", 1)), "where": where, "class": cls, "view": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["name"]) != String(b["name"]):
			return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
		return String(a["where"]) < String(b["where"]))
	return out


# Whether an item view is in the chip's kind: what the grids fade by. `all` fades nothing.
func _matches(d: Dictionary) -> bool:
	var kinds: Array = (FILTERS[clampi(_filter, 0, FILTERS.size() - 1)] as Array)[1] as Array
	return kinds.is_empty() or kinds.has(BagGrid.class_of(_world, String(d.get("baseId", ""))))


# The chips, laid left to right under the list's header and wrapped when the column is narrow:
# [{rect, index}].
func _chip_rects() -> Array[Dictionary]:
	var list: Rect2 = _list_rect()
	if not list.has_area():
		return []
	return _chips_at(list.position, list.size.x)


# The filter chips laid from a list's top-left corner across its width, wrapping to a new line when
# a chip would pass the right edge. Width only, never the list's height, so `_list_rect` can ask how
# tall the chips stand before it has decided its own height.
func _chips_at(at: Vector2, wide: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var x: float = at.x + Locker.PX * 4.0
	var y: float = at.y + Locker.HEAD_H + Locker.PX * 2.0
	var h: float = 24.0
	for i in FILTERS.size():
		var w: float = Locker.label_width(String((FILTERS[i] as Array)[0]), Locker.SMALL_SIZE)
		if x + w > at.x + wide - Locker.PX * 4.0:
			x = at.x + Locker.PX * 4.0
			y += h + Locker.PX * 2.0
		out.append({"rect": Rect2(Vector2(x, y), Vector2(w, h)), "index": i})
		x += w + Locker.PX * 3.0
	return out


# How far below the list's top its first row starts, for a list `wide` across: under the header and
# the chips, however many lines they wrap to.
func _rows_offset(wide: float) -> float:
	var chips: Array[Dictionary] = _chips_at(Vector2.ZERO, wide)
	if chips.is_empty():
		return Locker.HEAD_H
	return (chips[chips.size() - 1]["rect"] as Rect2).end.y + Locker.PX * 4.0


func _list_rows_top() -> float:
	var list: Rect2 = _list_rect()
	if not list.has_area():
		return list.position.y + Locker.HEAD_H
	return list.position.y + _rows_offset(list.size.x)


func _list_capacity() -> int:
	var list: Rect2 = _list_rect()
	return maxi(0, floori((list.end.y - Locker.PX * 4.0 - _list_rows_top()) / LIST_ROW))


# The rows on screen, {rect, row}, from the scroll: the one arithmetic the draw and the press share.
func _list_hits() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Rect2 = _list_rect()
	if not list.has_area():
		return out
	var rows: Array[Dictionary] = _list_rows()
	var cap: int = _list_capacity()
	_list_scroll = clampi(_list_scroll, 0, maxi(0, rows.size() - cap))
	var y: float = _list_rows_top()
	for i in mini(cap, rows.size() - _list_scroll):
		var r := Rect2(Vector2(list.position.x + Locker.PX * 3.0, y + float(i) * LIST_ROW), Vector2(list.size.x - Locker.PX * 6.0, LIST_ROW - Locker.PX))
		out.append({"rect": r, "row": rows[_list_scroll + i]})
	return out


# --- input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _open or _world == null or _view.is_empty():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP] and _body_rect().has_point(mb.position):
			var step: int = 1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			_condition_scroll = clampi(_condition_scroll + step, 0, maxi(0, _condition_rows().size() - _condition_capacity()))
			queue_redraw()
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP] and _list_rect().has_point(mb.position):
			var step2: int = 1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			_list_scroll = clampi(_list_scroll + step2, 0, maxi(0, _list_rows().size() - _list_capacity()))
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scroll = minf(_scroll + float(BagGrid.CELL), maxf(0.0, _column_height() - _column_rect().size.y))
			_redraw_columns()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scroll = maxf(0.0, _scroll - float(BagGrid.CELL))
			_redraw_columns()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press_at(mb.position, mb.ctrl_pressed)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_release_at(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right_at(mb.position)
			accept_event()
	# After the event has done what it does, so the pointer follows the state it left: a press
	# that lifts an item shows the move at once, a release shows the hand or the arrow again.
	if event is InputEventMouse:
		mouse_default_cursor_shape = cursor_at((event as InputEventMouse).position) as Control.CursorShape


func _redraw_columns() -> void:
	queue_redraw()
	if _column_layer != null:
		_column_layer.queue_redraw()


func _press_at(p: Vector2, ctrl: bool = false) -> void:
	if _world == null or _view.is_empty():
		return
	# A press anywhere puts the field down unsent: the name is kept only by Enter, so a click
	# elsewhere is the same as Escape, never a half-typed name sent by accident.
	if _naming != -1:
		_end_naming()
	# The menu first: it is drawn over everything, so it has to be tested before everything.
	if _menu_item != -1:
		for row in ItemMenu.verb_rects(_menu_at, _menu_verbs):
			if (row["rect"] as Rect2).has_point(p):
				_act(String(row["verb"]), _menu_item)
				_close_menu()
				return
		_close_menu()
		return
	# The navigation bar: a tab, or the close control. Through main.gd's one door, as a key would.
	var asked: Variant = NavBar.hit(_nav_layout(), p)
	if asked != null:
		navigate.emit("" if String(asked) == "survivor" else String(asked))
		return
	# The care pane's buttons, while it is the pane on show: the command the sim already said it
	# would take (`CarePane.view_for` dry-runs every verb through `SimTreatment.options_for`).
	if _showing_part() and _inspect_rect().has_area():
		var care: Dictionary = _care_view()
		for b in CarePane.button_rects(_inspect_rect(), care):
			if (b["rect"] as Rect2).has_point(p):
				var command: Dictionary = CarePane.command_for(care, String(b["verb"]))
				if not command.is_empty():
					_world.commands.push(command)
					if String(b["verb"]) != CarePane.STOP_VERB:
						_say("%s: %s" % [String(care.get("label", "")), CarePane.word_of(String(b["verb"]))], false)
				_redraw_columns()
				return
	# A part of the figure: the inspect slot becomes that part's condition and care. Before the
	# slots and the grids, which never overlap the figure, and after the bar and the pane, which do
	# not either -- so the order only matters for the empty-body press below that clears a pick.
	var part: String = _part_under(p)
	if not part.is_empty():
		_part = part
		_selected = -1
		_redraw_columns()
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
	# The inspect pane's buttons: the same verbs the word menu offers, said where you are reading.
	if _selected != -1:
		for b in InspectPane.button_rects(_inspect_rect(), _pane_verbs()):
			if (b["rect"] as Rect2).has_point(p):
				_act(String(b["verb"]), _selected)
				return
	# A chip on the list.
	for chip in _chip_rects():
		if (chip["rect"] as Rect2).has_point(p):
			_filter = int(chip["index"])
			_list_scroll = 0
			_redraw_columns()
			return
	# A row on the list: select it, and lift it -- a row can be dragged into a bag like a plate.
	for row in _list_hits():
		if (row["rect"] as Rect2).has_point(p):
			var r: Dictionary = row["row"] as Dictionary
			var d0: Dictionary = r["view"] as Dictionary
			_selected = int(r["item"])
			_part = ""
			if ctrl:
				_quick_move(_selected)
				_redraw_columns()
				return
			var dims0 := Vector2i(int(d0.get("w", 1)), int(d0.get("h", 1)))
			if bool(d0.get("rotated", false)):
				dims0 = Vector2i(dims0.y, dims0.x)
			_begin_drag(_selected, bool(d0.get("rotated", false)), dims0)
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
			_part = ""
			_begin_drag(id, false, Vector2i(1, 1))
			_world.commands.push({"type": "item.unequip", "slot": String(box["slot"]), "item": id})
		return
	# A grid cell.
	var found: Variant = _item_under(p)
	if found is Dictionary:
		var d: Dictionary = found as Dictionary
		_selected = int(d.get("item", -1))
		_part = ""
		if ctrl:
			_quick_move(_selected)
			_redraw_columns()
			return
		var dims := Vector2i(int(d.get("w", 1)), int(d.get("h", 1)))
		var rotated: bool = bool(d.get("rotated", false))
		if rotated:
			dims = Vector2i(dims.y, dims.x)
		_begin_drag(int(d.get("item", -1)), rotated, dims)
		return
	if _column_rect().has_point(p) or _body_rect().has_point(p):
		_selected = -1
		_part = ""
	_redraw_columns()


# The body part under `p` (sheet coordinates), off the figure's own pictures, or "". The figure is
# placed first, so a press before the first frame lands on the same figure the frame will draw.
func _part_under(p: Vector2) -> String:
	if _paperdoll == null or not _open or not _body_rect().has_point(p):
		return ""
	_place_doll()
	return String(_paperdoll.call("part_at", p - _paperdoll.position))


# Where the figure stands in the body panel: centred, under the tape, at the sheet's size for it.
func _place_doll() -> void:
	var body: Rect2 = _body_rect()
	var doll_size: Vector2 = Vector2(DOLL_W_COMPACT, DOLL_H_COMPACT) if _compact() else Vector2(DOLL_W, DOLL_H)
	_paperdoll.custom_minimum_size = doll_size
	_paperdoll.size = doll_size
	_paperdoll.set("drawing_offset", 0.0)
	_paperdoll.position = Vector2(roundf(body.get_center().x - doll_size.x / 2.0), body.position.y + Locker.HEAD_H + 8.0)


func _release_at(p: Vector2) -> void:
	if _drag_item == -1 or _world == null:
		return
	var item: int = _drag_item
	var rotated: bool = _drag_rotated
	var verdict: Dictionary = drop_hint(p)
	_cancel_drag()
	# A part dropped on a weapon fits it when there is an empty slot for it and the survivor may work
	# on it here. It is asked before the equipment boxes, as `drop_hint` asks it, so a worn weapon's
	# box fits a part rather than equipping it. Otherwise the drop is the box or the grid, as before.
	var host: Dictionary = _host_under(p)
	if not host.is_empty():
		var slot: String = SimGunsmith.drop_slot(_world, _actor, item, int(host["item"]))
		if slot != "":
			_world.commands.push({"type": "item.attach", "host": int(host["item"]), "item": item, "slot": slot})
			_redraw_columns()
			return
	for box in _slot_boxes():
		if (box["rect"] as Rect2).has_point(p):
			_world.commands.push({"type": "item.equip", "item": item, "slot": String(box["slot"])})
			_redraw_columns()
			return
	if not _column_rect().has_point(p):
		_redraw_columns()
		return
	for placed in _placed:
		var at: Vector2 = placed["at"] as Vector2
		var column: Dictionary = placed["column"] as Dictionary
		var cell: Variant = BagGrid.cell_at(at, column, p)
		if cell == null:
			continue
		# Propose the move; the sim decides depth, fit and cycle. A move the sim's own predicate
		# already refuses is still proposed -- the sim is the one that decides -- and the title bar
		# says why it will not land. Into or out of the stockpile it is the stockpile's command.
		_send(item, column, cell, rotated)
		if int(verdict.get("shape", Input.CURSOR_MOVE)) == Input.CURSOR_FORBIDDEN:
			_say(_refusal_words(String(verdict.get("reason", ""))), true)
		_redraw_columns()
		return
	# Dropped on nothing: no op. The item stays where it is until a command lands, which is what
	# makes a mis-drag cost nothing.
	_redraw_columns()


# What `SimInventory.can_place`'s reason means, in words.
static func _refusal_words(reason: String) -> String:
	match reason:
		"does-not-fit":
			return "it will not fit there"
		"too-deep":
			return "bags inside bags go no deeper than that"
		"would-nest-inside-itself":
			return "a bag cannot go inside itself"
		_:
			return "it will not go there"


func _right_at(p: Vector2) -> void:
	if _drag_item != -1:
		rotate()
		return
	var found: Variant = _item_under(p)
	if not (found is Dictionary):
		for row in _list_hits():
			if (row["rect"] as Rect2).has_point(p):
				_open_menu(p, int((row["row"] as Dictionary)["item"]))
				return
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


# The verbs the inspect pane offers as buttons for the selected item: the word menu's, less
# `inspect` (you are reading it), plus a quick move when there is somewhere to send it -- "take"
# out of the box you are at, or "stash" into it.
func _pane_verbs() -> Array[String]:
	var out: Array[String] = []
	if _world == null or _selected < 0:
		return out
	if _in_here(_selected):
		out.append("take")
		return out
	for v in SimInventory.verbs_for(_world, _actor, _selected):
		if v != "inspect":
			out.append(v)
	# Something worn is not stashed in one click: taking it off is its own decision.
	if not _open_here().is_empty() and _slot_of(_selected).is_empty():
		out.append("stash")
	return out


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
		"modify":
			_world.commands.push({"type": "bench.open", "item": item})
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
		"name":
			_begin_naming(item)
		"take", "stash":
			_quick_move(item)
	_redraw_columns()


# --- the name field ----------------------------------------------------------------------

# Whether the name field is open: `input_map.gd` asks before anything else reads a key.
func naming() -> bool:
	return _open and _naming != -1


# The field as the inspect pane draws it, {} while it is shut.
func name_field() -> Dictionary:
	if not naming():
		return {}
	return {"item": _naming, "text": _name_text, "caret": _name_caret}


# Opens the field on `item`, prefilled with the name it has now. A name longer than the field takes
# (a rolled weapon's prefixes and suffixes can run past it) starts the field empty rather than
# starting it over the cap, where Enter could only be refused.
func _begin_naming(item: int) -> void:
	if _world == null or item < 0:
		return
	_close_menu()
	_selected = item
	_naming = item
	var now: String = SimItems.item_name(_world, item)
	_name_text = now if now.length() <= SimItems.NAME_MAX else ""
	_name_caret = _name_text.length()
	_notice = ""
	queue_redraw()


func _end_naming() -> void:
	if _naming == -1:
		return
	_naming = -1
	_name_text = ""
	_name_caret = 0
	queue_redraw()


# Every key while the field is open, handed over by `input_map.gd` before its own table reads it.
# Returns true for a key the field took, which is every key: a field that let one through would let
# W walk the survivor mid-word. The cap shows itself by refusing the next character -- no counter,
# because a counter is a digit on the sheet.
func name_key(ke: InputEventKey) -> bool:
	if not naming():
		return false
	match ke.keycode:
		KEY_ESCAPE:
			_end_naming()
		KEY_ENTER, KEY_KP_ENTER:
			_commit_name()
		KEY_BACKSPACE:
			if _name_caret > 0:
				_name_text = _name_text.substr(0, _name_caret - 1) + _name_text.substr(_name_caret)
				_name_caret -= 1
		KEY_DELETE:
			if _name_caret < _name_text.length():
				_name_text = _name_text.substr(0, _name_caret) + _name_text.substr(_name_caret + 1)
		KEY_LEFT:
			_name_caret = maxi(0, _name_caret - 1)
		KEY_RIGHT:
			_name_caret = mini(_name_text.length(), _name_caret + 1)
		KEY_HOME, KEY_UP:
			_name_caret = 0
		KEY_END, KEY_DOWN:
			_name_caret = _name_text.length()
		_:
			var code: int = ke.unicode
			if not ke.ctrl_pressed and not ke.alt_pressed and not ke.meta_pressed \
					and code >= 32 and code != 127 and _name_text.length() < SimItems.NAME_MAX:
				_name_text = _name_text.substr(0, _name_caret) + String.chr(code) + _name_text.substr(_name_caret)
				_name_caret += 1
	queue_redraw()
	return true


# Enter: the sim says whether it would take the name, in its own words. A refusal is said on the
# title bar and the field stays open with the text in it, so the player fixes the name rather than
# typing it again; a name it would take goes out as `item.name` and the field shuts.
func _commit_name() -> void:
	if _world == null or _naming == -1:
		return
	var reason: String = SimItems.name_refusal(_world, _actor, _naming, _name_text)
	if reason != "":
		_say(SimItems.name_refusal_words(reason), true)
		return
	_world.commands.push({"type": "item.name", "item": _naming, "name": _name_text})
	_end_naming()


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


# The weapon, or any item with slots, under the pointer: its id and the rect it is drawn in, as
# {item, rect}, or {} over nothing. An equipment box answers for what is worn there; a grid answers
# for the plate under the cursor. Release and hover both ask this, so they cannot disagree.
func _host_under(p: Vector2) -> Dictionary:
	for box in _slot_boxes():
		if not (box["rect"] as Rect2).has_point(p):
			continue
		var worn: Variant = _slot_item(String(box["slot"]))
		if worn is Dictionary and int((worn as Dictionary).get("item", -1)) >= 0:
			return {"item": int((worn as Dictionary)["item"]), "rect": box["rect"] as Rect2}
		return {}
	if not _column_rect().has_point(p):
		return {}
	for placed in _placed:
		var at: Vector2 = placed["at"] as Vector2
		var column: Dictionary = placed["column"] as Dictionary
		var cell: Variant = BagGrid.cell_at(at, column, p)
		if cell == null:
			continue
		var view: Variant = BagGrid.item_at(column, cell as Vector2i)
		if not view is Dictionary or int((view as Dictionary).get("item", -1)) < 0:
			return {}
		# Clipped to the grid it is drawn in: a plate that runs under the scroll edge is not a target
		# past it, and its wash is not drawn past it either.
		var drawn: Rect2 = BagGrid.plate_rect(BagGrid.origin_of(at), view as Dictionary).intersection(_column_rect())
		if not drawn.has_area():
			return {}
		return {"item": int((view as Dictionary)["item"]), "rect": drawn}
	return {}


# The item view under a point, across every drawn grid, or null.
func _item_under(p: Vector2) -> Variant:
	if not _column_rect().has_point(p):
		return null
	for placed in _placed:
		var at: Vector2 = placed["at"] as Vector2
		var column: Dictionary = placed["column"] as Dictionary
		var cell: Variant = BagGrid.cell_at(at, column, p)
		if cell == null:
			continue
		return BagGrid.item_at(column, cell as Vector2i)
	return null


# --- the pointer ------------------------------------------------------------------------
#
# Which of the kit's pointers (ui/cursors.gd) the mouse wears over the open sheet, at `p` in sheet
# coordinates. The slots and grids come from the layout's own arithmetic, not the last frame, so it
# can be asked between frames; the response words are the ones the last frame drew, exactly as a
# press reads them. While an item is held it is `drop_hint`'s verdict; otherwise the hand over
# anything a press acts on -- a menu word, a response word, a button, a chip, a list row, a slot
# with something in it, an item in a grid -- and the arrow elsewhere.
func cursor_at(p: Vector2) -> int:
	if _drag_item != -1:
		return int(drop_hint(p).get("shape", Input.CURSOR_MOVE))
	if not _open or _world == null or _view.is_empty():
		return Input.CURSOR_ARROW
	if _menu_item != -1:
		for row in ItemMenu.verb_rects(_menu_at, _menu_verbs):
			if (row["rect"] as Rect2).has_point(p):
				return Input.CURSOR_POINTING_HAND
		return Input.CURSOR_ARROW
	for h in _hit:
		if (h["rect"] as Rect2).has_point(p):
			return Input.CURSOR_POINTING_HAND
	if NavBar.hit(_nav_layout(), p) != null or not _part_under(p).is_empty():
		return Input.CURSOR_POINTING_HAND
	if _showing_part():
		for b in CarePane.button_rects(_inspect_rect(), _care_view()):
			if (b["rect"] as Rect2).has_point(p):
				return Input.CURSOR_POINTING_HAND
	if _selected != -1:
		for b in InspectPane.button_rects(_inspect_rect(), _pane_verbs()):
			if (b["rect"] as Rect2).has_point(p):
				return Input.CURSOR_POINTING_HAND
	for chip in _chip_rects():
		if (chip["rect"] as Rect2).has_point(p):
			return Input.CURSOR_POINTING_HAND
	for row in _list_hits():
		if (row["rect"] as Rect2).has_point(p):
			return Input.CURSOR_POINTING_HAND
	for box in _slot_boxes():
		if (box["rect"] as Rect2).has_point(p):
			return Input.CURSOR_POINTING_HAND if _slot_item(String(box["slot"])) is Dictionary else Input.CURSOR_ARROW
	if not _column_rect().has_point(p):
		return Input.CURSOR_ARROW
	for placed in _column_places():
		var cell: Variant = BagGrid.cell_at(placed["at"] as Vector2, placed["column"] as Dictionary, p)
		if cell != null and BagGrid.item_at(placed["column"] as Dictionary, cell as Vector2i) is Dictionary:
			return Input.CURSOR_POINTING_HAND
	return Input.CURSOR_ARROW


# What letting go of the held item at `p` (sheet coordinates) would come to: `{shape, rect}`, the
# shape the pointer wears and the cells the item would cover, or {} with nothing held. Over an
# equipment slot it is the move with no cells -- `SimInventory.equip` has no pure predicate to ask,
# so an equip is judged by the sim when the command lands, as it always was.
func drop_hint(p: Vector2) -> Dictionary:
	if _drag_item == -1:
		return {}
	var host: Dictionary = _host_under(p)
	if not host.is_empty() and SimGunsmith.drop_slot(_world, _actor, _drag_item, int(host["item"])) != "":
		return {"shape": Input.CURSOR_MOVE, "rect": host["rect"] as Rect2, "fit": true}
	for box in _slot_boxes():
		if (box["rect"] as Rect2).has_point(p):
			return {"shape": Input.CURSOR_MOVE, "rect": Rect2()}
	if not _column_rect().has_point(p):
		return {"shape": Input.CURSOR_MOVE, "rect": Rect2()}
	return _drop_verdict(_column_places(), p)


# The verdict on dropping the held item at `p` over one of `places` ({at, column}, in p's frame),
# and it is the sim's: `SimInventory.can_place`, asked about exactly the cell and turn a release
# there would propose -- never a second copy of the fit rules here. Refused, the pointer is blocked
# and hazard stripes go over the cells; accepted, it is the move and the cells are outlined. Over
# no grid at all a release does nothing, which is the move too: the item is still in your hand.
#
# What this does not see: `can_place` is the grid, the nesting and the depth, and not the reach
# guard `inventory.intake` adds for a world container (`_move_is_reachable`). So a drag into a
# cupboard nobody is standing at can read as the move and be refused when it lands.
func _drop_verdict(places: Array, p: Vector2) -> Dictionary:
	if _world == null or _drag_item == -1:
		return {"shape": Input.CURSOR_MOVE, "rect": Rect2()}
	for placed in places:
		var at: Vector2 = placed["at"] as Vector2
		var column: Dictionary = placed["column"] as Dictionary
		var cell: Variant = BagGrid.cell_at(at, column, p)
		if cell == null:
			continue
		var c: Vector2i = cell as Vector2i
		# Over the stockpile, a thing you carry goes onto the pile wherever it is let go; the cells
		# are the window's, not the ground's, so the whole grid is the target.
		if _is_stores(column):
			if _lists(column, _drag_item):
				return {"shape": Input.CURSOR_MOVE, "rect": Rect2()}
			var put_ok: bool = SimInventory.owns(_world, _actor, _drag_item)
			return {
				"shape": Input.CURSOR_MOVE if put_ok else Input.CURSOR_FORBIDDEN,
				"rect": Rect2(BagGrid.origin_of(at), Vector2(float(int(column.get("w", 0))), float(int(column.get("h", 0)))) * float(BagGrid.CELL)),
				"reason": "" if put_ok else "not-carried",
			}
		var verdict: Dictionary = SimInventory.can_place(_world, _drag_item, int(column.get("container", -1)), c.x, c.y, _drag_rotated)
		var ok: bool = bool(verdict.get("ok", false))
		return {
			"shape": Input.CURSOR_MOVE if ok else Input.CURSOR_FORBIDDEN,
			"rect": _footprint_rect(at, column, c),
			"reason": String(verdict.get("reason", "")),
		}
	return {"shape": Input.CURSOR_MOVE, "rect": Rect2()}


# The cells the held item would cover with its top-left at `cell`, clipped to the grid it is over:
# its size from the sim's own view of it, turned the way the drag is turned.
func _footprint_rect(at: Vector2, column: Dictionary, cell: Vector2i) -> Rect2:
	var d: Dictionary = SimInventory.view_of(_world, _drag_item, {"rotated": _drag_rotated})
	var origin: Vector2 = BagGrid.origin_of(at)
	var cell_px: float = float(BagGrid.CELL)
	var want := Rect2(origin + Vector2(float(cell.x), float(cell.y)) * cell_px, Vector2(float(int(d.get("w", 1))), float(int(d.get("h", 1)))) * cell_px)
	var grid := Rect2(origin, Vector2(float(int(column.get("w", 0))), float(int(column.get("h", 0)))) * cell_px)
	return want.intersection(grid)


# Drawn by the ghost, under the held plate: hazard stripes over the cells a refused drop would
# cover, a green outline over the cells an accepted one would. The ghost sits at the sheet's
# origin, so a sheet rect is a ghost rect; the transfer window's rects are shifted by where the
# window stands.
func _draw_drop_hint_into(ci: CanvasItem) -> void:
	if _drag_item == -1:
		return
	var hint: Dictionary = {}
	var shift: Vector2 = Vector2.ZERO
	if _open:
		hint = drop_hint(get_local_mouse_position())
	elif loot_open():
		var window: Control = _loot_layer as Control
		hint = _drop_verdict(_loot_places(), window.get_local_mouse_position())
		shift = window.position
	var r: Rect2 = hint.get("rect", Rect2()) as Rect2
	if not r.has_area():
		return
	r.position += shift
	if bool(hint.get("fit", false)):
		Locker.fit(ci, r)
	elif int(hint.get("shape", Input.CURSOR_MOVE)) == Input.CURSOR_FORBIDDEN:
		Locker.refuse(ci, r)
	else:
		Locker.accept(ci, r)


# The held item itself, centred on the pointer: its plate, tinted by its kind, and its picture at
# the size it has in a bag, turned the way the drag is turned.
func _draw_ghost_into(ci: CanvasItem, at: Vector2) -> void:
	if _world == null or _drag_item == -1:
		return
	var d: Dictionary = SimInventory.view_of(_world, _drag_item, {"rotated": _drag_rotated})
	var px := Vector2(float(int(d.get("w", 1)) * BagGrid.CELL), float(int(d.get("h", 1)) * BagGrid.CELL))
	var plate := Rect2((at - px / 2.0) + Vector2(Locker.PX, Locker.PX), px - Vector2(Locker.PX, Locker.PX) * 2.0)
	var base: String = ItemPicture.base_of(_world, _drag_item)
	Locker.plate(ci, plate, BagGrid.class_of(_world, base), 0.85)
	ItemPicture.draw(ci, plate.grow(-Locker.PX), Appearance.item_look(_world, base), 0.95)


func _begin_drag(item: int, rotated: bool, dims: Vector2i) -> void:
	_drag_item = item
	_drag_rotated = rotated
	_drag_dims = dims
	_close_menu()
	_redraw_columns()


func _cancel_drag() -> void:
	_drag_item = -1
	_drag_rotated = false
	if _ghost != null:
		_ghost.queue_redraw()


# How tall the bags stand in the tallest lane, so the wheel knows how far there is to scroll.
func _column_height() -> float:
	var total: float = 0.0
	var top: float = _column_rect().position.y - _scroll
	for placed in _column_places():
		var d: Dictionary = placed["column"] as Dictionary
		var bottom: float = (placed["at"] as Vector2).y + BagGrid.size_of(int(d.get("w", 0)), int(d.get("h", 0))).y
		total = maxf(total, bottom - top)
	return total


# --- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	# Cleared before the early returns, not inside the body: a closed screen has no clickable
	# words and no placed grids, and rects left over from the last frame it was open would still
	# be hit-testable.
	_hit.clear()
	_placed.clear()
	var view: Vector2 = get_viewport_rect().size
	# The strip is drawn whether the sheet is open or not, and that is the whole reason the
	# pinnable pouches could be deleted: what is on your belt and in your pockets is on screen
	# during play, and a number key spends one. Drawing it from the closed sheet is free -- this
	# Control ignores the mouse while closed, so nothing here can eat a click meant for the world.
	if not _open:
		if _world != null and not _view.is_empty() and not strip_hidden:
			QuickStrip.draw_strip(self, QuickStrip.rect_for(view, PAD, STRIP_H), SimInventory.quick_strip_view(_world, _actor), UiPrefs.opacity("inventory_opacity"), _selected, _ping_view(), _world)
		return
	draw_rect(Rect2(Vector2.ZERO, view), Locker.WASH)
	var alpha: float = UiPrefs.opacity("inventory_opacity")
	var font: Font = Chrome.font()
	if _view.is_empty():
		draw_string(font, Vector2(PAD, PAD + 32.0), "no inventory", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Locker.TEXT_DIM)
		return
	_draw_top(font, alpha)
	_draw_body(font, alpha)
	if _column_layer != null:
		var area: Rect2 = _column_rect()
		_column_layer.position = area.position
		_column_layer.size = area.size
		_column_layer.queue_redraw()
	_draw_list(font, alpha)
	if _inspect_rect().has_area():
		if _showing_part():
			CarePane.draw_pane(self, _inspect_rect(), _care_view(), alpha)
		else:
			InspectPane.draw_pane(self, _inspect_rect(), _inspect_view(), alpha, _pane_verbs(), name_field(), _world)
	QuickStrip.draw_strip(self, QuickStrip.rect_for(view, PAD, STRIP_H), SimInventory.quick_strip_view(_world, _actor) if _world != null else [], alpha, _selected, _ping_view(), _world)
	ItemMenu.draw_menu(self, _menu_at, _menu_verbs, alpha)


# Whether the inspect slot is talking about a body part rather than an item: a part is picked and
# no item has been picked since.
func _showing_part() -> bool:
	return _selected == -1 and not _part.is_empty()


# The picked part as the care pane draws it: the player's hands on this sheet's survivor.
func _care_view() -> Dictionary:
	if _world == null or _part.is_empty():
		return {}
	return CarePane.view_for(_world, int(_world.player), _actor, _part)


# Escape, asked by `input_map.gd` before it closes the sheet: put down the one thing in front -- a
# lifted item, the word menu, a picked part -- and say so. False when there was nothing, and the
# sheet itself is what goes.
func escape() -> bool:
	if _naming != -1:
		_end_naming()
		return true
	if _drag_item != -1:
		_cancel_drag()
		_redraw_columns()
		return true
	if _menu_item != -1:
		_close_menu()
		return true
	if not _part.is_empty():
		_part = ""
		_redraw_columns()
		return true
	return false


func _inspect_view() -> Dictionary:
	if _world == null or _selected < 0:
		return {}
	return SimInventory.inspect_view(_world, _actor, _selected)


# The title bar is the shared navigation bar (ui/nav_bar.gd): the three tabs with Survivor lit, whose
# sheet this is, and the close control at the far end. The sheet's own line -- a notice when one is
# up, else the hint -- sits in the room the bar leaves between the two.
func _draw_top(font: Font, alpha: float) -> void:
	var top: Rect2 = _top_rect()
	var laid: Dictionary = NavBar.draw_bar(self, top, "survivor", _whose_name(), _is_you(), alpha, _compact())
	var x: float = float(laid.get("left", top.position.x))
	var right: float = float(laid.get("right", top.end.x))
	var mid: float = top.position.y + top.size.y / 2.0
	# A notice, when one is up, takes the hint line's place: it is the thing to read right now.
	var line: String = _notice
	var col: Color = Locker.DANGER if _notice_bad else Locker.GOOD
	if line.is_empty() and _naming != -1:
		line = NAME_HINT
		col = Locker.TEXT_DIM
	elif line.is_empty():
		line = "drag to move · right-click for what you can do · ctrl-click sends · R turns it · click the body for care"
		if _compact():
			line = "drag · right-click · click the body for care · ctrl-click sends · R turns"
		col = Locker.TEXT_FAINT
	var hint_base: float = floorf(mid - Chrome.line_height(HINT_SIZE) / 2.0 + Chrome.ascent(HINT_SIZE))
	var fitted: String = UiText.fit(font, line, HINT_SIZE, maxf(0.0, right - x))
	var lw: float = font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
	draw_string(font, Vector2(right - lw, hint_base), fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE, col)


# The navigation bar as it stands this frame, for a click: `NavBar.layout`, the same placement the
# draw used.
func _nav_layout() -> Dictionary:
	return NavBar.layout(_top_rect(), "survivor", _whose_name(), _is_you(), _compact())


func _is_you() -> bool:
	return _world == null or _actor == int(_world.player)


# The sheet's survivor by name, as the bar shows it: "" where the roster gave none, and the bar's
# stamp says whether it is you.
func _whose_name() -> String:
	if _world == null or _actor < 0:
		return ""
	var ident: Variant = _world.components.get_component(_actor, "identity")
	return String((ident as Dictionary).get("name", "")) if ident is Dictionary else ""


func _draw_body(font: Font, alpha: float) -> void:
	var body: Rect2 = _body_rect()
	Locker.panel(self, body, alpha)
	Locker.header(self, body, "worn", alpha, "", Chrome.GLYPH_SMALL + Locker.PX * 3.0)
	Chrome.glyph(self, "condition", Vector2(body.end.x - Chrome.GLYPH_SMALL - Locker.PX * 5.0, body.position.y + Locker.PX * 2.0 + floorf((Locker.TAPE_H - Chrome.GLYPH_SMALL) / 2.0)), true, alpha * 0.7)
	# One screen (the owner's call, 2026-08-19): the doll carries injuries and armour, the slots
	# flank it, and anything wrong with the body reads as prose below the figure.
	_place_doll()
	_paperdoll.set("selected_part", _part if _showing_part() else "")
	_paperdoll.visible = true
	for box in _slot_boxes():
		var rect: Rect2 = box["rect"] as Rect2
		var slot: String = String(box["slot"])
		var it: Variant = _slot_item(slot)
		Locker.well(self, rect, alpha)
		if it is Dictionary:
			var d: Dictionary = it as Dictionary
			var plate: Rect2 = rect.grow(-Locker.PX)
			var base: String = String(d.get("baseId", ""))
			if base.is_empty():
				base = ItemPicture.base_of(_world, int(d.get("item", -1)))
			Locker.plate(self, plate, BagGrid.class_of(_world, base), alpha)
			if _world != null:
				ItemPicture.draw(self, plate.grow(-Locker.PX), Appearance.item_look(_world, base), alpha)
			if int(d.get("item", -1)) == _selected:
				Locker.selected(self, plate, alpha)
		else:
			# An empty slot draws what goes there: the equipment glyph names the slot the same way
			# the word under it does. Ornament, not a replacement -- the word stays, and the glyph is
			# dimmed to sit back in the well (docs/30, "The UI Field Kit, live": no status icons, no
			# readout the word does not already say).
			Chrome.glyph(self, slot, (rect.get_center() - Vector2(12.0, 12.0)).round(), false, alpha * 0.35)
		# The word under the slot on a full window: the item's name when something is in it, the
		# slot's when not. A compact sheet has no room between slot and figure, and the picture and
		# the glyph carry it there.
		if not _compact():
			var left: bool = LEFT_SLOTS.has(slot)
			var label: String = slot
			var col: Color = Locker.TEXT_FAINT
			if it is Dictionary:
				label = String((it as Dictionary).get("name", slot))
				col = Locker.TEXT_DIM
			var room: float = (body.get_center().x - DOLL_W / 2.0) - rect.position.x if left else rect.end.x - (body.get_center().x + DOLL_W / 2.0)
			label = UiText.fit(font, label, SLOT_WORD_SIZE, room - 4.0)
			var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SLOT_WORD_SIZE).x
			var lx: float = rect.position.x if left else rect.end.x - lw
			draw_string(font, Vector2(lx, rect.end.y + Chrome.ascent(SLOT_WORD_SIZE) + 2.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, SLOT_WORD_SIZE, col)
	# Condition prose gets its own measured rows below the equipment. The wheel over the
	# survivor panel reaches every row when wounds need more room than the readout has.
	var rows: Array[Dictionary] = _condition_rows()
	var area: Rect2 = _condition_rect()
	Locker.groove(self, Vector2(body.position.x + Locker.PX * 4.0, area.position.y - 12.0), body.size.x - Locker.PX * 8.0, alpha)
	var capacity: int = _condition_capacity()
	_condition_scroll = clampi(_condition_scroll, 0, maxi(0, rows.size() - capacity))
	var text_size: int = 20 if _compact() else 25
	var line_h: float = 22.0 if _compact() else 28.0
	for i in mini(capacity, rows.size() - _condition_scroll):
		var row: Dictionary = rows[_condition_scroll + i]
		var text: String = String(row["text"])
		draw_string(font, Vector2(area.position.x, area.position.y + Chrome.ascent(text_size) + float(i) * line_h), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, row["colour"] as Color)
	if rows.size() > capacity:
		var more: String = "wheel for more" if _condition_scroll < rows.size() - capacity else "wheel back up"
		var mw: float = font.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
		draw_string(font, Vector2(area.end.x - mw, area.position.y - 18.0), more, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE, Locker.TEXT_FAINT)
	_draw_responses(font, body, area.end.y + (24.0 if _compact() else 30.0))


func _condition_rect() -> Rect2:
	var body: Rect2 = _body_rect()
	var last: Rect2 = slot_rect(body, 0, LEFT_SLOTS.size() - 1)
	var top: float = last.end.y + (22.0 if _compact() else 30.0) + 12.0
	if not _compact():
		top = maxf(top, body.position.y + Locker.HEAD_H + 8.0 + DOLL_H + 24.0)
	var rows: int = CONDITION_ROWS_COMPACT if _compact() else CONDITION_ROWS
	var line_h: float = 22.0 if _compact() else 28.0
	var reserved: float = 40.0 if _world != null and not SimTreatment.response_view(_world, _actor).is_empty() else 12.0
	var tall: float = minf(float(rows) * line_h, maxf(0.0, body.end.y - reserved - top))
	return Rect2(Vector2(body.position.x + SLOT_INSET, top), Vector2(body.size.x - SLOT_INSET * 2.0, tall))


func _condition_capacity() -> int:
	return maxi(1, floori(_condition_rect().size.y / (22.0 if _compact() else 28.0)))


func _condition_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var text_size: int = 20 if _compact() else 25
	for row in _condition_lines():
		for line in InspectPane._wrap(Chrome.font(), String(row["text"]), text_size, _condition_rect().size.x):
			out.append({"text": line, "colour": row["colour"]})
	if out.is_empty():
		out.append({"text": "no injuries", "colour": Locker.TEXT_DIM})
	return out


# The list down the right: everything on the sheet, a row a thing, under chips that narrow it by
# kind. A row is a handle on the same item a plate is -- click selects it for the inspect pane and
# rings its plate, drag lifts it, right-click asks for its verbs, ctrl-click sends it.
func _draw_list(font: Font, alpha: float) -> void:
	var list: Rect2 = _list_rect()
	if not list.has_area():
		return
	Locker.panel(self, list, alpha)
	var rows: Array[Dictionary] = _list_rows()
	# The header's note says there is more below when there is, rather than a line under the last
	# row that the row itself would have to make room for.
	Locker.header(self, list, "contents", alpha, "wheel for more" if rows.size() > _list_capacity() else "in reach")
	for chip in _chip_rects():
		var i: int = int(chip["index"])
		Locker.chip(self, chip["rect"] as Rect2, String((FILTERS[i] as Array)[0]), i == _filter, alpha)
	var hits: Array[Dictionary] = _list_hits()
	# "Nothing in reach" only when nothing is: a list with no room for a row is not an empty list.
	if rows.is_empty():
		draw_string(font, Vector2(list.position.x + Locker.PX * 6.0, _list_rows_top() + 28.0), "nothing of that kind in reach" if _filter != 0 else "nothing in reach", HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_NOTE_SIZE, Locker.TEXT_FAINT)
	for n in hits.size():
		var r: Rect2 = hits[n]["rect"] as Rect2
		var row: Dictionary = hits[n]["row"] as Dictionary
		var picked: bool = int(row["item"]) == _selected
		if picked:
			draw_rect(r, Color(Locker.ACCENT.r, Locker.ACCENT.g, Locker.ACCENT.b, 0.18 * alpha))
			draw_rect(r, Color(Locker.ACCENT.r, Locker.ACCENT.g, Locker.ACCENT.b, minf(1.0, alpha)), false, Locker.PX)
		elif (_list_scroll + n) % 2 == 1:
			draw_rect(r, Color(1.0, 1.0, 1.0, 0.03 * alpha))
		# A chip of the plate's tint, so a row and its plate read as the same kind of thing.
		draw_rect(Rect2(r.position + Vector2(Locker.PX, Locker.PX * 2.0), Vector2(Locker.PX * 2.0, r.size.y - Locker.PX * 4.0)), Locker.tint_of(String(row["class"])).lightened(0.25))
		var icon := Rect2(r.position + Vector2(Locker.PX * 5.0, (r.size.y - LIST_ICON) / 2.0), Vector2(LIST_ICON, LIST_ICON))
		if _world != null:
			ItemPicture.draw(self, icon, Appearance.item_look(_world, String(row["baseId"])), alpha, 1, false)
		var note: String = String(row["where"])
		if int(row["count"]) > 1:
			note += "  x%d" % int(row["count"])
		var nw: float = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_NOTE_SIZE).x
		var mid: float = r.position.y + r.size.y / 2.0
		var name_x: float = icon.end.x + Locker.PX * 4.0
		var name: String = UiText.fit(font, String(row["name"]), LIST_NAME_SIZE, r.end.x - Locker.PX * 6.0 - nw - name_x)
		draw_string(font, Vector2(name_x, floorf(mid - Chrome.line_height(LIST_NAME_SIZE) / 2.0 + Chrome.ascent(LIST_NAME_SIZE))), name, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_NAME_SIZE, Locker.TEXT)
		draw_string(font, Vector2(r.end.x - nw - Locker.PX * 3.0, floorf(mid - Chrome.line_height(LIST_NOTE_SIZE) / 2.0 + Chrome.ascent(LIST_NOTE_SIZE))), note, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_NOTE_SIZE, Locker.TEXT_DIM)


# Called by the clipped child, and drawing into it: `at` is built in sheet coordinates so the
# placement list the hit test walks is the same arithmetic, then shifted by the child's own origin
# at the moment of drawing. One layout, two frames of reference, and the translation is one line.
func _draw_columns_into(ci: CanvasItem) -> void:
	var alpha: float = UiPrefs.opacity("inventory_opacity")
	var area: Rect2 = _column_rect()
	_placed = _column_places()
	var origin_for_selected: Variant = null
	for placed in _placed:
		var d: Dictionary = placed["column"] as Dictionary
		var box: Vector2 = BagGrid.size_of(int(d.get("w", 0)), int(d.get("h", 0)))
		var at: Vector2 = placed["at"] as Vector2
		# Only what is on screen, so a deep loadout scrolls rather than painting under the strip.
		if at.y + box.y > area.position.y and at.y < area.position.y + area.size.y:
			var note: String = ""
			var id: int = int(d.get("container", -1))
			if id == _actor:
				note = "on you"
			elif _opened.has(id):
				note = "opened"
			elif not _open_here().is_empty() and id == int(_open_here().get("container", -2)):
				note = "here"
			else:
				note = _slot_of(id)
			BagGrid.draw_bag(ci, at - area.position, d, alpha, _drag_item, note, _world, Callable(self, "_matches") if _filter != 0 else Callable())
			var sel: Variant = _selected_in(d)
			if sel is Dictionary:
				origin_for_selected = {"origin": BagGrid.origin_of(at - area.position), "item": sel}
	# There is no scrollbar on this screen and there is not going to be one, so the one thing the
	# wheel does has to be said out loud when it matters.
	if _column_height() > area.size.y:
		var font2: Font = Chrome.font()
		var more: String = "wheel to scroll"
		var nw: float = font2.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
		ci.draw_rect(Rect2(Vector2(area.size.x - nw - 16.0, area.size.y - 28.0), Vector2(nw + 16.0, 28.0)), Color(0.0, 0.0, 0.0, 0.6))
		ci.draw_string(font2, Vector2(area.size.x - nw - 8.0, area.size.y - 8.0), more, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE, Locker.TEXT_DIM)
	# The selection ring last, so it is never painted over by the next bag's panel.
	if origin_for_selected is Dictionary and _drag_item != _selected:
		var o: Dictionary = origin_for_selected as Dictionary
		if _pulse_item != _selected:
			_pulse_item = _selected
			_pulse_since_ms = Time.get_ticks_msec()
		_pulse_frame = BagGrid.draw_item(ci, o["origin"] as Vector2, o["item"] as Dictionary, alpha, true, _world, _pulse_elapsed())
	else:
		# Nothing selected on screen (none, or scrolled away): no pulse, so nothing to redraw for.
		_pulse_item = -1


# Every column's panel origin, {at, column}, in sheet coordinates: each lane's bags laid left to
# right and wrapped, a BAG_GAP apart, from the scroll. The one arithmetic -- the draw keeps what it
# returns as `_placed` for the hit test, and the pointer asks it directly. In the column's own
# order, lane by lane, so a press finds the same bag the eye does.
func _column_places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lane in _lanes():
		var r: Rect2 = lane["rect"] as Rect2
		var x: float = r.position.x
		var y: float = r.position.y - _scroll
		var row_h: float = 0.0
		for column in lane["columns"] as Array:
			var d: Dictionary = column as Dictionary
			var box: Vector2 = BagGrid.size_of(int(d.get("w", 0)), int(d.get("h", 0)))
			if x > r.position.x and x + box.x > r.end.x:
				x = r.position.x
				y += row_h + BAG_GAP
				row_h = 0.0
			out.append({"at": Vector2(x, y), "column": d})
			x += box.x + BAG_GAP
			row_h = maxf(row_h, box.y)
	return out


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
	var text_size: int = 20 if _compact() else 25
	var rows: Array = SimTreatment.response_view(_world, _actor)
	if rows.is_empty():
		return
	var lead: String = "you could "
	var sep: String = " · "
	# Centred by measurement, the way the condition lines above are, rather than nudged by a
	# constant: a second response one day must not push the first off centre.
	var total: float = font.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	for i in rows.size():
		total += font.get_string_size(String((rows[i] as Dictionary).get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		if i < rows.size() - 1:
			total += font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var at: float = roundf(body.position.x + body.size.x / 2.0 - total / 2.0)
	draw_string(font, Vector2(at, y), lead, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Chrome.TEXT_DIM)
	at += font.get_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	for i in rows.size():
		var row: Dictionary = rows[i] as Dictionary
		var word: String = String(row.get("text", ""))
		draw_string(font, Vector2(at, y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Chrome.ACCENT)
		_hit.append({"rect": _word_rect(font, Vector2(at, y), word, text_size), "verb": String(row.get("verb", ""))})
		at += font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		if i < rows.size() - 1:
			draw_string(font, Vector2(at, y), sep, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Chrome.TEXT_DIM)
			at += font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x


# The one place a word's extent is measured, so the rectangle that is drawn and the rectangle that
# is clicked cannot drift apart. Same shape as work_panel.gd's, which set the convention.
func _word_rect(font: Font, at: Vector2, word: String, font_size: int) -> Rect2:
	var w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# The typeface's own ascent and line height (Chrome's, which a fallback cannot stretch), not a
	# fraction of the size: the fraction was the engine font's, and VT323's line is a fifth shorter.
	return Rect2(Vector2(at.x, at.y - Chrome.ascent(font_size)), Vector2(w, Chrome.line_height(font_size)))


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
