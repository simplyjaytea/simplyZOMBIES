extends RefCounted
# The fixed scenes the screenshot review captures, and the one boot every scene starts from.
#
# `review/shots.gd` photographs these and `check_shots.gd` judges them, and both call the same
# functions here: the gate checks the setups the driver really makes, not a copy of them. Every
# scene boots a fresh `main.tscn` through real key presses (the title, the legend), then sets the
# world up through the sim's own commands and clock, and `verify` asks the world whether the
# setup is what the scene's name says. A scene the world does not match is refused rather than
# photographed, so a before/after pair cannot silently compare two different states.
#
# The capture itself is the one `check_shots.gd` skips without a display: `root.get_texture()`
# is empty under `--headless`, so the pixels need `DISPLAY` (docs/34, "Screenshots").

const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSurface = preload("res://sim/map/surface.gd")
const Dressing = preload("res://presentation/dressing.gd")
const SimBootRes = preload("res://sim/boot.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimHealthModule = preload("res://sim/modules/health.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")

const SCENE_PATH: String = "res://presentation/main.tscn"
# The two windows the game supports: check_play's WORK-LAYOUT lane lays out at both.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const NAMES: Array[String] = [
	"day_street", "interior", "night_lights", "combat", "inventory", "care", "skills", "colony", "viewing",
	"colony_picked", "colony_crowd", "colony_scrolled", "bench_drop",
	"bench", "bench_field",
	"context_menu",
]
# The Colony screen's two fuller shots (art QA, slice 2): Mara picked by a click on her name, her
# row made manual by one changed number, the pointer resting on the medic chip; and a roster of
# CROWD colonists with a generated one picked, so a backstory not authored by hand is shown whole;
# and the same roster with its last colonist picked in the game, as a click on their body in the
# street would, so the screen opens scrolled to a row past the fold.
const HOVER_FOCUS: String = "Medic"
const CROWD: int = 7
# The scrolled shot's roster: more than the 1920x1080 window draws, so both windows scroll.
const SCROLL_CROWD: int = 12
# The weapon the drop scene holds a spare over: a rifle carried in a pack, its magazine taken off by
# hand, so the spare held over it is a fit and the rifle wears the fit wash.
const RIFLE: String = "item.rifle.hunting"
const PACK: String = "item.pack.frame"
# The part the care scene cuts and then picks on the figure: an arm, so the pane has a bleeding
# wound to offer pressure for and a dressing it can say is missing.
const CARE_PART: String = "arm_left"
# The assembly scene (UI overhaul, slice 3): a hunting rifle on the bench, with parts in the pack
# that fit three of its slots, and the sight picked so the candidates column has something to list.
const BENCH_WEAPON: String = "item.rifle.hunting"
const BENCH_PARTS: Array[String] = ["item.attach.optic.red_dot", "item.attach.optic.scope", "item.attach.suppressor", "item.attach.magazine.extended", "item.attach.barrel.long"]
const BENCH_SLOT: String = "optic"
const BENCH_PACK: String = "item.pack.hiking"
# The same rifle and parts by hand (C1's field work), out on the street with no bench in reach, and
# the magazine picked: a slot hands can change, so the screen says "by hand" over a real job.
const BENCH_FIELD_SLOT: String = "magazine"

const TICK_SECONDS: float = 1.0 / 20.0
const DAY: int = 1
const NOON: float = 0.5
const NIGHT: float = 0.9
# A zombie is placed this many metres east of the body, close enough to read as a fight in frame.
const ZOMBIE_METRES: float = 3.0
const ZOMBIE_ID: String = "zombie.base"
# How far from the body the verifier looks for the zombie it asked for.
const ZOMBIE_NEAR: float = 4.5
# How far the street search walks from the body, in tiles.
const SEARCH_TILES: int = 80
# How far the interior search walks, in tiles: the whole district if it has to, because a room with a
# clear seven-tile square round the survivor is not on every block.
const INTERIOR_SEARCH_TILES: int = 256
# How far, in tiles (Chebyshev), a shot's survivor stands from any dressing picture. A room shot
# takes the clearest spot its rooms offer, down to one tile, so that it can show a counter
# (`_interior_spot`).
const SPOT_CLEAR: int = 3
# The share of a room shot's window, in percent, that has to be indoor floor to count as a room: a
# sixth or so, since the district's houses are small and the rooms that keep a counter (a table
# against a plain north wall) are their kitchens, which fill about that much of the window.
const ROOM_SHARE: int = 15
# A room shot's score for showing a table against a north wall, the counter the pack has none of.
const INTERIOR_COUNTER_BONUS: int = 6
const COUNTER_KEY: String = "prop_table"
# How far from the survivor a counter earns its bonus: the middle of the smaller window, clear of the
# HUD's corner panels, so the counter the score chose is one the 1280 shot shows.
const COUNTER_HALF: Vector2i = Vector2i(7, 3)

# The street a day shot wants: a window the size of the 1280x720 view (20 x 11 tiles at 64 px a
# tile, centred on the body), and the share of it that has to be paved outdoor street for the spot
# to count as mostly street. The shots were 50 percent building at 1280 before this.
const STREET_WINDOW_HALF: Vector2i = Vector2i(10, 5)
const STREET_WINDOW_AREA: int = 21 * 11
const STREET_SHARE: int = 75


## Boot a fresh main scene the way a player reaches the street: the title takes Enter, the
## legend takes Escape. Returns null when the scene does not come up with a world.
static func boot(tree: SceneTree) -> Node:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return null
	var main: Node = packed.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	if main.get("world") == null:
		main.queue_free()
		return null
	main.set_process(false)
	main.set("accumulator", 0.0)
	var shell: Variant = main.get("_shell")
	if shell != null and bool((shell as CanvasItem).visible):
		press(tree, KEY_ENTER)
		await tree.process_frame
	var legend: Variant = main.get("_legend")
	if legend != null and bool((legend as CanvasItem).visible):
		press(tree, KEY_ESCAPE)
		await tree.process_frame
	# The first-day hints are a player's, not a picture's: a hint card over the middle of a shot hides
	# what the review came to judge. Every hint is marked told, so none comes due.
	var session: Variant = main.get("session")
	if session != null and session.get("onboarding") != null:
		var hints: Variant = session.get("onboarding")
		for id in hints.ORDER:
			hints.seen[id] = true
		hints.dismiss()
	main.set("accumulator", 0.0)
	return main


## One real key press, down and up, through the viewport's own dispatch.
static func press(tree: SceneTree, code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	tree.root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	tree.root.push_input(up)


## One real left click at `at` (window coordinates), down and up, through the viewport's dispatch.
static func click(tree: SceneTree, at: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = at
		mb.global_position = at
		tree.root.push_input(mb)


# The street menu's shot (C4): a crate in reach on the street, right-clicked, so the menu's header
# ("the crate"), its first row and the action bar's E clause are in one picture and can be read
# against each other.
const HudRes = preload("res://ui/hud.gd")
const PickRes = preload("res://presentation/pick.gd")
const ProjectionRes = preload("res://presentation/projection.gd")
const MENU_CRATE: String = "crate"


## Set up the named scene on a booted `main`. Returns "" on success, or the reason it could not.
static func setup(tree: SceneTree, main: Node, scene: String) -> String:
	var world: Variant = main.get("world")
	if world == null:
		return "no world"
	match scene:
		"day_street":
			# The body starts indoors, so a day shot taken where it stands is a room, not a street.
			# Move it to the nearest open paved street tile first.
			world.tick = Clock.tick_on_day(DAY, NOON)
			var street: Vector2 = _street_spot(world)
			if street.x < 0.0:
				return "no open paved street within %d tiles" % SEARCH_TILES
			world.components.set_component(world.player, "position", {"x": street.x, "y": street.y})
		"night_lights":
			# A lit campfire near the body, so the night shot has its warm pool on screen (the boot
			# campfire starts unlit, and an unlit fire lights nothing).
			world.tick = Clock.tick_on_day(DAY, NIGHT)
			var body: Dictionary = world.components.get_component(world.player, "position") as Dictionary
			var fire: int = SimNeeds.nearest_campfire(world, float(body["x"]), float(body["y"]))
			if fire < 0:
				return "no campfire in the world"
			SimNeeds.set_lit(world, fire, true)
		"interior":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var spot: Vector2 = _interior_spot(world)
			if spot.x < 0.0:
				return "no indoor floor within %d tiles" % INTERIOR_SEARCH_TILES
			world.components.set_component(world.player, "position", {"x": spot.x, "y": spot.y})
		"combat":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var at: Dictionary = world.components.get_component(world.player, "position") as Dictionary
			world.commands.push({
				"type": "debug.spawn", "kind": "zombie", "id": ZOMBIE_ID,
				"x": float(at["x"]) + ZOMBIE_METRES, "y": float(at["y"]),
			})
		"inventory":
			world.tick = Clock.tick_on_day(DAY, NOON)
			press(tree, KEY_TAB)
		"care":
			# The first playable journey's middle (docs/32, "Acceptance"): the sheet open on a body
			# with a bleeding cut, and the cut arm picked on the figure with a real click.
			world.tick = Clock.tick_on_day(DAY, NOON)
			# The cut takes the arm down the way a blade would, so the pane reads a hurt arm that
			# bleeds rather than an unhurt one that somehow does.
			var body: Variant = world.components.get_component(int(world.player), "body")
			if body is Dictionary and SimHealthModule.max_of(body as Dictionary, CARE_PART) != null:
				(body as Dictionary)[CARE_PART] = float(SimHealthModule.max_of(body as Dictionary, CARE_PART)) * 0.55
			SimWounds.append_wound(world, int(world.player), "cut", CARE_PART, -1, 0.0, "", SimWounds.Severity.Laceration)
			press(tree, KEY_TAB)
			for i in 2:
				main.call("_process", TICK_SECONDS)
			await tree.process_frame
			var panel: Variant = main.get("_inventory_panel")
			var doll: Variant = panel.get("_paperdoll") if panel != null else null
			if doll == null:
				return "the sheet has no figure to click"
			var at: Vector2 = (doll as Control).global_position + Vector2(doll.call("point_of", CARE_PART))
			click(tree, at)
		"skills":
			world.tick = Clock.tick_on_day(DAY, NOON)
			press(tree, KEY_K)
		"colony":
			world.tick = Clock.tick_on_day(DAY, NOON)
			press(tree, KEY_J)
		"colony_picked":
			world.tick = Clock.tick_on_day(DAY, NOON)
			press(tree, KEY_J)
			await _settle(tree, main)
			var mara: int = _row_named(world, "Mara")
			if mara < 0:
				return "the colony has no Mara"
			if not await _click_row(tree, main, mara):
				return "Mara's name is not on the screen to click"
			# One changed number: a priority edit makes the row manual, as the legend says.
			var cook: int = int(((_row_of(world, mara)).get("cols", {}) as Dictionary).get("Cook", 0))
			world.commands.push({"type": "job.priority", "entity": mara, "column": "Cook", "value": 1 if cook != 1 else 2})
			await _settle(tree, main)
			if not _hover_chip(tree, main, HOVER_FOCUS):
				return "the %s chip is not on the screen to point at" % HOVER_FOCUS
		"colony_crowd", "colony_scrolled":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var born: Array[int] = _crowd(world, SCROLL_CROWD if scene == "colony_scrolled" else CROWD)
			if born.is_empty():
				return "the generated colonists did not spawn"
			if scene == "colony_scrolled":
				var rows: Array[Dictionary] = SimJobs.work_view(world)
				main.set("_selected", int(rows[rows.size() - 1]["entity"]))
				press(tree, KEY_J)
			else:
				press(tree, KEY_J)
				await _settle(tree, main)
				if not await _click_row(tree, main, born[0]):
					return "no generated colonist's name is on the screen to click"
		"bench_drop":
			# C3 of the three-features plan: a magazine held over a rifle whose magazine slot is empty.
			# The rifle sits in a pack on the back; its magazine comes off by hand, which is the fit.
			world.tick = Clock.tick_on_day(DAY, NOON)
			var pack: int = SimItems.spawn_item(world, PACK, {"tier": "scavenged"})
			if not SimInventory.equip(world, world.player, pack, "back"):
				return "no pack would go on the back"
			var rifle: int = SimItems.spawn_item(world, RIFLE, {"tier": "scavenged"})
			if not SimInventory.stow(world, world.player, rifle):
				return "the rifle would not go in the pack"
			var mag: int = SimAttachments.in_slot(world, rifle, "magazine")
			if mag < 0:
				return "the rifle has no magazine to take off"
			world.commands.push({"type": "item.detach", "item": mag})
			await _settle(tree, main)
			await _settle(tree, main)
			press(tree, KEY_TAB)
			await _settle(tree, main)
			var sheet: Variant = main.get("_inventory_panel")
			if sheet == null:
				return "the sheet is not on the screen"
			var plate: Variant = _plate_rect(sheet as Control, rifle)
			if plate == null:
				return "the rifle has no plate on the sheet to point at"
			# The top third of the plate, not its centre: the held magazine is drawn on the pointer,
			# and the rifle has to show around it.
			var over: Vector2 = (plate as Rect2).position + Vector2((plate as Rect2).size.x * 0.5, (plate as Rect2).size.y / 3.0)
			sheet.set("_drag_item", mag)
			sheet.set("_placed", sheet.call("_column_places"))
			var window_at: Vector2 = (sheet as Control).get_global_transform_with_canvas() * over
			Input.warp_mouse(window_at)
			main.set_meta("bench_drop_rifle", rifle)
			await _settle(tree, main)
		"viewing":
			# Skills on somebody else: a colonist picked on the street, then K -- the bar names them
			# and stamps the page "viewing".
			world.tick = Clock.tick_on_day(DAY, NOON)
			var other: int = _a_colonist(world)
			if other < 0:
				return "the colony has nobody but you to view"
			main.set("_selected", other)
			press(tree, KEY_K)
		"bench":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var why: String = _bench_setup(world)
			if not why.is_empty():
				return why
			main.call("_process", TICK_SECONDS)
			await tree.process_frame
			var bench_panel: Variant = main.get("_bench_panel")
			if bench_panel != null and bench_panel.has_method("pick_slot"):
				bench_panel.call("pick_slot", BENCH_SLOT)
				# Enter on an empty slot crosses to what fits it, through the router as a key would,
				# so the shot shows a candidate focused and the footer's lit button.
				press(tree, KEY_ENTER)
		"bench_field":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var street_b: Vector2 = _street_spot(world)
			if street_b.x < 0.0:
				return "no open paved street within %d tiles" % SEARCH_TILES
			world.components.set_component(world.player, "position", {"x": street_b.x, "y": street_b.y})
			var why_f: String = _bench_setup(world, false)
			if not why_f.is_empty():
				return why_f
			main.call("_process", TICK_SECONDS)
			await tree.process_frame
			var field_panel: Variant = main.get("_bench_panel")
			if field_panel != null and field_panel.has_method("pick_slot"):
				# The plate keeps the keys: the column beside it already lists what fits, and the footer
				# shows "take off" lit, the hands' own job on a fitted magazine.
				field_panel.call("pick_slot", BENCH_FIELD_SLOT)
		"context_menu":
			world.tick = Clock.tick_on_day(DAY, NOON)
			var street_m: Vector2 = _street_spot(world)
			if street_m.x < 0.0:
				return "no open paved street within %d tiles" % SEARCH_TILES
			world.components.set_component(world.player, "position", {"x": street_m.x, "y": street_m.y})
			world.components.set_component(world.player, "facing", {"radians": 0.0})
			var crate: int = int(world.entities.spawn())
			world.components.set_component(crate, "position", {"x": street_m.x + 1.0, "y": street_m.y})
			world.components.set_component(crate, "searchable", {"kind": MENU_CRATE, "searched": false})
			main.call("_snap_camera")
			await _settle(tree, main)
			main.call("_snap_camera")
			var camera: Dictionary = main.get("camera")
			var cp: Dictionary = world.components.get_component(crate, "position") as Dictionary
			var sc: Dictionary = ProjectionRes.world_to_screen(camera, float(cp["x"]), float(cp["y"]))
			var at := Vector2(float(sc["sx"]), float(sc["sy"]))
			if String(PickRes.pick_at(world, camera, at).get("kind", "")) != "container":
				return "the crate beside the body does not pick as a container"
			for pressed in [true, false]:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_RIGHT
				mb.pressed = pressed
				mb.position = at
				mb.global_position = at
				tree.root.push_input(mb)
		_:
			return "unknown scene %s" % scene
	# The camera jumps to where the body now stands. Without this the follow lerp was still walking
	# from the body's old tile when the shot was taken, so the body sat off centre (or at the top
	# edge) and a shot of the old spot's neighbourhood was the one photographed.
	main.call("_snap_camera")
	# Two ticks: the first runs the spawn intake and the second lets its components settle. The
	# frame after draws the result.
	for i in 2:
		main.call("_process", TICK_SECONDS)
	await tree.process_frame
	return ""


## Ask the world whether it is the scene `scene` names. "" when it is, else the reason it is not.
static func verify(main: Node, scene: String) -> String:
	var world: Variant = main.get("world")
	if world == null:
		return "no world"
	match scene:
		"bench_drop":
			var rifle: int = int(main.get_meta("bench_drop_rifle", -1))
			var sheet: Variant = main.get("_inventory_panel")
			if rifle < 0 or sheet == null:
				return "the rifle or the sheet is not there"
			var held: int = int(sheet.get("_drag_item"))
			if held < 0:
				return "nothing is held over the sheet"
			if SimAttachments.in_slot(world, rifle, "magazine") >= 0:
				return "the rifle's magazine slot is not empty"
			return "" if SimGunsmith.drop_slot(world, int(world.player), held, rifle) != "" else "the held part does not fit the rifle"
		"day_street":
			if Clock.phase_of(int(world.tick)) != Clock.Phase.Day:
				return "it is not day"
			return "" if _outdoor_paved(world.tilemap, _tile_under_player(world)) else "the body is not on an open paved street tile"
		"night_lights":
			if Clock.phase_of(int(world.tick)) != Clock.Phase.Night:
				return "it is not night"
			for e in world.components.query(["campfire"]):
				if bool((world.components.get_component(int(e), "campfire") as Dictionary).get("lit", false)):
					return ""
			return "no campfire is lit"
		"interior":
			var at: Vector2i = _tile_under_player(world)
			if SimTileMap.tile_at(world.tilemap, at.x, at.y) != SimTileMap.Tile.Floor:
				return "the body is not on a floor tile"
			return "" if SimTileMap.is_indoors(world.tilemap, at.x, at.y) else "the body is not indoors"
		"combat":
			var at_pos: Dictionary = world.components.get_component(world.player, "position") as Dictionary
			for e in world.components.query(["zombieType", "position"]):
				if int(e) == int(world.player):
					continue
				var p: Dictionary = world.components.get_component(int(e), "position") as Dictionary
				var dx: float = float(p["x"]) - float(at_pos["x"])
				var dy: float = float(p["y"]) - float(at_pos["y"])
				if dx * dx + dy * dy <= ZOMBIE_NEAR * ZOMBIE_NEAR:
					return ""
			return "no zombie stands within %.1f m of the body" % ZOMBIE_NEAR
		"inventory":
			return "" if bool(main.get("inventory_open")) else "the inventory sheet is not open"
		"care":
			if not bool(main.get("inventory_open")):
				return "the inventory sheet is not open"
			var panel: Variant = main.get("_inventory_panel")
			if panel == null or String(panel.get("_part")) != CARE_PART:
				return "the %s is not picked on the figure" % CARE_PART
			return ""
		"skills":
			if not bool(main.get("web_open")):
				return "the skills screen is not open"
			var nav: Variant = main.get("_nav_bar")
			return "" if nav != null and bool((nav as CanvasItem).visible) else "the navigation bar is not over the skills screen"
		"colony":
			if not bool(main.get("work_open")):
				return "the colony screen is not open"
			var nav_c: Variant = main.get("_nav_bar")
			return "" if nav_c != null and bool((nav_c as CanvasItem).visible) and String(nav_c.get("screen")) == "colony" else "the navigation bar is not over the colony screen"
		"colony_picked":
			if not bool(main.get("work_open")):
				return "the colony screen is not open"
			var mara_v: int = _row_named(world, "Mara")
			var panel_p: Variant = main.get("_work_panel")
			if mara_v < 0 or int(main.get("_selected")) != mara_v or int(panel_p.call("selected")) != mara_v:
				return "Mara is not picked for the game"
			if String(_row_of(world, mara_v).get("focus", "")) != "Manual":
				return "Mara's row is not manual"
			return "" if String(panel_p.get("_hover_focus")) == HOVER_FOCUS else "the pointer is not on the %s chip" % HOVER_FOCUS
		"colony_scrolled":
			if not bool(main.get("work_open")):
				return "the colony screen is not open"
			var rows_s: Array[Dictionary] = SimJobs.work_view(world)
			var last: int = int(rows_s[rows_s.size() - 1]["entity"]) if rows_s.size() >= SCROLL_CROWD else -1
			var panel_s: Object = main.get("_work_panel") as Object
			var drawn_rows: Array = ((panel_s.call("_layout") as Dictionary)["rows"] as Array).map(func(r: Variant) -> int: return int((r as Dictionary)["entity"]))
			if last < 0 or int(panel_s.call("selected")) != last or not drawn_rows.has(last):
				return "the last of the roster is not picked and drawn"
			return "" if int(panel_s.get("_row_scroll")) > 0 else "the roster is not scrolled"
		"colony_crowd":
			if not bool(main.get("work_open")):
				return "the colony screen is not open"
			if SimJobs.work_view(world).size() < CROWD:
				return "the roster is %d, not %d" % [SimJobs.work_view(world).size(), CROWD]
			var picked: int = int((main.get("_work_panel") as Object).call("selected"))
			var ident: Variant = world.components.get_component(picked, "identity") if picked >= 0 else null
			return "" if ident is Dictionary and String((ident as Dictionary).get("backstoryId", "")) != "" else "no generated colonist is picked"
		"context_menu":
			var menu: Variant = main.get("_context_menu")
			if menu == null or not bool(menu.call("is_open")):
				return "the street menu is not open"
			if String(menu.call("header")) != "the " + MENU_CRATE:
				return "the menu is headed '%s', not the crate" % String(menu.call("header"))
			var rows: Array = menu.call("rows") as Array
			var first: String = String((rows[0] as Dictionary).get("text", "")) if not rows.is_empty() else ""
			if first != "open the " + MENU_CRATE:
				return "the menu's first row is '%s', not opening the crate" % first
			var line: String = HudRes.action_line(world, int(world.player))
			if line.find("E — " + first) < 0:
				return "the action bar says '%s', not E for the menu's first row" % line
			return ""
		"viewing":
			if not bool(main.get("web_open")):
				return "the skills screen is not open"
			var nav_v: Variant = main.get("_nav_bar")
			if nav_v == null or bool(nav_v.get("subject_is_you")) or String(nav_v.get("subject_name")).is_empty():
				return "the bar is not viewing a colonist"
			return ""
		"bench":
			var rifle: int = SimGunsmith.focus_of(world, int(world.player))
			var base: Variant = world.components.get_component(rifle, "itemBase") if rifle >= 0 else null
			if not base is Dictionary or String((base as Dictionary).get("baseId", "")) != BENCH_WEAPON:
				return "the bench is not open on the %s" % BENCH_WEAPON
			var bench_panel_v: Variant = main.get("_bench_panel")
			if bench_panel_v == null or not bool((bench_panel_v as CanvasItem).visible):
				return "the assembly screen is not up"
			if bench_panel_v.has_method("picked_slot") and String(bench_panel_v.call("picked_slot")) != BENCH_SLOT:
				return "the %s is not picked" % BENCH_SLOT
			if bench_panel_v.has_method("side") and String(bench_panel_v.call("side")) != "offers":
				return "no candidate for the %s is focused" % BENCH_SLOT
			return ""
		"bench_field":
			var gun: int = SimGunsmith.focus_of(world, int(world.player))
			if gun < 0:
				return "no weapon is open by hand"
			if SimGunsmith.bench_in_reach(world, int(world.player)) >= 0:
				return "a bench is in reach, so this is not by hand"
			var field_v: Variant = main.get("_bench_panel")
			if field_v == null or not bool((field_v as CanvasItem).visible):
				return "the assembly screen is not up by hand"
			if String(field_v.call("picked_slot")) != BENCH_FIELD_SLOT:
				return "the %s is not picked" % BENCH_FIELD_SLOT
			if String(field_v.call("side")) != "slots":
				return "the keys are not on the %s plate" % BENCH_FIELD_SLOT
			return ""
		_:
			return "unknown scene %s" % scene


## A hunting rifle in the survivor's hands and the parts that fit it in the pack, a bench where they
## stand unless `at_bench` is false, and the screen opened on the rifle through the sim's own command.
static func _bench_setup(world: Variant, at_bench: bool = true) -> String:
	var me: int = int(world.player)
	var at: Dictionary = world.components.get_component(me, "position") as Dictionary
	if at_bench:
		SimGunsmith.make_bench(world, float(at["x"]), float(at["y"]))
	var rifle: int = SimItems.spawn_item(world, BENCH_WEAPON, {"tier": "scavenged"})
	if not SimInventory.equip(world, me, rifle):
		return "the survivor could not take up the %s" % BENCH_WEAPON
	# A pack on the back, so the parts have somewhere to be carried whatever the boot kit holds.
	var pack: int = SimItems.spawn_item(world, BENCH_PACK, {"tier": "scavenged"})
	if not SimInventory.equip(world, me, pack):
		return "the survivor could not shoulder the %s" % BENCH_PACK
	for part_id in BENCH_PARTS:
		var part: int = SimItems.spawn_item(world, part_id, {"tier": "scavenged"})
		if not SimInventory.stow(world, me, part):
			return "the pack had no room for %s" % part_id
	world.commands.push({"type": "bench.open", "item": rifle})
	return ""


## Generated colonists by the player until the roster is `size`. Returns the ones made.
static func _crowd(world: Variant, size: int) -> Array[int]:
	var at: Dictionary = world.components.get_component(world.player, "position") as Dictionary
	var rng: Variant = world.rng.stream("recruit")
	var born: Array[int] = []
	while SimJobs.work_view(world).size() < size:
		var e: int = int(SimRecruits.spawn_generated(world, SimRecruits.roll(world, rng), float(at["x"]) + 2.0 + float(born.size()), float(at["y"]) + 1.0))
		if e < 0:
			break
		born.append(e)
	return born


## Two ticks and a frame, so the screen draws what the world now holds.
static func _settle(tree: SceneTree, main: Node) -> void:
	for i in 2:
		main.call("_process", TICK_SECONDS)
	await tree.process_frame


## An item's plate on the sheet, in the sheet's own coordinates, or null when it is not drawn there.
## The same arithmetic the drop path uses, so the pointer lands on the plate it names.
static func _plate_rect(sheet: Control, item: int) -> Variant:
	var bag: GDScript = load("res://ui/bag_grid.gd") as GDScript
	for placed in sheet.call("_column_places") as Array:
		var column: Dictionary = (placed as Dictionary)["column"] as Dictionary
		for entry in column.get("items", []) as Array:
			if int((entry as Dictionary).get("item", -1)) == item:
				var origin: Vector2 = bag.call("origin_of", (placed as Dictionary)["at"] as Vector2)
				return bag.call("plate_rect", origin, entry) as Rect2
	return null


## The colonist whose name begins with `first`, from the Colony screen's own view, or -1.
static func _row_named(world: Variant, first: String) -> int:
	for row in SimJobs.work_view(world):
		if String(row.get("name", "")).begins_with(first):
			return int(row["entity"])
	return -1


static func _row_of(world: Variant, ent: int) -> Dictionary:
	for row in SimJobs.work_view(world):
		if int(row["entity"]) == ent:
			return row
	return {}


## A real click on `ent`'s name on the Colony screen. False when the row is not drawn.
static func _click_row(tree: SceneTree, main: Node, ent: int) -> bool:
	var panel: Control = main.get("_work_panel") as Control
	for row in (panel.call("_layout") as Dictionary)["rows"] as Array:
		if int((row as Dictionary)["entity"]) == ent:
			click(tree, panel.global_position + ((row as Dictionary)["band"] as Rect2).position + Vector2(24.0, 12.0))
			await _settle(tree, main)
			return true
	return false


## The pointer moved onto a Focus chip in the drawer, through the viewport. False with no chip.
static func _hover_chip(tree: SceneTree, main: Node, focus: String) -> bool:
	var panel: Control = main.get("_work_panel") as Control
	for chip in (panel.call("_layout") as Dictionary)["chips"] as Array:
		if String((chip as Dictionary)["focus"]) == focus:
			var move := InputEventMouseMotion.new()
			move.position = panel.global_position + ((chip as Dictionary)["rect"] as Rect2).get_center()
			move.global_position = move.position
			tree.root.push_input(move)
			return true
	return false


## The first colonist who is not you and not dead, or -1.
static func _a_colonist(world: Variant) -> int:
	for e in world.components.query(["identity", "position"]):
		if int(e) != int(world.player) and not world.components.has_component(int(e), "corpse"):
			return int(e)
	return -1


## The tile the body stands on, from the sim's own position.
static func _tile_under_player(world: Variant) -> Vector2i:
	var at: Dictionary = world.components.get_component(world.player, "position") as Dictionary
	return Vector2i(floori(float(at["x"])), floori(float(at["y"])))


## How many of the four cardinal neighbours of `at` are walls.
static func _walls_beside(world: Variant, at: Vector2i) -> int:
	var n: int = 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = at + d
		if SimTileMap.tile_at(world.tilemap, t.x, t.y) == SimTileMap.Tile.Wall:
			n += 1
	return n


## Whether a tile is open, paved ground outside a building: the street a day shot needs.
static func _outdoor_paved(map: Variant, at: Vector2i) -> bool:
	if at.x < 0 or at.y < 0 or at.x >= int(map.w) or at.y >= int(map.h):
		return false
	var idx: int = at.y * int(map.w) + at.x
	return int(map.tiles[idx]) == SimTileMap.Tile.Floor \
		and int(map.indoors[idx]) == 0 \
		and int(map.surfaces[idx]) == SimSurface.Surface.Paved


## The open paved street tile a day shot stands on: open (outdoor paved on all four sides, so the shot
## sees street and not a kerb), no furniture or sim object within SPOT_CLEAR tiles, and at least
## STREET_SHARE of its STREET_WINDOW paved outdoor tiles. Of those, out to SEARCH_TILES, the one with
## the fewest scraps within SPOT_CLEAR, the nearest ring first on a tie: the street deals a scrap to
## about one paved tile in five and a half, evenly block by block, so a seven-tile square with none
## is all but absent and the scraps are weighed rather than refused, as a room shot weighs them.
## Failing a candidate that much street, the one with the most. Its centre, or (-1, -1) for none.
static func _street_spot(world: Variant) -> Vector2:
	var from: Vector2i = _tile_under_player(world)
	var occ: Dictionary = _spot_occupancy(world)
	var best := Vector2(-1.0, -1.0)
	var best_count: int = -1
	var street := Vector2(-1.0, -1.0)
	var fewest: int = 1 << 30
	for ring in range(1, SEARCH_TILES + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var t := Vector2i(from.x + dx, from.y + dy)
				if world.is_blocked_tile(t.x, t.y) or not _outdoor_paved(world.tilemap, t):
					continue
				var open: bool = true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if not _outdoor_paved(world.tilemap, t + d):
						open = false
						break
				if not open:
					continue
				if not Dressing.clear_around(occ, t.x, t.y, SPOT_CLEAR, false) or not _held_free(occ, t):
					continue
				var centre := Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
				var count: int = _street_count(world.tilemap, t)
				if count * 100 >= STREET_SHARE * STREET_WINDOW_AREA:
					var scraps: int = _scraps_near(occ, t)
					if scraps < fewest:
						fewest = scraps
						street = centre
						if scraps == 0:
							return street
				if count > best_count:
					best_count = count
					best = centre
	return street if street.x >= 0.0 else best


## How many outdoor paved tiles lie in the STREET_WINDOW box centred on `at`: the share of the
## picture a day shot at that spot would show as street.
static func _street_count(map: Variant, at: Vector2i) -> int:
	var n: int = 0
	for dy in range(-STREET_WINDOW_HALF.y, STREET_WINDOW_HALF.y + 1):
		for dx in range(-STREET_WINDOW_HALF.x, STREET_WINDOW_HALF.x + 1):
			if _outdoor_paved(map, Vector2i(at.x + dx, at.y + dy)):
				n += 1
	return n


## Whether the survivor may stand on `at` in a shot: no picture of any kind reaches within
## SPOT_CLEAR tiles of it, so no shot has a table or a scrap drawn over or beside the survivor.
## Dressing's own test, on an occupancy that holds the world's props the way main.gd's does.
static func _ring_free(occ: Dictionary, at: Vector2i, radius: int = SPOT_CLEAR) -> bool:
	return Dressing.clear_around(occ, at.x, at.y, radius)


## Whether no tile within `radius` tiles of `at` holds a sim object -- a parked car, a heap, a tree,
## a prop: a street shot with a wreck beside the survivor shows the wreck, not the street. Room shots
## ask only at radius 1, so the survivor never stands on a chest while the room's own props still
## show around them.
static func _held_free(occ: Dictionary, at: Vector2i, radius: int = SPOT_CLEAR) -> bool:
	var map: Variant = occ["map"]
	for dy in range(-radius - 1, radius + 2):
		for dx in range(-radius, radius + 1):
			var x: int = at.x + dx
			var y: int = at.y + dy
			if x < 0 or y < 0 or x >= int(map.w) or y >= int(map.h):
				continue
			if Dressing._held_rect(occ, map, x, y) != null:
				return false
	return true


## The occupancy a spot search tests every candidate against, built once per search.
static func _spot_occupancy(world: Variant) -> Dictionary:
	return Dressing.occupancy(Dressing.block_of(world), world.tilemap, int(world.seed), Dressing.held_props(world))


## The indoor floor tile a room shot stands on: walkable, in a room of at least ROOM_SHARE percent of
## the STREET_WINDOW and not the colony's hall (the combat shot already stands there, in the start's
## clearing), with no furniture within SPOT_CLEAR tiles, else within one or two tiles fewer: the
## district's houses are small, and once their walls take their pieces a seven-tile square of bare
## floor outside the hall is all but absent. No sim object stands on the tile or the tiles north and
## south of it (`_held_free` at radius 0), and no scrap reaches the tile itself, so the survivor never
## stands on a chest or a scrap. Of those, one with a counter within COUNTER_HALF in its own room
## first (`_counter_near`: the review asks the room shot to show one), then one that shows a table
## set in its own room (`_set_near`), then the clearest, then the
## one whose shot shows the most: the furnished pictures on its own room's floor in the STREET_WINDOW
## round it, one more for each kind, and INTERIOR_COUNTER_BONUS for a counter, less the scraps within
## SPOT_CLEAR (a furnished room seldom has a seven-tile square with no scrap either, so the scraps
## are weighed rather than refused). Ties go to the nearest by Chebyshev ring from the body, then the
## first in row order, so the answer is the same on every run from the same seed. Failing any, the
## clearest candidate the old way (`_clearest_room_spot`). Its centre, or (-1, -1) for none.
static func _interior_spot(world: Variant) -> Vector2:
	var from: Vector2i = _tile_under_player(world)
	var occ: Dictionary = _spot_occupancy(world)
	var map: Variant = world.tilemap
	var start: Vector2i = SimBootRes.colony_start(map)
	var hall: int = Dressing._room_of(occ, map, start.x, start.y)
	var best := Vector2(-1.0, -1.0)
	var best_key: Array = []
	for ty in range(maxi(0, from.y - INTERIOR_SEARCH_TILES), mini(int(map.h), from.y + INTERIOR_SEARCH_TILES + 1)):
		for tx in range(maxi(0, from.x - INTERIOR_SEARCH_TILES), mini(int(map.w), from.x + INTERIOR_SEARCH_TILES + 1)):
			var t := Vector2i(tx, ty)
			if SimTileMap.tile_at(map, t.x, t.y) != SimTileMap.Tile.Floor:
				continue
			if world.is_blocked_tile(t.x, t.y) or not SimTileMap.is_indoors(map, t.x, t.y):
				continue
			if Dressing._room_of(occ, map, t.x, t.y) == hall or not _held_free(occ, t, 0):
				continue
			var radius: int = 0
			for r in [SPOT_CLEAR, SPOT_CLEAR - 1, SPOT_CLEAR - 2]:
				if Dressing.clear_around(occ, t.x, t.y, r, false):
					radius = r
					break
			if radius == 0 or not Dressing.clear_around(occ, t.x, t.y, 0):
				continue
			if _room_count(map, t) * 100 < ROOM_SHARE * STREET_WINDOW_AREA:
				continue
			var counter: bool = _counter_near(occ, map, t)
			var seated: bool = _set_near(occ, map, t)
			var score: int = _shot_score(occ, map, t)
			var ring: int = maxi(absi(t.x - from.x), absi(t.y - from.y))
			var key: Array = [1 if counter and seated else 0, 1 if seated else 0, 1 if counter else 0, radius, score, -ring]
			if best_key.is_empty() or key > best_key:
				best_key = key
				best = Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	if best.x >= 0.0:
		return best
	return _clearest_room_spot(world, occ, from)


## What a room shot centred on `at` shows: one for each furnished picture on the floor of its own room
## in the STREET_WINDOW (the walls hide the rooms behind them), one for each kind of them,
## INTERIOR_COUNTER_BONUS when one is a table against a north wall (a counter), less one for each
## scrap within SPOT_CLEAR tiles.
static func _shot_score(occ: Dictionary, map: Variant, at: Vector2i) -> int:
	var pieces: int = 0
	var kinds: Dictionary = {}
	var counter: bool = false
	var room: int = Dressing._room_of(occ, map, at.x, at.y)
	for dy in range(-STREET_WINDOW_HALF.y, STREET_WINDOW_HALF.y + 1):
		for dx in range(-STREET_WINDOW_HALF.x, STREET_WINDOW_HALF.x + 1):
			var x: int = at.x + dx
			var y: int = at.y + dy
			if Dressing._room_of(occ, map, x, y) != room:
				continue
			var top: Dictionary = Dressing._kept_top(occ, map, x, y)
			if top.is_empty() or int(top["rank"]) == Dressing.RANK_HELD:
				continue
			pieces += 1
			kinds[String(top["key"])] = true
			if absi(dx) <= COUNTER_HALF.x and absi(dy) <= COUNTER_HALF.y and _is_counter(occ, map, x, y):
				counter = true
	return pieces + kinds.size() + (INTERIOR_COUNTER_BONUS if counter else 0) - _scraps_near(occ, at)


## Whether a room shot centred on `at` shows a counter within COUNTER_HALF of the survivor, in the
## survivor's own room (a counter behind a wall is on a tile the survivor does not see).
static func _counter_near(occ: Dictionary, map: Variant, at: Vector2i) -> bool:
	var room: int = Dressing._room_of(occ, map, at.x, at.y)
	for dy in range(-COUNTER_HALF.y, COUNTER_HALF.y + 1):
		for dx in range(-COUNTER_HALF.x, COUNTER_HALF.x + 1):
			if Dressing._room_of(occ, map, at.x + dx, at.y + dy) == room and _is_counter(occ, map, at.x + dx, at.y + dy):
				return true
	return false


## Whether a room shot centred on `at` shows a table set in the survivor's own room: a chair kept
## at its table within the STREET_WINDOW, so the room reads as lived in, not a counter and a cabinet.
static func _set_near(occ: Dictionary, map: Variant, at: Vector2i) -> bool:
	var room: int = Dressing._room_of(occ, map, at.x, at.y)
	for dy in range(-STREET_WINDOW_HALF.y, STREET_WINDOW_HALF.y + 1):
		for dx in range(-STREET_WINDOW_HALF.x, STREET_WINDOW_HALF.x + 1):
			if Dressing._room_of(occ, map, at.x + dx, at.y + dy) != room:
				continue
			if Dressing._kept_top(occ, map, at.x + dx, at.y + dy).get("table", null) != null:
				return true
	return false


## Whether (x, y) keeps a table standing in for a counter: a plain wall north of it, and no window
## on the wall either side, so the counter is never read as a table pushed under a pane.
static func _is_counter(occ: Dictionary, map: Variant, x: int, y: int) -> bool:
	if not Dressing._wall_at(map, x, y - 1):
		return false
	for side in [-1, 1]:
		if SimTileMap.tile_at(map, x + side, y - 1) == SimTileMap.Tile.Window:
			return false
	var top: Dictionary = Dressing._kept_top(occ, map, x, y)
	return not top.is_empty() and String(top["key"]) == COUNTER_KEY


## How many tiles within SPOT_CLEAR of `at` keep a scrap of litter.
static func _scraps_near(occ: Dictionary, at: Vector2i) -> int:
	var map: Variant = occ["map"]
	var scraps: int = 0
	for dy in range(-SPOT_CLEAR, SPOT_CLEAR + 1):
		for dx in range(-SPOT_CLEAR, SPOT_CLEAR + 1):
			if not Dressing._kept_litter(occ, map, at.x + dx, at.y + dy).is_empty():
				scraps += 1
	return scraps


## The fallback room spot: the nearest candidate in a room of ROOM_SHARE that is clear of every
## picture within SPOT_CLEAR tiles, else within one fewer, down to a tile; failing a room that large,
## the candidate in the biggest room.
static func _clearest_room_spot(world: Variant, occ: Dictionary, from: Vector2i) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_count: int = -1
	var by_radius: Dictionary = {}
	for ring in range(0, INTERIOR_SEARCH_TILES + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var t := Vector2i(from.x + dx, from.y + dy)
				if SimTileMap.tile_at(world.tilemap, t.x, t.y) != SimTileMap.Tile.Floor:
					continue
				if world.is_blocked_tile(t.x, t.y) or not SimTileMap.is_indoors(world.tilemap, t.x, t.y):
					continue
				if not _ring_free(occ, t, 1):
					continue
				var count: int = _room_count(world.tilemap, t)
				var centre := Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
				if count > best_count:
					best_count = count
					best = centre
				if count * 100 < ROOM_SHARE * STREET_WINDOW_AREA:
					continue
				for radius in range(SPOT_CLEAR, 0, -1):
					if by_radius.has(radius):
						break
					if _ring_free(occ, t, radius):
						by_radius[radius] = centre
						break
		if by_radius.has(SPOT_CLEAR):
			break
	for radius in range(SPOT_CLEAR, 0, -1):
		if by_radius.has(radius):
			return by_radius[radius]
	return best


## How many tiles of the room `at` stands in lie in the STREET_WINDOW box centred on it: indoor
## floor reached from `at` by side steps without leaving the box, so the count is the room the
## survivor sees and not the rooms behind its walls.
static func _room_count(map: Variant, at: Vector2i) -> int:
	var seen: Dictionary = {at: true}
	var queue: Array[Vector2i] = [at]
	var n: int = 0
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		n += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = c + d
			if seen.has(nx) or absi(nx.x - at.x) > STREET_WINDOW_HALF.x or absi(nx.y - at.y) > STREET_WINDOW_HALF.y:
				continue
			if SimTileMap.tile_at(map, nx.x, nx.y) != SimTileMap.Tile.Floor or not SimTileMap.is_indoors(map, nx.x, nx.y):
				continue
			seen[nx] = true
			queue.append(nx)
	return n
