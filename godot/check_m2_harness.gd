extends SceneTree
# Alpha tuning harness: CI clock-jump invariants + soft contact/noisy prints.
# HARNESS_FULL=1 → real 10-day step loop (nightly; never fails on distributions).

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const Clock = preload("res://sim/time/clock.gd")

const SEED: int = 20260805
const CONTACT_TICKS: int = 600

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _turtle_floor() and ok
	ok = _nothing_personal() and ok
	_noisy_night()
	_contact_kd()
	if OS.get_environment("HARNESS_FULL") == "1":
		_full_ten_day()
	if ok:
		print("M2_HARNESS_OK turtle personal noisy contact")
		quit(0)
	else:
		push_error("M2_HARNESS_FAIL")
		quit(1)

func _boot() -> Variant:
	return SimBoot.playable(SEED, 64)["world"]

func _jump_dusk(world: Variant, day: int) -> void:
	world.tick = Clock.tick_on_day(day, Clock.DAY_ENDS) - 1
	world.step()

func _live(world: Variant) -> int:
	return world.components.query(["shambler"]).size()

func _ids(world: Variant) -> Array[int]:
	return world.components.query(["shambler"])

func _edge_new(world: Variant, before: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for e in world.components.query(["shambler", "position"]):
		if before.has(int(e)):
			continue
		var pos: Variant = world.components.get_component(int(e), "position")
		if not pos is Dictionary:
			continue
		out.append(Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"]))))
	return out

# The gates and the annex come off the world that placed the packet, not off constants: they are
# map state now, so this follows the colony if the generator ever sites it elsewhere. Read once
# per call rather than per tile.
func _packet_ok(world: Variant, tiles: Array[Vector2i]) -> bool:
	var gate_a: Vector2i = SimTileMap.gate_a(world.tilemap)
	var gate_b: Vector2i = SimTileMap.gate_b(world.tilemap)
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if gate_a.x < 0 or gate_b.x < 0 or annex.size.x <= 0:
		push_error("the booted district names no gates or annex, so the exclusion is unmeasurable")
		return false
	for tile in tiles:
		if tile == gate_a or tile == gate_b:
			push_error("packet on gate %s" % str(tile))
			return false
		if annex.has_point(tile):
			push_error("packet in annex %s" % str(tile))
			return false
		var gx: float = float(tile.x) + 0.5
		var gy: float = float(tile.y) + 0.5
		for gate in [gate_a, gate_b]:
			var dx: float = gx - (float((gate as Vector2i).x) + 0.5)
			var dy: float = gy - (float((gate as Vector2i).y) + 0.5)
			if dx * dx + dy * dy < SimDirector.GATE_EXCLUSION * SimDirector.GATE_EXCLUSION:
				push_error("packet within 32m of gate %s" % str(tile))
				return false
	return true

func _turtle_floor() -> bool:
	var w: Variant = _boot()
	var peak: float = SimDirector._annex_peak(w)
	if peak >= SimDirector.QUIET_NOISE:
		push_error("annex peak_noise %s want < %s" % [str(peak), str(SimDirector.QUIET_NOISE)])
		return false
	var packets: int = 0
	for day in [8, 9, 10]:
		var before: Array[int] = _ids(w)
		_jump_dusk(w, day)
		var spawned: Array[Vector2i] = _edge_new(w, before)
		if not _packet_ok(w, spawned):
			return false
		packets += spawned.size()
	if packets < 1:
		push_error("turtle floor packets=%d across dusk 8-10" % packets)
		return false
	print("TURTLE OK packets=%d peak=%.2f" % [packets, peak])
	return true

func _nothing_personal() -> bool:
	var w: Variant = _boot()
	if not w.systems.unregister("director.dusk"):
		push_error("director.dusk missing")
		return false
	var packets: int = 0
	for day in [8, 9, 10]:
		var before: Array[int] = _ids(w)
		_jump_dusk(w, day)
		packets += _edge_new(w, before).size()
	if packets != 0:
		push_error("Nothing Personal leaked packets=%d" % packets)
		return false
	print("PERSONAL OK zero packets")
	return true

func _windows(world: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var map: Variant = world.tilemap
	var a: Rect2i = SimTileMap.annex_rect(map)
	for y in range(a.position.y, a.position.y + a.size.y):
		for x in range(a.position.x, a.position.x + a.size.x):
			if SimTileMap.tile_at(map, x, y) == SimTileMap.Tile.Window:
				out.append(Vector2i(x, y))
	return out

func _avenue_live(world: Variant) -> int:
	var n: int = 0
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	var south: int = annex.position.y + annex.size.y
	for e in world.components.query(["shambler", "position"]):
		var pos: Variant = world.components.get_component(int(e), "position")
		if pos is Dictionary and float((pos as Dictionary)["y"]) >= float(south):
			n += 1
	return n

func _noisy_night() -> void:
	var w: Variant = _boot()
	var wins: Array[Vector2i] = _windows(w)
	if wins.size() >= 2:
		SimFortify._board_window(w, wins[0].x, wins[0].y)
		SimFortify._board_window(w, wins[1].x, wins[1].y)
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	var by: int = mini(int(w.tilemap.h) - 3, annex.position.y + annex.size.y + 8)
	SimFortify._place_noisemaker(w, 50, by)
	SimFortify._wind_noisemaker(w)
	for _i in 400:
		w.step()
	var peak: float = float(w.field.peak_noise()) if w.field != null else 0.0
	print("NOISY live=%d avenue=%d peak=%.2f" % [_live(w), _avenue_live(w), peak])

func _arena() -> Variant:
	var f: Dictionary = {
		"seed": 21,
		"tick_hz": 20,
		"map": {"width": 24, "height": 24, "walls": []},
		"player": {"id": 0, "x": 8.0, "y": 12.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	return w

func _spawn_twelve(w: Variant, x0: float) -> void:
	var rng: Variant = w.rng.stream("shambler")
	for i in 12:
		SimRoster.spawn_zombie(w, x0 + float(i % 4) * 0.45, 11.4 + float(i / 4) * 0.45, SimRoster.TYPE_SHAMBLER, rng)

func _player_down(w: Variant) -> bool:
	var body: Variant = w.components.get_component(w.player, "body")
	return not (body is Dictionary and SimHealth.is_alive(body as Dictionary))

func _contact_branch(label: String, x0: float, setup: Callable, fight: Callable) -> void:
	var w: Variant = _arena()
	setup.call(w)
	_spawn_twelve(w, x0)
	w.events.drain()
	var connected: int = 0
	var kills: int = 0
	for _t in CONTACT_TICKS:
		fight.call(w)
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			var t: String = String(ev.get("type", ""))
			if t == "attack.connected" and int(ev.get("attacker", -1)) == w.player:
				connected += 1
			elif t == "entity.killed" and int(ev.get("killer", -1)) == w.player:
				kills += 1
	print("KD %s connected=%d kills=%d player_down=%s" % [label, connected, kills, str(_player_down(w))])

func _contact_kd() -> void:
	_contact_branch("knife", 9.0, func(w: Variant) -> void:
		var knife: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
		SimInventory.equip(w, w.player, knife)
	, func(w: Variant) -> void:
		w.commands.push({"type": "swing"})
	)
	_contact_branch("bow", 12.0, func(w: Variant) -> void:
		var bow: int = SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"})
		SimInventory.equip(w, w.player, bow)
		var arrows: int = SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 40})
		SimInventory.stow(w, w.player, arrows)
	, func(w: Variant) -> void:
		w.commands.push({"type": "fire"})
	)
	_contact_branch("pistol", 12.0, func(w: Variant) -> void:
		var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
		SimInventory.equip(w, w.player, pistol)
		var ammo: int = SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 40})
		SimInventory.stow(w, w.player, ammo)
	, func(w: Variant) -> void:
		w.commands.push({"type": "fire"})
		var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
		if rw is Dictionary and int((rw as Dictionary).get("mag", 0)) == 0:
			w.commands.push({"type": "reload"})
	)

func _full_ten_day() -> void:
	var w: Variant = _boot()
	var nights_with_packet: int = 0
	var max_live: int = _live(w)
	var cap_hit: bool = false
	var gate_touch: int = 0
	var end_tick: int = Clock.tick_on_day(10, Clock.DUSK_ENDS)
	var last_day: int = Clock.day_number(int(w.tick))
	# Hoisted above a 2.88 M tick loop: the colony's fixed points are map lookups now, and this
	# loop consults them on every tick that placed something.
	var gate_a: Vector2i = SimTileMap.gate_a(w.tilemap)
	var gate_b: Vector2i = SimTileMap.gate_b(w.tilemap)
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	while int(w.tick) < end_tick:
		var before: Array[int] = _ids(w)
		w.step()
		var live: int = _live(w)
		if live > max_live:
			max_live = live
		if live >= SimDirector.LIVE_CAP:
			cap_hit = true
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "director.packet":
				nights_with_packet += 1
		var day: int = Clock.day_number(int(w.tick))
		if day != last_day:
			print("FULL day=%d live=%d" % [day, live])
			last_day = day
		for tile in _edge_new(w, before):
			if tile == gate_a or tile == gate_b or annex.has_point(tile):
				gate_touch += 1
			else:
				var gx: float = float(tile.x) + 0.5
				var gy: float = float(tile.y) + 0.5
				for gate in [gate_a, gate_b]:
					var dx: float = gx - (float((gate as Vector2i).x) + 0.5)
					var dy: float = gy - (float((gate as Vector2i).y) + 0.5)
					if dx * dx + dy * dy < SimDirector.GATE_EXCLUSION * SimDirector.GATE_EXCLUSION:
						gate_touch += 1
						break
	print(
		"FULL nights_with_packet=%d max_live=%d cap24=%s gate_touch=%d"
		% [nights_with_packet, max_live, str(cap_hit), gate_touch]
	)
