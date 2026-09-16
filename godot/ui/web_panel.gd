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

# The web's square inside the panel: where the unit square lands, in pixels. The panel is wider
# than the square so a name beside a rim node has room to the left or the right of it.
const WEB_X: float = 220.0
const WEB_Y: float = 64.0
const WEB_SIDE: float = 600.0
const NODE_R: float = 9.0
# A keystone's disc, and the ring outside it: the one thing on the web that costs something.
const KEY_R: float = 12.5
const RING_GAP: float = 3.0
const PRICE_SIZE: int = 13
const PRICE_DY: float = 17.0
const NAME_GAP: float = 14.0
const NAME_SIZE: int = 16
const REGION_SIZE: int = 16
const FOOTER_SIZE: int = 14
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


# The survivor the header names: the one selected on the street, or "you".
func header_label() -> String:
	var who: String = String(_map.get("who", ""))
	if _world != null and _who == int(_world.player):
		who = "you"
	if who.is_empty():
		who = "nobody"
	return "skill web — " + who


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
	return Vector2(WEB_X + unit.x * WEB_SIDE, WEB_Y + unit.y * WEB_SIDE)


# The one place a word's extent is measured, so the rectangle drawn and the rectangle clicked
# cannot drift apart (work_panel.gd's rule).
func _word_rect(font: Font, at: Vector2, word: String, font_size: int) -> Rect2:
	var w: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return Rect2(Vector2(at.x, at.y - float(font_size) * 0.8), Vector2(w, float(font_size) * 1.15))


# Where a node's name goes: to the right of the disc on the web's right half, ending to the left
# of it on the left half, fitted to whatever room the panel has on that side.
func _name_placement(font: Font, unit: Vector2, name: String, radius: float = NODE_R) -> Dictionary:
	return _beside(font, unit, name, radius, NAME_SIZE, 0.0)


# A keystone's price, in words, on the row under its name and on the same side.
func _price_placement(font: Font, unit: Vector2, price: String, radius: float) -> Dictionary:
	return _beside(font, unit, price, radius, PRICE_SIZE, PRICE_DY)


func _beside(font: Font, unit: Vector2, text: String, radius: float, font_size: int, dy: float) -> Dictionary:
	var at: Vector2 = _at(unit)
	var baseline: float = at.y + float(NAME_SIZE) * 0.35 + dy
	if unit.x >= WebLayout.HUB.x:
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
	Chrome.panel(self, Rect2(Vector2.ZERO, size), 0.96)
	Chrome.header(self, Rect2(Vector2.ZERO, size), header_label(), 0.96)
	var footer_at := Vector2(16.0, size.y - 18.0)
	draw_string(font, footer_at, UiText.fit(font, footer(), FOOTER_SIZE, size.x - 32.0), HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE, Chrome.TEXT_FAINT)
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
			fan.append(hub + Vector2(cos(a), sin(a)) * FAN_RADIUS * WEB_SIDE)
		# Warm where they have lived, and only there; every fan gets the same hairline so the six
		# sectors read as sectors whether or not anybody has earned anything yet.
		if lived:
			var fill: Color = Chrome.ITEM_FILL
			fill.a = 0.7
			draw_colored_polygon(fan, fill)
		var rim: PackedVector2Array = fan.duplicate()
		rim.append(hub)
		draw_polyline(rim, Chrome.CELL_EDGE, 1.0)
		var word: String = region.to_lower()
		var ww: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, REGION_SIZE).x
		var label_at: Vector2 = _at(anchor) + Vector2(-ww * 0.5, float(REGION_SIZE) * 0.35)
		draw_string(font, label_at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, REGION_SIZE, Chrome.TEXT if lived else Chrome.TEXT_FAINT)
	# The lines: a focus path between two nodes, a spoke from the hub to where a path starts,
	# and a dotted line to a node no path reaches. Bright where the survivor has walked it.
	for e in WebLayout.edges(_def):
		var a: String = String((e as Array)[0])
		var b: String = String((e as Array)[1])
		if not (pos.has(a) and pos.has(b)):
			continue
		var walked: bool = state.get(a, "") == "known" and state.get(b, "") == "known"
		draw_line(_at(pos[a] as Vector2), _at(pos[b] as Vector2), Chrome.TEXT_DIM if walked else Chrome.CELL_EDGE, 2.0 if walked else 1.5)
	for s in WebLayout.spokes(_def):
		if not pos.has(s):
			continue
		var walked_s: bool = state.get(s, "") == "known"
		draw_line(hub, _at(pos[s] as Vector2), Chrome.TEXT_DIM if walked_s else Chrome.CELL_EDGE, 2.0 if walked_s else 1.5)
	for d in WebLayout.drift_only(_def):
		if not pos.has(d):
			continue
		var walked_d: bool = state.get(d, "") == "known"
		draw_dashed_line(hub, _at(pos[d] as Vector2), Chrome.TEXT_DIM if walked_d else Chrome.CELL_EDGE, 1.5, 6.0)
	# The hub.
	draw_circle(hub, NODE_R * 0.6, Chrome.TEXT_DIM)
	var start_w: float = font.get_string_size("start", HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE).x
	draw_string(font, hub + Vector2(-start_w * 0.5, NODE_R + float(FOOTER_SIZE)), "start", HORIZONTAL_ALIGNMENT_LEFT, -1, FOOTER_SIZE, Chrome.TEXT_FAINT)
	# The nodes: known bright, learnable amber, the rest an outline -- and the name beside each
	# in the same colour, so the disc and the word agree.
	# A keystone is a bigger disc with a ring round it in the same colour, and its price in
	# words on the row beneath its name: the one thing on the web that costs something.
	for nid in pos.keys():
		var st: String = String(state.get(nid, "unknown"))
		var at: Vector2 = _at(pos[nid] as Vector2)
		var key: bool = bool(keystones.get(nid, false))
		var r: float = KEY_R if key else NODE_R
		var col: Color = Chrome.TEXT_FAINT
		match st:
			"known":
				col = Chrome.TEXT
				draw_circle(at, r, col)
			"learnable":
				col = Chrome.ACCENT
				draw_circle(at, r, col)
			_:
				draw_circle(at, r, Chrome.PANEL)
				draw_circle(at, r, col, false, 1.5)
		var reach: float = r
		if key:
			reach = KEY_R + RING_GAP
			draw_circle(at, reach, col, false, 1.5)
		var placed: Dictionary = _name_placement(font, pos[nid] as Vector2, String(names.get(nid, "")), reach)
		draw_string(font, placed["at"] as Vector2, String(placed["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, col)
		var price: String = String(prices.get(nid, ""))
		if key and not price.is_empty():
			var priced: Dictionary = _price_placement(font, pos[nid] as Vector2, price, reach)
			draw_string(font, priced["at"] as Vector2, String(priced["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_SIZE, Chrome.TEXT_FAINT)
