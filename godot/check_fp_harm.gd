extends SceneTree
# The first-person harm readout: the HUD says what the player's body carries. Each lane builds the real hud.gd
# node, sets the sim state through the sim (a grab, a bite, a fixture write where a lane needs one), reads
# lines(), and prints one line. A FAIL names what is missing. Nothing is loosened.
#
#   CLEAN     a fresh player: no harm line and no weapon line.
#   HELD      a shambler grabs the player: the held line names F; a second holder reads as several things (a
#             fixture write to grabbed.sources); after the hold breaks by struggle the line is gone.
#   BITE      the first bite: the newest wound is a sentence on the sim's presentation word and the part label; it
#             is gone WOUND_HUD_TICKS after it landed; the bleeding line stays while a wound bleeds.
#   BLOOD     blood loss through the sim's own words (SimWounds.hud_clause); none at zero.
#   INFECTED  a transmitted exposure (a fixture write on zombieInfection, as infection.gd records one) shows the
#             infected line; a bite that did not transmit shows none.
#   WEAPON    the rifle profile (magSize 4, reloadTicks 70): Raise, then Steady (a press in Steady does nothing:
#             the shot fires on its own), then Recover after the shot, then nothing at Idle; Reload and Clearing.
#   DIGITS    every line every lane drew passes the digit scan.
#
# Plant (run by hand, restored): hud.gd's held test ignored; HELD goes red.
# Placement only: the district's zombies are removed and the other survivors parked (as in check_fp_encounter).

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimRangedMod = preload("res://sim/modules/ranged.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const Hud = preload("res://presentation/first_person/hud.gd")

const SEED: int = SimBoot.DISTRICT_SEED
const DISTRICT_TILES: int = 64
const NEAR_METRES: int = 3
const PARK_METRES: float = 40.0
const GRAB_TICKS: int = 400
const BITE_TICKS: int = 200
const HOLD_TICKS: int = 400
const SWING_EVERY_TICKS: int = 12
const RIFLE_MAG: int = 4
const RIFLE_RELOAD_TICKS: int = 70
const RIFLE_RANGE_METRES: float = 60.0

var _fails: int = 0
var _all_lines: Array[String] = []
var _sub_serial: int = 0
var _hud: Control = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_clean()
	_held()
	_bite()
	_blood()
	_infected()
	_weapon()
	_digits()
	print("FP_HARM_RESULT gate %s: %d FAIL" % ["green" if _fails == 0 else "red", _fails])
	quit(0 if _fails == 0 else 1)


func _ok(lane: String, message: String) -> void:
	print("FP_HARM_OK %s %s" % [lane, message])


func _fail(lane: String, message: String) -> void:
	_fails += 1
	push_error("FP_HARM_FAIL %s %s" % [lane, message])


func _info(lane: String, message: String) -> void:
	print("FP_HARM_INFO %s %s" % [lane, message])


# --- SETUP -----------------------------------------------------------------------------------------

func _boot() -> Dictionary:
	var boot: Dictionary = SimBoot.playable(SEED, DISTRICT_TILES)
	var world: Variant = boot["world"]
	var map: Variant = boot["map"]
	var player: int = int(world.player)
	var doomed: Array = []
	for ent in world.components.query(["zombieType"]):
		doomed.append(int(ent))
	for ent in world.components.query(["shambler"]):
		if not doomed.has(int(ent)):
			doomed.append(int(ent))
	for ent in doomed:
		world.despawn(int(ent))
	var far: Vector2i = _far_open_tile(map, _entity_pos(world, player))
	for ent in world.components.query(["identity", "position"]):
		if int(ent) != player:
			_place(world, int(ent), _centre(far))
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	return {"world": world, "map": map}


func _far_open_tile(map: Variant, here: Vector2) -> Vector2i:
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			if _open_ground(map, x, y) and _centre(Vector2i(x, y)).distance_to(here) >= PARK_METRES:
				return Vector2i(x, y)
	return Vector2i(1, 1)


func _open_ground(map: Variant, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= int(map.w) or y >= int(map.h):
		return false
	if SimTileMap.tile_at(map, x, y) != SimTileMap.Tile.Floor or SimTileMap.is_solid(map, x, y):
		return false
	return not SimTileMap.is_indoors(map, x, y)


func _open_line(map: Variant, metres: int) -> Dictionary:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			for d in dirs:
				var clear: bool = true
				for k in range(0, metres + 1):
					if not _open_ground(map, x + d.x * k, y + d.y * k):
						clear = false
						break
				if clear:
					return {"from": Vector2i(x, y), "dir": d}
	return {}


# A shambler 3 m away on the first open line the sim's own detail sees (the encounter gate's setup: lines that
# are not seen are passed over). Returns {} when none of the first candidates is seen.
func _encounter(world: Variant, map: Variant) -> Dictionary:
	var player: int = int(world.player)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var tried: int = 0
	for y in range(1, int(map.h) - 1):
		for x in range(1, int(map.w) - 1):
			for d in dirs:
				var clear: bool = true
				for k in range(0, NEAR_METRES + 1):
					if not _open_ground(map, x + d.x * k, y + d.y * k):
						clear = false
						break
				if not clear:
					continue
				tried += 1
				_place(world, player, _centre(Vector2i(x, y)))
				var zed: int = _spawn(world, _centre(Vector2i(x, y) + d * NEAR_METRES))
				_settle(world, 6)
				var at: Vector2 = _entity_pos(world, player)
				if int(world.vision.call("detail", zed, at.x, at.y, -1, player)) > 0:
					return {"player": player, "zed": zed}
				world.despawn(zed)
				if tried >= 200:
					return {}
	return {}


func _spawn(world: Variant, at: Vector2) -> int:
	return int(SimRoster.spawn_zombie(world, at.x, at.y, SimRoster.TYPE_SHAMBLER, world.rng.stream("shambler")))


func _place(world: Variant, ent: int, at: Vector2) -> void:
	world.components.set_component(ent, "position", {"x": at.x, "y": at.y})
	var vel: Variant = world.components.get_component(ent, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


func _settle(world: Variant, ticks: int) -> void:
	for _i in ticks:
		world.step()


func _centre(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)


func _entity_pos(world: Variant, ent: int) -> Vector2:
	var pos: Variant = world.components.get_component(ent, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _held_by(world: Variant, zed: int, player: int) -> bool:
	return world.components.has_component(zed, "grabState") and world.components.has_component(player, "grabbed")


func _step_until_held(world: Variant, zed: int, player: int) -> bool:
	for _t in range(GRAB_TICKS):
		world.step()
		if _held_by(world, zed, player):
			return true
	return false


# A fresh HUD node on the sim, the way the scene holds one. set_state takes the world and the player; the
# lines are read live from the sim.
func _hud_for(world: Variant, player: int) -> Control:
	if _hud != null:
		_hud.queue_free()
	var h: Control = Hud.new()
	root.add_child(h)
	h.set_state(world, player, "", "", false, false)
	_hud = h
	return h


func _collect(lines: Array) -> void:
	for l in lines:
		_all_lines.append(String(l))


func _has(lines: Array, text: String) -> bool:
	return lines.has(text)


func _has_prefix(lines: Array, prefix: String) -> String:
	for l in lines:
		if String(l).begins_with(prefix):
			return String(l)
	return ""


func _has_harm(lines: Array) -> String:
	for text in [Hud.HELD_LINE, Hud.HELD_SEVERAL_LINE, Hud.BLEEDING_LINE, Hud.INFECTED_LINE]:
		if lines.has(text):
			return String(text)
	var wound: String = _has_prefix(lines, "A ")
	if wound != "" and wound.contains(" on your "):
		return wound
	for prefix in ["You raise the weapon", "You are steady. The weapon", "The weapon recovers", "You are reloading", "You clear a jam"]:
		var weapon: String = _has_prefix(lines, prefix)
		if weapon != "":
			return weapon
	var blood: String = SimWounds.hud_clause(_world, _player)
	if blood != "" and lines.has(blood) and blood != Hud.BLEEDING_CLAUSE_FIRST:
		return blood
	return ""


var _world: Variant = null
var _player: int = -1


# --- CLEAN -----------------------------------------------------------------------------------------

func _clean() -> void:
	var b: Dictionary = _boot()
	_world = b["world"]
	_player = int(_world.player)
	var h: Control = _hud_for(_world, _player)
	var lines: Array = h.call("lines")
	_collect(lines)
	var harm: String = _has_harm(lines)
	if harm != "":
		_fail("CLEAN", "a fresh player has a harm or weapon line: %s" % harm)
		return
	_ok("CLEAN", "a fresh player: %d lines, none of them harm or weapon" % lines.size())


# --- HELD ------------------------------------------------------------------------------------------

func _held() -> void:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var player: int = int(world.player)
	var setup: Dictionary = _encounter(world, b["map"])
	if setup.is_empty():
		_fail("HELD", "no %d m open line with sight" % NEAR_METRES)
		return
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail("HELD", "no grab within %d ticks" % GRAB_TICKS)
		return
	var h: Control = _hud_for(world, player)
	var lines: Array = h.call("lines")
	_collect(lines)
	if not _has(lines, Hud.HELD_LINE):
		_fail("HELD", "held, but the held line is not drawn; lines: %s" % str(lines.slice(0, 3)))
		return
	if not Hud.HELD_LINE.contains("F "):
		_fail("HELD", "the held line does not name F")
		return
	# A second holder, as a fixture write on the grabbed sources (the line reads the count).
	var second: int = _spawn(world, _entity_pos(world, zed) + Vector2(0.0, 0.5))
	var grabbed: Dictionary = world.components.get_component(player, "grabbed") as Dictionary
	(grabbed["sources"] as Array).append(second)
	lines = h.call("lines")
	_collect(lines)
	if not _has(lines, Hud.HELD_SEVERAL_LINE) or _has(lines, Hud.HELD_LINE):
		_fail("HELD", "two holders should read as several things; lines: %s" % _has_prefix(lines, "Several") + _has_prefix(lines, "Something"))
		return
	(grabbed["sources"] as Array).erase(second)
	world.despawn(second)
	# Break the hold by the victim's own struggle: F presses until grab.broken names the player.
	var broke: Dictionary = {}
	_sub_serial += 1
	world.events.subscribe({"type": "grab.broken", "id": "fp_harm.broke.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("victim", -1)) == player:
			broke["tick"] = int(world.tick)
			broke["cause"] = str(ev.get("cause", "?"))
	})
	var presses: int = 0
	var start: int = int(world.tick)
	for t in range(HOLD_TICKS):
		if t % SWING_EVERY_TICKS == 0:
			world.commands.push({"type": "swing"})
			presses += 1
		world.step()
		if broke.has("tick"):
			break
	if not broke.has("tick"):
		_fail("HELD", "the hold did not break in %d ticks of F presses" % HOLD_TICKS)
		return
	lines = h.call("lines")
	_collect(lines)
	if _has(lines, Hud.HELD_LINE) or _has(lines, Hud.HELD_SEVERAL_LINE):
		_fail("HELD", "the hold broke at tick +%d (%s) but the held line is still drawn" % [int(broke["tick"]) - start, broke["cause"]])
		return
	_ok("HELD", "held line names F (\"%s\"); two holders read as several things; the hold broke at +%d (%s, after %d F presses) and the line is gone" % [Hud.HELD_LINE, int(broke["tick"]) - start, broke["cause"], presses])


# --- BITE ------------------------------------------------------------------------------------------

func _bite() -> void:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var player: int = int(world.player)
	var setup: Dictionary = _encounter(world, b["map"])
	if setup.is_empty():
		_fail("BITE", "no %d m open line with sight" % NEAR_METRES)
		return
	var zed: int = int(setup["zed"])
	if not _step_until_held(world, zed, player):
		_fail("BITE", "no grab within %d ticks" % GRAB_TICKS)
		return
	var bites: Dictionary = {}
	_sub_serial += 1
	world.events.subscribe({"type": "bite.landed", "id": "fp_harm.bite.%d" % _sub_serial, "handler": func(ev: Dictionary) -> void:
		if int(ev.get("victim", -1)) == player and not bites.has("tick"):
			bites["tick"] = int(world.tick)
	})
	var h: Control = _hud_for(world, player)
	for _t in range(BITE_TICKS):
		world.step()
		if bites.has("tick"):
			break
	if not bites.has("tick"):
		_fail("BITE", "no bite landed in %d ticks of grab" % BITE_TICKS)
		return
	# The bite is the victim's last wound; stop the biter so no later wound lands in the window.
	world.despawn(zed)
	var at: int = int(bites["tick"])
	var wounds: Array = (world.components.get_component(player, "injuries") as Dictionary)["wounds"] as Array
	var newest: Dictionary = wounds[wounds.size() - 1] as Dictionary
	var expected: String = "A %s on your %s." % [String(newest.get("presentation", "scratch")), SimCondition.label_of(String(newest.get("bodyPart", "")))]
	var lines: Array = h.call("lines")
	_collect(lines)
	if not _has(lines, expected):
		_fail("BITE", "the wound sentence is not drawn; expected \"%s\"; lines: %s" % [expected, _has_prefix(lines, "A ")])
		return
	var presentation: String = String(newest.get("presentation", ""))
	if presentation != "bite" and presentation != "scratch":
		_info("BITE", "the wound presents as \"%s\" (kind %s): the sentence says the presentation, not the kind" % [presentation, String(newest.get("kind", ""))])
	# Hold the window: 79 ticks after the bite it is still drawn, at 80 it is gone.
	var bleeding_now: bool = false
	for w in wounds:
		if bool((w as Dictionary).get("bleeding", false)):
			bleeding_now = true
	while int(world.tick) - at < Hud.WOUND_HUD_TICKS - 1:
		world.step()
	lines = h.call("lines")
	_collect(lines)
	if not _has(lines, expected):
		_fail("BITE", "the wound sentence left at +%d, before the window closed" % (int(world.tick) - at))
		return
	while int(world.tick) - at < Hud.WOUND_HUD_TICKS:
		world.step()
	lines = h.call("lines")
	_collect(lines)
	if _has(lines, expected):
		_fail("BITE", "the wound sentence is still drawn at +%d" % (int(world.tick) - at))
		return
	var bleed_line: bool = _has(lines, Hud.BLEEDING_LINE)
	var still_bleeds: bool = false
	for w in (world.components.get_component(player, "injuries") as Dictionary)["wounds"] as Array:
		if bool((w as Dictionary).get("bleeding", false)):
			still_bleeds = true
	if still_bleeds and not bleed_line:
		_fail("BITE", "a wound still bleeds at +%d but the bleeding line is gone" % (int(world.tick) - at))
		return
	_ok("BITE", "first bite at tick +%d: \"%s\" drawn; gone at +%d; bleeding line %s while a wound bleeds (%s at +%d)" % [at, expected, int(world.tick) - at, "drawn" if bleed_line else "absent", "bleeds" if still_bleeds else "clotted", int(world.tick) - at])


# --- BLOOD -----------------------------------------------------------------------------------------

func _blood() -> void:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var player: int = int(world.player)
	var h: Control = _hud_for(world, player)
	var none: Array = h.call("lines")
	if SimWounds.hud_clause(world, player) != "":
		_fail("BLOOD", "a fresh player already has a blood-loss clause: %s" % SimWounds.hud_clause(world, player))
		return
	var inj: Dictionary = world.components.get_component(player, "injuries") as Dictionary
	inj["bloodLoss"] = 0.3 * SimWounds.BLOOD_LOSS_FATAL
	var clause: String = SimWounds.hud_clause(world, player)
	var lines: Array = h.call("lines")
	_collect(lines)
	if clause == "" or not _has(lines, clause):
		_fail("BLOOD", "blood loss 30%% of fatal: the sim's clause \"%s\" is not drawn" % clause)
		return
	_ok("BLOOD", "blood loss at 30%% of fatal: \"%s\" drawn (the sim's words, unchanged)" % clause)


# --- INFECTED --------------------------------------------------------------------------------------

func _infected() -> void:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var player: int = int(world.player)
	var h: Control = _hud_for(world, player)
	var lines: Array = h.call("lines")
	_collect(lines)
	# A bite that did not transmit: no line.
	world.components.set_component(player, "zombieInfection", {"exposures": [{"source": -1, "bodyPart": "torso", "exposedAtTick": int(world.tick), "transmitted": false, "stage": SimInfection.Stage.Latent, "stageEnteredAtTick": int(world.tick), "cauterized": false, "amputated": false}]})
	lines = h.call("lines")
	_collect(lines)
	if _has(lines, Hud.INFECTED_LINE):
		_fail("INFECTED", "a bite that did not transmit shows the infected line")
		return
	# A transmitted bite: the line appears, and it carries no stage or clock.
	(world.components.get_component(player, "zombieInfection") as Dictionary)["exposures"][0]["transmitted"] = true
	lines = h.call("lines")
	_collect(lines)
	if not _has(lines, Hud.INFECTED_LINE):
		_fail("INFECTED", "a transmitted bite does not show the infected line")
		return
	var text: String = Hud.INFECTED_LINE
	if text.contains("stage") or text.contains("day") or text.contains("hour"):
		_fail("INFECTED", "the infected line carries a stage or a clock: %s" % text)
		return
	_ok("INFECTED", "a transmitted bite draws \"%s\"; a bite that did not transmit draws nothing; no stage, no clock" % text)


# --- WEAPON ----------------------------------------------------------------------------------------

func _weapon() -> void:
	var b: Dictionary = _boot()
	var world: Variant = b["world"]
	var player: int = int(world.player)
	SimRangedMod.make_ranged_armed(world, player, {"magSize": RIFLE_MAG, "reloadTicks": RIFLE_RELOAD_TICKS, "rangeMetres": RIFLE_RANGE_METRES, "damage": 34.0, "weight": 1.5, "handling": 1.0})
	var h: Control = _hud_for(world, player)
	var rw: Dictionary = world.components.get_component(player, "rangedWeapon") as Dictionary
	var mag0: int = int(rw.get("mag", -1))
	var lines: Array = h.call("lines")
	_collect(lines)
	if _has_prefix(lines, "You raise") != "" or _has_prefix(lines, "You are steady") != "":
		_fail("WEAPON", "an Idle rifle draws a fire line")
		return
	world.commands.push({"type": "fire"})
	world.step()
	lines = h.call("lines")
	_collect(lines)
	if _has_prefix(lines, "You raise the weapon") == "":
		_fail("WEAPON", "after the first press the Raise line is not drawn (state %d)" % int(rw["state"]))
		return
	var steady_at: int = -1
	for t in range(1, 200):
		world.step()
		if int(rw["state"]) == SimRangedMod.FireState.Steady:
			steady_at = t
			break
	if steady_at < 0:
		_fail("WEAPON", "never reached Steady")
		return
	lines = h.call("lines")
	_collect(lines)
	if _has_prefix(lines, "You are steady. The weapon fires on its own.") == "":
		_fail("WEAPON", "Steady is not drawn with the self-firing wording")
		return
	# A second press in Steady does nothing: the state stays Steady and no round is spent.
	world.commands.push({"type": "fire"})
	world.step()
	if int(rw["state"]) != SimRangedMod.FireState.Steady or int(rw.get("mag", -1)) != mag0:
		_fail("WEAPON", "a press in Steady changed the weapon (state %d, mag %d)" % [int(rw["state"]), int(rw.get("mag", -1))])
		return
	var shot_at: int = -1
	for t in range(1, 200):
		world.step()
		if int(rw["state"]) == SimRangedMod.FireState.Recover:
			shot_at = t
			break
	if shot_at < 0 or int(rw.get("mag", -1)) != mag0 - 1:
		_fail("WEAPON", "no shot at the end of Steady (state %d, mag %d from %d)" % [int(rw["state"]), int(rw.get("mag", -1)), mag0])
		return
	lines = h.call("lines")
	_collect(lines)
	if _has_prefix(lines, "The weapon recovers") == "":
		_fail("WEAPON", "Recover is not drawn")
		return
	for t in range(1, 200):
		world.step()
		if int(rw["state"]) == SimRangedMod.FireState.Idle:
			break
	lines = h.call("lines")
	_collect(lines)
	if _has_harm(lines) != "" and (_has_prefix(lines, "You raise") != "" or _has_prefix(lines, "The weapon recovers") != ""):
		_fail("WEAPON", "Idle still draws a fire line")
		return
	# Reload: empty the magazine, then press reload.
	rw["mag"] = 0
	world.commands.push({"type": "reload"})
	world.step()
	lines = h.call("lines")
	_collect(lines)
	if int(rw["state"]) != SimRangedMod.FireState.Reload or _has_prefix(lines, "You are reloading.") == "":
		_fail("WEAPON", "reload does not draw the reloading line (state %d)" % int(rw["state"]))
		return
	_settle(world, RIFLE_RELOAD_TICKS + 2)
	# Clearing: a jam is a state the sim enters (ranged.gd); the line reads it.
	rw["state"] = SimRangedMod.FireState.Clearing
	rw["ticksLeft"] = 30
	lines = h.call("lines")
	_collect(lines)
	if _has_prefix(lines, "You clear a jam.") == "":
		_fail("WEAPON", "Clearing is not drawn as a jam")
		return
	_ok("WEAPON", "rifle profile (magSize %d, reload %d): Raise, Steady (\"The weapon fires on its own\"; a second press changes nothing), Recover after the shot at +%d, Idle silent, Reload, Clearing" % [RIFLE_MAG, RIFLE_RELOAD_TICKS, shot_at])


# --- DIGITS ----------------------------------------------------------------------------------------

func _digits() -> void:
	var bad: String = ""
	for line in _all_lines:
		if Hud.has_digit(line):
			bad = line
			break
	if bad != "":
		_fail("DIGITS", "a drawn line has a digit: %s" % bad)
		return
	_ok("DIGITS", "%d drawn lines across every lane, none with a digit" % _all_lines.size())
