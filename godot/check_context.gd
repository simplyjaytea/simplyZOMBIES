extends SceneTree
# The right-click menu and walk-here: `sim/context.gd`'s `verbs_at` names only what the sim would
# accept (VERBS), every row it hands back actually moves the sim when pushed and stepped
# (DISPATCH), a click orders a walk at the same speed the stick would (SPEED), and the scene
# itself opens the menu, dispatches a row and closes on anything else (RIGHT-CLICK). The menu's
# header names what was clicked and the bare ground has none (HEADER, in the sim and on the
# scene's menu); Up, Down, Enter and Escape drive it (KEYS); and the action bar's E clause is the
# menu's first in-reach row, word for word, at a window, a door, a loose item and a crate (BAR).
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
const SimRecruitsRes = preload("res://sim/modules/recruits.gd")
const SimCamp = preload("res://sim/modules/camp.gd")
const SimPath = preload("res://sim/path.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const Clock = preload("res://sim/time/clock.gd")
const TopDownProjection = preload("res://presentation/projection.gd")
const SimItems = preload("res://sim/modules/items.gd")
const ItemMenu = preload("res://ui/item_menu.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const Hud = preload("res://ui/hud.gd")
const Pick = preload("res://presentation/pick.gd")
const Locker = preload("res://ui/locker.gd")
const SimStockpile = preload("res://sim/modules/stockpile.gd")

const MAP_TILES: int = 24
const SCENE_PATH: String = "res://presentation/main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _verbs() and ok
	ok = _raised_rows() and ok
	ok = _decline() and ok
	ok = _dispatch() and ok
	ok = _speed() and ok
	ok = _labels() and ok
	ok = _bar() and ok
	var right_click_ok: bool = await _right_click()
	ok = right_click_ok and ok
	if ok:
		print("CONTEXT_OK the street menu offers only what the sim would accept, every row moves the sim, a click walks at the stick's own speed, its header names what was clicked, the bar's E words are its first row's, the raised walls are offered only where their material is carried and the ground takes them, and the scene opens, dispatches, closes it and answers its keys")
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

	# A planted floodlight: a planted lamp in reach offers "take down", through the sim's own
	# `light.unplant`, and dispatching the row's own command takes the lamp down into the pack.
	# The bare ground beside it and the same lamp out of reach offer none, and neither does the
	# lamp once it is back in the pack. The fixture pack is on purpose: a 3x3 stand has somewhere
	# to come home to only if the refusal is about reach, not about room.
	var wfl: Variant = _world()
	var pack_fixture: int = SimItems.spawn_item(wfl, "item.pack.hiking", {"tier": "scavenged"})
	if not SimInventory.equip(wfl, wfl.player, pack_fixture):
		push_error("VERBS: the take-down fixture pack would not go on")
		ok = false
	SimLightMod.register_module(wfl)
	var flood_ent: int = int(wfl.entities.spawn())
	wfl.components.set_component(flood_ent, "itemBase", {"baseId": "item.floodlight.rigged"})
	wfl.components.set_component(flood_ent, "placedLight", {"baseId": "item.floodlight.rigged", "tx": 11, "ty": 10})
	wfl.components.set_component(flood_ent, "position", {"x": 11.5, "y": 10.5})
	wfl.components.set_component(flood_ent, "stored", {"container": flood_ent, "x": 0, "y": 0, "rotated": false})
	var hit_lamp: Dictionary = {"kind": "prop", "entity": flood_ent, "tile": Vector2i(11, 10)}
	var rows_lamp: Array[Dictionary] = SimContext.verbs_at(wfl, wfl.player, hit_lamp)
	if not _has_row(rows_lamp, "take down the"):
		push_error("VERBS: a planted floodlight in reach offers no take-down row")
		ok = false
	_collect(all_texts, rows_lamp)
	var lamp_row: Dictionary = {}
	for r in rows_lamp:
		if String((r as Dictionary).get("text", "")).begins_with("take down the"):
			lamp_row = r as Dictionary
	wfl.commands.push((lamp_row as Dictionary).get("command", {}) as Dictionary)
	wfl.step()
	if wfl.components.has_component(flood_ent, "placedLight") or not SimInventory.owns(wfl, wfl.player, flood_ent):
		push_error("VERBS: dispatching the take-down row did not take the lamp down into the pack")
		ok = false
	if _has_row(SimContext.verbs_at(wfl, wfl.player, {"kind": "ground", "entity": -1, "tile": Vector2i(11, 10)}), "take down"):
		push_error("VERBS: bare ground beside the lamp was offered the take-down")
		ok = false
	if _has_row(SimContext.verbs_at(wfl, wfl.player, {"kind": "prop", "entity": flood_ent, "tile": Vector2i(11, 10)}), "take down"):
		push_error("VERBS: the packed floodlight still offers the take-down row")
		ok = false
	var flood_far: int = int(wfl.entities.spawn())
	wfl.components.set_component(flood_far, "itemBase", {"baseId": "item.floodlight.rigged"})
	wfl.components.set_component(flood_far, "placedLight", {"baseId": "item.floodlight.rigged", "tx": 20, "ty": 2})
	wfl.components.set_component(flood_far, "position", {"x": 20.5, "y": 2.5})
	wfl.components.set_component(flood_far, "stored", {"container": flood_far, "x": 0, "y": 0, "rotated": false})
	if _has_row(SimContext.verbs_at(wfl, wfl.player, {"kind": "prop", "entity": flood_far, "tile": Vector2i(20, 2)}), "take down"):
		push_error("VERBS: a lamp out of reach still offers the take-down")
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
		print("VERBS OK reach, doors, a planted lamp's take-down, a grabbed colonist, a shambler, your own tile and a wall, every row digit-free")
	return ok


# A waiting recruit in reach offers "turn them away", and the row's command sends them off through
# the sim's own `recruit.ignore`: the recruit leaves the world and never joins the colony. Out of
# reach the row is absent, and so is it for a body that is not waiting at the gate.
func _decline() -> bool:
	var ok: bool = true
	var w: Variant = _world()
	SimRecruitsRes.register_module(w)
	var near: int = int(w.entities.spawn())
	w.components.set_component(near, "position", {"x": 11.0, "y": 10.5})
	w.components.set_component(near, "identity", {"name": "Ren"})
	w.components.set_component(near, "recruit", {"waiting": true})
	var hit: Dictionary = {"kind": "colonist", "entity": near, "tile": Vector2i(11, 10)}
	var rows: Array[Dictionary] = SimContext.verbs_at(w, w.player, hit)
	if not _has_row(rows, "turn them away"):
		push_error("DECLINE: a waiting recruit in reach offers no 'turn them away' row")
		ok = false
	for r in rows:
		if String((r as Dictionary).get("text", "")) == "turn them away":
			var cmd: Dictionary = (r as Dictionary).get("command", {}) as Dictionary
			if String(cmd.get("type", "")) != "recruit.ignore" or int(cmd.get("entity", -1)) != near:
				push_error("DECLINE: the decline row does not carry recruit.ignore for the recruit: %s" % str(cmd))
				ok = false
			w.commands.push(cmd)
	w.step()
	# `despawn` leaves the components in place (CLAUDE.md's traps), so the judge is liveness.
	if bool(w.entities.is_alive(near)):
		push_error("DECLINE: dispatching the row did not send the recruit away")
		ok = false
	var far: int = int(w.entities.spawn())
	w.components.set_component(far, "position", {"x": 20.5, "y": 10.5})
	w.components.set_component(far, "recruit", {"waiting": true})
	var far_hit: Dictionary = {"kind": "colonist", "entity": far, "tile": Vector2i(20, 10)}
	if _has_row(SimContext.verbs_at(w, w.player, far_hit), "turn them away"):
		push_error("DECLINE: a recruit out of reach was offered the decline")
		ok = false
	var idle: int = int(w.entities.spawn())
	w.components.set_component(idle, "position", {"x": 11.0, "y": 10.5})
	w.components.set_component(idle, "identity", {"name": "Ren"})
	var idle_hit: Dictionary = {"kind": "colonist", "entity": idle, "tile": Vector2i(11, 10)}
	if _has_row(SimContext.verbs_at(w, w.player, idle_hit), "turn them away"):
		push_error("DECLINE: a colonist who is not waiting was offered the decline")
		ok = false
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


# The three raised walls: a row for each, offered on the tile in front only while the survivor
# carries its one substance and the ground takes a wall. Each row's `use.context` starts that
# wall's own channel, which is read back off the actor's construct component.
func _raised_rows() -> bool:
	var ok: bool = true
	var cases: Array[Dictionary] = [
		{"item": "item.plank.sawn", "row": "raise a timber wall", "verb": "timber"},
		{"item": "item.stone.block", "row": "raise a stone course", "verb": "stone"},
		{"item": "item.wire.steel", "row": "string a wire fence", "verb": "fence"},
	]
	var hit: Dictionary = {"kind": "ground", "entity": -1, "tile": Vector2i(11, 10)}
	for case in cases:
		var w: Variant = _world(10.5, 10.5, 0.0)
		var bare_rows: Array[Dictionary] = SimContext.verbs_at(w, w.player, hit)
		if _has_row(bare_rows, String(case["row"])):
			push_error("RAISED: '%s' offered with nothing carried" % String(case["row"]))
			ok = false
		var item: int = SimItems.spawn_item(w, String(case["item"]), {"tier": "scavenged", "count": 1})
		if not SimInventory.stow(w, w.player, item):
			push_error("RAISED: could not stow '%s'" % String(case["item"]))
			return false
		var rows: Array[Dictionary] = SimContext.verbs_at(w, w.player, hit)
		if not _has_row(rows, String(case["row"])):
			push_error("RAISED: '%s' not offered on open ground with its material carried" % String(case["row"]))
			ok = false
		SimFortify._use_context(w, w.player)
		var channel: Variant = w.components.get_component(w.player, "construct")
		if not channel is Dictionary or String((channel as Dictionary).get("verb", "")) != String(case["verb"]):
			push_error("RAISED: the row's use.context did not start the '%s' channel" % String(case["verb"]))
			ok = false

	# A window in front is not ground a wall takes: the scrap barricade's window rule is the
	# barricade's, and the raised walls ask only for open floor, so this refusal is the window's own.
	var wn: Variant = _world(10.5, 10.5, 0.0)
	_set_tile(wn, 11, 10, SimTileMap.Tile.Window)
	var plank: int = SimItems.spawn_item(wn, "item.plank.sawn", {"tier": "scavenged", "count": 1})
	SimInventory.stow(wn, wn.player, plank)
	if _has_row(SimContext.verbs_at(wn, wn.player, hit), "raise a timber wall"):
		push_error("RAISED: a timber wall offered on a window tile")
		ok = false
	return ok


# --- HEADER and BAR ----------------------------------------------------------------------------

# `SimContext.target_label`: the menu's header for whatever was clicked. True positives on a
# colonist (by name), a container (by kind), a loose item (by name), a door and a zombie; the true
# negative is the bare ground, which has none. And a zombie is "a zombie" whatever it is: the label
# must never say which kind of dead it is, so a runner reads the same as a shambler.
func _labels() -> bool:
	var ok: bool = true
	var w: Variant = _world()
	var ren: int = int(w.entities.spawn())
	w.components.set_component(ren, "position", {"x": 11.0, "y": 10.5})
	w.components.set_component(ren, "identity", {"name": "Ren Okafor"})
	var crate: int = int(w.entities.spawn())
	w.components.set_component(crate, "position", {"x": 12.5, "y": 10.5})
	w.components.set_component(crate, "searchable", {"kind": "crate", "searched": false})
	var item: int = _spawn_test_item(w)
	w.components.set_component(item, "position", {"x": 11.0, "y": 11.5})
	var zed: int = int(w.entities.spawn())
	w.components.set_component(zed, "position", {"x": 13.0, "y": 10.5})
	w.components.set_component(zed, "shambler", {"type": "runner"})
	var item_name: String = SimItems.item_name(w, item).to_lower()
	var cases: Array = [
		# The whole name the identity carries, not a first name cut out of it.
		[{"kind": "colonist", "entity": ren, "tile": Vector2i(11, 10)}, "Ren Okafor"],
		[{"kind": "colonist", "entity": int(w.player), "tile": Vector2i(10, 10)}, "you"],
		[{"kind": "container", "entity": crate, "tile": Vector2i(12, 10)}, "the crate"],
		[{"kind": "item", "entity": item, "tile": Vector2i(11, 11)}, "the " + item_name],
		[{"kind": "door", "entity": -1, "tile": Vector2i(14, 10)}, "the door"],
		[{"kind": "zombie", "entity": zed, "tile": Vector2i(13, 10)}, "a zombie"],
		[{"kind": "ground", "entity": -1, "tile": Vector2i(15, 15)}, ""],
	]
	for c in cases:
		var got: String = SimContext.target_label(w, c[0] as Dictionary)
		if got != String(c[1]):
			push_error("HEADER: %s is labelled '%s', not '%s'" % [str(c[0]), got, String(c[1])])
			ok = false
		if _has_digit(got):
			push_error("HEADER: a label carries a digit: '%s'" % got)
			ok = false
	if SimContext.target_label(w, {}) != "" or SimContext.target_label(null, cases[0][0] as Dictionary) != "":
		push_error("HEADER: an empty hit or a null world was given a label")
		ok = false
	# The header is drawn above the rows and is not one: the rows start below it, and a menu with
	# no header keeps its old shape -- the loot sheet's menu passes none.
	var texts: Array = ["attack", "walk here"]
	var with_head: Array[Dictionary] = ItemMenu.verb_rects(Vector2.ZERO, texts, "a zombie")
	var bare: Array[Dictionary] = ItemMenu.verb_rects(Vector2.ZERO, texts)
	if (with_head[0]["rect"] as Rect2).position.y < ItemMenu.PAD_Y + ItemMenu.HEADER_H:
		push_error("HEADER: the first row starts inside the header line")
		ok = false
	if (bare[0]["rect"] as Rect2).position.y != ItemMenu.PAD_Y:
		push_error("HEADER: a menu without a header moved its rows")
		ok = false
	if ItemMenu.size_of(texts, "a zombie").y != ItemMenu.size_of(texts).y + ItemMenu.HEADER_H:
		push_error("HEADER: the header does not add exactly its own line to the menu")
		ok = false
	# The street menu's ink follows its ring: the ringed row alone is amber, so an old lead word
	# ("walk here") cannot outshine the row Enter takes. The loot sheet's menu (no ring) keeps its
	# lead verbs lit -- the negative that shows `lit` is what moved the colour.
	if ItemMenu.row_colour("open the crate", 0, 0) != Locker.ACCENT or ItemMenu.row_colour("walk here", 1, 0) != Locker.TEXT:
		push_error("HEADER: the ringed row is not the one amber row on the street menu")
		ok = false
	if ItemMenu.row_colour("walk here", 1, -1) != Locker.ACCENT or ItemMenu.row_colour("open the crate", 0, -1) != Locker.TEXT:
		push_error("HEADER: the loot menu's lead verbs lost their accent")
		ok = false
	var menu_src: String = FileAccess.get_file_as_string("res://ui/context_menu.gd")
	if menu_src.find("ItemMenu.draw_menu(self, Vector2.ZERO, _texts(), 1.0, _header, _focus)") < 0:
		push_error("HEADER: the street menu does not hand its ring to the draw, so the ink cannot follow it")
		ok = false
	if ok:
		print("HEADER OK a colonist by name, you, the crate, the tin's name, the door and 'a zombie' for a runner; nothing for the ground; the rows sit under it and a menu without one keeps its shape")
	return ok


# The action bar's E clause is the menu's first in-reach row for the same thing, word for word:
# `ui/hud.gd`'s `_reach_clause` asks `SimContext.reach_words`, the menu writes `verbs_at`'s rows,
# and this holds them equal at a window, a door (shut, then open), a loose item and a crate. The true
# negative is the source the bar used to read: a boarded window's look-at state ("intact") is not
# the menu's row, so a bar that went back to it would fail here, as it failed before this slice.
func _bar() -> bool:
	var ok: bool = true
	var cases: Array = []
	# A window, facing east from (10.5, 10.5), with a board on it.
	var ww: Variant = _world(10.5, 10.5, 0.0)
	_set_tile(ww, 11, 10, SimTileMap.Tile.Window)
	SimFortify._board_window(ww, 11, 10)
	cases.append(["window", ww, {"kind": "ground", "entity": -1, "tile": Vector2i(11, 10)}])
	# A door, the same way, shut and then open.
	var wd: Variant = _world(10.5, 10.5, 0.0)
	_set_tile(wd, 11, 10, SimTileMap.Tile.Door)
	SimFortify.spawn_doors(wd, wd.tilemap)
	cases.append(["shut door", wd, {"kind": "door", "entity": -1, "tile": Vector2i(11, 10)}])
	# A loose tin in reach.
	var wi: Variant = _world()
	var item: int = _spawn_test_item(wi)
	wi.components.set_component(item, "position", {"x": 11.0, "y": 10.5})
	cases.append(["loose item", wi, {"kind": "item", "entity": item, "tile": Vector2i(11, 10)}])
	# An unsearched crate in reach.
	var wc: Variant = _world()
	var crate: int = int(wc.entities.spawn())
	wc.components.set_component(crate, "position", {"x": 11.0, "y": 10.5})
	wc.components.set_component(crate, "searchable", {"kind": "crate", "searched": false})
	cases.append(["crate", wc, {"kind": "container", "entity": crate, "tile": Vector2i(11, 10)}])
	# A loose tin in reach on a stockpile the player stands in (slice S4): E opens the stockpile, and
	# that is the menu's first row too. The same tin off the pile stays "pick up" -- the loose-item
	# case above is that negative.
	var wsp: Variant = _world()
	SimStockpile.register_module(wsp)
	var bits: PackedByteArray = PackedByteArray()
	bits.resize(int((MAP_TILES * MAP_TILES + 7) / 8))
	bits.fill(255)
	wsp.components.set_component(wsp.player, "explored", {"w": MAP_TILES, "h": MAP_TILES, "bits": Marshalls.raw_to_base64(bits)})
	SimStockpile.mark(wsp, {"x0": 9, "y0": 9, "x1": 11, "y1": 11, "on": true})
	var tin: int = _spawn_test_item(wsp)
	wsp.components.set_component(tin, "position", {"x": 11.0, "y": 10.5})
	if SimContext.reach_words(wsp, wsp.player) != SimStockpile.OPEN_WORDS:
		push_error("BAR: on the stockpile with a tin of it in reach, E's words are '%s'" % SimContext.reach_words(wsp, wsp.player))
		ok = false
	cases.append(["tin on the stockpile", wsp, {"kind": "item", "entity": tin, "tile": Vector2i(11, 10)}])
	# The same tin with a crate in reach too: E keeps its ladder (the pick-up), the bar says so, and
	# the stockpile row follows rather than leads (the review's finding 6).
	var wsc: Variant = _world()
	SimStockpile.register_module(wsc)
	wsc.components.set_component(wsc.player, "explored", {"w": MAP_TILES, "h": MAP_TILES, "bits": Marshalls.raw_to_base64(bits)})
	SimStockpile.mark(wsc, {"x0": 9, "y0": 9, "x1": 11, "y1": 11, "on": true})
	var tin2: int = _spawn_test_item(wsc)
	wsc.components.set_component(tin2, "position", {"x": 11.0, "y": 10.5})
	var crate2: int = int(wsc.entities.spawn())
	wsc.components.set_component(crate2, "position", {"x": 10.5, "y": 11.5})
	wsc.components.set_component(crate2, "searchable", {"kind": "crate", "searched": false})
	if SimContext.reach_words(wsc, wsc.player).find("pick up") != 0:
		push_error("BAR: on the stockpile beside a crate, E's words are '%s'" % SimContext.reach_words(wsc, wsc.player))
		ok = false
	var rows_c: Array[Dictionary] = SimContext.verbs_at(wsc, wsc.player, {"kind": "item", "entity": tin2, "tile": Vector2i(11, 10)})
	var has_stores_row: bool = false
	for r in rows_c:
		if String(r.get("text", "")) == SimStockpile.OPEN_WORDS:
			has_stores_row = true
	if not has_stores_row:
		push_error("BAR: on the stockpile beside a crate the menu lost the stockpile row")
		ok = false
	cases.append(["tin on the stockpile beside a crate", wsc, {"kind": "item", "entity": tin2, "tile": Vector2i(11, 10)}])
	for c in cases:
		ok = _bar_matches(String(c[0]), c[1], c[2] as Dictionary) and ok
	SimFortify.toggle_door(wd, 11, 10)
	ok = _bar_matches("open door", wd, {"kind": "door", "entity": -1, "tile": Vector2i(11, 10)}) and ok
	# The negative: the look-at state the bar used to put under E is not the menu's row.
	var state: String = String(SimFortify.look_at(ww, ww.player).get("window", ""))
	var first: Array[Dictionary] = SimContext.verbs_at(ww, ww.player, {"kind": "ground", "entity": -1, "tile": Vector2i(11, 10)})
	if state.is_empty() or first.is_empty() or state == String(first[0].get("text", "")):
		push_error("BAR: the boarded window's state '%s' cannot be told from the menu's row, so this lane cannot fail" % state)
		ok = false
	if ok:
		print("BAR OK the bar's E clause is the menu's first row at a boarded window, a shut and an open door, a loose tin, a crate, a tin on the stockpile and the same tin beside a crate, and the window's state is not that row")
	return ok


func _bar_matches(what: String, w: Variant, hit: Dictionary) -> bool:
	var rows: Array[Dictionary] = SimContext.verbs_at(w, w.player, hit)
	if rows.is_empty():
		push_error("BAR: the menu at the %s offers nothing, so there is no row to match" % what)
		return false
	var row: String = String(rows[0].get("text", ""))
	var line: String = Hud.action_line(w, w.player)
	var e: String = ""
	for clause in line.split(Hud.ACTION_SEP):
		if String(clause).begins_with("E — "):
			e = String(clause).substr(4)
	if e != row:
		push_error("BAR: at the %s the bar says E '%s' and the menu's first row says '%s'" % [what, e, row])
		return false
	return true


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

# A key press and release through the viewport, the way check_play.gd presses its keys.
func _tap(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	root.push_input(up)


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
				var rects: Array[Dictionary] = menu.call("row_rects") as Array[Dictionary]
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

		# Escape is spent on the open menu: it closes and the pause menu does not rise on the same
		# press. The negative is the same key with no menu open, which must still reach the peel
		# order and pause -- otherwise "Escape closed the menu" could be "Escape reaches nothing".
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, true))
		root.push_input(_mouse(screen_pos, MOUSE_BUTTON_RIGHT, false))
		if menu == null or not bool(menu.call("is_open")):
			push_error("RIGHT-CLICK: re-opening the menu for the Escape lane failed")
			ok = false
		else:
			_tap(KEY_ESCAPE)
			var shell: Variant = main.get("_shell")
			if bool(menu.call("is_open")):
				push_error("RIGHT-CLICK: Escape left the menu open")
				ok = false
			if shell != null and bool((shell as CanvasItem).visible):
				push_error("RIGHT-CLICK: the Escape that closed the menu also raised the pause menu -- one press, two meanings")
				ok = false
			_tap(KEY_ESCAPE)
			if shell == null or not bool((shell as CanvasItem).visible):
				push_error("RIGHT-CLICK: with no menu open, Escape no longer raises the pause menu -- the Escape lane cannot fail")
				ok = false
			# Back to the street for the lanes below.
			_tap(KEY_ESCAPE)

		ok = _menu_header_and_keys(main, world, screen_pos, px, py) and ok

	main.queue_free()
	await process_frame
	if ok:
		print("RIGHT-CLICK OK the scene opens the menu on a Focal shambler, dispatches its row, closes on anything else, and Escape is spent on it")
	return ok


# On the scene's own menu. HEADER: a right-click on the shambler heads the menu "a zombie" above
# its rows, a click on the header picks nothing, and a right-click on the bare ground opens a menu
# with no header line at all. KEYS: the ring opens on the first row; Down then Enter dispatches the
# second row's own command and closes the menu; Up from the first row wraps to the last; an arrow
# under the menu walks nobody; Escape closes it with nothing dispatched.
func _menu_header_and_keys(main: Node, world: Variant, zombie_at: Vector2, px: float, py: float) -> bool:
	var ok: bool = true
	var menu: Variant = main.get("_context_menu")
	if menu == null:
		push_error("HEADER: the scene has no context menu")
		return false
	var shell: Variant = main.get("_shell")
	if shell != null and bool((shell as CanvasItem).visible):
		push_error("HEADER: the pause menu is still up, so the street lanes cannot run")
		return false
	root.push_input(_mouse(zombie_at, MOUSE_BUTTON_RIGHT, true))
	root.push_input(_mouse(zombie_at, MOUSE_BUTTON_RIGHT, false))
	if not bool(menu.call("is_open")):
		push_error("HEADER: the menu did not open on the shambler")
		return false
	if String(menu.call("header")) != "a zombie":
		push_error("HEADER: the menu over a shambler is headed '%s'" % String(menu.call("header")))
		ok = false
	# A click on the header line is no row: it closes the menu and dispatches nothing.
	var origin: Vector2 = menu.get("position") as Vector2
	(world.commands as Variant)._pending.clear()
	var on_head: Vector2 = origin + Vector2(ItemMenu.PAD_X + 4.0, ItemMenu.PAD_Y + ItemMenu.HEADER_H / 2.0)
	root.push_input(_mouse(on_head, MOUSE_BUTTON_LEFT, true))
	root.push_input(_mouse(on_head, MOUSE_BUTTON_LEFT, false))
	if not ((world.commands as Variant)._pending as Array).is_empty():
		push_error("HEADER: a click on the header dispatched %s" % str((world.commands as Variant)._pending))
		ok = false

	# KEYS, on the shambler's menu again.
	root.push_input(_mouse(zombie_at, MOUSE_BUTTON_RIGHT, true))
	root.push_input(_mouse(zombie_at, MOUSE_BUTTON_RIGHT, false))
	var rows: Array = menu.call("rows") as Array
	if rows.size() < 2:
		push_error("KEYS: the shambler's menu has %d rows, so Down has nowhere to go" % rows.size())
		return false
	if int(menu.call("focused")) != 0:
		push_error("KEYS: the ring did not open on the first row")
		ok = false
	(world.commands as Variant)._pending.clear()
	_tap(KEY_DOWN)
	if int(menu.call("focused")) != 1 or not bool(menu.call("is_open")):
		push_error("KEYS: Down did not move the ring to the second row (ring %d)" % int(menu.call("focused")))
		ok = false
	_tap(KEY_UP)
	if int(menu.call("focused")) != 0:
		push_error("KEYS: Up did not bring the ring back to the first row (ring %d)" % int(menu.call("focused")))
		ok = false
	_tap(KEY_UP)
	if int(menu.call("focused")) != rows.size() - 1:
		push_error("KEYS: Up from the first row did not wrap to the last (ring %d)" % int(menu.call("focused")))
		ok = false
	# Down from the last wraps to the first, and once more is the second row again.
	_tap(KEY_DOWN)
	_tap(KEY_DOWN)
	if int(menu.call("focused")) != 1:
		push_error("KEYS: Down from the last row did not wrap round to the second (ring %d)" % int(menu.call("focused")))
		ok = false
	for c in (world.commands as Variant)._pending as Array:
		if String((c as Dictionary).get("type", "")) == "move" and (absf(float((c as Dictionary).get("dx", 0.0))) > 0.0 or absf(float((c as Dictionary).get("dy", 0.0))) > 0.0):
			push_error("KEYS: an arrow under the menu walked the body (%s)" % str(c))
			ok = false
	var want: Dictionary = (rows[1] as Dictionary).get("command", {}) as Dictionary
	(world.commands as Variant)._pending.clear()
	_tap(KEY_ENTER)
	var pushed: Array = (world.commands as Variant)._pending as Array
	if want.is_empty() or String(want.get("type", "")) == "attack.context":
		push_error("KEYS: the second row (%s) carries no plain command to compare" % str(rows[1]))
		ok = false
	elif not pushed.has(want):
		push_error("KEYS: Enter on the second row pushed %s, not its command %s" % [str(pushed), str(want)])
		ok = false
	if bool(menu.call("is_open")):
		push_error("KEYS: the menu stayed open after Enter dispatched a row")
		ok = false
	# Escape: closed, nothing dispatched.
	root.push_input(_mouse(zombie_at, MOUSE_BUTTON_RIGHT, true))
	root.push_input(_mouse(zombie_at, MOUSE_BUTTON_RIGHT, false))
	(world.commands as Variant)._pending.clear()
	_tap(KEY_ESCAPE)
	if bool(menu.call("is_open")) or not ((world.commands as Variant)._pending as Array).is_empty():
		push_error("KEYS: Escape left the menu open or dispatched %s" % str((world.commands as Variant)._pending))
		ok = false

	# The bare ground: a menu with rows and no header line. Found by asking the pick, since the
	# district is procedural.
	var camera: Dictionary = main.get("camera")
	# Input reaches the viewport at any point, on the screen or off it (the headless window is
	# tiny), so the search walks tiles round the player rather than the window's pixels.
	var ground_at: Vector2 = Vector2.ZERO
	var found: bool = false
	for off in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3), Vector2(-4, -2), Vector2(4, 2), Vector2(-2, 4), Vector2(2, -4)]:
		var sc: Dictionary = TopDownProjection.world_to_screen(camera, px + (off as Vector2).x, py + (off as Vector2).y)
		var at := Vector2(float(sc["sx"]), float(sc["sy"]))
		var hit: Dictionary = Pick.pick_at(world, camera, at)
		if String(hit.get("kind", "")) == "ground" and not SimContext.verbs_at(world, int(world.player), hit).is_empty():
			ground_at = at
			found = true
			break
	if not found:
		print("HEADER: the bare-ground negative skipped, no open ground with a row near spawn")
	else:
		root.push_input(_mouse(ground_at, MOUSE_BUTTON_RIGHT, true))
		root.push_input(_mouse(ground_at, MOUSE_BUTTON_RIGHT, false))
		if not bool(menu.call("is_open")):
			push_error("HEADER: a right-click on open ground opened no menu")
			ok = false
		elif not String(menu.call("header")).is_empty():
			push_error("HEADER: the bare ground's menu is headed '%s'" % String(menu.call("header")))
			ok = false
		elif ((menu.call("row_rects") as Array)[0]["rect"] as Rect2).position.y != ItemMenu.PAD_Y:
			push_error("HEADER: the bare ground's menu left room for a header it does not have")
			ok = false
		_tap(KEY_ESCAPE)
	if ok:
		print("KEYS OK the ring opens on the first row and wraps, Down then Enter dispatches the second row and closes, an arrow walks nobody, Escape closes with nothing sent; the header names the shambler, is not a row%s" % (", and the ground has none" if found else " (the ground's negative skipped)"))
	return ok
