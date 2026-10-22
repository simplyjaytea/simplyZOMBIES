extends SceneTree
# The ten-day playtest driver (alpha plan A24). One survivor, scripted to play the way a careful
# first-time player does, through the shipped district for ten in-game days, with a line per day of
# what the run looked like: food, water, wounds, infection, kills, deaths, the colony's headcount
# and what each tick cost.
#
# It is a driver and not a gate, and it says so: `check_m2_balance.gd` is the gate, and its FULL
# tier runs a colony with nobody at the controls. This one puts somebody at them. Nothing here
# asserts a band -- a ten-day campaign at the shipped 256 tiles is about three hours of headless
# GDScript on a four-core container, so it is run by hand, and its numbers are recorded with the
# commit that used them (docs/23's record, and the report in the project's planning folder). What
# it does assert is that the scripted survivor actually played: a run in which the bot never
# searched, never ate, never slept or never swung measured an idle body, and it ends
# `PLAYTEST_FAIL` rather than reporting a survivable game that nobody tried to survive.
#
# The survivor goes through the commands a player's keys push -- `walk.to`, `container.open`,
# `container.takeAll`, `item.use`, `treat.context`, `aim`, `swing`, `fire`, `use.context` -- and
# reads only what a player could reasonably know: what is on their own body, what is in their own
# pack and on the colony's floor, and which zombies are within a few metres. The one thing it
# knows that a player does not is where the unsearched containers are, which a player learns by
# walking the streets and a ten-day script cannot afford to.
#
# The plan, in priority order, re-decided every tick:
#   1. Held or something in reach: fight (swing, or fire when a gun is loaded and the target is
#      not on top of you).
#   2. Otherwise back off at a jog, homeward where home is not through them; at home, or with a
#      weapon that outreaches a shambler's hands against a lone one, stand and let it come.
#   3. Bleeding with nothing near: treat (the T key's own choice of treatment).
#   4. Hungry or thirsty: eat or drink from the pack; with nothing in it, fetch from the colony's
#      floor; thirsty with nothing on the floor either, walk to the nearest well and press E.
#   5. Dusk or night, or exhausted: go home, lie down in a free bed, sleep until dawn.
#   6. Day: scavenge the nearest unsearched container within reach of home, keep what is useful
#      (food, water, medicine, weapons, ammunition), drop the rest, carry the surplus home.
#
# Environment: PLAYTEST_SEED (20260805), PLAYTEST_DAYS (10), PLAYTEST_TILES (the shipped
# district), PLAYTEST_LOG (a path for the JSON-lines log; stdout always carries the table).
#
#   npm run godot:playtest
#   PLAYTEST_SEED=404 PLAYTEST_LOG=/tmp/p404.jsonl npm run godot:playtest

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimStances = preload("res://sim/stances.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const Clock = preload("res://sim/time/clock.gd")

const DAYS: int = 10
const SEED: int = 20260805

# How far the survivor looks for trouble, in metres. A few metres is what a player watching the
# screen around their own body notices; the rest of the district is theirs to be surprised by.
const THREAT_RADIUS: float = 8.0
const MOB_RADIUS: float = 6.0
const MOB_SIZE: int = 3
# How far from home the survivor will walk to a container, in tiles. Wide enough to reach the
# neighbourhood of a 256-tile district and the whole of a 64-tile one.
const SCAVENGE_RADIUS: float = 70.0
# The need line at which a careful player eats or drinks: needs.gd's own SEEK_START, the line the
# colonists' autonomy reaches for food at.
const EAT_AT: float = SimNeeds.SEEK_START
const REST_AT: float = 25.0
# What the survivor keeps in the pack before carrying the rest home.
const KEEP_FOOD: int = 2
const KEEP_DRINK: int = 2
const HAUL_AT_FRACTION: float = 0.8
# A walk that has not moved the body this many ticks is stuck; the target is given up.
const STUCK_TICKS: int = 200
const REACH: float = 1.4
# The reach at which standing your ground beats backing off: a weapon that lands before a
# shambler's hands close (a pipe's 1.2 does; a kitchen knife's 0.9 does not).
const HOLD_REACH: float = 1.1

var _days: int = int(OS.get_environment("PLAYTEST_DAYS")) if OS.get_environment("PLAYTEST_DAYS") != "" else DAYS
var _seed: int = int(OS.get_environment("PLAYTEST_SEED")) if OS.get_environment("PLAYTEST_SEED") != "" else SEED
var _tiles: int = int(OS.get_environment("PLAYTEST_TILES")) if OS.get_environment("PLAYTEST_TILES") != "" else SimTileMap.DISTRICT_TILES
var _log_path: String = OS.get_environment("PLAYTEST_LOG")
# Every N ticks, one line of what the survivor is doing and why. 0 is off.
var _trace: int = int(OS.get_environment("PLAYTEST_TRACE")) if OS.get_environment("PLAYTEST_TRACE") != "" else 0

var w: Variant = null
var _log: FileAccess = null

# The bot's working memory.
var _goal: String = "idle"
var _target: int = -1
var _target_tile: Vector2i = Vector2i(-1, -1)
var _walking_to: Vector2i = Vector2i(-1, -1)
var _last_pos: Vector2 = Vector2.ZERO
var _still_ticks: int = 0
var _given_up: Dictionary = {}
var _open_step: int = 0
var _home: Rect2i = Rect2i()
var _home_tile: Vector2i = Vector2i(-1, -1)

# Per-day and whole-run counters, all read off the bus or the bot's own actions.
var _day: Dictionary = {}
var _run_total: Dictionary = {}
var _tick_us: PackedInt64Array = PackedInt64Array()
# The roster as last seen, id -> {job, x, y}: a colonist can leave the colony without an
# `entity.killed` (a turn, a body taken off the books), so a departure is read off the roster.
var _roster: Dictionary = {}
var _accounted: Dictionary = {}
# Each colonist's swing state as last polled, id -> SwingState int. A swing is counted on the tick
# it leaves Idle; the fight is read off the bus and the `swing` component, never by driving it.
var _swing_state: Dictionary = {}
const ROSTER_EVERY: int = 20


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _log_path.is_empty():
		_log = FileAccess.open(_log_path, FileAccess.WRITE)
	var boot_t0: int = Time.get_ticks_msec()
	w = SimBoot.playable(_seed, _tiles)["world"]
	w.events.drain()
	_home = SimTileMap.annex_rect(w.tilemap)
	_home_tile = _home.position + _home.size / 2
	_emit({"kind": "boot", "seed": _seed, "tiles": _tiles, "days": _days, "boot_ms": Time.get_ticks_msec() - boot_t0,
		"colony": _colony().size(), "shamblers": _live_shamblers().size(), "containers": w.components.query(["searchable"]).size(),
		"home": [_home.position.x, _home.position.y, _home.size.x, _home.size.y]})
	print("PLAYTEST seed=%d tiles=%d days=%d colony=%d shamblers=%d" % [_seed, _tiles, _days, _colony().size(), _live_shamblers().size()])
	_run_total = _blank_counters()
	_day = _blank_counters()
	var end_tick: int = Clock.tick_on_day(_days + 1, 0.0)
	var last_day: int = Clock.day_number(int(w.tick))
	var wall_t0: int = Time.get_ticks_msec()
	while int(w.tick) < end_tick:
		_think()
		var t0: int = Time.get_ticks_usec()
		w.step()
		_tick_us.append(Time.get_ticks_usec() - t0)
		_observe()
		var day: int = Clock.day_number(int(w.tick))
		if day != last_day:
			_close_day(last_day)
			last_day = day
		if bool(w.runOver):
			_close_day(last_day)
			break
	var ok: bool = _summary(Time.get_ticks_msec() - wall_t0)
	if _log != null:
		_log.close()
	if ok:
		print("PLAYTEST_OK")
		quit(0)
	else:
		push_error("PLAYTEST_FAIL")
		quit(1)


# --- the scripted survivor --------------------------------------------------------------------

func _think() -> void:
	var me: int = int(w.player)
	if me < 0 or not w.entities.is_alive(me) or w.components.has_component(me, "corpse"):
		return
	var here: Vector2 = _pos(me)
	if here.x < 0.0:
		return
	_track_stuck(here)
	var phase: int = Clock.phase_of(int(w.tick))
	var sleeping: bool = w.components.has_component(me, "sleeping")
	if _trace > 0 and int(w.tick) % _trace == 0:
		var tn: Array = _threats(here, THREAT_RADIUS)
		var body: Variant = w.components.get_component(me, "body")
		print("TRACE t=%d goal=%s pos=(%.1f,%.1f) threats=%d nearest=%.2f held=%s sleeping=%s body=%s" % [int(w.tick), _goal, here.x, here.y, tn.size(), float((tn[0] as Dictionary)["d"]) if not tn.is_empty() else -1.0, str(w.components.has_component(me, "grabbed")), str(sleeping), str(body)])

	# 1-2. Trouble first.
	var near: Array = _threats(here, THREAT_RADIUS)
	if not near.is_empty():
		if sleeping:
			# A player woken by the screen fast-forward stopping: up, and deal with it.
			SimNeeds.wake(w, me)
			_day["woken"] = int(_day["woken"]) + 1
		var nearest: Dictionary = near[0] as Dictionary
		var dist: float = float(nearest["d"])
		var reach: float = _reach(me) + 0.5
		var held: bool = w.components.has_component(me, "grabbed")
		var mob: int = 0
		for t in near:
			if float((t as Dictionary)["d"]) <= MOB_RADIUS:
				mob += 1
		if held or dist <= reach:
			# Cornered, or already in hand: hit it (a swing while held is the struggle).
			if not held and _goal == "fight" and int(nearest["e"]) == _fight_target:
				_fight_ticks += 1
				if _fight_ticks > FIGHT_GIVE_UP_TICKS:
					# Swinging at it all this while and it neither falls nor reaches: a window or a
					# fence between. Leave it be.
					_ignored[_fight_target] = int(w.tick) + IGNORE_TICKS
					_fight_ticks = 0
					_set_goal("idle")
					_day["ignored"] = int(_day.get("ignored", 0)) + 1
					return
			else:
				_fight_target = int(nearest["e"])
				_fight_ticks = 0
			_strike(me, here, nearest)
			return
		if _loaded_gun(me) and dist <= 10.0:
			_shoot(me, here, nearest)
			return
		if _goal == "hold":
			_hold_ticks += 1
			if _hold_ticks > HOLD_GIVE_UP_TICKS:
				# Waited and it never came: something stands between. Leave it be and get on.
				_ignored[int(nearest["e"])] = int(w.tick) + IGNORE_TICKS
				_hold_ticks = 0
				_set_goal("idle")
				_day["ignored"] = int(_day.get("ignored", 0)) + 1
				return
		else:
			_hold_ticks = 0
		if mob <= 1 and _reach(me) >= HOLD_REACH and dist <= MOB_RADIUS:
			# One, and a weapon long enough to land before its hands do: stand, face it, and let it
			# walk into the swing.
			_set_goal("hold")
			_stop()
			var hp: Vector2 = nearest["p"] as Vector2
			w.commands.push({"type": "aim", "radians": atan2(hp.y - here.y, hp.x - here.x)})
			_stance(SimStances.Stance.Walk)
			return
		if dist <= MOB_RADIUS:
			if _at_home(here):
				# Home and they are coming: hold inside and take them as they reach you.
				_set_goal("hold")
				_stop()
				var ap: Vector2 = nearest["p"] as Vector2
				w.commands.push({"type": "aim", "radians": atan2(ap.y - here.y, ap.x - here.x)})
				return
			# Otherwise do not trade blows with a knife: back off at a jog, homeward when home is
			# not through them.
			# A box with a zombie standing by it is not worth walking back to; pick another.
			if _target >= 0 and _pos(_target).distance_to(nearest["p"] as Vector2) <= THREAT_RADIUS:
				_given_up[_target] = true
				_day["gave_up"] = int(_day["gave_up"]) + 1
				_target = -1
			_set_goal("evade")
			_stance(SimStances.Stance.Jog)
			var away: Vector2 = Vector2.ZERO
			for t in near:
				if float((t as Dictionary)["d"]) <= MOB_RADIUS:
					away += (here - ((t as Dictionary)["p"] as Vector2)).normalized()
			var home_dir: Vector2 = (Vector2(_home_tile) + Vector2(0.5, 0.5) - here).normalized()
			if away.length() > 0.0 and home_dir.dot(away.normalized()) > -0.2:
				_go(_home_tile)
			else:
				var a: Vector2 = away if away.length() > 0.0 else home_dir
				w.commands.push({"type": "move", "dx": a.x, "dy": a.y})
				_walking_to = Vector2i(-1, -1)
			return
	elif _goal == "evade" or _goal == "hold" or _goal == "fight":
		_stance(SimStances.Stance.Walk)
		_set_goal("idle")

	if sleeping:
		# Up at dawn, the way a player lifts their hand off the fast-forward.
		if phase == Clock.Phase.Dawn or phase == Clock.Phase.Day:
			if float(SimNeeds.of(w, me).get("rest", 0.0)) >= 60.0 or phase == Clock.Phase.Day:
				SimNeeds.wake(w, me)
		return

	# 3. Bleeding with nothing near: treat.
	if _bleeding(me) and not w.components.has_component(me, "treatment"):
		if int(w.tick) % 40 == 0:
			w.commands.push({"type": "treat.context"})
			_day["treats"] = int(_day["treats"]) + 1
		return
	if w.components.has_component(me, "treatment"):
		return

	_equip_best(me)
	# An empty gun with nothing near: reload, as a player does between fights.
	var rw: Variant = w.components.get_component(me, "rangedWeapon")
	if rw is Dictionary and int((rw as Dictionary).get("mag", 0)) <= 0 and int(w.tick) % 100 == 50:
		w.commands.push({"type": "reload"})

	# 4. Food and water. Still at the well from the last press: keep pressing while E is the well.
	if _well_visit:
		_well_presses += 1
		if _well_presses <= WELL_PRESS_CAP and String(SimFortify.rung_of(w, me).get("verb", "")) == "well":
			w.commands.push({"type": "use.context"})
			_day["well"] = int(_day["well"]) + 1
			return
		_well_visit = false
		_well_presses = 0
	var n: Dictionary = SimNeeds.of(w, me)
	if float(n.get("thirst", 100.0)) < EAT_AT:
		if _consume(me, "drink"):
			return
	if float(n.get("hunger", 100.0)) < EAT_AT:
		if _consume(me, "food"):
			return

	# 5. Night: home and to bed.
	var night: bool = phase == Clock.Phase.Dusk or phase == Clock.Phase.Night
	if night or float(n.get("rest", 100.0)) < REST_AT:
		_bed_down(me, here)
		return

	# 6. Day: carry surplus home, then scavenge.
	if _goal == "haul" or _should_haul(me):
		_haul_home(me, here)
		return
	_scavenge(me, here)


func _set_goal(goal: String) -> void:
	if _goal != goal:
		_goal = goal
		_open_step = 0


var _retries: int = 0
# Pressing E at a well until it is no longer the well (drunk, then every empty filled).
var _well_visit: bool = false
var _well_presses: int = 0
# A visit is a drink or two and a bottle per empty; anything past this is a loop, not a visit.
const WELL_PRESS_CAP: int = 12
# A pile item the survivor stood on and could not pick up, and for how long.
var _fetch_item: int = -1
var _fetch_ticks: int = 0
const FETCH_GIVE_UP_TICKS: int = 40
# A zombie the survivor stood and waited for that never came (a wall or a fence between them): left
# alone until the tick stored here, unless it comes within reach or takes hold.
var _ignored: Dictionary = {}
var _hold_ticks: int = 0
const HOLD_GIVE_UP_TICKS: int = 300
const FIGHT_GIVE_UP_TICKS: int = 600
var _fight_target: int = -1
var _fight_ticks: int = 0
# A box or a thing on the ground with a zombie this close to it is not worth the walk.
const GUARDED_METRES: float = 10.0
const IGNORE_TICKS: int = 3000
const WANTED: Array[String] = ["food", "drink", "medical", "ammo", "weapon"]
func _go(tile: Vector2i) -> void:
	if tile == _walking_to:
		if w.components.has_component(int(w.player), "walkTo"):
			return
		# The walk let go short of the tile: no route from here, or a body in the way. Asked again
		# a few times, then `_arrived_or_failed` gives the target up.
		_retries += 1
	else:
		_retries = 0
		_still_ticks = 0
	_walking_to = tile
	w.commands.push({"type": "walk.to", "tx": tile.x, "ty": tile.y})


var _stance_asked: int = -1
func _stance(st: int) -> void:
	if st == _stance_asked:
		return
	_stance_asked = st
	w.commands.push({"type": "stance", "stance": st})


func _stop() -> void:
	w.commands.push({"type": "move", "dx": 0.0, "dy": 0.0})
	_walking_to = Vector2i(-1, -1)


func _track_stuck(here: Vector2) -> void:
	if here.distance_to(_last_pos) < 0.05:
		_still_ticks += 1
	else:
		_still_ticks = 0
	_last_pos = here


func _arrived_or_failed(here: Vector2, tile: Vector2i) -> String:
	if here.distance_to(Vector2(tile) + Vector2(0.5, 0.5)) <= REACH:
		return "arrived"
	if _walking_to == tile and (_retries > 3 or _still_ticks > STUCK_TICKS):
		return "failed"
	return "walking"


func _strike(me: int, here: Vector2, t: Dictionary) -> void:
	_set_goal("fight")
	var p: Vector2 = t["p"] as Vector2
	_stop()
	w.commands.push({"type": "aim", "radians": atan2(p.y - here.y, p.x - here.x)})
	if _loaded_gun(me) and float(t["d"]) > 1.0:
		w.commands.push({"type": "fire"})
		_day["shots"] = int(_day["shots"]) + 1
	else:
		w.commands.push({"type": "swing"})
		_day["swings"] = int(_day["swings"]) + 1


func _shoot(_me: int, here: Vector2, t: Dictionary) -> void:
	_set_goal("fight")
	var p: Vector2 = t["p"] as Vector2
	_stop()
	w.commands.push({"type": "aim", "radians": atan2(p.y - here.y, p.x - here.x)})
	w.commands.push({"type": "fire"})
	_day["shots"] = int(_day["shots"]) + 1


func _consume(me: int, what: String) -> bool:
	var item: int = _carried_kind(me, what)
	if item >= 0:
		w.commands.push({"type": "item.use", "item": item})
		_day["ate" if what == "food" else "drank"] = int(_day["ate" if what == "food" else "drank"]) + 1
		return true
	# Nothing in the pack: the colony's floor, if it has any.
	var stock: int = _stock_kind(what)
	if stock < 0:
		return _drink_at_well(me) if what == "drink" else false
	_set_goal("fetch")
	var sp: Vector2 = _pos(stock)
	var tile := Vector2i(floori(sp.x), floori(sp.y))
	match _arrived_or_failed(_pos(me), tile):
		"arrived":
			# Standing on it and the pickup still does not take (no room, nothing the pack can
			# hold): leave it, or a drink nobody can lift would keep the survivor from the well.
			_fetch_ticks = _fetch_ticks + 1 if stock == _fetch_item else 0
			_fetch_item = stock
			if _fetch_ticks > FETCH_GIVE_UP_TICKS:
				_given_up[stock] = true
				return false
			w.commands.push({"type": "item.pickup", "item": stock})
		"failed":
			_given_up[stock] = true
			return false
		_:
			_go(tile)
	return true


# Nothing to drink in the pack or on the pile: the nearest well (or river source), walked to and
# E pressed, the way a player does it. A well with a zombie standing by it is not worth the walk
# while there is thirst to spare, the same call the survivor makes about a guarded box; with the
# pool empty it goes anyway. At the well it presses E for as long as E is the well: drink, then
# fill every empty bottle carried, so the next drink is in the pack and not past the gate. Only
# when E there would be the well -- anything else E would do first (a loose item, a box) is not a
# drink, and the plan falls through.
func _drink_at_well(me: int) -> bool:
	var here: Vector2 = _pos(me)
	var source: int = SimNeeds.nearest_water_source(w, here.x, here.y)
	if source < 0:
		return false
	var sp: Vector2 = _pos(source)
	if float(SimNeeds.of(w, me).get("thirst", 100.0)) > 0.0 and not _threats(sp, THREAT_RADIUS).is_empty():
		return false
	var tile := Vector2i(floori(sp.x), floori(sp.y))
	_set_goal("well")
	match _arrived_or_failed(here, tile):
		"arrived":
			_stop()
			if String(SimFortify.rung_of(w, me).get("verb", "")) != "well":
				return false
			w.commands.push({"type": "use.context"})
			_well_visit = true
			_day["well"] = int(_day["well"]) + 1
		"failed":
			return false
		_:
			_go(_stand_tile(tile))
	return true


func _bed_down(me: int, here: Vector2) -> void:
	_set_goal("bed")
	var bed: int = _free_bed(here)
	var tile: Vector2i = _home_tile
	if bed >= 0:
		var bp: Vector2 = _pos(bed)
		tile = Vector2i(floori(bp.x), floori(bp.y))
	var state: String = _arrived_or_failed(here, tile)
	if state == "arrived" or (state == "failed" and _at_home(here)):
		_stop()
		w.commands.push({"type": "use.context"})
		_open_step += 1
		# The E ladder picks up a loose item or opens a box before it reaches the bed, so a third
		# press that has still not put the survivor to bed lies down where they stand -- the same
		# `start_sleep` the rung calls, counted so the report can say how often it happened.
		if _open_step > 3:
			SimNeeds.start_sleep(w, me, bed)
			_day["bed_fallback"] = int(_day["bed_fallback"]) + 1
		return
	_go(tile)


func _should_haul(me: int) -> bool:
	var cap: float = SimInventory.capacity_of(w, me)
	if cap <= 0.0:
		return false
	return SimInventory.carried_mass_kg(w, me) >= HAUL_AT_FRACTION * cap


func _haul_home(me: int, here: Vector2) -> void:
	_set_goal("haul")
	if not _at_home(here) or not SimNeeds.is_stockpile_tile(w, floori(here.x), floori(here.y)):
		var state: String = _arrived_or_failed(here, _home_tile)
		if state != "arrived" and not (state == "failed" and _at_home(here)):
			_go(_home_tile)
			return
	_stop()
	# Keep a little for the road, put the rest on the colony's floor.
	var food: int = 0
	var drink: int = 0
	var dropped: int = 0
	for item in SimInventory.carried_items(w, me):
		if SimInventory.equipped_items(w, me).has(item):
			continue
		var kind: String = _kind_of(item)
		if kind == "food":
			food += 1
			if food <= KEEP_FOOD:
				continue
		elif kind == "drink":
			drink += 1
			if drink <= KEEP_DRINK:
				continue
		elif kind == "medical" or kind == "ammo" or kind == "weapon" or kind == "empty":
			continue
		w.commands.push({"type": "item.drop", "item": item})
		dropped += 1
	_day["hauled"] = int(_day["hauled"]) + dropped
	_goal = "idle"


func _scavenge(me: int, here: Vector2) -> void:
	if _goal != "scavenge" or _target < 0 or _given_up.has(_target):
		_target = _next_container(here)
		var item: int = _next_item(here)
		if item >= 0 and (_target < 0 or here.distance_to(_pos(item)) < here.distance_to(_pos(_target))):
			_target = item
		_set_goal("scavenge")
		if _target < 0:
			# Nothing left in reach: stand at home, which is what a run looks like once a
			# neighbourhood is picked clean.
			if not _at_home(here):
				_go(_home_tile)
			return
		var cp: Vector2 = _pos(_target)
		_target_tile = _stand_tile(Vector2i(floori(cp.x), floori(cp.y)))
	match _arrived_or_failed(here, _target_tile):
		"arrived":
			if w.components.has_component(_target, "searchable"):
				_loot(me)
			else:
				_pick_up(me)
		"failed":
			_given_up[_target] = true
			_day["gave_up"] = int(_day["gave_up"]) + 1
			_target = -1
		_:
			_go(_target_tile)


# Open, take everything, drop what is not worth carrying, close: three ticks, so each command
# lands on the state the one before it left.
func _loot(me: int) -> void:
	_stop()
	match _open_step:
		0:
			w.commands.push({"type": "container.open", "container": _target})
			_open_step = 1
		1:
			if SimContainers.opened_by(w, me) != _target:
				_given_up[_target] = true
				_target = -1
				_open_step = 0
				return
			w.commands.push({"type": "container.takeAll"})
			_open_step = 2
		_:
			w.commands.push({"type": "container.close"})
			var junk: int = 0
			for item in SimInventory.carried_items(w, me):
				if SimInventory.equipped_items(w, me).has(item):
					continue
				if _kind_of(item) == "junk":
					w.commands.push({"type": "item.drop", "item": item})
					junk += 1
			_day["searched"] = int(_day["searched"]) + 1
			_given_up[_target] = true
			_target = -1
			_open_step = 0


# A useful thing lying loose: the district scatters most of its loot on the ground (47 containers
# on a whole 256-tile map), so a survivor who only opened boxes would starve beside it.
func _pick_up(me: int) -> void:
	_stop()
	if _open_step == 0:
		w.commands.push({"type": "item.pickup", "item": _target})
		_open_step = 1
		return
	if SimInventory.owns(w, me, _target):
		_day["picked"] = int(_day.get("picked", 0)) + 1
	_given_up[_target] = true
	_target = -1
	_open_step = 0


func _next_item(here: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	var home_c: Vector2 = Vector2(_home_tile) + Vector2(0.5, 0.5)
	for item in SimInventory.ground_items(w):
		if _given_up.has(int(item)) or w.components.has_component(int(item), "corpse"):
			continue
		var p: Vector2 = _pos(int(item))
		if p.x < 0.0 or SimNeeds.is_stockpile_tile(w, floori(p.x), floori(p.y)):
			continue
		if p.distance_to(home_c) > SCAVENGE_RADIUS:
			continue
		if not WANTED.has(_kind_of(int(item))):
			continue
		if not _threats(p, GUARDED_METRES).is_empty():
			continue
		var d: float = here.distance_to(p)
		if d < best_d:
			best_d = d
			best = int(item)
	return best


func _equip_best(me: int) -> void:
	if int(w.tick) % 100 != 0:
		return
	var best: int = -1
	var best_dmg: float = 0.0
	var held: float = 0.0
	if not SimMelee.is_unarmed(w, me):
		var mw: Variant = w.components.get_component(me, "meleeWeapon")
		if mw is Dictionary:
			held = float((mw as Dictionary).get("damage", 0.0))
	for item in SimInventory.carried_items(w, me):
		if SimInventory.equipped_items(w, me).has(item):
			continue
		var prof: Variant = SimItems.melee_profile_of(w, int(item))
		if prof is Dictionary and float((prof as Dictionary).get("damage", 0.0)) > maxf(held, best_dmg):
			best = int(item)
			best_dmg = float((prof as Dictionary).get("damage", 0.0))
	if best >= 0:
		w.commands.push({"type": "item.equip", "item": best})
		_day["equipped"] = int(_day["equipped"]) + 1


# --- what the survivor can see -----------------------------------------------------------------

func _pos(e: int) -> Vector2:
	var p: Variant = w.components.get_component(e, "position")
	if not (p is Dictionary):
		return Vector2(-1, -1)
	return Vector2(float((p as Dictionary)["x"]), float((p as Dictionary)["y"]))


func _live_shamblers() -> Array[int]:
	var out: Array[int] = []
	for e in w.components.query(["shambler", "position"]):
		if not w.components.has_component(int(e), "corpse"):
			out.append(int(e))
	return out


# Zombies and raiders within `radius`, nearest first, as {e, p, d}.
func _threats(here: Vector2, radius: float) -> Array:
	var out: Array = []
	for kind in ["shambler", "raider"]:
		for e in w.components.query([kind, "position"]):
			if w.components.has_component(int(e), "corpse"):
				continue
			var p: Vector2 = _pos(int(e))
			var d: float = here.distance_to(p)
			if d <= radius:
				if int(_ignored.get(int(e), -1)) > int(w.tick) and d > _reach(int(w.player)) + 0.5 and not w.components.has_component(int(w.player), "grabbed"):
					continue
				out.append({"e": int(e), "p": p, "d": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	return out


func _reach(me: int) -> float:
	var mw: Variant = w.components.get_component(me, "meleeWeapon")
	return float((mw as Dictionary).get("reachMetres", 0.6)) if mw is Dictionary else 0.6


func _loaded_gun(me: int) -> bool:
	var rw: Variant = w.components.get_component(me, "rangedWeapon")
	if not (rw is Dictionary):
		return false
	var d: Dictionary = rw as Dictionary
	return int(d.get("mag", 0)) > 0 and String(d.get("blocked", "")) == ""


func _bleeding(me: int) -> bool:
	var inj: Variant = w.components.get_component(me, "injuries")
	if not (inj is Dictionary):
		return false
	for wd in (inj as Dictionary).get("wounds", []) as Array:
		if bool((wd as Dictionary).get("bleeding", false)) and String((wd as Dictionary).get("bandage", "none")) == "none":
			return true
	return false


func _at_home(here: Vector2) -> bool:
	return _home.has_point(Vector2i(floori(here.x), floori(here.y)))


func _base(item: int) -> String:
	var b: Variant = w.components.get_component(item, "itemBase")
	return String((b as Dictionary).get("baseId", "")) if b is Dictionary else ""


func _kind_of(item: int) -> String:
	var base: String = _base(item)
	if base.is_empty():
		return "junk"
	if SimNeeds.is_food(w, base):
		return "food"
	if SimNeeds.is_drink(w, base):
		return "drink"
	# An empty bottle is kept, not junk: the well fills it, and a survivor who drops it on the
	# colony floor can never drink from the well again. docs/23 "Balance after the alpha" (a).
	if base == "item.water.bottle.empty":
		return "empty"
	if SimTreatment.verb_of_supply(w, item) != "":
		return "medical"
	if base.begins_with("item.ammo"):
		return "ammo"
	if SimItems.melee_profile_of(w, item) != null or SimItems.ranged_profile_of(w, item) != null:
		return "weapon"
	# Clothing, a bag, a light: kept, because a careful player keeps them; scrap and the rest go.
	if w.components.has_component(item, "container") or SimInventory.equip_slot_for(w, item) != null:
		return "gear"
	return "junk"


func _carried_kind(me: int, what: String) -> int:
	for item in SimInventory.carried_items(w, me):
		if _kind_of(int(item)) == what:
			if what == "drink" and _base(int(item)) == SimNeeds.UNTREATED_ID and float(SimNeeds.of(w, me).get("thirst", 100.0)) > SimNeeds.SOFT:
				continue
			return int(item)
	return -1


func _stock_kind(what: String) -> int:
	for item in SimNeeds.stockpile_items(w):
		if _given_up.has(int(item)):
			continue
		if _kind_of(int(item)) == what and w.components.has_component(int(item), "position"):
			return int(item)
	return -1


func _free_bed(here: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	for bed in w.components.query(["bed", "position"]):
		var b: Dictionary = w.components.get_component(int(bed), "bed") as Dictionary
		var by: int = int(b.get("occupiedBy", -1))
		if by >= 0 and by != int(w.player):
			continue
		var d: float = here.distance_to(_pos(int(bed)))
		if d < best_d:
			best_d = d
			best = int(bed)
	return best


func _next_container(here: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	var home_c: Vector2 = Vector2(_home_tile) + Vector2(0.5, 0.5)
	for c in w.components.query(["searchable", "position"]):
		if _given_up.has(int(c)):
			continue
		var s: Dictionary = w.components.get_component(int(c), "searchable") as Dictionary
		if bool(s.get("searched", false)):
			continue
		var p: Vector2 = _pos(int(c))
		if p.distance_to(home_c) > SCAVENGE_RADIUS:
			continue
		if not _threats(p, GUARDED_METRES).is_empty():
			continue
		var d: float = here.distance_to(p)
		if d < best_d:
			best_d = d
			best = int(c)
	return best


# The tile to stand on to reach something: its own tile when that is floor, else the nearest open
# neighbour.
func _stand_tile(t: Vector2i) -> Vector2i:
	if not SimTileMap.is_solid(w.tilemap, t.x, t.y):
		return t
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = t + (d as Vector2i)
		if not SimTileMap.is_solid(w.tilemap, n.x, n.y):
			return n
	return t


func _colony() -> Array[int]:
	var out: Array[int] = []
	for ent in w.components.query(["needs", "body"]):
		if w.components.has_component(int(ent), "corpse") or w.components.has_component(int(ent), "recruit"):
			continue
		var body: Variant = w.components.get_component(int(ent), "body")
		if body is Dictionary and SimHealth.is_alive(body as Dictionary):
			out.append(int(ent))
	return out


# --- observation --------------------------------------------------------------------------------

func _blank_counters() -> Dictionary:
	return {
		"kills": 0, "player_kills": 0, "deaths": 0, "turned": 0, "bites": 0, "player_bites": 0,
		"hits_taken": 0, "grabs": 0, "player_grabs": 0, "packets": 0, "raids": 0, "recruits": 0,
		"searched": 0, "picked": 0, "ignored": 0, "npc_searches": 0, "ate": 0, "drank": 0, "swings": 0, "shots": 0, "treats": 0,
		"hauled": 0, "gave_up": 0, "equipped": 0, "woken": 0, "bed_fallback": 0, "slept_ticks": 0,
		"successions": 0, "left": 0, "well": 0,
		"colonist_swings": 0, "colonist_shots": 0, "colonist_hits": 0, "colonist_kills": 0,
	}


func _observe() -> void:
	var me: int = int(w.player)
	if w.components.has_component(me, "sleeping"):
		_day["slept_ticks"] = int(_day["slept_ticks"]) + 1
	for e in w.events.drained:
		var ev: Dictionary = e as Dictionary
		match String(ev.get("type", "")):
			"entity.killed":
				var victim: int = int(ev.get("entity", -1))
				if w.components.has_component(victim, "shambler"):
					_day["kills"] = int(_day["kills"]) + 1
					if int(ev.get("killer", -2)) == me:
						_day["player_kills"] = int(_day["player_kills"]) + 1
					elif w.components.has_component(int(ev.get("killer", -2)), "needs"):
						_day["colonist_kills"] = int(_day["colonist_kills"]) + 1
				elif not w.components.has_component(victim, "raider") and (w.components.has_component(victim, "needs") or w.components.has_component(victim, "identity") or victim == me):
					_day["deaths"] = int(_day["deaths"]) + 1
					_accounted[victim] = true
					var last: Dictionary = _roster.get(victim, {}) as Dictionary
					_emit({"kind": "death", "tick": int(w.tick), "day": Clock.day_number(int(w.tick)), "entity": victim, "player": victim == me, "cause": String(ev.get("cause", ev.get("need", "wounds" if ev.has("killer") else "other"))), "job": last.get("job", ""), "x": last.get("x", -1.0), "y": last.get("y", -1.0)})
			"survivor.turned":
				_day["turned"] = int(_day["turned"]) + 1
			"bite.landed":
				_day["bites"] = int(_day["bites"]) + 1
				if int(ev.get("victim", -1)) == me:
					_day["player_bites"] = int(_day["player_bites"]) + 1
			"weapon.fired":
				var shooter: int = int(ev.get("entity", -1))
				if shooter != me and w.components.has_component(shooter, "needs"):
					_day["colonist_shots"] = int(_day["colonist_shots"]) + 1
			"attack.connected":
				var attacker: int = int(ev.get("attacker", -1))
				if attacker != me and w.components.has_component(attacker, "needs") and w.components.has_component(int(ev.get("target", -1)), "shambler"):
					_day["colonist_hits"] = int(_day["colonist_hits"]) + 1
				if w.components.has_component(int(ev.get("target", -1)), "needs"):
					_day["hits_taken"] = int(_day["hits_taken"]) + 1
			"grab.started":
				_day["grabs"] = int(_day["grabs"]) + 1
				if int(ev.get("victim", -1)) == me:
					_day["player_grabs"] = int(_day["player_grabs"]) + 1
			"director.packet":
				_day["packets"] = int(_day["packets"]) + 1
			"director.raid":
				if int(ev.get("size", 0)) > 0:
					_day["raids"] = int(_day["raids"]) + 1
			"recruit.arrived":
				_day["recruits"] = int(_day["recruits"]) + 1
			"recruit.left":
				_day["left"] = int(_day["left"]) + 1
				_accounted[int(ev.get("entity", -1))] = true
				_emit({"kind": "left", "tick": int(w.tick), "day": Clock.day_number(int(w.tick)), "entity": int(ev.get("entity", -1)), "reason": String(ev.get("reason", ""))})
			"container.searched":
				if int(ev.get("actor", -1)) != me:
					_day["npc_searches"] = int(_day["npc_searches"]) + 1
			"player.succeeded", "succession", "player.changed":
				_day["successions"] = int(_day["successions"]) + 1
	_count_colonist_swings(me)
	if int(w.tick) % ROSTER_EVERY == 0:
		_roster_diff()


# A colonist's swing, counted on the tick its `swing` leaves Idle. Polled off the component rather
# than evented, because melee.gd publishes no swing-started event and the driver must not change
# the game to get one.
func _count_colonist_swings(me: int) -> void:
	for ent in w.components.query(["swing", "needs"]):
		var id: int = int(ent)
		if id == me:
			continue
		var state: int = int((w.components.get_component(id, "swing") as Dictionary)["state"])
		if int(_swing_state.get(id, 0)) == 0 and state != 0:
			_day["colonist_swings"] = int(_day["colonist_swings"]) + 1
		_swing_state[id] = state


# Who was in the colony last look and is not now, with no event that said why: a death the event
# stream did not carry (the old counter missed every colonist who bled out), logged with the job
# they were on and where they stood.
func _roster_diff() -> void:
	var now: Dictionary = {}
	for ent in _colony():
		var job: Variant = w.components.get_component(ent, "job")
		var p: Vector2 = _pos(ent)
		now[ent] = {"job": String((job as Dictionary).get("kind", "")) if job is Dictionary else "", "x": snappedf(p.x, 0.1), "y": snappedf(p.y, 0.1)}
	for ent in _roster:
		if now.has(ent) or _accounted.has(ent):
			continue
		_accounted[ent] = true
		var last: Dictionary = _roster[ent] as Dictionary
		var body: Variant = w.components.get_component(int(ent), "body")
		var dead: bool = w.components.has_component(int(ent), "corpse") or not (body is Dictionary and SimHealth.is_alive(body as Dictionary))
		var inj: Variant = w.components.get_component(int(ent), "injuries")
		var lost: float = float((inj as Dictionary).get("bloodLoss", 0.0)) if inj is Dictionary else 0.0
		var cause: String = ("dead, blood loss %.2f" % lost) if dead else "gone"
		if dead:
			_day["deaths"] = int(_day["deaths"]) + 1
		else:
			_day["left"] = int(_day["left"]) + 1
		_emit({"kind": "death" if dead else "gone", "tick": int(w.tick), "day": Clock.day_number(int(w.tick)), "entity": int(ent), "player": int(ent) == int(w.player), "cause": cause, "job": last["job"], "x": last["x"], "y": last["y"]})
		print("LOST %d tick=%d day=%d %s job=%s at (%.1f, %.1f)" % [int(ent), int(w.tick), Clock.day_number(int(w.tick)), cause, String(last["job"]), float(last["x"]), float(last["y"])])
	_roster = now


func _close_day(day: int) -> void:
	var colony: Array[int] = _colony()
	var me: int = int(w.player)
	var n: Dictionary = SimNeeds.of(w, me) if w.components.has_component(me, "needs") else {}
	var food_stock: int = 0
	var drink_stock: int = 0
	for item in SimNeeds.stockpile_items(w):
		var k: String = _kind_of(int(item))
		if k == "food":
			food_stock += 1
		elif k == "drink":
			drink_stock += 1
	var food_carried: int = 0
	var drink_carried: int = 0
	var wounds: int = 0
	var bleeding: int = 0
	var infected: int = 0
	var hungry: int = 0
	var thirsty: int = 0
	for ent in colony:
		for item in SimInventory.carried_items(w, int(ent)):
			var k2: String = _kind_of(int(item))
			if k2 == "food":
				food_carried += 1
			elif k2 == "drink":
				drink_carried += 1
		var inj: Variant = w.components.get_component(int(ent), "injuries")
		if inj is Dictionary:
			for wd in (inj as Dictionary).get("wounds", []) as Array:
				wounds += 1
				if bool((wd as Dictionary).get("bleeding", false)):
					bleeding += 1
		var zi: Variant = w.components.get_component(int(ent), "zombieInfection")
		if zi is Dictionary:
			for ex in (zi as Dictionary).get("exposures", []) as Array:
				if bool((ex as Dictionary).get("transmitted", false)) and not bool((ex as Dictionary).get("amputated", false)):
					infected += 1
					break
		var cn: Dictionary = SimNeeds.of(w, int(ent))
		if float(cn.get("hunger", 100.0)) < SimNeeds.SOFT:
			hungry += 1
		if float(cn.get("thirst", 100.0)) < SimNeeds.SOFT:
			thirsty += 1
	var times: PackedInt64Array = _tick_us.duplicate()
	times.sort()
	var mean_ms: float = 0.0
	for t in times:
		mean_ms += float(t)
	mean_ms = mean_ms / maxf(1.0, float(times.size())) / 1000.0
	var p99_ms: float = float(times[mini(times.size() - 1, int(float(times.size()) * 0.99))]) / 1000.0 if times.size() > 0 else 0.0
	var max_ms: float = float(times[times.size() - 1]) / 1000.0 if times.size() > 0 else 0.0
	var row: Dictionary = {
		"kind": "day", "day": day, "tick": int(w.tick),
		"headcount": colony.size(), "player_alive": colony.has(me),
		"hunger": snappedf(float(n.get("hunger", 0.0)), 0.1), "thirst": snappedf(float(n.get("thirst", 0.0)), 0.1), "rest": snappedf(float(n.get("rest", 0.0)), 0.1),
		"food_stock": food_stock, "drink_stock": drink_stock, "food_carried": food_carried, "drink_carried": drink_carried,
		"hungry": hungry, "thirsty": thirsty,
		"wounds": wounds, "bleeding": bleeding, "infected": infected,
		"live_shamblers": _live_shamblers().size(),
		"tick_ms_mean": snappedf(mean_ms, 0.01), "tick_ms_p99": snappedf(p99_ms, 0.01), "tick_ms_max": snappedf(max_ms, 0.01),
	}
	for key in _day.keys():
		row[key] = _day[key]
		_run_total[key] = int(_run_total.get(key, 0)) + int(_day[key])
	_emit(row)
	print("DAY %2d head=%d alive=%s hunger=%5.1f thirst=%5.1f rest=%5.1f food=%d+%d drink=%d+%d wounds=%d bleed=%d infected=%d bites=%d kills=%d(you %d) deaths=%d left=%d searched=%d picked=%d ate=%d drank=%d well=%d swings=%d grabs=%d(you %d) packets=%d raids=%d colonist=swings %d hits %d shots %d kills %d live=%d tick=%.2f/%.2f/%.2f ms" % [
		day, colony.size(), str(colony.has(me)), float(row["hunger"]), float(row["thirst"]), float(row["rest"]),
		food_stock, food_carried, drink_stock, drink_carried, wounds, bleeding, infected, int(_day["bites"]),
		int(_day["kills"]), int(_day["player_kills"]), int(_day["deaths"]), int(_day["left"]), int(_day["searched"]), int(_day["picked"]), int(_day["ate"]), int(_day["drank"]), int(_day["well"]),
		int(_day["swings"]), int(_day["grabs"]), int(_day["player_grabs"]), int(_day["packets"]), int(_day["raids"]),
		int(_day["colonist_swings"]), int(_day["colonist_hits"]), int(_day["colonist_shots"]), int(_day["colonist_kills"]),
		int(row["live_shamblers"]), mean_ms, p99_ms, max_ms,
	])
	_day = _blank_counters()
	_tick_us = PackedInt64Array()


func _summary(wall_ms: int) -> bool:
	var colony: Array[int] = _colony()
	var day_reached: int = Clock.day_number(int(w.tick))
	var row: Dictionary = {"kind": "summary", "seed": _seed, "tiles": _tiles, "days": _days, "day_reached": day_reached,
		"run_over": bool(w.runOver), "survivors_end": colony.size(), "wall_s": wall_ms / 1000}
	for key in _run_total.keys():
		row[key] = _run_total[key]
	_emit(row)
	print("SUMMARY seed=%d day_reached=%d run_over=%s survivors=%d deaths=%d kills=%d(you %d) bites=%d searched=%d ate=%d drank=%d swings=%d colonist_swings=%d colonist_hits=%d colonist_shots=%d colonist_kills=%d wall=%ds" % [
		_seed, day_reached, str(bool(w.runOver)), colony.size(), int(_run_total["deaths"]), int(_run_total["kills"]),
		int(_run_total["player_kills"]), int(_run_total["bites"]), int(_run_total["searched"]), int(_run_total["ate"]),
		int(_run_total["drank"]), int(_run_total["swings"]),
		int(_run_total["colonist_swings"]), int(_run_total["colonist_hits"]), int(_run_total["colonist_shots"]), int(_run_total["colonist_kills"]), wall_ms / 1000,
	])
	# The driver's one assertion: the survivor played. Each behaviour is only owed when the run was
	# long enough for it to come up -- a quarter-day smoke never reaches a night, so it never owes
	# a sleep, and says so rather than passing quietly.
	var ok: bool = true
	if int(_run_total["searched"]) <= 0:
		push_error("PLAYTEST the scripted survivor never searched a container")
		ok = false
	if day_reached > 1 or _days > 1:
		if int(_run_total["slept_ticks"]) <= 0:
			push_error("PLAYTEST the scripted survivor never slept across a night")
			ok = false
	else:
		print("PLAYTEST skip: SLEEP -- the run never reached a night")
	if _days >= 3:
		if int(_run_total["ate"]) + int(_run_total["drank"]) <= 0:
			push_error("PLAYTEST the scripted survivor never ate or drank in %d days" % _days)
			ok = false
		if int(_run_total["swings"]) + int(_run_total["shots"]) <= 0:
			push_error("PLAYTEST the scripted survivor never fought in %d days" % _days)
			ok = false
	else:
		print("PLAYTEST skip: EAT, FIGHT -- under three days, neither is owed")
	return ok


func _emit(row: Dictionary) -> void:
	if _log != null:
		_log.store_line(JSON.stringify(row))
