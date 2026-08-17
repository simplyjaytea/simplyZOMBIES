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
	if ok:
		print("M2_FORTIFY_OK board scrap alarm bait v14")
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
	# Left as-is rather than refactored under this fix; see docs/30-decisions.md.
	if int(SimSerialize.SAVE_VERSION) != 14:
		push_error("SAVE_VERSION %d want 14" % int(SimSerialize.SAVE_VERSION))
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
	var z: int = int(w.entities.spawn())
	w.components.set_component(z, "position", {"x": 11.5, "y": 12.5})
	w.components.set_component(z, "shambler", {})
	for _i in SimFortify.CONTACT_PER_STAGE * 4 + 5:
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
	if SimFortify.can_scrap(w.tilemap, 49, 49) or SimFortify.can_scrap(w.tilemap, 50, 49):
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
	if SimFortify._has_scrap(w, w.player):
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
