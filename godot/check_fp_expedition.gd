extends SceneTree
# The first-person expedition gate: one run, in order, through the real opt-in scene, proving the
# pieces work together. It is the scripted start of docs/39's "End-to-end conversion and default
# switch" proof. Every step asserts the sim's state, not the screen.
#
#   LEDGER    E at the ledger, in reach and aimed at it, opens the real work panel. A click on a
#             colonist's name picks the row, a click on its first priority cell dispatches
#             job.priority, and the sim's value moves. Escape closes the ledger.
#   DOOR      E at a shut door, in reach and aimed at it, opens it through the sim's door verb.
#             Holding W with the look aimed past it walks the body through the doorway onto the
#             far side.
#   CONTAINER E at a sim container in reach and aimed at it sends container.open and opens the
#             real grid sheet. In the full run a press on the box's item selects it, and the pane's
#             take button sends item.move, so the item is in the player's pack and not the box.
#             Escape closes the sheet and sends container.close.
#   RETURN    Holding W with the look aimed back at the door walks the body back inside.
#   SAVE      F5 writes the sim's save into the gate's own slot and says Saved. on the HUD.
#   WALK      Holding W away from the door moves the body.
#   LOAD      F9 puts the body back on the saved tile, at the saved tick, and says Loaded. The
#             item is in the pack after a full run and still in the box after a run that skipped
#             the take.
#   FIGHT     A shambler walks up from two metres in front. Swinging with F, the bat connects
#             (attack.connected, attacker the player, target the shambler), and its body loses
#             health.
#   TIME      The whole gate runs under TIME_BUDGET_SECONDS on this machine. The time is printed.
#
# True negatives, each a run of its own in a freshly booted scene:
#   SKIP-TAKE the same expedition with the take skipped ends with the item still in the container
#             and not in the pack, after the load and after the fight. The item check is the one
#             thing that differs between the two runs, so a take that did nothing is red in the
#             full run and a take that did everything is red in the skipped one.
#   NO-SAVE   a run that loads before anything was saved says Nothing to load., and changes neither
#             the tick, the body's tile, the pack nor the box.
#
# Setup, the way check_first_person does it: the gate places the body on its standing spots (the
# walk between them is not what is under test) and spawns the one shambler. Everything the player
# does is an input event through root.push_input, and the world advances by the sim's own tick. The
# gate's save slot is its own key, deleted before and after, so a real player's save is never touched.

const SCENE_PATH: String = "res://presentation/first_person/first_person.tscn"
const WorkPanel = preload("res://ui/work_panel.gd")
const InventoryPanel = preload("res://ui/inventory_panel.gd")
const InspectPane = preload("res://ui/inspect_pane.gd")
const BagGrid = preload("res://ui/bag_grid.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SaveSlot = preload("res://presentation/first_person/save_slot.gd")

# Small on purpose, as in check_first_person: every step walks the sim, and the shipped district is
# for the player, not for a gate. The district is seeded the same way on every boot.
const SMALL_DISTRICT_TILES: int = 64
# The gate's own save slot. It must never be the real first-person slot.
const GATE_SAVE_KEY: String = "fp_expedition_gate.slot"
const TICK_SECONDS: float = 1.0 / 20.0
const EPSILON: float = 0.0001
const WALK_TICK_LIMIT: int = 240
const WALK_AWAY_TICKS: int = 40
const SWING_TICK_LIMIT: int = 400
const SWING_EVERY_TICKS: int = 12
const CENTRE_REACH_METRES: float = 0.15
# The shambler must close at least this far before the bat connects: a walk toward it, not a swing at a body that
# was already in reach.
const APPROACH_METRES: float = 1.0
const TIME_BUDGET_SECONDS: float = 60.0

var _failures: Array[String] = []
var _started_ms: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	var old_size: Vector2i = root.size
	# The sheet lays out its inspect column (where the take button is) only at its full size.
	root.size = Vector2i(1920, 1080)
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("SCENE", "could not load %s" % SCENE_PATH)
		_finish(old_size, false)
		return
	var saved_key: String = SaveSlot.slot_key
	if GATE_SAVE_KEY == SaveSlot.DEFAULT_KEY:
		_fail("SAVE", "the gate's save key is the real first-person slot")
		_finish(old_size, false)
		return
	SaveSlot.slot_key = GATE_SAVE_KEY
	SaveSlot.remove()

	var ok: bool = true
	var full: Node = await _boot(packed)
	var full_ok: bool = await _expedition(full, true)
	ok = full_ok and ok
	await _retire(full)

	var skipped: Node = await _boot(packed)
	var skip_ok: bool = await _expedition(skipped, false)
	ok = skip_ok and ok
	await _retire(skipped)

	SaveSlot.remove()
	var fresh: Node = await _boot(packed)
	var load_ok: bool = _load_before_save(fresh)
	ok = load_ok and ok
	await _retire(fresh)

	SaveSlot.remove()
	SaveSlot.slot_key = saved_key
	_finish(old_size, ok)


func _finish(old_size: Vector2i, ok: bool) -> void:
	root.size = old_size
	var seconds: float = float(Time.get_ticks_msec() - _started_ms) / 1000.0
	if seconds > TIME_BUDGET_SECONDS:
		_fail("TIME", "the gate took %.1f s, over its %.0f s budget" % [seconds, TIME_BUDGET_SECONDS])
		ok = false
	if ok and _failures.is_empty():
		print("FP_EXPEDITION_OK one run in order (ledger priority, door out, container take, door back, F5, walk, F9, a shambler struck by the bat) and two true negatives (the same run with the take skipped, a load before any save), in %.1f s" % seconds)
		quit(0)
		return
	for failure in _failures:
		push_error("FP_EXPEDITION_FAIL " + failure)
	quit(1)


func _fail(lane: String, message: String) -> bool:
	_failures.append(lane + ": " + message)
	return false


func _boot(packed: PackedScene) -> Node:
	var scene: Node = packed.instantiate()
	scene.set("district_tiles", SMALL_DISTRICT_TILES)
	scene.set("skip_title", true)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	return scene


func _retire(scene: Node) -> void:
	scene.queue_free()
	await process_frame


# --- THE EXPEDITION --------------------------------------------------------------------------------

# One run, in order. `take` is true for the run that takes the item and false for the true negative
# that skips it. Everything else is the same in both, so the item is the only thing the two differ on.
func _expedition(scene: Node, take: bool) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var run: Dictionary = {"take": take, "mode": "full" if take else "skip-take"}

	var ledger_ok: bool = await _ledger_priority(scene)
	ok = ledger_ok and ok

	var passage: Dictionary = _find_door_passage(world, map)
	if passage.is_empty():
		return _fail("DOOR", "the district has no shut door with open floor on both sides of it")
	var door_ok: bool = _door_out(scene, passage, run)
	ok = door_ok and ok
	if not door_ok:
		return false

	var container_ok: bool = await _container(scene, run)
	ok = container_ok and ok
	if not container_ok:
		return false

	var back_ok: bool = _walk_back_inside(scene, run)
	ok = back_ok and ok
	if not back_ok:
		return false

	var save_ok: bool = _save_here(scene, run)
	ok = save_ok and ok
	if not save_ok:
		return false

	var walk_ok: bool = _walk_away(scene, run)
	ok = walk_ok and ok
	if not walk_ok:
		return false

	var load_ok: bool = _load_back(scene, run)
	ok = load_ok and ok
	if not load_ok:
		return false

	var fight_ok: bool = _strike(scene, run)
	ok = fight_ok and ok

	var item: int = int(run["item"])
	var box: int = int(run["box"])
	var player: int = int(world.player)
	var in_pack: bool = SimInventory.owns(world, player, item)
	var in_box: bool = SimContainers.contents_of(world, box).has(item)
	if take:
		if not in_pack or in_box:
			ok = _fail("TAKE", "the full run ended with the item in the box (%s) and not the pack (%s)" % [in_box, in_pack])
	else:
		if in_pack or not in_box:
			ok = _fail("SKIP-TAKE", "the run with the take skipped ended with the item in the pack (%s) and not the box (%s)" % [in_pack, in_box])
	return ok


# LEDGER: the real work panel, one priority cell, Escape.
func _ledger_priority(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var ledger: Vector2 = scene.call("ledger_sim_position")
	var approach: Vector2 = scene.call("ledger_approach_position")
	_place_player(scene, approach)
	scene.call("look_toward", Vector3(ledger.x, 0.90, ledger.y))
	_settle_vision(scene)
	if String(scene.call("interaction_verdict")) != "ok":
		return _fail("LEDGER", "the ledger in reach and in aim did not read as usable")
	_key(KEY_E, true)
	_key(KEY_E, false)
	if not bool(scene.get("menu_open")):
		return _fail("LEDGER", "E in reach and in aim did not open the ledger")
	var panel: Control = scene.call("work_panel_node") as Control
	if panel == null or not panel.visible or panel.get_script() != WorkPanel:
		return _fail("LEDGER", "E did not open the real work panel")
	await process_frame

	var laid: Dictionary = panel.call("_layout")
	var rows: Array = laid.get("rows", []) as Array
	if rows.is_empty():
		return _fail("LEDGER", "the work panel drew no colonist rows")
	var row: Dictionary = rows[0] as Dictionary
	var ent: int = int(row.get("entity", -1))
	if ent == int(world.player):
		return _fail("LEDGER", "the player is drawn as a colonist row")
	var name_at: Vector2 = row.get("name_at", Vector2(-1.0, -1.0)) as Vector2
	if name_at.x < 0.0:
		return _fail("LEDGER", "the first row has no name to pick")
	if String(panel.call("_click", name_at, false)) != "row":
		ok = _fail("LEDGER", "a click on the colonist's name did not pick the row")
	scene.call("_process", TICK_SECONDS)

	laid = panel.call("_layout")
	rows = laid.get("rows", []) as Array
	if rows.is_empty():
		return _fail("LEDGER", "the work panel drew no rows after the pick")
	row = rows[0] as Dictionary
	var cells: Array = row.get("cells", []) as Array
	if cells.is_empty():
		return _fail("LEDGER", "the picked row has no priority cells")
	var cell: Dictionary = cells[0] as Dictionary
	var column: String = String(cell.get("column", ""))
	var rect: Rect2 = cell.get("rect", Rect2()) as Rect2
	var jp: Variant = world.components.get_component(ent, "jobPriorities")
	if not (jp is Dictionary):
		return _fail("LEDGER", "the colonist has no job priorities")
	var before: int = int(((jp as Dictionary).get("cols", {}) as Dictionary).get(column, 0))

	world.commands.record = true
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	if String(panel.call("_click", rect.get_center(), false)) != "cell":
		ok = _fail("LEDGER", "the priority cell click did nothing")
	scene.call("step_sim_once")
	var after: int = int(((world.components.get_component(ent, "jobPriorities") as Dictionary).get("cols", {}) as Dictionary).get(column, 0))
	var expected: int = 0 if before >= 4 else before + 1
	if after != expected:
		ok = _fail("LEDGER", "%s priority is %d after the click, expected %d" % [column, after, expected])
	var cmd: Dictionary = _last_command(world, "job.priority", tick_before)
	if cmd.is_empty() or int(cmd.get("entity", -1)) != ent or String(cmd.get("column", "")) != column:
		ok = _fail("LEDGER", "the priority click sent no job.priority for that colonist and column")

	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	if bool(scene.get("menu_open")):
		ok = _fail("LEDGER", "Escape did not close the ledger")
	if not bool(scene.call("mouse_captured")):
		_click_mouse()
	return ok


# DOOR: E opens it through the door verb, and the body walks through the doorway to the far side.
func _door_out(scene: Node, passage: Dictionary, run: Dictionary) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var door: Vector2i = passage["door"] as Vector2i
	var inside: Vector2i = passage["inside"] as Vector2i
	var outside: Vector2i = passage["outside"] as Vector2i
	var inside_at: Vector2 = _centre(inside)
	var door_at: Vector2 = _centre(door)
	run["door"] = door
	run["inside"] = inside
	run["outside"] = outside

	_place_player(scene, inside_at)
	scene.call("look_toward", Vector3(door_at.x, 1.0, door_at.y))
	scene.call("step_sim_once")
	if _door_open(world, door):
		return _fail("DOOR", "the door at %s is open before the expedition opens it" % str(door))
	_key(KEY_E, true)
	_key(KEY_E, false)
	scene.call("step_sim_once")
	if not _door_open(world, door):
		return _fail("DOOR", "E in reach and aimed at a shut door did not open it")

	var walked: Dictionary = _walk_to(scene, world, outside, _centre(outside), door, WALK_TICK_LIMIT)
	if not bool(walked["reached"]):
		return _fail("DOOR", "holding W did not walk the body out to %s" % str(outside))
	if not bool(walked["passed"]):
		ok = _fail("DOOR", "the body reached the far side without standing in the doorway")
	if not _door_open(world, door):
		ok = _fail("DOOR", "the door shut behind the walk")
	return ok


# CONTAINER: E at a sim container in reach and aimed at it opens the real sheet; the take is a
# press on the item and then on the pane's take button; Escape closes it.
func _container(scene: Node, run: Dictionary) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var spot: Dictionary = _find_container_approach(scene)
	if spot.is_empty():
		return _fail("CONTAINER", "no sim container has a standable spot in reach with a clear line")
	var box: int = int(spot["entity"])
	var stand: Vector2 = spot["at"] as Vector2
	_place_player(scene, stand)
	scene.call("look_toward", scene.call("container_world_point", box))
	_settle_vision(scene, 6)
	if String(scene.call("container_verdict")) != "ok":
		return _fail("CONTAINER", "a container in reach and in aim did not read as usable (%s)" % String(scene.call("container_verdict")))
	run["box"] = box

	world.commands.record = true
	world.commands.recorded.clear()
	var tick_before: int = int(world.tick)
	_key(KEY_E, true)
	_key(KEY_E, false)
	if not bool(scene.get("inventory_open")):
		return _fail("CONTAINER", "E at a container in reach and aimed at it did not open the inventory")
	var panel: Control = scene.call("inventory_panel_node") as Control
	if panel == null or not panel.visible or panel.get_script() != InventoryPanel:
		return _fail("CONTAINER", "E did not open the real grid sheet")
	scene.call("_process", TICK_SECONDS)
	await process_frame
	var open_cmd: Dictionary = _last_command(world, "container.open", tick_before)
	if open_cmd.is_empty() or int(open_cmd.get("container", -1)) != box:
		ok = _fail("CONTAINER", "container.open did not name the container in aim")
	if int(SimContainers.opened_by(world, int(world.player))) != box:
		ok = _fail("CONTAINER", "the sim does not have that container open")

	var box_items: Array[int] = SimContainers.contents_of(world, box)
	if box_items.is_empty():
		return _fail("CONTAINER", "the opened container rolled no items to take")
	var item: int = box_items[0]
	run["item"] = item

	if bool(run["take"]):
		var taken: bool = await _take(scene, panel, world, box, item)
		ok = taken and ok

	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	if bool(scene.get("inventory_open")):
		ok = _fail("CONTAINER", "Escape did not close the sheet")
	scene.call("_process", TICK_SECONDS)
	if _last_command(world, "container.close", tick_before).is_empty():
		ok = _fail("CONTAINER", "Escape did not send container.close")
	if int(SimContainers.opened_by(world, int(world.player))) != -1:
		ok = _fail("CONTAINER", "the sim still has the container open after Escape")
	if not bool(scene.call("mouse_captured")):
		ok = _fail("CONTAINER", "Escape did not give the mouse back")
	return ok


# A press on the item selects it on the sheet, and a press on the pane's take button pushes the sheet's
# `item.move`. Both presses land where the panel itself draws them, through its own press handler.
func _take(scene: Node, panel: Control, world: Variant, box: int, item: int) -> bool:
	var player: int = int(world.player)
	var plate: Variant = _plate_point(panel, item)
	if plate == null:
		return _fail("TAKE", "the sheet draws no plate for the item in the box")
	panel.call("_press_at", plate as Vector2)
	panel.call("_cancel_drag")
	await process_frame
	var pane: Rect2 = panel.call("_inspect_rect") as Rect2
	var take_at: Variant = null
	for b in InspectPane.button_rects(pane, panel.call("_pane_verbs")):
		if String((b as Dictionary)["verb"]) == "take":
			take_at = ((b as Dictionary)["rect"] as Rect2).get_center()
	if take_at == null:
		return _fail("TAKE", "the inspect pane offers no take button for the item in the box: %s" % str(panel.call("_pane_verbs")))

	var before_total: int = SimContainers.contents_of(world, box).size() + SimInventory.contents_of(world, player).size()
	world.commands.recorded.clear()
	var transfer_tick: int = int(world.tick)
	panel.call("_press_at", take_at as Vector2)
	scene.call("_process", TICK_SECONDS)
	var ok: bool = true
	var move: Dictionary = _last_command(world, "item.move", transfer_tick)
	if move.is_empty() or int(move.get("container", -1)) != player:
		ok = _fail("TAKE", "the take button did not send item.move into the player")
	if not SimInventory.owns(world, player, item):
		ok = _fail("TAKE", "the taken item is not in the player's pack")
	if SimContainers.contents_of(world, box).has(item):
		ok = _fail("TAKE", "the taken item is still in the box")
	var after_total: int = SimContainers.contents_of(world, box).size() + SimInventory.contents_of(world, player).size()
	if after_total != before_total:
		ok = _fail("TAKE", "the take changed the box-plus-pack count from %d to %d" % [before_total, after_total])
	return ok


# Back through the open door: the body walks from the far side onto the inside tile.
func _walk_back_inside(scene: Node, run: Dictionary) -> bool:
	var world: Variant = scene.get("world")
	var door: Vector2i = run["door"] as Vector2i
	var inside: Vector2i = run["inside"] as Vector2i
	var outside: Vector2i = run["outside"] as Vector2i
	_place_player(scene, _centre(outside))
	var walked: Dictionary = _walk_to(scene, world, inside, _centre(inside), door, WALK_TICK_LIMIT)
	if not bool(walked["reached"]):
		return _fail("RETURN", "holding W did not walk the body back in to %s" % str(inside))
	if not bool(walked["passed"]):
		return _fail("RETURN", "the body came back inside without standing in the doorway")
	return true


# SAVE: F5 writes the sim's save into the gate's slot, and says so.
func _save_here(scene: Node, run: Dictionary) -> bool:
	var world: Variant = scene.get("world")
	run["saved_pos"] = _player_pos(world)
	run["saved_tick"] = int(world.tick)
	_key(KEY_F5, true)
	_key(KEY_F5, false)
	if SaveSlot.read().is_empty():
		return _fail("SAVE", "F5 wrote no save")
	if not _joined_hud(scene).contains("Saved."):
		return _fail("SAVE", "F5 did not say Saved. on the HUD")
	return true


# WALK: the body walks away from the door, across open floor, so a load that did nothing would show.
func _walk_away(scene: Node, run: Dictionary) -> bool:
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var inside: Vector2i = run["inside"] as Vector2i
	var door: Vector2i = run["door"] as Vector2i
	var away: Vector2i = _find_walk_away(map, inside, door)
	if away == Vector2i.ZERO:
		return _fail("WALK", "no open floor leads away from the inside tile %s" % str(inside))
	var start: Vector2 = _player_pos(world)
	var aim: Vector2 = _centre(inside) + Vector2(float(away.x), float(away.y)) * 2.0
	scene.call("look_toward", Vector3(aim.x, 1.0, aim.y))
	_key(KEY_W, true)
	for i in WALK_AWAY_TICKS:
		scene.call("step_sim_once")
	_key(KEY_W, false)
	scene.call("step_sim_once")
	var moved: float = _player_pos(world).distance_to(start)
	if moved < 0.5:
		return _fail("WALK", "walking away moved the body only %.2f m" % moved)
	if _player_pos(world).distance_to(run["saved_pos"] as Vector2) < 0.5:
		return _fail("WALK", "the body is still at the saved spot after the walk away")
	return true


# LOAD: F9 puts the body back on the saved spot at the saved tick, and says so. Then the item's place is
# checked against the run: in the pack after a full run, still in the box after the skipped one.
func _load_back(scene: Node, run: Dictionary) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var saved_pos: Vector2 = run["saved_pos"] as Vector2
	var saved_tick: int = int(run["saved_tick"])
	_key(KEY_F9, true)
	_key(KEY_F9, false)
	if _player_pos(world).distance_to(saved_pos) > EPSILON:
		ok = _fail("LOAD", "F9 put the body at %s, not the saved %s" % [str(_player_pos(world)), str(saved_pos)])
	if int(world.tick) != saved_tick:
		ok = _fail("LOAD", "F9 restored tick %d, not the saved %d" % [int(world.tick), saved_tick])
	var rendered: Vector2 = scene.call("rendered_player_position")
	if rendered.distance_to(saved_pos) > EPSILON:
		ok = _fail("LOAD", "the scene still renders the body at %s after F9" % str(rendered))
	if not _joined_hud(scene).contains("Loaded."):
		ok = _fail("LOAD", "F9 did not say Loaded. on the HUD")
	var item: int = int(run["item"])
	var box: int = int(run["box"])
	var player: int = int(world.player)
	if bool(run["take"]):
		if not SimInventory.owns(world, player, item):
			ok = _fail("LOAD", "the item is not in the pack after F9, though the save was taken after the take")
		if SimContainers.contents_of(world, box).has(item):
			ok = _fail("LOAD", "the item is back in the box after F9")
	else:
		if SimInventory.owns(world, player, item):
			ok = _fail("LOAD", "the item is in the pack after F9, though the save was taken before any take")
		if not SimContainers.contents_of(world, box).has(item):
			ok = _fail("LOAD", "the item left the box before any take")
	return ok


# FIGHT: a shambler two metres ahead walks up, and the bat's swing, pressed on the F key, connects.
func _strike(scene: Node, run: Dictionary) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	var player: int = int(world.player)
	var inside: Vector2i = run["inside"] as Vector2i
	var door: Vector2i = run["door"] as Vector2i
	var away: Vector2i = _find_walk_away(map, inside, door)
	if away == Vector2i.ZERO:
		return _fail("FIGHT", "no open floor in front of the body for a shambler")
	var here: Vector2 = _player_pos(world)
	var dir: Vector2 = Vector2(float(away.x), float(away.y))
	SimMelee.make_melee_armed(world, player)
	SimHealth.make_stamina(world, player, 100)
	# On a tile centre two tiles out, so the body has clearance from the walls beside the line.
	var spawn_at: Vector2 = _centre(inside + away * 3)
	var rng: Variant = world.rng.stream("shambler")
	var zed: int = int(SimRoster.spawn_zombie(world, spawn_at.x, spawn_at.y, SimRoster.TYPE_SHAMBLER, rng))
	var start_gap: float = _entity_pos(world, zed).distance_to(_player_pos(world))
	var body_before: float = _body_total(_body_of(world, zed))
	scene.call("look_toward", Vector3(spawn_at.x, 1.0, spawn_at.y))
	scene.call("step_sim_once")

	var hit: bool = false
	var closest: float = start_gap
	for t in SWING_TICK_LIMIT:
		if t % SWING_EVERY_TICKS == 0:
			_key(KEY_F, true)
			_key(KEY_F, false)
		scene.call("_process", TICK_SECONDS)
		for event in world.events.drained:
			var e: Dictionary = event as Dictionary
			if String(e.get("type", "")) == "attack.connected" and int(e.get("attacker", -1)) == player and int(e.get("target", -1)) == zed:
				hit = true
		closest = minf(closest, _entity_pos(world, zed).distance_to(_player_pos(world)))
		if hit:
			break
	if not hit:
		return _fail("FIGHT", "no attack.connected on the shambler in %d ticks of swinging (closest %.2f m)" % [SWING_TICK_LIMIT, closest])
	if closest > start_gap - APPROACH_METRES:
		ok = _fail("FIGHT", "the shambler did not approach: it started %.2f m away and got no closer than %.2f m" % [start_gap, closest])
	if _body_total(_body_of(world, zed)) >= body_before:
		ok = _fail("FIGHT", "the shambler's body did not change on a landed swing")
	return ok


# --- THE NO-SAVE TRUE NEGATIVE ---------------------------------------------------------------------

# A run that loads before anything was saved: F9 says so and the sim does not move.
func _load_before_save(scene: Node) -> bool:
	var ok: bool = true
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	if not SaveSlot.read().is_empty():
		return _fail("NO-SAVE", "the gate's slot already holds a save before the run")
	var origin: Vector2 = _find_open_area(map, 2)
	if origin == Vector2(-1.0, -1.0):
		return _fail("NO-SAVE", "the district has no open area for the run")
	_place_player(scene, origin)
	scene.call("set_look", 0.0, 0.0)
	var player: int = int(world.player)
	var tick_before: int = int(world.tick)
	var pos_before: Vector2 = _player_pos(world)
	var pack_before: int = SimInventory.contents_of(world, player).size()
	_key(KEY_F9, true)
	_key(KEY_F9, false)
	if not _joined_hud(scene).contains("Nothing to load."):
		ok = _fail("NO-SAVE", "F9 with no save did not say Nothing to load. on the HUD")
	if not SaveSlot.read().is_empty():
		ok = _fail("NO-SAVE", "F9 with no save wrote a save")
	if int(world.tick) != tick_before:
		ok = _fail("NO-SAVE", "F9 with no save moved the tick from %d to %d" % [tick_before, int(world.tick)])
	if _player_pos(world).distance_to(pos_before) > EPSILON:
		ok = _fail("NO-SAVE", "F9 with no save moved the body")
	if SimInventory.contents_of(world, player).size() != pack_before:
		ok = _fail("NO-SAVE", "F9 with no save changed the pack")
	return ok


# --- DOOR AND WALK GEOMETRY ------------------------------------------------------------------------

# A shut door with open floor on both sides of it along one axis: the inside tile the body starts on,
# and the outside tile it walks to.
func _find_door_passage(world: Variant, map: Variant) -> Dictionary:
	for ent in world.components.query(["door"]):
		var d: Variant = world.components.get_component(int(ent), "door")
		if not (d is Dictionary) or bool((d as Dictionary).get("open", false)):
			continue
		var door: Vector2i = Vector2i(int((d as Dictionary).get("tx", 0)), int((d as Dictionary).get("ty", 0)))
		for axis in [Vector2i(1, 0), Vector2i(0, 1)]:
			var inside: Vector2i = door - axis
			var outside: Vector2i = door + axis
			if _walkable_floor(map, inside.x, inside.y) and _walkable_floor(map, outside.x, outside.y):
				return {"door": door, "inside": inside, "outside": outside}
	return {}


# A direction, not the door's, with three tiles of walkable floor ahead of the inside tile.
func _find_walk_away(map: Variant, from: Vector2i, door: Vector2i) -> Vector2i:
	var toward: Vector2i = door - from
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if d == toward:
			continue
		var clear: bool = true
		for k in range(1, 4):
			var tile: Vector2i = from + d * k
			if not _walkable_floor(map, tile.x, tile.y):
				clear = false
				break
		if clear:
			return d
	return Vector2i.ZERO


# Holds W with the look aimed at `aim` until the body stands on `tile`, or the tick limit runs out.
# `passed` says the body stood on `through` (the doorway) at some tick on the way.
func _walk_to(scene: Node, world: Variant, tile: Vector2i, aim: Vector2, through: Vector2i, limit: int) -> Dictionary:
	scene.call("look_toward", Vector3(aim.x, 1.0, aim.y))
	_key(KEY_W, true)
	var reached: bool = false
	var passed: bool = false
	for i in limit:
		scene.call("step_sim_once")
		var at: Vector2i = _tile_of(_player_pos(world))
		if at == through:
			passed = true
		if at == tile:
			reached = true
			break
	# Keep walking until the body is centred on the tile it was walking to, so a spawn or a later
	# walk starts from the middle of a tile rather than its edge.
	if reached:
		for i in WALK_TICK_LIMIT:
			if _player_pos(world).distance_to(aim) <= CENTRE_REACH_METRES:
				break
			scene.call("step_sim_once")
	_key(KEY_W, false)
	scene.call("step_sim_once")
	return {"reached": reached, "passed": passed}


func _tile_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x), floori(point.y))


func _centre(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)


func _door_open(world: Variant, door: Vector2i) -> bool:
	var d: Variant = SimFortify.door_state(world, door.x, door.y)
	return d is Dictionary and bool((d as Dictionary).get("open", false))


## A box and a standable floor tile within the sim's own reach from which the eye has a clear
## line to it. Places the player and settles the sim's sight, because that is what "in reach and
## in sight" means to the presentation.
func _find_container_approach(scene: Node) -> Dictionary:
	var world: Variant = scene.get("world")
	var map: Variant = scene.get("map")
	for entity in world.components.query(["searchable", "position"]):
		var ent: int = int(entity)
		var at: Vector2 = scene.call("container_sim_position", ent)
		var base: Vector2i = Vector2i(floori(at.x), floori(at.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var tx: int = base.x + dx
				var ty: int = base.y + dy
				if not _walkable_floor(map, tx, ty):
					continue
				var stand: Vector2 = Vector2(float(tx) + 0.5, float(ty) + 0.5)
				if stand.distance_to(at) > float(SimContainers.SEARCH_REACH) - 0.05:
					continue
				_place_player(scene, stand)
				scene.call("look_toward", scene.call("container_world_point", ent))
				_settle_vision(scene, 6)
				if int(scene.call("container_target")) == ent and String(scene.call("container_verdict")) == "ok":
					return {"entity": ent, "at": stand}
	return {}


func _plate_point(panel: Control, item: int) -> Variant:
	for placed in panel.call("_column_places") as Array:
		var column: Dictionary = (placed as Dictionary)["column"] as Dictionary
		for entry in column.get("items", []) as Array:
			if int((entry as Dictionary).get("item", -1)) == item:
				var origin: Vector2 = BagGrid.origin_of((placed as Dictionary)["at"] as Vector2)
				return BagGrid.plate_rect(origin, entry as Dictionary).get_center()
	return null


func _walkable_floor(map: Variant, tx: int, ty: int) -> bool:
	if tx <= 0 or ty <= 0 or tx >= int(map.w) - 1 or ty >= int(map.h) - 1:
		return false
	if SimTileMap.is_solid(map, tx, ty):
		return false
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return false
	var index: int = ty * int(map.w) + tx
	return int(map.surfaces[index]) != SimTileMap.SURFACE_WATER


func _find_open_area(map: Variant, radius: int) -> Vector2:
	for ty in range(radius + 1, int(map.h) - radius - 1):
		for tx in range(radius + 1, int(map.w) - radius - 1):
			var clear: bool = true
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if not _walkable_floor(map, tx + dx, ty + dy):
						clear = false
						break
				if not clear:
					break
			if clear:
				return Vector2(float(tx) + 0.5, float(ty) + 0.5)
	return Vector2(-1.0, -1.0)


# --- FIXTURES --------------------------------------------------------------------------------------

func _key(code: Key, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	root.push_input(ev)


func _click_mouse() -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	root.push_input(ev)


## Test setup, kept in the gate so the presentation never writes a sim component. The scene is
## told only to re-read the position afterwards (`snap_render_to_sim` is read-only).
func _place_player(scene: Node, point: Vector2) -> void:
	var world: Variant = scene.get("world")
	if world == null:
		return
	world.components.set_component(int(world.player), "position", {"x": point.x, "y": point.y})
	var velocity: Variant = world.components.get_component(int(world.player), "velocity")
	if velocity is Dictionary:
		(velocity as Dictionary)["dx"] = 0.0
		(velocity as Dictionary)["dy"] = 0.0
	scene.call("snap_render_to_sim")


## The player's shadowcast is deliberately staggered over a few ticks (`STAGGER_PLAYER_CAST`), so
## a teleport in the gate needs the same few ticks a walk would take before the sim's sight agrees.
func _settle_vision(scene: Node, ticks: int = 6) -> void:
	for _i in ticks:
		scene.call("step_sim_once")


func _player_pos(world: Variant) -> Vector2:
	var pos: Variant = world.components.get_component(int(world.player), "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _entity_pos(world: Variant, entity: int) -> Vector2:
	var pos: Variant = world.components.get_component(entity, "position")
	if not (pos is Dictionary):
		return Vector2.ZERO
	return Vector2(float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]))


func _last_command(world: Variant, type: String, after_tick: int) -> Dictionary:
	var recorded: Array = world.commands.recorded as Array
	for i in range(recorded.size() - 1, -1, -1):
		var rec: Dictionary = recorded[i] as Dictionary
		if int(rec.get("tick", -1)) <= after_tick:
			continue
		var command: Dictionary = rec.get("command", {}) as Dictionary
		if String(command.get("type", "")) == type:
			return command
	return {}


func _body_of(world: Variant, entity: int) -> Dictionary:
	var body: Variant = world.components.get_component(entity, "body")
	return (body as Dictionary).duplicate() if body is Dictionary else {}


func _body_total(body: Dictionary) -> float:
	var total: float = 0.0
	for value in body.values():
		if value is float or value is int:
			total += float(value)
	return total


# The words the HUD is drawing, joined, for the lanes that check what it says.
func _joined_hud(scene: Node) -> String:
	scene.call("_update_hud")
	var joined: String = ""
	for line in scene.call("hud_lines") as Array:
		joined += String(line) + "\n"
	return joined
