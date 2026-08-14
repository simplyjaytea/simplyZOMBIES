extends SceneTree
# Bow/pistol loop: quiet 4 vs loud 180, ammo consume, mag reload.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const Clock = preload("res://sim/time/clock.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _bow_quiet() and ok
	ok = _pistol_loud() and ok
	if ok:
		print("M2_RANGED_OK bow pistol")
		quit(0)
	else:
		push_error("M2_RANGED_FAIL")
		quit(1)

func _world() -> Variant:
	var f: Dictionary = {"seed": 21, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 12.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
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

func _fire_through(w: Variant, shots: int = 1) -> Array:
	var noises: Array = []
	for s in shots:
		w.commands.push({"type": "fire"})
		for i in 40:
			w.step()
			for e in w.events.drained:
				if String((e as Dictionary).get("type", "")) == "noise.emitted" and int((e as Dictionary).get("source", -1)) == w.player:
					noises.append(float((e as Dictionary).get("magnitude", 0)))
			var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary)["state"]) == SimRanged.FireState.Idle:
				break
	return noises

func _bow_quiet() -> bool:
	var w: Variant = _world()
	var bow: int = SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"})
	SimInventory.equip(w, w.player, bow)
	var arrows: int = SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 6})
	if not SimInventory.stow(w, w.player, arrows):
		w.components.set_component(arrows, "stored", {"container": w.player})
	var rng: Variant = w.rng.stream("shambler")
	SimRoster.spawn_zombie(w, 14.0, 12.0, SimRoster.TYPE_SHAMBLER, rng)
	w.events.drain()
	var noises: Array = _fire_through(w, 1)
	if noises.is_empty() or absf(float(noises[0]) - 4.0) > 0.01:
		push_error("bow noise %s" % str(noises))
		return false
	print("BOW OK noise=%s" % str(noises[0]))
	return true

func _pistol_loud() -> bool:
	var w: Variant = _world()
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	SimInventory.equip(w, w.player, pistol)
	var ammo: int = SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 20})
	SimInventory.stow(w, w.player, ammo)
	var rng: Variant = w.rng.stream("shambler")
	SimRoster.spawn_zombie(w, 14.0, 12.0, SimRoster.TYPE_SHAMBLER, rng)
	w.events.drain()
	var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
	if rw == null or int((rw as Dictionary).get("mag", 0)) != 8:
		push_error("pistol mag %s" % str(rw))
		return false
	var noises: Array = _fire_through(w, 1)
	if noises.is_empty() or absf(float(noises[0]) - 180.0) > 0.01:
		push_error("pistol noise %s" % str(noises))
		return false
	rw = w.components.get_component(w.player, "rangedWeapon")
	if int((rw as Dictionary).get("mag", 0)) != 7:
		push_error("pistol mag after shot %s" % (rw as Dictionary).get("mag", -1))
		return false
	print("PISTOL OK noise=180 mag=%s" % (rw as Dictionary)["mag"])
	return true
