extends SceneTree
# Window overlay opacity, one scrap choke, alarm (no DPS), noisemaker 45 / 12000.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const SimSave = preload("res://sim/save.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimPath = preload("res://sim/path.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimDirector = preload("res://sim/modules/director.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _version() and ok
	ok = _board_opacity() and ok
	ok = _scrap_choke() and ok
	ok = _alarm_no_dps() and ok
	ok = _noisemaker_field() and ok
	ok = _e_pickup_first() and ok
	ok = _a_door_opens_closes_and_breaks() and ok
	ok = _the_district_has_doors_and_the_boot_shuts_them() and ok
	ok = _a_crowd_gets_through() and ok
	if ok:
		print("M2_FORTIFY_OK board scrap alarm bait v18, doors that open, close and break, and a crowd that presses through")
		quit(0)
	else:
		push_error("M2_FORTIFY_FAIL")
		quit(1)

func _world(px: float = 10.5, py: float = 13.5) -> Variant:
	var f: Dictionary = {"seed": 21, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": px, "y": py, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimFortify.register_module(w)
	SimAttention.register_module(w, map)
	w.components.set_component(w.player, "facing", {"radians": -PI / 2.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	SimAttention.make_emitter(w, w.player)
	return w

func _channel(w: Variant, cmd: Dictionary) -> void:
	w.commands.push(cmd)
	for _i in SimFortify.CHANNEL_TICKS + 2:
		w.step()

func _set_tile(w: Variant, tx: int, ty: int, tile: int) -> void:
	w.tilemap.tiles[ty * int(w.tilemap.w) + tx] = tile

func _version() -> bool:
	# This duplicates check_m2_save.gd's _version() -- two gates asserting the same fact
	# independently, which is exactly how one of them got missed on the last version bump.
	# Left as-is rather than refactored, and it has now caught a bump twice: the container-grid
	# slice of 2026-09-08 updated check_m2_save.gd and not this one. The duplication is doing its
	# job; what it was missing is a message that says where its twin lives, so whoever bumps the
	# constant finds both pins the first time rather than twelve minutes into the chain.
	if int(SimSerialize.SAVE_VERSION) != 29:
		push_error("SAVE_VERSION %d want 29 -- bump it here AND in check_m2_save.gd's _version(), which pins the same number" % int(SimSerialize.SAVE_VERSION))
		return false
	var stale: Dictionary = SimSave.decode_save("{\"snapshot\":{\"version\":13},\"meta\":{}}")
	if String(stale.get("__error", "")) != "StaleSaveError":
		push_error("v13 not rejected: %s" % str(stale))
		return false
	print("VERSION OK 14 rejects 13")
	return true

func _board_opacity() -> bool:
	var w: Variant = _world()
	_set_tile(w, 10, 12, SimTileMap.Tile.Window)
	_set_tile(w, 14, 12, SimTileMap.Tile.Window)
	if int(SimTileMap.opacity_at(w.tilemap, 10, 12)) != int(SimTileMap.Opacity.Clear):
		push_error("unboarded window not clear")
		return false
	if SimTileMap.blocks_sight(w.tilemap, 10, 12):
		push_error("unboarded window blocked sight")
		return false
	_channel(w, {"type": "barricade.window", "tx": 10, "ty": 12})
	if int(SimTileMap.opacity_at(w.tilemap, 10, 12)) != int(SimTileMap.Opacity.Opaque):
		push_error("boarded window opacity %d" % int(SimTileMap.opacity_at(w.tilemap, 10, 12)))
		return false
	if not SimTileMap.blocks_sight(w.tilemap, 10, 12):
		push_error("boarded window did not block sight")
		return false
	if int(SimTileMap.opacity_at(w.tilemap, 14, 12)) != int(SimTileMap.Opacity.Clear):
		push_error("other window overlay leaked")
		return false
	var look: Dictionary = SimFortify.look_at(w, w.player)
	if String(look.get("window", "")) != "intact":
		push_error("look-at %s" % str(look))
		return false
	# The shambler presses: a wanted move west into the board every tick (the kernel zeroes a
	# blocked velocity, so it is re-armed each step). Standing beside a board wears nothing
	# since the pressing slice; PRESS below holds that half.
	var z: int = int(w.entities.spawn())
	w.components.set_component(z, "position", {"x": 11.5, "y": 12.5})
	w.components.set_component(z, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(z, "shambler", {})
	for _i in SimFortify.CONTACT_PER_STAGE * 4 + 5:
		(w.components.get_component(z, "velocity") as Dictionary)["dx"] = -2.0
		w.step()
	if SimTileMap.overlay_at(w.tilemap, 10, 12) != null:
		push_error("board did not breach")
		return false
	if int(SimTileMap.opacity_at(w.tilemap, 10, 12)) != int(SimTileMap.Opacity.Clear):
		push_error("breached window not clear")
		return false
	print("BOARD OK opaque then breach")
	return true

func _scrap_choke() -> bool:
	var w: Variant = _world()
	_set_tile(w, 10, 11, SimTileMap.Tile.Window)
	# The gate refusal, with something to refuse. This used to probe (49, 49) and (50, 49) --
	# `SimFortify.GATE_A`'s old neighbourhood -- on a 24-tile arena, so both were off the map and
	# refused as walls whatever the gate rule did. The gates are map anchors now, so the arena can
	# carry a pair, on tiles that are otherwise perfectly scrappable: same open floor, same window
	# to face, so the only difference between the control tile and the two gate tiles is the rule
	# under test.
	for gx in [3, 4, 5]:
		_set_tile(w, int(gx), 3, SimTileMap.Tile.Window)
	w.tilemap.anchors = {"gate_a": {"x": 4, "y": 4}, "gate_b": {"x": 5, "y": 4}}
	if not SimFortify.can_scrap(w.tilemap, 3, 4):
		push_error("the control tile beside the gate was refused, so this proves nothing")
		return false
	if SimFortify.can_scrap(w.tilemap, 4, 4) or SimFortify.can_scrap(w.tilemap, 5, 4):
		push_error("gate accepted scrap")
		return false
	var scrap: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged", "count": 1})
	if not SimInventory.stow(w, w.player, scrap):
		push_error("could not stow scrap")
		return false
	_channel(w, {"type": "barricade.scrap", "tx": 10, "ty": 12})
	if not SimTileMap.is_solid(w.tilemap, 10, 12):
		push_error("scrap tile not solid")
		return false
	if int(SimTileMap.opacity_at(w.tilemap, 10, 12)) != int(SimTileMap.Opacity.Opaque):
		push_error("scrap not opaque")
		return false
	if w.is_blocked_tile(10, 12) != true:
		push_error("map_cells missed scrap")
		return false
	if w.components.query(["scrapBarricade"]).size() != 1:
		push_error("scrap count %d" % w.components.query(["scrapBarricade"]).size())
		return false
	if SimFortify.carried_material(w, w.player, SimFortify.recipe_kind("scrap")) >= 0:
		push_error("scrap not consumed")
		return false
	print("SCRAP OK solid opaque consumed")
	return true

func _alarm_no_dps() -> bool:
	var w: Variant = _world(8.5, 13.5)
	_channel(w, {"type": "trap.alarm.place", "tx": 8, "ty": 12})
	var alarm: Variant = w.components.query(["alarmLine"])
	if alarm.is_empty():
		push_error("alarm not placed")
		return false
	var body: Dictionary = (w.components.get_component(w.player, "body") as Dictionary).duplicate(true)
	var z: int = int(w.entities.spawn())
	w.components.set_component(z, "position", {"x": 8.5, "y": 12.5})
	w.components.set_component(z, "shambler", {})
	w.step()
	var tripped: bool = false
	var mag8: bool = false
	for e in w.events.drained:
		var ev: Dictionary = e as Dictionary
		if String(ev.get("type", "")) == "alarm.tripped":
			tripped = true
		if String(ev.get("type", "")) == "noise.emitted" and absf(float(ev.get("magnitude", 0)) - 8.0) < 0.01:
			mag8 = true
	if not tripped or not mag8:
		push_error("alarm trip=%s noise8=%s" % [str(tripped), str(mag8)])
		return false
	var after: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	if int(after.get("torso", 0)) != int(body.get("torso", 0)) or int(after.get("head", 0)) != int(body.get("head", 0)):
		push_error("alarm dealt damage")
		return false
	if SimFortify.speed_after_events(10, w.events.drained) != 1:
		push_error("10x did not drop")
		return false
	if SimFortify.speed_after_events(3, w.events.drained) != 3:
		push_error("3x should stay")
		return false
	print("ALARM OK trip noise8 no dps drop10x")
	return true

func _noisemaker_field() -> bool:
	var w: Variant = _world(12.5, 13.5)
	_channel(w, {"type": "bait.noisemaker.place", "tx": 12, "ty": 12})
	var found: Array[int] = w.components.query(["noisemaker"])
	if found.is_empty():
		push_error("noisemaker missing")
		return false
	var nm: Dictionary = w.components.get_component(found[0], "noisemaker") as Dictionary
	var remain: int = int(nm.get("expiresAtTick", 0)) - int(w.tick)
	if remain < SimFortify.NOISEMAKER_TICKS - 5 or remain > SimFortify.NOISEMAKER_TICKS:
		push_error("duration remain=%d tick=%s exp=%s" % [remain, str(w.tick), str(nm.get("expiresAtTick"))])
		return false
	var em: Dictionary = w.components.get_component(found[0], "attention_emitter") as Dictionary
	if absf(float(em.get("ambient", 0)) - SimFortify.NOISEMAKER_MAG) > 0.01:
		push_error("ambient %s" % str(em.get("ambient")))
		return false
	w.step()
	var noise: float = float(w.field.noise_at(12.5, 12.5))
	if noise < 20.0:
		push_error("field %s want ~45" % str(noise))
		return false
	nm["expiresAtTick"] = int(w.tick)
	w.step()
	em = w.components.get_component(found[0], "attention_emitter") as Dictionary
	if float(em.get("ambient", 1)) > 0.0:
		push_error("expired still ambient %s" % str(em.get("ambient")))
		return false
	print("BAIT OK mag45 dur12000 then silent")
	return true

func _e_pickup_first() -> bool:
	var w: Variant = _world()
	_set_tile(w, 10, 12, SimTileMap.Tile.Window)
	var knife: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
	w.components.set_component(knife, "position", {"x": 10.5, "y": 13.5})
	w.commands.push({"type": "use.context"})
	w.step()
	if w.components.has_component(knife, "position"):
		push_error("E did not pick up")
		return false
	if SimTileMap.overlay_at(w.tilemap, 10, 12) != null:
		push_error("E boarded instead of pickup")
		return false
	print("E-CONTEXT OK pickup first")
	return true


# --- The playable state, slice 9: doors ------------------------------------------------------

# A wall across row 12 with a Door tile at (10, 12) between the player (south) and the open
# north. Closed, the door is solid and opaque; open, neither; a shambler pushing at it for a
# thousand ticks never opens it; a person's A* routes through it and their walk opens it as the
# step, after which it swings shut DOOR_SWING_TICKS after the tile empties; E latches it open
# for good, or shut; a broken one is a doorway nothing can close.
func _a_door_opens_closes_and_breaks() -> bool:
	var w: Variant = _world(10.5, 14.5)
	for x in range(6, 15):
		_set_tile(w, x, 12, SimTileMap.Tile.Wall)
	_set_tile(w, 10, 12, SimTileMap.Tile.Door)
	if SimFortify.spawn_doors(w, w.tilemap) != 1:
		push_error("DOOR: one Door tile should spawn one door")
		return false
	if not SimTileMap.is_solid(w.tilemap, 10, 12) or not SimTileMap.blocks_sight(w.tilemap, 10, 12) or not w.is_blocked_tile(10, 12):
		push_error("DOOR: a closed door is not solid and opaque to the map and the kernel")
		return false
	# The dead never *open* one: pushed at from the north for 300 ticks (under the 640 a lone
	# body needs to break it by pressing -- PRESS holds that half) the door is still shut, the
	# body still north of it, and the pressing has registered as a stage.
	var zed: int = int(w.entities.spawn())
	w.components.set_component(zed, "position", {"x": 10.5, "y": 11.5})
	w.components.set_component(zed, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(zed, "shambler", {})
	for _i in 300:
		(w.components.get_component(zed, "velocity") as Dictionary)["dy"] = 2.0
		w.step()
	var zpos: Dictionary = w.components.get_component(zed, "position") as Dictionary
	var dstate: Dictionary = SimFortify.door_state(w, 10, 12) as Dictionary
	if float(zpos["y"]) >= 12.0 or bool(dstate["open"]):
		push_error("DOOR: a shambler got through a closed door (y=%.2f open=%s)" % [float(zpos["y"]), str(dstate["open"])])
		return false
	if int(dstate["stage"]) < 1:
		push_error("DOOR: 300 ticks of pushing moved the door nothing -- the press is not reaching it")
		return false
	dstate["stage"] = 0
	dstate["contactTicks"] = 0.0
	w.despawn(zed)
	# A person's planner routes through it, and the walk opens it as the step.
	var route: Array[Vector2i] = SimPath.find(w, Vector2i(10, 14), Vector2i(10, 10))
	if route.is_empty() or not route.has(Vector2i(10, 12)):
		push_error("DOOR: A* did not route a person through the closed door (%s)" % str(route))
		return false
	var walker: int = int(w.entities.spawn())
	w.components.set_component(walker, "position", {"x": 10.5, "y": 14.5})
	w.components.set_component(walker, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(walker, "facing", {"radians": -PI / 2.0})
	var job: Dictionary = {"kind": "Haul", "target": -1, "ticksLeft": 0, "path": [], "pathGen": -1}
	var opened_at: int = -1
	var crossed_at: int = -1
	for i in 200:
		SimJobs._walk(w, walker, job, Vector2i(10, 10))
		w.step()
		if opened_at < 0 and bool((SimFortify.door_state(w, 10, 12) as Dictionary)["open"]):
			opened_at = i
		var wp: Dictionary = w.components.get_component(walker, "position") as Dictionary
		if crossed_at < 0 and float(wp["y"]) < 11.0:
			crossed_at = i
			break
	if opened_at < 0 or crossed_at < 0:
		push_error("DOOR: the walker never opened the door (%d) or never crossed it (%d)" % [opened_at, crossed_at])
		return false
	if SimTileMap.is_solid(w.tilemap, 10, 12) or SimTileMap.blocks_sight(w.tilemap, 10, 12):
		push_error("DOOR: an open door still blocks the map")
		return false
	# It swings shut DOOR_SWING_TICKS after the tile emptied, and not before.
	w.components.set_component(walker, "position", {"x": 10.5, "y": 9.5})
	(w.components.get_component(walker, "velocity") as Dictionary)["dy"] = 0.0
	# Measured from the door's own stamp of when its tile emptied (the walker left it during
	# the crossing loop above), not from here: shut on exactly the swing tick, not before.
	var shut_at: int = -1
	var emptied: int = int((SimFortify.door_state(w, 10, 12) as Dictionary)["emptySinceTick"])
	for i in SimFortify.DOOR_SWING_TICKS + 40:
		w.step()
		if not bool((SimFortify.door_state(w, 10, 12) as Dictionary)["open"]):
			shut_at = int(w.tick) - emptied
			break
	if shut_at != SimFortify.DOOR_SWING_TICKS:
		push_error("DOOR: the door swung shut %d ticks after its tile emptied (swing is %d)" % [shut_at, SimFortify.DOOR_SWING_TICKS])
		return false
	# E latches it open: no swing for 300 ticks. E again shuts it.
	w.components.set_component(w.player, "position", {"x": 10.5, "y": 13.5})
	w.components.set_component(w.player, "facing", {"radians": -PI / 2.0})
	SimFortify._use_context(w, w.player)
	var latched: Dictionary = SimFortify.door_state(w, 10, 12) as Dictionary
	if not bool(latched["open"]) or not bool(latched["latched"]):
		push_error("DOOR: E did not open and latch the door (%s)" % str(latched))
		return false
	for _i in 300:
		w.step()
	if not bool((SimFortify.door_state(w, 10, 12) as Dictionary)["open"]):
		push_error("DOOR: a latched-open door swung shut")
		return false
	SimFortify._use_context(w, w.player)
	if bool((SimFortify.door_state(w, 10, 12) as Dictionary)["open"]) or not w.is_blocked_tile(10, 12):
		push_error("DOOR: E did not shut the door")
		return false
	# Broken is a doorway for good.
	(SimFortify.door_state(w, 10, 12) as Dictionary)["stage"] = SimFortify.DOOR_BROKEN
	(SimFortify.door_state(w, 10, 12) as Dictionary)["open"] = true
	SimFortify.sync_map(w)
	if SimTileMap.is_solid(w.tilemap, 10, 12) or SimTileMap.blocks_sight(w.tilemap, 10, 12) or w.is_blocked_tile(10, 12):
		push_error("DOOR: a broken door still blocks")
		return false
	if SimFortify.toggle_door(w, 10, 12) or SimFortify.close_door(w, 10, 12, true):
		push_error("DOOR: a broken door was closed")
		return false
	print("DOOR OK closed: solid, opaque, a shambler pushed 300 ticks and stayed north (y=%.2f); A* routes through it, the walk opened it at tick %d and crossed at %d; shut again %d ticks after the tile emptied; E latched it open through 300 ticks and shut it; broken cannot close" % [float(zpos["y"]), opened_at, crossed_at, shut_at])
	return true


# The district: every building's doorway and both gates are Door tiles on a generated map (open
# by class, nothing booted), and a playable boot stands a closed door on each; the Guard's post is
# the annex-side neighbour of the gate, not the gate.
func _the_district_has_doors_and_the_boot_shuts_them() -> bool:
	var map: Variant = SimTileMap.generate_district(20260805, 64)
	var doorways: int = 0
	for record in map.buildings as Array:
		for door in (record as Dictionary).get("doors", []) as Array:
			var dx: int = int((door as Dictionary).get("x", -1))
			var dy: int = int((door as Dictionary).get("y", -1))
			if SimTileMap.tile_at(map, dx, dy) != SimTileMap.Tile.Door:
				push_error("DOOR-DISTRICT: the doorway at (%d, %d) is tile %d, not Door" % [dx, dy, SimTileMap.tile_at(map, dx, dy)])
				return false
			if SimTileMap.is_solid(map, dx, dy):
				push_error("DOOR-DISTRICT: a doorway on a map nobody booted is solid")
				return false
			doorways += 1
	for gate in [SimTileMap.gate_a(map), SimTileMap.gate_b(map)]:
		if SimTileMap.tile_at(map, (gate as Vector2i).x, (gate as Vector2i).y) != SimTileMap.Tile.Door:
			push_error("DOOR-DISTRICT: gate %s is not a Door tile" % str(gate))
			return false
	if doorways < 4:
		push_error("DOOR-DISTRICT: only %d doorways on a 64-tile district -- nothing to judge" % doorways)
		return false
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var doors: int = w.components.query(["door"]).size()
	var door_tiles: int = 0
	var shut: int = 0
	for y in 64:
		for x in 64:
			if SimTileMap.tile_at(w.tilemap, x, y) == SimTileMap.Tile.Door:
				door_tiles += 1
				if SimTileMap.is_solid(w.tilemap, x, y):
					shut += 1
	if doors != door_tiles or shut != door_tiles:
		push_error("DOOR-DISTRICT: %d Door tiles, %d door entities, %d shut at boot" % [door_tiles, doors, shut])
		return false
	var gate_a: Vector2i = SimTileMap.gate_a(w.tilemap)
	var post: Vector2i = SimJobs._post_tile(w)
	if post == gate_a or not SimTileMap.annex_rect(w.tilemap).has_point(post) or (post - gate_a).length() > 1.01:
		push_error("DOOR-DISTRICT: the Guard's post %s is not the annex-side neighbour of the gate %s" % [str(post), str(gate_a)])
		return false
	print("DOOR-DISTRICT OK %d doorways and both gates are Door tiles, open by class; the boot shuts all %d; the post %s stands inside the annex beside the gate %s" % [doorways, door_tiles, str(post), str(gate_a)])
	return true


# --- The playable state, slice 10: pressing ---------------------------------------------------

# One shambler pushing at a shut door breaks it in four stages at 160 a stage (a push a tick is
# pressure 1); three pushing at once (pressure 6) in a sixth of that; a body standing beside
# the door with nowhere it wants to go presses nothing over 300 ticks, and a survivor pushing at
# it presses nothing either; the kernel's press keys are asserted by name; and the breach says
# its kind and reaches the director's lull.
func _a_crowd_gets_through() -> bool:
	var ticks_for: Dictionary = {}
	for n in [1, 3]:
		var w: Variant = _world(10.5, 16.5)
		for x in range(6, 15):
			_set_tile(w, x, 12, SimTileMap.Tile.Wall)
		_set_tile(w, 10, 12, SimTileMap.Tile.Door)
		SimFortify.spawn_doors(w, w.tilemap)
		SimDirector.register_module(w)
		var zeds: Array[int] = []
		for i in n:
			var z: int = int(w.entities.spawn())
			w.components.set_component(z, "position", {"x": 10.5, "y": 11.5})
			w.components.set_component(z, "velocity", {"dx": 0.0, "dy": 0.0})
			w.components.set_component(z, "shambler", {})
			zeds.append(z)
		var breached: Array = []
		w.events.subscribe({"id": "check.press-%d" % n, "type": "fortify.breached", "handler": func(e: Dictionary) -> void:
			breached.append(String(e.get("kind", "")))
		})
		var ticks: int = -1
		for t in 800:
			for z in zeds:
				(w.components.get_component(int(z), "velocity") as Dictionary)["dy"] = 2.0
			w.step()
			if t == 5:
				var vel: Dictionary = w.components.get_component(int(zeds[0]), "velocity") as Dictionary
				if not vel.has("pressX") or not vel.has("pressY") or int(vel["pressX"]) != 10 or int(vel["pressY"]) != 12:
					push_error("PRESS: the kernel did not write pressX/pressY for a body pushing at the door (%s)" % str(vel))
					return false
			if not breached.is_empty():
				ticks = t + 1
				break
		if ticks < 0:
			push_error("PRESS: %d shambler(s) never broke the door in 800 ticks" % n)
			return false
		if breached[0] != "door":
			push_error("PRESS: the breach said kind '%s'" % breached[0])
			return false
		var d: Dictionary = SimFortify.door_state(w, 10, 12) as Dictionary
		if int(d["stage"]) < SimFortify.DOOR_BROKEN or not bool(d["open"]) or SimTileMap.is_solid(w.tilemap, 10, 12):
			push_error("PRESS: a broken door is not a doorway (%s)" % str(d))
			return false
		if int((w.director as Dictionary).get("lullUntilTick", 0)) <= 0:
			push_error("PRESS: the door breach did not reach the director's lull")
			return false
		ticks_for[n] = ticks
	var one: int = int(ticks_for[1])
	var three: int = int(ticks_for[3])
	if one < 4 * int(SimFortify.STAGE_COST["door"]) or one > 4 * int(SimFortify.STAGE_COST["door"]) + 8:
		push_error("PRESS: one shambler took %d ticks, wanted ~%d" % [one, 4 * int(SimFortify.STAGE_COST["door"])])
		return false
	if three > one / 3:
		push_error("PRESS: three shamblers took %d ticks against one's %d -- the crowd is not pressing harder than its number" % [three, one])
		return false
	# The negatives: no heading, no press; a survivor pushing, no press.
	var quiet: Variant = _world(10.5, 16.5)
	for x in range(6, 15):
		_set_tile(quiet, x, 12, SimTileMap.Tile.Wall)
	_set_tile(quiet, 10, 12, SimTileMap.Tile.Door)
	SimFortify.spawn_doors(quiet, quiet.tilemap)
	var idle: int = int(quiet.entities.spawn())
	quiet.components.set_component(idle, "position", {"x": 10.5, "y": 11.5})
	quiet.components.set_component(idle, "velocity", {"dx": 0.0, "dy": 0.0})
	quiet.components.set_component(idle, "shambler", {})
	quiet.components.set_component(quiet.player, "position", {"x": 10.5, "y": 13.5})
	for _t in 300:
		(quiet.components.get_component(quiet.player, "velocity") as Dictionary)["dy"] = -2.0
		quiet.step()
	var qd: Dictionary = SimFortify.door_state(quiet, 10, 12) as Dictionary
	if int(qd["stage"]) != 0 or float(qd.get("contactTicks", 0)) != 0.0:
		push_error("PRESS: an idle shambler beside the door, or the survivor pushing at it, pressed (%s)" % str(qd))
		return false
	var pv: Dictionary = quiet.components.get_component(quiet.player, "velocity") as Dictionary
	if int(pv.get("pressX", -1)) != 10:
		push_error("PRESS: the survivor's push was not recorded by the kernel (%s) -- the negative is not testing the reader" % str(pv))
		return false
	print("PRESS OK one shambler broke the door in %d ticks, three in %d; the breach says 'door' and starts a lull; an idle shambler and a pushing survivor press nothing (the kernel recorded the survivor's push, fortify ignored it)" % [one, three])
	return true
