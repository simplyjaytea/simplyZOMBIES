extends SceneTree
# The right-click menu and walk-here: `sim/context.gd`'s `verbs_at` names only what the sim would
# accept (VERBS), every row it hands back actually moves the sim when pushed and stepped
# (DISPATCH), a click orders a walk at the same speed the stick would (SPEED), and the scene
# itself opens the menu, dispatches a row and closes on anything else (RIGHT-CLICK).
#
# Every assertion below carries its own negative, the convention `check_ban_health_bar.gd` set:
# a row that only ever appears would pass just as happily if `verbs_at` always returned
# everything, so every presence is paired with an absence right beside it.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimContext = preload("res://sim/context.gd")
const SimCamp = preload("res://sim/modules/camp.gd")
const SimPath = preload("res://sim/path.gd")
const Clock = preload("res://sim/time/clock.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const SimItems = preload("res://sim/modules/items.gd")
const ItemMenu = preload("res://ui/item_menu.gd")
const SimRoster = preload("res://sim/modules/roster.gd")

const MAP_TILES: int = 24
const SCENE_PATH: String = "res://presentation/main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _verbs() and ok
	ok = _dispatch() and ok
	ok = _speed() and ok
	var right_click_ok: bool = await _right_click()
	ok = right_click_ok and ok
	if ok:
		print("CONTEXT_OK the street menu offers only what the sim would accept, every row moves the sim, a click walks at the stick's own speed, and the scene opens, dispatches and closes it")
		quit(0)
	else:
		push_error("CONTEXT_FAIL")
		quit(1)


# --- the fixture ---------------------------------------------------------------------------

func _world(px: float = 10.5, py: float = 10.5, angle: float = 0.0) -> Variant:
	var f: Dictionary = {"seed": 9201, "tick_hz": 20, "map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []}, "player": {"id": 0, "x": px, "y": py, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	SimBoot.attach_kernel(w, map)
	SimInventory.register_module(w)
	SimFortify.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": angle})
	SimInventory.make_inventory(w, w.player)
	return w


func _set_tile(w: Variant, tx: int, ty: int, tile: int) -> void:
	w.tilemap.tiles[ty * int(w.tilemap.w) + tx] = tile
	SimFortify.sync_map(w)


func _wall_box(w: Variant, tx: int, ty: int) -> void:
	_set_tile(w, tx - 1, ty, SimTileMap.Tile.Wall)
	_set_tile(w, tx + 1, ty, SimTileMap.Tile.Wall)
	_set_tile(w, tx, ty - 1, SimTileMap.Tile.Wall)
	_set_tile(w, tx, ty + 1, SimTileMap.Tile.Wall)


func _has_digit(text: String) -> bool:
	for i in text.length():
		if text[i].is_valid_int():
			return true
	return false


# --- VERBS -----------------------------------------------------------------------------------

func _verbs() -> bool:
	var ok: bool = true
	var all_texts: Array = []

	# An item in reach offers "pick up"; the same item far away offers "walk over" and not
	# "pick up".
	var wi: Variant = _world()
	var item: int = _spawn_test_item(wi)
	wi.components.set_component(item, "position", {"x": 11.0, "y": 10.5})
	var hit_near: Dictionary = {"kind": "item", "entity": item, "tile": Vector2i(11, 10)}
	var rows_near: Array[Dictionary] = SimContext.verbs_at(wi, wi.player, hit_near)
	if not _has_row(rows_near, "pick up"):
		push_error("VERBS: an item in reach offers no pick-up row")
		ok = false
	_collect(all_texts, rows_near)
	wi.components.set_component(item, "position", {"x": 20.5, "y": 10.5})
	var hit_far: Dictionary = {"kind": "item", "entity": item, "tile": Vector2i(20, 10)}
	var rows_far: Array[Dictionary] = SimContext.verbs_at(wi, wi.player, hit_far)
	if _has_row(rows_far, "pick up"):
		push_error("VERBS: an item 10 m away still offers pick-up")
		ok = false
	if not _has_row(rows_far, "walk over"):
		push_error("VERBS: an item 10 m away offers no walk-over row")
		ok = false
	_collect(all_texts, rows_far)

	# A shut door in reach offers "open the door"; toggled open, it offers "shut the door".
	var wd: Variant = _world(10.5, 10.5, 0.0)
	_set_tile(wd, 11, 10, SimTileMap.Tile.Door)
	SimFortify.spawn_doors(wd, wd.tilemap)
	var door_tile := Vector2i(11, 10)
	var hit_door: Dictionary = {"kind": "door", "entity": -1, "tile": door_tile}
	var rows_shut: Array[Dictionary] = SimContext.verbs_at(wd, wd.player, hit_door)
	if not _has_row(rows_shut, "open the door"):
		push_error("VERBS: a shut door in reach offers no open row")
		ok = false
	if _has_row(rows_shut, "shut the door"):
		push_error("VERBS: a shut door already offers to shut itself")
		ok = false
	_collect(all_texts, rows_shut)
	SimFortify.toggle_door(wd, 11, 10)
	var rows_open: Array[Dictionary] = SimContext.verbs_at(wd, wd.player, hit_door)
	if not _has_row(rows_open, "shut the door"):
		push_error("VERBS: an open door in reach offers no shut row")
		ok = false
	if _has_row(rows_open, "open the door"):
		push_error("VERBS: an open door still offers to open itself")
		ok = false
	_collect(all_texts, rows_open)
	# The same door tile out of reach offers neither -- the door in `wd` above stands one tile
	# from the player; here the player stands far from it instead.
	var wd2: Variant = _world(2.5, 2.5, 0.0)
	_set_tile(wd2, 11, 10, SimTileMap.Tile.Door)
	SimFortify.spawn_doors(wd2, wd2.tilemap)
	var rows_far_door: Array[Dictionary] = SimContext.verbs_at(wd2, wd2.player, hit_door)
	if _has_row(rows_far_door, "open the door") or _has_row(rows_far_door, "shut the door"):
		push_error("VERBS: a door out of reach still offers to toggle")
		ok = false

	# A colonist offers "pull ... free" only while grabbed.
	var wc: Variant = _world()
	var colonist: int = int(wc.entities.spawn())
	wc.components.set_component(colonist, "position", {"x": 11.0, "y": 10.5})
	wc.components.set_component(colonist, "identity", {"name": "Ren"})
	var hit_colonist: Dictionary = {"kind": "colonist", "entity": colonist, "tile": Vector2i(11, 10)}
	var rows_free: Array[Dictionary] = SimContext.verbs_at(wc, wc.player, hit_colonist)
	if _has_row(rows_free, "pull "):
		push_error("VERBS: an ungrabbed colonist already offers to be pulled free")
		ok = false
	_collect(all_texts, rows_free)
	wc.components.set_component(colonist, "grabbed", {"sources": [999], "struggleTicks": 0, "heldTicks": 0})
	var rows_grabbed: Array[Dictionary] = SimContext.verbs_at(wc, wc.player, hit_colonist)
	if not _has_row(rows_grabbed, "pull "):
		push_error("VERBS: a grabbed colonist offers no pull-free row")
		ok = false
	_collect(all_texts, rows_grabbed)

	# A shambler offers "attack"; the same tile with nobody on it does not.
	var wz: Variant = _world()
	var zed: int = int(wz.entities.spawn())
	wz.components.set_component(zed, "position", {"x": 11.0, "y": 10.5})
	wz.components.set_component(zed, "shambler", {})
	var hit_zombie: Dictionary = {"kind": "zombie", "entity": zed, "tile": Vector2i(11, 10)}
	var rows_zombie: Array[Dictionary] = SimContext.verbs_at(wz, wz.player, hit_zombie)
	if not _has_row(rows_zombie, "attack"):
		push_error("VERBS: a shambler offers no attack row")
		ok = false
	_collect(all_texts, rows_zombie)
	var hit_empty: Dictionary = {"kind": "ground", "entity": -1, "tile": Vector2i(11, 10)}
	var rows_empty_tile: Array[Dictionary] = SimContext.verbs_at(wz, wz.player, hit_empty)
	if _has_row(rows_empty_tile, "attack"):
		push_error("VERBS: an empty tile offers an attack row")
		ok = false

	# Own tile offers "shout" always, and "make camp here" only where SimCamp.can_establish.
	var wo: Variant = _world()
	var here := Vector2i(10, 10)
	var hit_here: Dictionary = {"kind": "ground", "entity": -1, "tile": here}
	var rows_here: Array[Dictionary] = SimContext.verbs_at(wo, wo.player, hit_here)
	if not _has_row(rows_here, "shout"):
		push_error("VERBS: your own tile offers no shout row")
		ok = false
	if not _has_row(rows_here, "make camp here"):
		push_error("VERBS: an establishable tile offers no camp row")
		ok = false
	_collect(all_texts, rows_here)
	var camp_ent: int = int(wo.entities.spawn())
	wo.components.set_component(camp_ent, "camp", {"tx": here.x, "ty": here.y, "home": false, "abandonedAtTick": -1})
	var rows_camped: Array[Dictionary] = SimContext.verbs_at(wo, wo.player, hit_here)
	if _has_row(rows_camped, "make camp here"):
		push_error("VERBS: a tile with a camp on it still offers to camp there")
		ok = false
	if not _has_row(rows_camped, "shout"):
		push_error("VERBS: a camped tile lost its shout row")
		ok = false
	_collect(all_texts, rows_camped)

	# A wall tile, nobody's, offers nothing.
	var ww: Variant = _world()
	_set_tile(ww, 15, 15, SimTileMap.Tile.Wall)
	var hit_wall: Dictionary = {"kind": "ground", "entity": -1, "tile": Vector2i(15, 15)}
	var rows_wall: Array[Dictionary] = SimContext.verbs_at(ww, ww.player, hit_wall)
	if not rows_wall.is_empty():
		push_error("VERBS: a wall tile offers %s" % str(rows_wall))
		ok = false

	# Every text digit-free, and the scanner itself proved on a fabricated row first.
	if not _has_digit("walk 3 m"):
		push_error("VERBS: the digit scanner missed a fabricated \"walk 3 m\"")
		ok = false
	for text in all_texts:
		if _has_digit(String(text)):
			push_error("VERBS: a row carries a digit: \"%s\"" % text)
			ok = false

	if ok:
		print("VERBS OK reach, doors, a grabbed colonist, a shambler, your own tile and a wall, every row digit-free")
	return ok


func _has_row(rows: Array[Dictionary], prefix: String) -> bool:
	for r in rows:
		if String((r as Dictionary).get("text", "")).begins_with(prefix):
			return true
	return false


func _collect(into: Array, rows: Array[Dictionary]) -> void:
	for r in rows:
		into.append(String((r as Dictionary).get("text", "")))


# A minimal ground item. Digit-free by name on purpose: docs/30's "the cartridge on the label"
# narrow amendment lets an item's `name` carry a digit (a caliber, say), and this lane's blanket
# digit scan is about the menu's *own* words, not a re-litigation of that amendment -- so the
# fixture picks a base that was never going to collide with it.
func _spawn_test_item(w: Variant) -> int:
	return SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})


# --- DISPATCH --------------------------------------------------------------------------------

func _dispatch() -> bool:
	var ok: bool = true

	# item.pickup: the item leaves the ground and lands in the pack.
	var wi: Variant = _world()
	var item: int = _spawn_test_item(wi)
	wi.components.set_component(item, "position", {"x": 11.0, "y": 10.5})
	wi.commands.push({"type": "item.pickup", "item": item})
	wi.step()
	if not SimInventory.owns(wi, wi.player, item):
		push_error("DISPATCH: item.pickup did not put the item in the pack")
		ok = false

	# door.toggle: the door opens.
	var wd: Variant = _world(10.5, 10.5, 0.0)
	_set_tile(wd, 11, 10, SimTileMap.Tile.Door)
	SimFortify.spawn_doors(wd, wd.tilemap)
	wd.commands.push({"type": "door.toggle", "tx": 11, "ty": 10})
	wd.step()
	var dstate: Dictionary = SimFortify.door_state(wd, 11, 10) as Dictionary
	if not bool(dstate.get("open", false)):
		push_error("DISPATCH: door.toggle did not open the door")
		ok = false

	# walk.to: the body arrives within half a metre of the tile and lets go of walkTo.
	var ww: Variant = _world(10.5, 10.5, 0.0)
	ww.commands.push({"type": "walk.to", "tx": 13, "ty": 10})
	for _i in 300:
		ww.step()
	var wpos: Dictionary = ww.components.get_component(ww.player, "position") as Dictionary
	var dx: float = float(wpos["x"]) - 13.5
	var dy: float = float(wpos["y"]) - 10.5
	if dx * dx + dy * dy > 0.25:
		push_error("DISPATCH: walk.to did not arrive (at %.2f,%.2f)" % [float(wpos["x"]), float(wpos["y"])])
		ok = false
	if ww.components.has_component(ww.player, "walkTo"):
		push_error("DISPATCH: walkTo is still standing after arrival")
		ok = false

	# A move pushed mid-walk removes it and the body stops where it was pushed to (a wait
	# straight after reads the velocity that stop left behind).
	var wm: Variant = _world(10.5, 10.5, 0.0)
	wm.commands.push({"type": "walk.to", "tx": 20, "ty": 10})
	for _i in 5:
		wm.step()
	if not wm.components.has_component(wm.player, "walkTo"):
		push_error("DISPATCH: walk-to let go before the move test could cancel it")
		ok = false
	wm.commands.push({"type": "move", "dx": 0.0, "dy": -1.0})
	wm.step()
	if wm.components.has_component(wm.player, "walkTo"):
		push_error("DISPATCH: a move command did not cancel a standing walk-to")
		ok = false
	var mvel: Dictionary = wm.components.get_component(wm.player, "velocity") as Dictionary
	if float(mvel["dx"]) != 0.0 or float(mvel["dy"]) >= 0.0:
		push_error("DISPATCH: the move that cancelled the walk did not take the body")
		ok = false

	# A walk-to at an unreachable tile (a floor tile walled in on all four sides) removes the
	# component on the first tick.
	var wu: Variant = _world(10.5, 10.5, 0.0)
	_wall_box(wu, 5, 5)
	wu.commands.push({"type": "walk.to", "tx": 5, "ty": 5})
	wu.step()
	if wu.components.has_component(wu.player, "walkTo"):
		push_error("DISPATCH: a walk-to with no route was not removed on the first tick")
		ok = false

	if ok:
		print("DISPATCH OK a pickup, a door, an arrival, a cancelling move and a routeless walk-to")
	return ok


# --- SPEED -----------------------------------------------------------------------------------

func _speed() -> bool:
	var ok: bool = true

	var wm: Variant = _world(10.5, 10.5, 0.0)
	var expected_move: float = wm.move_speed_of(wm.player)
	wm.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
	wm.step()
	var mvel: Dictionary = wm.components.get_component(wm.player, "velocity") as Dictionary
	var move_speed: float = sqrt(float(mvel["dx"]) * float(mvel["dx"]) + float(mvel["dy"]) * float(mvel["dy"]))
	if not is_equal_approx(move_speed, expected_move):
		push_error("SPEED: move's own speed is %.4f, move_speed_of says %.4f" % [move_speed, expected_move])
		ok = false

	var ww: Variant = _world(10.5, 10.5, 0.0)
	var expected_walk: float = ww.move_speed_of(ww.player)
	ww.commands.push({"type": "walk.to", "tx": 13, "ty": 10})
	ww.step()
	var wvel: Dictionary = ww.components.get_component(ww.player, "velocity") as Dictionary
	var walk_speed: float = sqrt(float(wvel["dx"]) * float(wvel["dx"]) + float(wvel["dy"]) * float(wvel["dy"]))
	if not is_equal_approx(walk_speed, expected_walk):
		push_error("SPEED: walk.to's own speed is %.4f, move_speed_of says %.4f" % [walk_speed, expected_walk])
		ok = false
	if not is_equal_approx(move_speed, walk_speed):
		push_error("SPEED: a click walks at %.4f and the stick moves at %.4f" % [walk_speed, move_speed])
		ok = false

	if ok:
		print("SPEED OK a click orders the same speed the stick would")
	return ok


# --- RIGHT-CLICK -----------------------------------------------------------------------------

func _mouse(pos: Vector2, button: int, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = button
	ev.pressed = pressed
	return ev


func _click(pos: Vector2, button: int) -> void:
	root.push_input(_mouse(pos, button, true))
	root.push_input(_mouse(pos, button, false))


func _boot_scene() -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("cannot load %s" % SCENE_PATH)
		return null
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	if main.get("world") == null:
		push_error("the main scene did not construct a world")
		main.queue_free()
		return null
	main.set_process(false)
	main.set("accumulator", 0.0)
	return main


func _boot() -> Node:
	var main: Node = await _boot_scene()
	if main == null:
		return null
	var shell: Variant = main.get("_shell")
	if shell != null and bool((shell as CanvasItem).visible):
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.physical_keycode = KEY_ENTER
		ev.pressed = true
		root.push_input(ev)
		ev = InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.physical_keycode = KEY_ENTER
		ev.pressed = false
		root.push_input(ev)
		await process_frame
	var legend: Variant = main.get("_legend")
	if legend != null and bool((legend as CanvasItem).visible):
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		root.push_input(esc)
		esc = InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = false
		root.push_input(esc)
		await process_frame
	main.set("accumulator", 0.0)
	return main


# Any floor two tiles deep from the player's spawn, in one of the four cardinal directions --
# the booted district is procedural, so this asks the map rather than assuming one.
func _open_lane(world: Variant, px: float, py: float) -> Vector2:
	var dirs: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	for d in dirs:
		var ok: bool = true
		for step in [1, 2]:
			var tx: int = floori(px + d.x * float(step))
			var ty: int = floori(py + d.y * float(step))
			if world.is_blocked_tile(tx, ty):
				ok = false
				break
		if ok:
			return d
	return Vector2.ZERO


func _right_click() -> bool:
	var main: Node = await _boot()
	if main == null:
		push_error("CONTEXT: the scene did not boot")
		return false
	var ok: bool = true
	var world: Variant = main.get("world")
	var ppos: Dictionary = world.components.get_component(int(world.player), "position") as Dictionary
	var px: float = float(ppos["x"])
	var py: float = float(ppos["y"])
	# The boot colony's other two survivors stand right beside the player and would otherwise
	# contest the click -- their own rect can overlap the zombie's and win the depth tie-break.
	# Tucked into the map's corner, out of the pick's way, for the rest of this lane only.
	for other in world.components.query(["identity", "position"]):
		if int(other) == int(world.player):
			continue
		world.components.set_component(int(other), "position", {"x": 1.5, "y": 1.5})
	var dir: Vector2 = _open_lane(world, px, py)
	if dir == Vector2.ZERO:
		print("CONTEXT: RIGHT-CLICK skipped, no open lane found near spawn")
	else:
		world.components.set_component(int(world.player), "facing", {"radians": atan2(dir.y, dir.x)})
		var zx: float = px + dir.x * 1.5
		var zy: float = py + dir.y * 1.5
		# A real roster body, not a bare component -- `shambler.think` reads fields
		# (`ticksToGrab` among them) a hand-built `{"shambler": {}}` does not carry, and this
		# lane runs the whole game a tick, AI included.
		var zed: int = SimRoster.spawn_zombie(world, zx, zy, SimRoster.TYPE_SHAMBLER, world.rng.stream("shambler"))
		main.call("_process", 1.0 / 20.0)

		var camera: Dictionary = main.get("camera")
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, zx, zy)
		var screen_pos := Vector2(float(sc["sx"]), float(sc["sy"]))
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, true))
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, false))

		var menu: Variant = main.get("_context_menu")
		if menu == null or not bool(menu.call("is_open")):
			push_error("RIGHT-CLICK: a right click on a Focal shambler opened no menu")
			ok = false
		else:
			var rows: Array = menu.call("rows")
			var attack_index: int = -1
			for i in rows.size():
				if String((rows[i] as Dictionary).get("text", "")) == "attack":
					attack_index = i
					break
			if attack_index < 0:
				var texts_dbg: Array = []
				for r in rows:
					texts_dbg.append(String((r as Dictionary).get("text", "")))
				push_error("RIGHT-CLICK: the menu over a shambler carries no attack row (rows: %s, dir %s, zombie at %.2f,%.2f)" % [str(texts_dbg), str(dir), zx, zy])
				ok = false
			else:
				var texts: Array = []
				for r in rows:
					texts.append(String((r as Dictionary).get("text", "")))
				var rects: Array[Dictionary] = ItemMenu.verb_rects(Vector2.ZERO, texts)
				var row_pos: Vector2 = menu.get("position") as Vector2
				var click_at: Vector2 = row_pos + (rects[attack_index]["rect"] as Rect2).get_center()
				(world.commands as Variant)._pending.clear()
				root.push_input(_mouse(click_at, MOUSE_BUTTON_LEFT, true))
				root.push_input(_mouse(click_at, MOUSE_BUTTON_LEFT, false))
				var types: Array = []
				for cmd in (world.commands as Variant)._pending as Array:
					types.append(String((cmd as Dictionary).get("type", "")))
				if not types.has("aim") or not (types.has("swing") or types.has("fire")):
					push_error("RIGHT-CLICK: picking the attack row did not push aim and swing/fire (pushed %s)" % str(types))
					ok = false
				if bool(menu.call("is_open")):
					push_error("RIGHT-CLICK: the menu is still open after a row was picked")
					ok = false

		# A right click while the inventory sheet is up opens nothing.
		main.call("_set_inventory_open", true)
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, true))
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, false))
		if menu != null and bool(menu.call("is_open")):
			push_error("RIGHT-CLICK: a right click with the sheet open opened the menu")
			ok = false
		main.call("_set_inventory_open", false)

		# A left click off the menu closes it and pushes no swing.
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, true))
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, false))
		if menu == null or not bool(menu.call("is_open")):
			push_error("RIGHT-CLICK: re-opening the menu for the off-menu-click lane failed")
			ok = false
		else:
			(world.commands as Variant)._pending.clear()
			var away := Vector2(4.0, 4.0)
			root.push_input(_mouse(away, MOUSE_BUTTON_LEFT, true))
			root.push_input(_mouse(away, MOUSE_BUTTON_LEFT, false))
			if bool(menu.call("is_open")):
				push_error("RIGHT-CLICK: a left click off the menu left it open")
				ok = false
			var types2: Array = []
			for cmd in (world.commands as Variant)._pending as Array:
				types2.append(String((cmd as Dictionary).get("type", "")))
			if types2.has("swing") or types2.has("fire"):
				push_error("RIGHT-CLICK: the click that closed the menu also swung (%s)" % str(types2))
				ok = false

	main.queue_free()
	await process_frame
	if ok:
		print("RIGHT-CLICK OK the scene opens the menu on a Focal shambler, dispatches its row and closes on anything else")
	return ok
