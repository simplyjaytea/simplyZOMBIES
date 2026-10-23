extends Control
# The skill web, drawn as a web: six regions round a hub, the nodes where the content puts them,
# lines where the focus paths run, and one survivor's history laid over it -- what they know
# bright, what they could learn amber, what they have not touched dim, and each region warm or
# faint by whether they have ever earned anything in it.
#
# It draws two things and computes neither. Layout comes from the content through
# `SimSkills.definition()` and `ui/web_layout.gd`; the survivor's standing comes from
# `SimSkills.web_map`, which carries words and booleans and nothing a number could be rebuilt
# from -- no cost, no point total, no count. An affordable node is simply in the "learnable"
# state; one that is not is "unknown". That is `web_view`'s rule (docs/30, "Who manages a
# survivor's skill web"), and this screen is the same rule with geometry.
#
# Every click goes through the command queue, `work_panel.gd`'s rule: a learnable node pushes
# `web.buy` and nothing here reaches into the sim. main.gd re-pulls the map every frame it is
# open, so the disc turns bright on the tick the buy lands.

const SimSkills = preload("res://sim/modules/skills.gd")
const WebLayout = preload("res://ui/web_layout.gd")
const UiText = preload("res://ui/text.gd")
const Chrome = preload("res://ui/chrome.gd")
const Locker = preload("res://ui/locker.gd")

# The web's square inside the panel: where the unit square lands, in pixels. The panel is wider
# than the square so a name beside a rim node has room to the left or the right of it.
const WEB_Y: float = 64.0
const WEB_SIDE: float = 600.0
# Even radii, with centres snapped to even pixels (`_at`), so every disc starts on the screen's
# two-pixel art grid.
const NODE_R: float = 8.0
# The hub's dot. The lines are drawn in whole 2x2 art pixels (`line_blocks`), so they need no width.
const HUB_R: float = 4.0
# A dotted line's dash and gap, in art pixels.
const DASH: int = 3
# A keystone's disc, and the ring outside it: the one thing on the web that costs something.
const KEY_R: float = 12.0
const RING_GAP: float = 4.0
# What is not yours yet -- a locked node's name, a region not lived in, the footer -- in an ink that
# still reads on the locker's steel: about 4.6:1 against it, where the kit's faint ink was 1.9:1.
const LOCKED_INK: Color = Color8(146, 140, 130)
# The least room between two labels, or a label and a disc that is not its own.
const LABEL_CLEAR: float = 8.0
# The rows a crowded name may move, in order: its own row first, then a little down or up.
const LABEL_TRIES: Array[float] = [0.0, 12.0, -12.0, 22.0, -22.0]
# Every word on the web at the ladder's smallest rung (ui/chrome.gd's LADDER): twenty-odd names
# round a 600 px web is the densest text in the game.
const PRICE_SIZE: int = 20
const PRICE_DY: float = 18.0
const NAME_GAP: float = 10.0
const NAME_SIZE: int = 20
const REGION_SIZE: int = 20
const FOOTER_SIZE: int = 20
# Half the fan a region is drawn as: six regions, sixty degrees each.
const FAN_HALF: float = PI / 6.0
const FAN_RADIUS: float = 0.5

var _world: Variant = null
var _who: int = -1
var _map: Dictionary = {}
var _def: Dictionary = {}
# Click targets, {rect, node}, rebuilt by every draw from `layout_hits` and read by _gui_input.
var _hit: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func set_world(world: Variant, who: int) -> void:
	_world = world
	_who = who
	_map = SimSkills.web_map(world, who) if world != null else {}
	_def = SimSkills.definition() if world != null else {}
	queue_redraw()


# --- what a gate can ask without a draw pass ---------------------------------------------------


func map() -> Dictionary:
	return _map


# The survivor this web belongs to: the one selected on the street, or "you". The navigation bar
# over the screen carries it now (with its "you" or "viewing" stamp), so the panel's own tape says
# only what the panel is (`TAPE_WORD`) and this is the bar's subject as the web sees it -- the gate
# holds the two to the same person.
func header_label() -> String:
	var who: String = String(_map.get("who", ""))
	if _world != null and _who == int(_world.player):
		who = "you"
	if who.is_empty():
		who = "nobody"
	return "skill web — " + who


const TAPE_WORD: String = "skill web"
# The size the web is laid out at; main.gd makes the panel shorter to fit a smaller window, and the
# web inside it shrinks with it (`_side`).
const NATURAL: Vector2 = Vector2(1040.0, 760.0)


func footer() -> String:
	if _map.is_empty():
		return "nothing to show — esc to close"
	if bool(_map.get("manual", false)):
		# Your own web is yours by construction (SimSkills._focus_of): no focus word, nobody
		# spends it for you. A colonist's reads manual only because you set them so.
		if _world != null and _who == int(_world.player):
			return "amber: could learn now, click it · this web is yours and nobody spends it for you · a bright line: a path you have walked · dotted: no focus leads there · ringed: a keystone, it costs something · esc closes"
		return "amber: could learn now, click it · a bright line: a path they have walked · dotted: no focus leads there · ringed: a keystone, it costs something · esc closes"
	var who: String = String(_map.get("who", ""))
	if _world != null and _who == int(_world.player):
		who = "you"
	if who.is_empty():
		who = "they"
	return "%s %s on %s own path — set them to manual on the work grid to choose for them · esc to close" % [
		who, "are" if who == "you" else "is", "your" if who == "you" else "their"]


# The footer as the panel draws it: broken at its " · " separators into at most two lines that fit
# `wide`, the second fitted if it still runs over.
func footer_lines(font: Font, wide: float) -> Array[String]:
	var parts: PackedStringArray = footer().split(" · ")
	var out: Array[String] = [""]
	for part in parts:
		var line: String = out[out.size() - 1]
		var joined: String = part if line.is_empty() else line + " · " + part
		if line.is_empty() or font.get_string_size(joined, HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE).x <= wide or out.size() >= 2:
			out[out.size() - 1] = joined
		else:
			out.append(part)
	return out


# Every string the draw pass writes on the panel, for the gate's digit and raw-key scans.
func words() -> Array[String]:
	var out: Array[String] = [header_label(), "start"]
	for r in _map.get("regions", []) as Array:
		out.append(String((r as Dictionary).get("region", "")).to_lower())
	for n in _map.get("nodes", []) as Array:
		out.append(String((n as Dictionary).get("name", "")))
		var price: String = String((n as Dictionary).get("price", ""))
		if not price.is_empty():
			out.append(price)
	out.append(footer())
	return out


# The click targets: one per learnable node, the disc and its name together. Pure over the map,
# the layout and the panel's size, so a gate can ask for them with no draw pass having run.
func layout_hits() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var font: Font = Chrome.font()
	var pos: Dictionary = WebLayout.positions(_def)
	for n in _map.get("nodes", []) as Array:
		var nd: Dictionary = n as Dictionary
		if String(nd.get("state", "")) != "learnable":
			continue
		var nid: String = String(nd.get("node", ""))
		if not pos.has(nid):
			continue
		var at: Vector2 = _at(pos[nid] as Vector2)
		var key: bool = bool(nd.get("keystone", false))
		var r: float = KEY_R + RING_GAP if key else NODE_R
		var disc := Rect2(at - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		var placed: Dictionary = _name_placement(font, pos[nid] as Vector2, String(nd.get("name", "")), r)
		var rect: Rect2 = disc.merge(placed["rect"] as Rect2)
		if key and not String(nd.get("price", "")).is_empty():
			var priced: Dictionary = _price_placement(font, pos[nid] as Vector2, String(nd.get("price", "")), r)
			rect = rect.merge(priced["rect"] as Rect2)
		out.append({"rect": rect, "node": nid})
	return out


# --- input -------------------------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return
	# A click on the panel is a click on the panel, never a swing at the street behind it.
	accept_event()
	if mb.button_index != MOUSE_BUTTON_LEFT or _world == null:
		return
	for h in _hit:
		if (h["rect"] as Rect2).has_point(mb.position):
			_act(String(h["node"]))
			return


func _act(node: String) -> void:
	if _world == null or node.is_empty():
		return
	_world.commands.push({"type": "web.buy", "entity": _who, "node": node})


# --- geometry ----------------------------------------------------------------------------------


# The one mapping from the content's unit square to the panel's pixels.
func _at(unit: Vector2) -> Vector2:
	var span: Vector2 = _span()
	var raw := Vector2(size.x / 2.0 - span.x / 2.0 + unit.x * span.x, WEB_Y + unit.y * span.y)
	return (raw / 2.0).round() * 2.0


# The web's width and height on this panel. Only the height gives way on a short window
# (`_side`); the width stays WEB_SIDE while the panel is wide enough, because the names run
# sideways and a web squeezed in both directions put them on top of each other at 1280x720
# (UI review, round 2). The web reads a little wide there, and every name keeps its room.
func _span() -> Vector2:
	return Vector2(minf(WEB_SIDE, maxf(_side(), size.x - (NATURAL.x - WEB_SIDE))), _side())


# The web's side on this panel: WEB_SIDE at the natural size, and smaller on a panel main.gd had to
# make shorter to fit a 1280x720 window -- the words stay at their size and only the web between
# them shrinks, because a pixel face scaled by a fraction breaks its letters. The room under the
# web is what the natural layout leaves for the bottom labels and the footer.
func _side() -> float:
	return clampf(size.y - (NATURAL.y - WEB_SIDE), WEB_SIDE * 0.6, WEB_SIDE)


# A disc or ring in whole 2x2 art pixels: every cell whose centre lies within `r_out` of `at` and
# beyond `r_in`. `at` and both radii are even, so the shape's box starts and ends on even pixels
# and its edge steps by a whole art pixel, where `draw_circle` drew a smooth outline with 1 px
# stairs on odd edges (UI review, round 3). Rows are drawn as runs, a rect each.
func _blocks(at: Vector2, r_out: float, r_in: float, col: Color) -> void:
	for run in block_runs(r_out, r_in):
		draw_rect(Rect2(at + (run as Rect2).position, (run as Rect2).size), col)


# A line from `a` to `b` in whole 2x2 art pixels, `dash` art pixels on and as many off when it is
# dotted (0 for solid). UI review, slice 1's leftovers: a smooth two-pixel line stepped a screen
# pixel per row on a diagonal, and a dashed one could start on an odd row; this one steps a whole
# art pixel, so every block is on the even grid whatever the angle.
func _line(a: Vector2, b: Vector2, col: Color, dash: int = 0) -> void:
	for r in line_blocks(a, b, dash):
		draw_rect(r as Rect2, col)


# The blocks of `_line`, absolute: both ends snapped down to the even grid, then Bresenham's walk in
# art-pixel steps, one block per step, with blocks that touch along a row or a column merged into
# one rect. Static so the gate can hold what is drawn to the grid without a screen.
static func line_blocks(a: Vector2, b: Vector2, dash: int = 0) -> Array[Rect2]:
	var p: float = Locker.PX
	var x0: int = floori(a.x / p)
	var y0: int = floori(a.y / p)
	var x1: int = floori(b.x / p)
	var y1: int = floori(b.y / p)
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var cells: Array[Vector2i] = []
	var step: int = 0
	while true:
		if dash <= 0 or (step / dash) % 2 == 0:
			cells.append(Vector2i(x0, y0))
		step += 1
		if x0 == x1 and y0 == y1:
			break
		var e2: int = err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	var out: Array[Rect2] = []
	for c in cells:
		var r := Rect2(Vector2(float(c.x) * p, float(c.y) * p), Vector2(p, p))
		if not out.is_empty():
			var last: Rect2 = out[out.size() - 1]
			if last.position.y == r.position.y and last.size.y == p and (r.position.x == last.end.x or r.end.x == last.position.x):
				out[out.size() - 1] = last.merge(r)
				continue
			if last.position.x == r.position.x and last.size.x == p and (r.position.y == last.end.y or r.end.y == last.position.y):
				out[out.size() - 1] = last.merge(r)
				continue
		out.append(r)
	return out


# The rows of `_blocks`' shape, relative to its centre: one rect per run of art pixels. Static so
# the gate can hold what is drawn to the grid without a screen.
static func block_runs(r_out: float, r_in: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var p: float = Locker.PX
	var cy: float = -r_out
	while cy < r_out:
		var run_from: float = INF
		var cx: float = -r_out
		while cx <= r_out:
			var inside: bool = false
			if cx < r_out:
				var d: float = Vector2(cx + p / 2.0, cy + p / 2.0).length()
				inside = d <= r_out and d > r_in
			if inside and run_from == INF:
				run_from = cx
			elif not inside and run_from != INF:
				out.append(Rect2(Vector2(run_from, cy), Vector2(cx - run_from, p)))
				run_from = INF
			cx += p
		cy += p
	return out


# The outer box of every disc and ring the web draws -- the hub's dot, each node, each keystone's
# ring -- for the gate that holds them to the even grid.
func disc_boxes() -> Array[Rect2]:
	var out: Array[Rect2] = [Rect2(_at(WebLayout.HUB) - Vector2(HUB_R, HUB_R), Vector2(HUB_R, HUB_R) * 2.0)]
	if _def.is_empty():
		return out
	var pos: Dictionary = WebLayout.positions(_def)
	for n in _map.get("nodes", []) as Array:
		var nd: Dictionary = n as Dictionary
		var nid: String = String(nd.get("node", ""))
		if not pos.has(nid):
			continue
		var r: float = KEY_R + RING_GAP if bool(nd.get("keystone", false)) else NODE_R
		out.append(Rect2(_at(pos[nid] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	return out


# The one place a word's extent is measured, so the rectangle drawn and the rectangle clicked
# cannot drift apart (work_panel.gd's rule).
func _word_rect(font: Font, at: Vector2, word: String, font_size: int) -> Rect2:
	var w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# The typeface's own ascent and line height (Chrome's, which a fallback cannot stretch), not a
	# fraction of the size: the fraction was the engine font's, and VT323's line is a fifth shorter.
	return Rect2(Vector2(at.x, at.y - Chrome.ascent(font_size)), Vector2(w, Chrome.line_height(font_size)))


# Where a node's name goes: to the right of the disc on the web's right half, ending to the left
# of it on the left half, fitted to whatever room the panel has on that side.
#
# On a web shrunk to fit a small window, names that would land on another name or on somebody
# else's disc try the other side, then a row down or up (`_label_plan`); the first spot that keeps
# LABEL_CLEAR all round wins. At the natural size every name keeps its first spot.
func _name_placement(font: Font, unit: Vector2, name: String, radius: float = NODE_R) -> Dictionary:
	var plan: Dictionary = _label_plan(font)
	var spot: Dictionary = plan.get(unit, {}) as Dictionary
	return _beside(font, unit, name, radius, NAME_SIZE, float(spot.get("dy", 0.0)), int(spot.get("side", 0)))


# A keystone's price, in words, on the row under its name and on the same side.
func _price_placement(font: Font, unit: Vector2, price: String, radius: float) -> Dictionary:
	var plan: Dictionary = _label_plan(font)
	var spot: Dictionary = plan.get(unit, {}) as Dictionary
	return _beside(font, unit, price, radius, PRICE_SIZE, PRICE_DY + float(spot.get("dy", 0.0)), int(spot.get("side", 0)))


var _plan_key: String = ""
var _plan: Dictionary = {}


# Where each node's name goes, keyed by the node's unit position: {side: -1 left, 1 right, 0 the
# default for its half; dy: rows moved}. Cached per panel size and map, since the draw, the click
# targets and the gate all ask.
func _label_plan(font: Font) -> Dictionary:
	var key: String = "%s|%s|%d" % [str(size), str(_map.get("who", "")), (_map.get("nodes", []) as Array).size()]
	if key == _plan_key:
		return _plan
	_plan_key = key
	_plan = {}
	if _def.is_empty():
		return _plan
	var pos: Dictionary = WebLayout.positions(_def)
	var names: Dictionary = {}
	var keys: Dictionary = {}
	var prices: Dictionary = {}
	for n in _map.get("nodes", []) as Array:
		var nd: Dictionary = n as Dictionary
		names[String(nd.get("node", ""))] = String(nd.get("name", ""))
		keys[String(nd.get("node", ""))] = bool(nd.get("keystone", false))
		prices[String(nd.get("node", ""))] = String(nd.get("price", ""))
	var discs: Array[Rect2] = []
	var ids: Array = pos.keys()
	ids.sort()
	for nid in ids:
		var r: float = KEY_R + RING_GAP if bool(keys.get(nid, false)) else NODE_R
		discs.append(Rect2(_at(pos[nid] as Vector2) - Vector2(r, r), Vector2(r * 2.0, r * 2.0)))
	# The fixed words go in first: the region words and "start" do not move, so a name gives way
	# to them rather than landing on one.
	var taken: Array[Rect2] = []
	for word_rect in _fixed_word_rects(font):
		taken.append(word_rect.grow(LABEL_CLEAR / 2.0))
	for i in ids.size():
		var nid: String = String(ids[i])
		var unit: Vector2 = pos[nid] as Vector2
		var r2: float = KEY_R + RING_GAP if bool(keys.get(nid, false)) else NODE_R
		var price: String = String(prices.get(nid, "")) if bool(keys.get(nid, false)) else ""
		var home: int = 1 if unit.x >= WebLayout.HUB.x else -1
		# The first spot clear all round wins; when none is, the one with the fewest overlaps.
		var best: Dictionary = {"side": 0, "dy": 0.0}
		var fewest: int = 1 << 30
		for side in [home, -home]:
			for dy in LABEL_TRIES:
				var rect: Rect2 = _label_extent(font, unit, String(names.get(nid, "")), price, r2, dy, side).grow(LABEL_CLEAR / 2.0)
				var hits: int = 0
				for t in taken:
					if t.intersects(rect):
						hits += 1
				for j in discs.size():
					if j != i and discs[j].grow(LABEL_CLEAR / 2.0).intersects(rect):
						hits += 1
				if hits < fewest:
					fewest = hits
					best = {"side": side, "dy": dy}
				if hits == 0:
					break
			if fewest == 0:
				break
		_plan[unit] = best
		taken.append(_label_extent(font, unit, String(names.get(nid, "")), price, r2, float(best["dy"]), int(best["side"])).grow(LABEL_CLEAR / 2.0))
	return _plan


# Every pair of words closer than LABEL_CLEAR, and every word over a disc that is not its own, as
# prose: the gate's view of what a reader would see crowded. `planned` false lays every name on its
# home side and row, as the web did before the plan, so the gate can show the check sees a crowd.
func label_faults(planned: bool = true) -> Array[String]:
	var font: Font = Chrome.font()
	var faults: Array[String] = []
	if _def.is_empty():
		return faults
	var pos: Dictionary = WebLayout.positions(_def)
	var plan: Dictionary = _label_plan(font) if planned else {}
	var boxes: Array[Dictionary] = []
	for w in _fixed_word_rects(font):
		boxes.append({"who": "", "rect": w})
	var discs: Array[Dictionary] = []
	for n in _map.get("nodes", []) as Array:
		var nd: Dictionary = n as Dictionary
		var nid: String = String(nd.get("node", ""))
		if not pos.has(nid):
			continue
		var unit: Vector2 = pos[nid] as Vector2
		var key: bool = bool(nd.get("keystone", false))
		var r: float = KEY_R + RING_GAP if key else NODE_R
		var spot: Dictionary = plan.get(unit, {}) as Dictionary
		var price: String = String(nd.get("price", "")) if key else ""
		boxes.append({"who": nid, "rect": _label_extent(font, unit, String(nd.get("name", "")), price, r, float(spot.get("dy", 0.0)), int(spot.get("side", 0)))})
		discs.append({"who": nid, "rect": Rect2(_at(unit) - Vector2(r, r), Vector2(r * 2.0, r * 2.0))})
	for i in boxes.size():
		var a: Rect2 = boxes[i]["rect"] as Rect2
		for j in range(i + 1, boxes.size()):
			if a.grow(LABEL_CLEAR / 2.0).intersects((boxes[j]["rect"] as Rect2).grow(LABEL_CLEAR / 2.0)):
				faults.append("%s and %s are closer than the clearance" % [String(boxes[i]["who"]), String(boxes[j]["who"])])
		for d in discs:
			if String(d["who"]) != String(boxes[i]["who"]) and a.intersects(d["rect"] as Rect2):
				faults.append("%s sits on the disc of %s" % [String(boxes[i]["who"]), String(d["who"])])
	return faults


# The rows a node's words take: its name, and a keystone's price on the row beneath. Measured as
# ink, not as the line box: a line box carries leading above and below the letters, and the
# clearance LABEL_CLEAR promises is the one a reader sees between two words.
func _label_extent(font: Font, unit: Vector2, name: String, price: String, radius: float, dy: float, side: int) -> Rect2:
	var rect: Rect2 = _ink(_beside(font, unit, name, radius, NAME_SIZE, dy, side)["rect"] as Rect2, NAME_SIZE)
	if not price.is_empty():
		rect = rect.merge(_ink(_beside(font, unit, price, radius, PRICE_SIZE, PRICE_DY + dy, side)["rect"] as Rect2, PRICE_SIZE))
	return rect


# A word's line box cut to its letters: from the top of an ascender to the foot of a descender
# (VT323 at the web's size draws both inside 0.7 em above and 0.2 em below the baseline).
static func _ink(line_box: Rect2, font_size: int) -> Rect2:
	var base: float = line_box.position.y + Chrome.ascent(font_size)
	var top: float = base - ceilf(float(font_size) * 0.6)
	return Rect2(Vector2(line_box.position.x, top), Vector2(line_box.size.x, ceilf(float(font_size) * 0.8)))


# Where the region words and the hub's "start" are drawn, in the draw's own arithmetic.
func _fixed_word_rects(font: Font) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in _map.get("regions", []) as Array:
		var region: String = String((r as Dictionary).get("region", ""))
		var anchor: Vector2 = WebLayout.region_anchor(_def, region)
		if anchor == WebLayout.HUB:
			continue
		var word: String = region.to_lower()
		out.append(_ink(_word_rect(font, _region_word_at(font, anchor, word), word, REGION_SIZE), REGION_SIZE))
	out.append(_ink(_word_rect(font, _start_at(font), "start", FOOTER_SIZE), FOOTER_SIZE))
	return out


func _region_word_at(font: Font, anchor: Vector2, word: String) -> Vector2:
	var ww: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, REGION_SIZE).x
	return (_at(anchor) + Vector2(-ww * 0.5, float(REGION_SIZE) * 0.35)).round()


func _start_at(font: Font) -> Vector2:
	var start_w: float = font.get_string_size("start", HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE).x
	return (_at(WebLayout.HUB) + Vector2(-start_w * 0.5, NODE_R + float(FOOTER_SIZE))).round()


func _beside(font: Font, unit: Vector2, text: String, radius: float, font_size: int, dy: float, side: int = 0) -> Dictionary:
	var at: Vector2 = _at(unit)
	var baseline: float = at.y + float(NAME_SIZE) * 0.35 + dy
	var right: bool = unit.x >= WebLayout.HUB.x if side == 0 else side > 0
	if right:
		var room: float = size.x - 16.0 - (at.x + radius + NAME_GAP)
		var fitted: String = UiText.fit(font, text, font_size, room)
		var origin := Vector2(at.x + radius + NAME_GAP, baseline)
		return {"text": fitted, "at": origin, "rect": _word_rect(font, origin, fitted, font_size)}
	var room_l: float = (at.x - radius - NAME_GAP) - 16.0
	var fitted_l: String = UiText.fit(font, text, font_size, room_l)
	var w: float = font.get_string_size(fitted_l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin_l := Vector2(at.x - radius - NAME_GAP - w, baseline)
	return {"text": fitted_l, "at": origin_l, "rect": _word_rect(font, origin_l, fitted_l, font_size)}


# --- draw --------------------------------------------------------------------------------------


func _draw() -> void:
	var font: Font = Chrome.font()
	_hit = layout_hits()
	# The Salvage Locker's steel and a tape label, like the sheet and the bar above it; whose web this
	# is lives on the bar, so the tape does not say it twice.
	var rect := Rect2(Vector2.ZERO, size)
	Locker.panel(self, rect, 0.96)
	Locker.header(self, rect, TAPE_WORD, 0.96, "", Chrome.GLYPH_SMALL + Locker.PX * 3.0)
	Chrome.glyph(self, "skills", Vector2(rect.end.x - Chrome.GLYPH_SMALL - Locker.PX * 5.0, Locker.PX * 2.0 + floorf((Locker.TAPE_H - Chrome.GLYPH_SMALL) / 2.0)), true, 0.7)
	# The legend wraps at its own separators, two lines at most, rather than losing its end.
	var lines: Array[String] = footer_lines(font, size.x - 48.0)
	for i in lines.size():
		var footer_at := Vector2(24.0, size.y - 20.0 - float(lines.size() - 1 - i) * Chrome.line_height(FOOTER_SIZE))
		draw_string(font, footer_at, UiText.fit(font, lines[i], FOOTER_SIZE, size.x - 48.0), HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE, LOCKED_INK)
	if _map.is_empty() or _def.is_empty():
		return
	var pos: Dictionary = WebLayout.positions(_def)
	var state: Dictionary = {}
	var names: Dictionary = {}
	var keystones: Dictionary = {}
	var prices: Dictionary = {}
	for n in _map.get("nodes", []) as Array:
		var nd: Dictionary = n as Dictionary
		state[String(nd.get("node", ""))] = String(nd.get("state", "unknown"))
		names[String(nd.get("node", ""))] = String(nd.get("name", ""))
		keystones[String(nd.get("node", ""))] = bool(nd.get("keystone", false))
		prices[String(nd.get("node", ""))] = String(nd.get("price", ""))
	var hub: Vector2 = _at(WebLayout.HUB)
	# The regions: a fan each, warm where the survivor has lived and faint where they have not,
	# with the region's word out past its nodes.
	for r in _map.get("regions", []) as Array:
		var rd: Dictionary = r as Dictionary
		var region: String = String(rd.get("region", ""))
		var lived: bool = bool(rd.get("lived", false))
		var anchor: Vector2 = WebLayout.region_anchor(_def, region)
		if anchor == WebLayout.HUB:
			continue
		var dir: Vector2 = (anchor - WebLayout.HUB).normalized()
		var mid: float = atan2(dir.y, dir.x)
		var fan: PackedVector2Array = PackedVector2Array([hub])
		for i in 13:
			var a: float = mid - FAN_HALF + FAN_HALF * 2.0 * float(i) / 12.0
			fan.append(hub + Vector2(cos(a), sin(a)) * FAN_RADIUS * _span())
		# Warm where they have lived, and only there; every fan gets the same hairline so the six
		# sectors read as sectors whether or not anybody has earned anything yet.
		if lived:
			var fill: Color = Chrome.ITEM_FILL
			fill.a = 0.7
			draw_colored_polygon(fan, fill)
		# The fan's edge in whole art pixels too: the two radii and the arc between them.
		var rim: PackedVector2Array = fan.duplicate()
		rim.append(hub)
		for i in rim.size() - 1:
			_line(rim[i], rim[i + 1], Chrome.CELL_EDGE)
		var word: String = region.to_lower()
		var label_at: Vector2 = _region_word_at(font, anchor, word)
		draw_string(font, label_at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, REGION_SIZE, Chrome.TEXT if lived else LOCKED_INK)
	# The lines: a focus path between two nodes, a spoke from the hub to where a path starts,
	# and a dotted line to a node no path reaches. Bright where the survivor has walked it.
	for e in WebLayout.edges(_def):
		var a: String = String((e as Array)[0])
		var b: String = String((e as Array)[1])
		if not (pos.has(a) and pos.has(b)):
			continue
		var walked: bool = state.get(a, "") == "known" and state.get(b, "") == "known"
		_line(_at(pos[a] as Vector2), _at(pos[b] as Vector2), Chrome.TEXT_DIM if walked else Chrome.CELL_EDGE)
	for s in WebLayout.spokes(_def):
		if not pos.has(s):
			continue
		var walked_s: bool = state.get(s, "") == "known"
		_line(hub, _at(pos[s] as Vector2), Chrome.TEXT_DIM if walked_s else Chrome.CELL_EDGE)
	for d in WebLayout.drift_only(_def):
		if not pos.has(d):
			continue
		var walked_d: bool = state.get(d, "") == "known"
		_line(hub, _at(pos[d] as Vector2), Chrome.TEXT_DIM if walked_d else Chrome.CELL_EDGE, DASH)
	# The hub.
	_blocks(hub, HUB_R, 0.0, Chrome.TEXT_DIM)
	draw_string(font, _start_at(font), "start", HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE, LOCKED_INK)
	# The nodes: known bright, learnable amber, the rest an outline -- and the name beside each
	# in the same colour, so the disc and the word agree.
	# A keystone is a bigger disc with a ring round it in the same colour, and its price in
	# words on the row beneath its name: the one thing on the web that costs something.
	for nid in pos.keys():
		var st: String = String(state.get(nid, "unknown"))
		var at: Vector2 = _at(pos[nid] as Vector2)
		var key: bool = bool(keystones.get(nid, false))
		var r: float = KEY_R if key else NODE_R
		var col: Color = LOCKED_INK
		match st:
			"known":
				col = Chrome.TEXT
				_blocks(at, r, 0.0, col)
			"learnable":
				col = Chrome.ACCENT
				_blocks(at, r, 0.0, col)
			_:
				_blocks(at, r, 0.0, Locker.STEEL)
				_blocks(at, r, r - Locker.PX, col)
		var reach: float = r
		if key:
			reach = KEY_R + RING_GAP
			_blocks(at, reach, reach - Locker.PX, col)
		var placed: Dictionary = _name_placement(font, pos[nid] as Vector2, String(names.get(nid, "")), reach)
		draw_string(font, placed["at"] as Vector2, String(placed["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, col)
		var price: String = String(prices.get(nid, ""))
		if key and not price.is_empty():
			var priced: Dictionary = _price_placement(font, pos[nid] as Vector2, price, reach)
			draw_string(font, priced["at"] as Vector2, String(priced["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_SIZE, LOCKED_INK)
