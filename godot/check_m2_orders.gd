extends SceneTree
# Colonist orders -- plan item A16, the colony half of the alpha.
#
# A player picks a colonist on the street and tells them one thing: go there, hold there, or haul
# that. What the gate holds the sim to, and why each lane exists:
#
#   GO      -- a colonist ordered to a tile walks there and the order ends on arrival. The true
#              positive is the walk itself, measured as position, not as "an order was issued".
#              The negatives: the tile they stand on is no order, a wall is no order, and the
#              player is never a colonist under orders.
#   HOLD    -- a held colonist stands on the spot and takes no work. The item on the ground is what
#              makes this a real test: a colonist with no order goes to it (the CONTROL lane), so
#              the held colonist's silence is the order's doing and not an empty street.
#   HAUL    -- an ordered item ends on a stockpile tile, carried there by the ordinary Haul job. The
#              negatives: an item already stocked is no order, and neither is one in somebody's pack.
#   CLEAR   -- a stand-down ends a hold, and standing down a colonist who has no order is refused.
#   ISSUE   -- an order drops the job the colonist was in the middle of, at once, not on a later tick.
#   WORDS   -- the HUD's line for the order says what it does, in prose with no digits, and only
#              while there is an order; the right-click menu offers the order to the selected colonist
#              and no one else, and only where the sim would take it.
#   PLAIN   -- the order record is plain values, so it round-trips a save the way every component does.
#
# Every lane carries its true negative.

const SimBoot = preload("res://sim/boot.gd")
const SimPath = preload("res://sim/path.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimOrders = preload("res://sim/modules/orders.gd")
const SimContext = preload("res://sim/context.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimClock = preload("res://sim/time/clock.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")

const SEED: int = 20260805
const MAP: int = 64
const REACH: float = 1.5
# Generous, and measured against the walk, not the clock: a colonist six tiles off crosses it in
# well under a second of game time at 20 Hz.
const WALK_TICKS: int = 900
const WATCH_TICKS: int = 300
const HAUL_TICKS: int = 1500
const SEARCH_RADIUS: int = 9


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _go_walks_there_and_ends() and ok
	ok = _hold_keeps_a_colonist_off_work_and_a_free_one_goes() and ok
	ok = _haul_carries_the_item_to_the_stockpile() and ok
	ok = _stand_down_ends_a_hold_and_refuses_when_there_is_none() and ok
	ok = _an_order_drops_the_job_in_hand_at_once() and ok
	ok = _the_words_and_the_menu_follow_the_order() and ok
	ok = _draft_holds_a_colonist_where_they_stand_and_a_second_press_frees_them() and ok
	ok = _an_attack_order_walks_to_its_target_and_strikes_it() and ok
	ok = _the_ordered_target_is_picked_before_a_nearer_one() and ok
	ok = _an_attack_order_refuses_what_is_unseen_colonist_or_dead() and ok
	ok = _a_critically_injured_colonist_loses_the_attack_order() and ok
	ok = _the_record_is_plain_values() and ok
	if ok:
		print("M2_ORDERS_OK go walks and ends, hold keeps off work against a free control, haul stocks the item, stand down refuses with none, an order drops the job in hand, the HUD and the menu follow the sim, the draft holds and frees a colonist, an attack walks to its target and strikes it, the order picks its target before a nearer one, and the record is plain values")
		quit(0)
	else:
		push_error("M2_ORDERS_FAIL")
		quit(1)


# --- fixtures ----------------------------------------------------------------------------------

# The lanes judge what an order does with a colonist's feet, so the district's zombies are cleared
# out of it. They used to be left in, and the walk passed because of where they happened to be:
# when the A24 danger rule changed what Ellis does on the first tick, seven of them gathered at
# the annex door and Mara could not walk through them, which says nothing about orders.
func _world() -> Variant:
	var w: Variant = SimBoot.playable(SEED, MAP)["world"]
	for z in w.components.query(["shambler"]):
		w.despawn(int(z))
	return w


func _survivor(w: Variant, id: String) -> int:
	for ent in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(ent), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == id:
			return int(ent)
	return -1


func _mara(w: Variant) -> int:
	return _survivor(w, "survivor.unique.mara")


func _ellis(w: Variant) -> int:
	return _survivor(w, "survivor.unique.ellis")


func _tile(w: Variant, ent: int) -> Vector2i:
	var p: Variant = w.components.get_component(ent, "position")
	if not (p is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))


func _dist(w: Variant, ent: int, tile: Vector2i) -> float:
	var p: Variant = w.components.get_component(ent, "position")
	if not (p is Dictionary):
		return INF
	var dx: float = float(tile.x) + 0.5 - float((p as Dictionary)["x"])
	var dy: float = float(tile.y) + 0.5 - float((p as Dictionary)["y"])
	return sqrt(dx * dx + dy * dy)


func _order(w: Variant, ent: int) -> Variant:
	return w.components.get_component(ent, SimJobs.ORDER_COMPONENT)


# A walkable tile between `lo` and `hi` tiles away (Chebyshev) that a route reaches from `from`.
# The route is checked, not assumed: a tile behind a wall is walkable and still no destination.
func _reachable_away(w: Variant, from: Vector2i, lo: int, hi: int) -> Vector2i:
	for dy in range(-hi, hi + 1):
		for dx in range(-hi, hi + 1):
			var d: int = maxi(absi(dx), absi(dy))
			if d < lo:
				continue
			var t := Vector2i(from.x + dx, from.y + dy)
			if SimPath.walkable(w, t.x, t.y) and not SimPath.find(w, from, t).is_empty():
				return t
	return Vector2i(-1, -1)


func _blocked_near(w: Variant, from: Vector2i) -> Vector2i:
	for dy in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for dx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			var t := Vector2i(from.x + dx, from.y + dy)
			if not SimPath.walkable(w, t.x, t.y):
				return t
	return Vector2i(-1, -1)


func _stockpile_tile(w: Variant) -> Vector2i:
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	for y in range(annex.position.y, annex.end.y):
		for x in range(annex.position.x, annex.end.x):
			if SimNeeds.is_stockpile_tile(w, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _loose_item_at(w: Variant, tile: Vector2i) -> int:
	var item: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	w.components.set_component(item, "position", {"x": float(tile.x) + 0.5, "y": float(tile.y) + 0.5})
	return item


func _cmd(ent: int, fields: Dictionary) -> Dictionary:
	var c: Dictionary = fields.duplicate()
	c["type"] = SimOrders.COMMAND
	c["entity"] = ent
	return c


func _has_digit(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) >= 48 and text.unicode_at(i) <= 57:
			return true
	return false


func _name_of(w: Variant, ent: int) -> String:
	var ident: Variant = w.components.get_component(ent, "identity")
	return String((ident as Dictionary).get("name", "")) if ident is Dictionary else ""


# --- lanes -------------------------------------------------------------------------------------

func _go_walks_there_and_ends() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var here: Vector2i = _tile(w, mara)
	var goal: Vector2i = _reachable_away(w, here, 4, SEARCH_RADIUS)
	var wall: Vector2i = _blocked_near(w, here)
	if goal.x < 0 or wall.x < 0:
		push_error("GO: no walkable goal or no blocked tile near Mara to test against")
		return false
	var start_gap: float = _dist(w, mara, goal)

	var refused_own: bool = not SimOrders.accepts(w, mara, {"kind": "go", "tx": here.x, "ty": here.y})
	var refused_wall: bool = not SimOrders.accepts(w, mara, {"kind": "go", "tx": wall.x, "ty": wall.y})
	var refused_player: bool = not SimOrders.accepts(w, int(w.player), {"kind": "go", "tx": goal.x, "ty": goal.y})

	w.commands.push(_cmd(mara, {"kind": "go", "tx": goal.x, "ty": goal.y}))
	w.step()
	var issued: bool = _order(w, mara) is Dictionary
	var ticks: int = 0
	while _order(w, mara) is Dictionary and ticks < WALK_TICKS:
		w.step()
		ticks += 1
	var ended: bool = not (_order(w, mara) is Dictionary)
	var arrived: bool = _dist(w, mara, goal) <= REACH

	var ok: bool = start_gap > REACH and issued and ended and arrived and refused_own and refused_wall and refused_player
	if not ok:
		push_error("GO: gap %.2f issued %s ended %s after %d ticks, arrived %s; refused own %s wall %s player %s" % [start_gap, issued, ended, ticks, arrived, refused_own, refused_wall, refused_player])
	return ok


func _hold_keeps_a_colonist_off_work_and_a_free_one_goes() -> bool:
	# CONTROL first, on its own world: no order, an item on the ground beside the annex, and
	# somebody must go for it. Without this the held lane below could pass on a street with no work.
	var free: Variant = _world()
	var free_mara: int = _mara(free)
	var stock_free: Vector2i = _stockpile_tile(free)
	var loose_free: Vector2i = _reachable_away(free, _tile(free, free_mara), 3, SEARCH_RADIUS)
	if stock_free.x < 0 or loose_free.x < 0:
		push_error("HOLD: no stockpile or loose tile to make work on")
		return false
	_loose_item_at(free, loose_free)
	var someone_works: bool = false
	for _i in WATCH_TICKS:
		free.step()
		if free.components.get_component(free_mara, "job") is Dictionary or free.components.get_component(_ellis(free), "job") is Dictionary:
			someone_works = true
			break
	if not someone_works:
		push_error("HOLD: control found no colonist take the loose item in %d ticks, so the held lane would prove nothing" % WATCH_TICKS)
		return false

	var w: Variant = _world()
	var ellis: int = _ellis(w)
	var here: Vector2i = _tile(w, ellis)
	var spot: Vector2i = _reachable_away(w, here, 2, SEARCH_RADIUS)
	var loose: Vector2i = _reachable_away(w, here, 3, SEARCH_RADIUS)
	if spot.x < 0 or loose.x < 0:
		push_error("HOLD: no hold spot or loose tile near Ellis")
		return false
	_loose_item_at(w, loose)
	w.commands.push(_cmd(ellis, {"kind": "hold", "tx": spot.x, "ty": spot.y}))
	w.step()
	var held: bool = _order(w, ellis) is Dictionary
	var worked: bool = false
	var reached: bool = false
	var strayed: bool = false
	for _i in WATCH_TICKS + WALK_TICKS:
		w.step()
		if w.components.get_component(ellis, "job") is Dictionary:
			worked = true
		if _dist(w, ellis, spot) <= REACH:
			reached = true
		elif reached:
			strayed = true
	var still_held: bool = _order(w, ellis) is Dictionary
	var ok: bool = held and reached and not worked and not strayed and still_held
	if not ok:
		push_error("HOLD: held %s reached %s worked %s strayed %s still held %s" % [held, reached, worked, strayed, still_held])
	return ok


func _haul_carries_the_item_to_the_stockpile() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var stock: Vector2i = _stockpile_tile(w)
	var loose: Vector2i = _reachable_away(w, _tile(w, mara), 3, SEARCH_RADIUS)
	if stock.x < 0 or loose.x < 0:
		push_error("HAUL: no stockpile or loose tile")
		return false
	var item: int = _loose_item_at(w, loose)

	var wanted: bool = SimOrders.accepts(w, mara, {"kind": "haul", "target": item})
	# The true negatives: stocked already, and in a pack. Built on a second item so the first is
	# untouched.
	var stocked: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	w.components.set_component(stocked, "position", {"x": float(stock.x) + 0.5, "y": float(stock.y) + 0.5})
	var packed: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	SimInventory.stow(w, _ellis(w), packed)
	var refuses_stocked: bool = not SimOrders.accepts(w, mara, {"kind": "haul", "target": stocked})
	var refuses_packed: bool = not SimOrders.accepts(w, mara, {"kind": "haul", "target": packed})

	w.commands.push(_cmd(mara, {"kind": "haul", "target": item}))
	w.step()
	var issued: bool = _order(w, mara) is Dictionary
	var ticks: int = 0
	while _order(w, mara) is Dictionary and ticks < HAUL_TICKS:
		w.step()
		ticks += 1
	var ended: bool = not (_order(w, mara) is Dictionary)
	var stocked_now: bool = false
	var p: Variant = w.components.get_component(item, "position")
	if p is Dictionary:
		stocked_now = SimNeeds.is_stockpile_tile(w, floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))
	var no_job_left: bool = not (w.components.get_component(mara, "job") is Dictionary)

	var ok: bool = wanted and refuses_stocked and refuses_packed and issued and ended and stocked_now and no_job_left
	if not ok:
		push_error("HAUL: wanted %s refuses stocked %s packed %s issued %s ended %s after %d ticks, stocked %s, job left %s" % [wanted, refuses_stocked, refuses_packed, issued, ended, ticks, stocked_now, not no_job_left])
	return ok


func _stand_down_ends_a_hold_and_refuses_when_there_is_none() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var spot: Vector2i = _reachable_away(w, _tile(w, mara), 2, SEARCH_RADIUS)
	if spot.x < 0:
		push_error("CLEAR: no spot to hold")
		return false
	var refused_with_none: bool = not SimOrders.accepts(w, mara, {"kind": "clear"})
	w.commands.push(_cmd(mara, {"kind": "hold", "tx": spot.x, "ty": spot.y}))
	w.step()
	var held: bool = _order(w, mara) is Dictionary
	var offered_with_one: bool = SimOrders.accepts(w, mara, {"kind": "clear"})
	w.commands.push(_cmd(mara, {"kind": "clear"}))
	w.step()
	var ended: bool = not (_order(w, mara) is Dictionary)
	var ok: bool = refused_with_none and held and offered_with_one and ended
	if not ok:
		push_error("CLEAR: refused with none %s held %s offered %s ended %s" % [refused_with_none, held, offered_with_one, ended])
	return ok


func _an_order_drops_the_job_in_hand_at_once() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var spot: Vector2i = _reachable_away(w, _tile(w, mara), 2, SEARCH_RADIUS)
	if spot.x < 0:
		push_error("ISSUE: no spot to walk to")
		return false
	w.components.set_component(mara, "job", {"kind": "Rest", "target": -1, "ticksLeft": 0, "path": [], "pathGen": -1})
	w.commands.push(_cmd(mara, {"kind": "go", "tx": spot.x, "ty": spot.y}))
	w.step()
	var job_gone: bool = not (w.components.get_component(mara, "job") is Dictionary)
	var ok: bool = job_gone and _order(w, mara) is Dictionary
	if not ok:
		push_error("ISSUE: job dropped %s, order taken %s" % [job_gone, _order(w, mara) is Dictionary])
	return ok


func _the_words_and_the_menu_follow_the_order() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var here: Vector2i = _tile(w, mara)
	var goal: Vector2i = _reachable_away(w, here, 4, SEARCH_RADIUS)
	if goal.x < 0:
		push_error("WORDS: no goal")
		return false
	var silent: bool = SimOrders.hud_clause(w, mara).is_empty()

	var player_hit: Dictionary = {"kind": "ground", "tile": goal}
	var name: String = _name_of(w, mara)
	var without: bool = _has_order_row(SimContext.verbs_at(w, int(w.player), player_hit), "go")
	var with_select: Array[Dictionary] = SimContext.verbs_at(w, int(w.player), player_hit, mara)
	var offered: bool = _find_row(with_select, "have %s go here" % name, "go") and _find_row(with_select, "have %s hold here" % name, "hold")
	var own_tile: Array[Dictionary] = SimContext.verbs_at(w, int(w.player), {"kind": "ground", "tile": here}, mara)
	var not_on_own_tile: bool = not _has_order_row(own_tile, "go")

	w.commands.push(_cmd(mara, {"kind": "go", "tx": goal.x, "ty": goal.y}))
	w.step()
	var go_line: String = SimOrders.hud_clause(w, mara)
	var go_words: bool = go_line.begins_with("On the way") and not _has_digit(go_line)
	var rows_while_ordered: Array[Dictionary] = SimContext.verbs_at(w, int(w.player), player_hit, mara)
	var stand_down: bool = _find_row(rows_while_ordered, "stand %s down" % name, "clear")

	w.commands.push(_cmd(mara, {"kind": "hold", "tx": goal.x, "ty": goal.y}))
	w.step()
	var hold_line: String = SimOrders.hud_clause(w, mara)
	var hold_words: bool = hold_line.begins_with("Holding") and not _has_digit(hold_line)

	# The ring the map draws sits where the sim says the colonist is going: the spot while the
	# order is held, and nowhere once there is no order.
	var dest_hold: bool = SimOrders.destination(w, mara) == goal
	w.commands.push(_cmd(mara, {"kind": "clear"}))
	w.step()
	var dest_none: bool = SimOrders.destination(w, mara) == Vector2i(-1, -1)

	var ok: bool = silent and not without and offered and not_on_own_tile and go_words and stand_down and hold_words and dest_hold and dest_none
	if not ok:
		push_error("WORDS: silent %s without-select-hides %s offered %s own-tile-hides %s go %s (%s) stand-down %s hold %s (%s) destination %s none %s" % [silent, not without, offered, not_on_own_tile, go_words, go_line, stand_down, hold_words, hold_line, dest_hold, dest_none])
	return ok


func _draft_holds_a_colonist_where_they_stand_and_a_second_press_frees_them() -> bool:
	# CONTROL first: an undrafted Mara with a loose item beside her takes the work. Without this the
	# drafted lane below could pass on a street with nothing to refuse.
	var free: Variant = _world()
	var free_mara: int = _mara(free)
	var loose_free: Vector2i = _reachable_away(free, _tile(free, free_mara), 3, SEARCH_RADIUS)
	if loose_free.x < 0:
		push_error("DRAFT: no loose tile near Mara to make work on")
		return false
	_loose_item_at(free, loose_free)
	var control_works: bool = false
	for _i in WATCH_TICKS:
		free.step()
		if free.components.get_component(free_mara, "job") is Dictionary:
			control_works = true
			break
	if not control_works:
		push_error("DRAFT: control found Mara take no work in %d ticks, so the drafted lane would prove nothing" % WATCH_TICKS)
		return false

	var w: Variant = _world()
	var mara: int = _mara(w)
	var start: Vector2i = _tile(w, mara)
	_loose_item_at(w, _reachable_away(w, start, 3, SEARCH_RADIUS))
	var draft: Dictionary = SimOrders.draft_command(w, mara)
	var drafts: bool = String(draft.get("kind", "")) == "hold" and int(draft.get("entity", -1)) == mara and int(draft.get("tx", -1)) == start.x and int(draft.get("ty", -1)) == start.y
	w.commands.push(draft)
	w.step()
	var held_order: Variant = _order(w, mara)
	var held: bool = held_order is Dictionary and String((held_order as Dictionary)["kind"]) == "hold"
	var worked: bool = false
	var strayed: bool = false
	for _i in 2400:
		w.step()
		if w.components.get_component(mara, "job") is Dictionary:
			worked = true
		if _dist(w, mara, start) > REACH:
			strayed = true
	# The same key again hands them back: a clear, the order gone, and work taken up at once.
	var free_cmd: Dictionary = SimOrders.draft_command(w, mara)
	var frees: bool = String(free_cmd.get("kind", "")) == "clear"
	w.commands.push(free_cmd)
	w.step()
	var free_again: bool = not (_order(w, mara) is Dictionary)
	var took_work: bool = false
	for _i in WATCH_TICKS:
		w.step()
		if w.components.get_component(mara, "job") is Dictionary:
			took_work = true
			break

	# Refusals: the player, and a colonist grabbed, a corpse or a recruit, get no command at all.
	var refused_player: bool = SimOrders.draft_command(w, int(w.player)).is_empty()
	var refused: bool = true
	for c in ["grabbed", "corpse", "recruit"]:
		w.components.set_component(mara, c, {})
		refused = refused and SimOrders.draft_command(w, mara).is_empty()
		w.components.remove_component(mara, c)
	var ok: bool = control_works and drafts and held and not worked and not strayed and frees and free_again and took_work and refused_player and refused
	if not ok:
		push_error("DRAFT: control works %s; drafted %s held %s worked %s strayed %s; freed %s free again %s took work %s; refused player %s, grabbed/corpse/recruit %s" % [control_works, drafts, held, worked, strayed, frees, free_again, took_work, refused_player, refused])
	return ok


# --- attack lanes (plan A2) -----------------------------------------------------------------

# A tile a route reaches from `from`, between `lo` and `hi` tiles away, that Mara can see right now.
# Reachable is not seen: a route round a wall is walkable and still out of sight, so the order's
# own "seen" test is what this lane has to meet.
func _seen_away(w: Variant, mara: int, lo: int, hi: int) -> Vector2i:
	var from: Vector2i = _tile(w, mara)
	for d in range(lo, hi + 1):
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				var t := Vector2i(from.x + dx, from.y + dy)
				if not SimPath.walkable(w, t.x, t.y) or SimPath.find(w, from, t).is_empty():
					continue
				if int(w.vision.detail(mara, float(t.x) + 0.5, float(t.y) + 0.5)) > 0:
					return t
	return Vector2i(-1, -1)

func _zombie(w: Variant, x: float, y: float) -> int:
	return SimRoster.spawn_zombie(w, x, y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))


# Midday: a survivor's night sight is 1.9 m, so a zombie 8 m off is unseen at the boot's 3 a.m.
func _noon(w: Variant) -> void:
	w.tick = SimClock.tick_on_day(1, 0.5)


func _wound_to(w: Variant, ent: int, part: String, state: int) -> void:
	var body: Dictionary = w.components.get_component(ent, "body") as Dictionary
	var maxv: Variant = SimHealth.max_of(body, part)
	var top: float = float(int(maxv)) if maxv != null else 40.0
	for step in range(int(top), -1, -1):
		body[part] = float(step)
		if int(SimHealth.part_state(body, part)) >= state:
			return


# Every attack.connected this step, as the attacker's and the target's ids, in the order they landed.
func _landed_this_step(w: Variant) -> Array:
	var out: Array = []
	for e in w.events.drained:
		var ev: Dictionary = e as Dictionary
		if String(ev.get("type", "")) == "attack.connected":
			out.append([int(ev.get("attacker", -1)), int(ev.get("target", -1))])
	return out


func _an_attack_order_walks_to_its_target_and_strikes_it() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	_noon(w)
	w.step()
	var spot: Vector2i = _seen_away(w, mara, 7, 9)
	if spot.x < 0:
		push_error("ATTACK: no tile 7 to 9 tiles from Mara that she can see and a route reaches")
		return false
	var zombie: int = _zombie(w, float(spot.x) + 0.5, float(spot.y) + 0.5)
	w.step()
	var accepted: bool = SimOrders.accepts(w, mara, {"kind": "attack", "target": zombie})
	w.commands.push(_cmd(mara, {"kind": "attack", "target": zombie}))
	w.step()
	var issued: bool = _order(w, mara) is Dictionary
	var struck: int = 0
	var ticks: int = 0
	while _order(w, mara) is Dictionary and ticks < WALK_TICKS:
		w.step()
		ticks += 1
		for pair in _landed_this_step(w):
			if int(pair[0]) == mara and int(pair[1]) == zombie:
				struck += 1
	var ok: bool = accepted and issued and struck >= 1
	if not ok:
		push_error("ATTACK: accepted %s issued %s struck the target %d times in %d ticks" % [accepted, issued, struck, ticks])
	return ok


func _the_ordered_target_is_picked_before_a_nearer_one() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var at: Dictionary = w.components.get_component(mara, "position") as Dictionary
	var mx: float = float(at["x"])
	var my: float = float(at["y"])
	_noon(w)
	w.step()
	var ordered: int = _zombie(w, mx + 0.7, my)
	var nearer: int = _zombie(w, mx - 0.3, my)
	# Staggered, so neither can grab Mara before the order lands: a grabbed colonist takes no order,
	# and that refusal is not what this lane is about.
	for z in [ordered, nearer]:
		(w.components.get_component(z, "shambler") as Dictionary)["state"] = SimShambler.ShamblerState["Staggered"]
	# Both inside knife reach, the ordered one a little further out. Free, Mara's pick is the nearer.
	var free_pick: int = SimNpcCombat._nearest_threat(w, mara, 2.0)
	var accepted: bool = SimOrders.accepts(w, mara, {"kind": "attack", "target": ordered})
	w.commands.push(_cmd(mara, {"kind": "attack", "target": ordered}))
	w.step()
	# Under the order the pick is the ordered one; the swing's own arc is melee.gd's and not asserted here.
	var ordered_pick: int = SimNpcCombat._nearest_threat(w, mara, 2.0)
	var ok: bool = accepted and free_pick == nearer and ordered_pick == ordered
	if not ok:
		push_error("ATTACK-PICK: accepted %s; free pick %d (nearer %d); under the order %d (ordered %d)" % [accepted, free_pick, nearer, ordered_pick, ordered])
	return ok


func _an_attack_order_refuses_what_is_unseen_colonist_or_dead() -> bool:
	var w: Variant = _world()
	_noon(w)
	var mara: int = _mara(w)
	var ellis: int = _ellis(w)
	var refused_colonist: bool = not SimOrders.accepts(w, mara, {"kind": "attack", "target": ellis})
	var spot: Vector2i = _reachable_away(w, _tile(w, mara), 4, 6)
	if spot.x < 0:
		push_error("ATTACK: no reachable tile for the corpse test")
		return false
	var corpse: int = _zombie(w, float(spot.x) + 0.5, float(spot.y) + 0.5)
	w.components.set_component(corpse, "corpse", {})
	var refused_corpse: bool = not SimOrders.accepts(w, mara, {"kind": "attack", "target": corpse})
	# Unseen: a standing zombie at least 10 tiles off that neither Mara nor the player can see now.
	var hidden: Vector2i = Vector2i(-1, -1)
	var here: Vector2i = _tile(w, mara)
	for d in range(10, 30):
		for dy in range(-d, d + 1):
			for dx in [-d, d]:
				var t := Vector2i(here.x + dx, here.y + dy)
				if hidden.x < 0 and SimPath.walkable(w, t.x, t.y) and not SimPath.find(w, here, t).is_empty():
					hidden = t
	if hidden.x < 0:
		push_error("ATTACK: no reachable tile for the unseen test")
		return false
	var far: int = _zombie(w, float(hidden.x) + 0.5, float(hidden.y) + 0.5)
	w.step()
	var unseen: bool = int(w.vision.detail(mara, float(hidden.x) + 0.5, float(hidden.y) + 0.5)) == 0 and int(w.vision.detail(int(w.player), float(hidden.x) + 0.5, float(hidden.y) + 0.5)) == 0
	var refused_unseen: bool = not SimOrders.accepts(w, mara, {"kind": "attack", "target": far})
	var ok: bool = refused_colonist and refused_corpse and (refused_unseen or not unseen)
	if not ok or not unseen:
		push_error("ATTACK: refused colonist %s corpse %s; unseen tile hidden %s refused %s" % [refused_colonist, refused_corpse, unseen, refused_unseen])
	return ok and unseen


func _a_critically_injured_colonist_loses_the_attack_order() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	_noon(w)
	w.step()
	var spot: Vector2i = _seen_away(w, mara, 3, 5)
	if spot.x < 0:
		push_error("ATTACK-BREAK: no tile 3 to 5 tiles from Mara that she can see")
		return false
	var zombie: int = _zombie(w, float(spot.x) + 0.5, float(spot.y) + 0.5)
	w.step()
	w.commands.push(_cmd(mara, {"kind": "attack", "target": zombie}))
	w.step()
	var held: bool = _order(w, mara) is Dictionary
	_wound_to(w, mara, "arm_right", SimNpcCombat.BREAK_OFF_STATE)
	w.step()
	var lost: bool = not (_order(w, mara) is Dictionary)
	var ok: bool = held and lost
	if not ok:
		push_error("ATTACK-BREAK: held %s, order gone after a critical wound %s" % [held, lost])
	return ok


func _the_record_is_plain_values() -> bool:
	var w: Variant = _world()
	var mara: int = _mara(w)
	var goal: Vector2i = _reachable_away(w, _tile(w, mara), 4, SEARCH_RADIUS)
	if goal.x < 0:
		push_error("PLAIN: no goal")
		return false
	w.commands.push(_cmd(mara, {"kind": "go", "tx": goal.x, "ty": goal.y}))
	w.step()
	var record: Dictionary = _order(w, mara) as Dictionary
	var back: Variant = JSON.parse_string(JSON.stringify(record))
	var ok: bool = back is Dictionary and String((back as Dictionary).get("kind", "")) == "go" and int((back as Dictionary).get("tx", -1)) == goal.x and int((back as Dictionary).get("ty", -1)) == goal.y
	if not ok:
		push_error("PLAIN: record did not survive a JSON round trip: %s" % JSON.stringify(record))
	return ok


func _find_row(rows: Array[Dictionary], text: String, kind: String) -> bool:
	for r in rows:
		var command: Dictionary = r.get("command", {}) as Dictionary
		if String(r.get("text", "")) == text and String(command.get("type", "")) == SimOrders.COMMAND and String(command.get("kind", "")) == kind:
			return true
	return false


func _has_order_row(rows: Array[Dictionary], kind: String) -> bool:
	for r in rows:
		var command: Dictionary = r.get("command", {}) as Dictionary
		if String(command.get("type", "")) == SimOrders.COMMAND and String(command.get("kind", "")) == kind:
			return true
	return false
