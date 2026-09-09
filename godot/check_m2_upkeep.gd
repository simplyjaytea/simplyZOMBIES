extends SceneTree
# Wear on hit + Repair ceiling drop (ADR 0014).

const SimBoot = preload("res://sim/boot.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const World = preload("res://sim/world.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const Clock = preload("res://sim/time/clock.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# `... and ok` rather than `ok and ...`, so one red lane does not hide the four behind it.
	var ok: bool = true
	ok = _wear() and ok
	ok = _repair() and ok
	ok = _focus() and ok
	ok = _spawn_delivery() and ok
	ok = _the_weapon_that_acted_is_the_weapon_that_wears() and ok
	ok = _a_shot_announces_itself_and_a_dry_hand_does_not() and ok
	if ok:
		print("M2_UPKEEP_OK wear broke repair spawn-deliver source fired")
		quit(0)
	else:
		push_error("M2_UPKEEP_FAIL")
		quit(1)

func _wear() -> bool:
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var player: int = int(w.player)
	var knife: int = -1
	for item in SimInventory.equipped_items(w, player):
		if SimItems.melee_profile_of(w, item) != null:
			knife = item
			break
	if knife < 0:
		knife = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
		if not SimInventory.equip(w, player, knife, "primary"):
			push_error("equip knife failed")
			return false
	var cond: Dictionary = w.components.get_component(knife, "condition") as Dictionary
	var before: float = float(cond.get("current", 1.0))
	# `item` is part of the event contract now -- the wear handler reads it rather than guessing
	# which hand acted. A publish without it wears nothing, which is the -1 a zombie's bite sends.
	w.events.publish({"type": "attack.connected", "attacker": player, "target": 0, "bodyPart": "torso", "damage": 1, "item": knife})
	w.events.drain()
	var after: float = float((w.components.get_component(knife, "condition") as Dictionary).get("current", 1.0))
	if after >= before:
		push_error("no wear %s→%s" % [str(before), str(after)])
		return false
	# Break
	cond["current"] = SimItems.WEAR_PER_HIT
	w.events.publish({"type": "attack.connected", "attacker": player, "target": 0, "bodyPart": "torso", "damage": 1, "item": knife})
	w.events.drain()
	var broken: float = float((w.components.get_component(knife, "condition") as Dictionary).get("current", -1.0))
	if broken > 0.0:
		push_error("not broken %s" % str(broken))
		return false
	var eq: Variant = w.components.get_component(player, "equipment")
	var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
	if slots.has("primary") and int(slots["primary"]) == knife:
		push_error("broken knife still equipped")
		return false
	print("WEAR OK hit broke unequip")
	return true

func _repair() -> bool:
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var mara: int = -1
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			mara = int(e)
			break
	if mara < 0:
		push_error("no mara")
		return false
	var knife: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
	w.components.set_component(knife, "condition", {"current": 0.4, "ceiling": 1.0})
	if not SimInventory.stow(w, mara, knife):
		push_error("stow knife")
		return false
	var scrap: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged", "count": 1})
	if not SimInventory.stow(w, mara, scrap):
		push_error("stow scrap")
		return false
	# The colony's start tile, off the district's own anchor rather than the old (46.0, 45.0)
	# literal twin of it -- the last of those outside check_buildings.gd's deliberate pins.
	var start: Vector2i = SimTileMap.player_start(w.tilemap)
	var work: Dictionary = SimJobs._repair_work(w, mara, float(start.x), float(start.y))
	if work.is_empty() or int(work.get("target", -1)) != knife:
		push_error("repair work %s" % str(work))
		return false
	var fires: Array = w.components.query(["campfire"])
	var fp: Variant = w.components.get_component(int(fires[0]), "position")
	w.components.set_component(mara, "position", {
		"x": float((fp as Dictionary)["x"]), "y": float((fp as Dictionary)["y"]),
	})
	work["ticksLeft"] = 1
	w.components.set_component(mara, "job", work)
	SimJobs._do_repair(w, mara, work)
	var c: Dictionary = w.components.get_component(knife, "condition") as Dictionary
	var cur: float = float(c.get("current", 0.0))
	var ceil: float = float(c.get("ceiling", 1.0))
	if ceil >= 1.0:
		push_error("ceiling not dropped %s" % str(ceil))
		return false
	if cur <= 0.4:
		push_error("current not restored %s" % str(cur))
		return false
	print("REPAIR OK current %.2f ceiling %.2f" % [cur, ceil])
	return true

# spawn_item used to end with events.drain(), so any system spawning an item mid-tick flushed
# every event other systems had queued that tick -- and since some spawns hang on an RNG roll
# (a recovered arrow), *which* events flushed was not stable between runs. It delivers just its
# own item.spawned now. Four assertions: a queued sentinel survives the spawn untouched; the
# synchronous half survives (a just-spawned pack already has its container grid -- the reason
# the drain was there); the delivered event still enters the record; and the true negative --
# a real drain() fires the probe, so "the probe stayed silent" above is a claim that can fail.
func _spawn_delivery() -> bool:
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	# An Array, not an int: a lambda captures primitives by value (CLAUDE.md's trap).
	var probe: Array = []
	w.events.subscribe({"id": "upkeep.spawn-probe", "type": "upkeep.sentinel", "handler": func(_e: Dictionary) -> void:
		probe.append(1)
	})
	w.events.publish({"type": "upkeep.sentinel"})
	var pack: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	if not probe.is_empty():
		push_error("spawn_item flushed the queue: the sentinel handler ran mid-spawn")
		return false
	if int(w.events.pending) < 1:
		push_error("the sentinel is no longer queued after spawn_item")
		return false
	if w.components.get_component(pack, "container") == null:
		push_error("a just-spawned pack has no container grid; delivery did not reach the subscriber")
		return false
	var recorded: bool = false
	for e in w.events.drained:
		var d: Dictionary = e as Dictionary
		if String(d.get("type", "")) == "item.spawned" and int(d.get("item", -1)) == pack:
			recorded = true
			break
	if not recorded:
		push_error("item.spawned missing from the event record")
		return false
	w.events.drain()
	if probe.is_empty():
		push_error("a drain did not fire the probe; the flush assertion above proves nothing")
		return false
	print("SPAWN-DELIVER OK sentinel queued through spawn, grid attached")
	return true

func _focus() -> bool:
	var auto: Dictionary = SimJobs.preset("Auto")
	if int(auto.get("Repair", 0)) != 3:
		push_error("auto repair %s" % str(auto.get("Repair", null)))
		return false
	var worker: Dictionary = SimJobs.preset("Worker")
	if int(worker.get("Repair", 0)) != 2:
		push_error("worker repair %s" % str(worker.get("Repair", null)))
		return false
	print("FOCUS OK repair columns")
	return true


# --- SOURCE ---
#
# The defect this lane exists for, in one sentence: `_weapon_for_attacker` walked
# ["primary", "secondary"] and returned the first item with a profile, so a survivor carrying a
# knife in one hand and a pistol in the other wore *the knife* every time the pistol fired -- and
# the pistol, never wearing, kept a jam chance of zero for the whole campaign.
#
# So the assertion is a pair, and neither half is worth anything alone. Fire: the pistol wears and
# the knife does not. Swing: the knife wears and the pistol does not. A lane that only checked the
# first would pass for an implementation that wears everything the actor is holding.
func _the_weapon_that_acted_is_the_weapon_that_wears() -> bool:
	var lane: String = "SOURCE"

	# The shot half.
	var w: Variant = _bare_world()
	var armed: Dictionary = _arm_both_hands(w)
	if armed.is_empty():
		push_error("%s: could not arm a knife and a pistol, so this lane is asserting nothing" % lane)
		return false
	var knife: int = int(armed["knife"])
	var pistol: int = int(armed["pistol"])
	var knife_before: float = _condition(w, knife)
	var pistol_before: float = _condition(w, pistol)
	if not _fire_once(w):
		push_error("%s: the pistol never fired, so the shot half is asserting nothing" % lane)
		return false
	var knife_after: float = _condition(w, knife)
	var pistol_after: float = _condition(w, pistol)
	if pistol_after >= pistol_before:
		push_error("%s: the pistol fired and did not wear (%.5f vs %.5f)" % [lane, pistol_before, pistol_after])
		return false
	if not is_equal_approx(knife_after, knife_before):
		push_error("%s: the pistol fired and the knife wore (%.5f vs %.5f) -- this is the bug" % [lane, knife_before, knife_after])
		return false

	# The swing half, on a fresh world so the numbers above cannot carry.
	var w2: Variant = _bare_world()
	var armed2: Dictionary = _arm_both_hands(w2)
	if armed2.is_empty():
		push_error("%s: could not arm the swing half" % lane)
		return false
	var knife2: int = int(armed2["knife"])
	var pistol2: int = int(armed2["pistol"])
	var rng: Variant = w2.rng.stream("shambler")
	SimRoster.spawn_zombie(w2, 9.0, 12.0, SimRoster.TYPE_SHAMBLER, rng)
	w2.events.drain()
	var knife2_before: float = _condition(w2, knife2)
	var pistol2_before: float = _condition(w2, pistol2)
	if not _swing_once(w2):
		push_error("%s: the swing never connected, so the swing half is asserting nothing" % lane)
		return false
	var knife2_after: float = _condition(w2, knife2)
	var pistol2_after: float = _condition(w2, pistol2)
	if knife2_after >= knife2_before:
		push_error("%s: the knife connected and did not wear (%.5f vs %.5f)" % [lane, knife2_before, knife2_after])
		return false
	if not is_equal_approx(pistol2_after, pistol2_before):
		push_error("%s: the knife swung and the pistol wore (%.5f vs %.5f)" % [lane, pistol2_before, pistol2_after])
		return false

	print("  SOURCE OK shot wore the pistol by %.5f, swing wore the knife by %.5f, neither touched the other" % [pistol_before - pistol_after, knife2_before - knife2_after])
	return true


# --- FIRED ---
#
# The dead-socket half: `weapon.fired` is the channel wear rides, so something has to assert it is
# published, that it names the weapon rather than the shooter's other hand, and that it is not
# published when no shot happened. The last of those is the true negative and it is the one that
# matters -- an implementation that published on every trigger pull would wear a weapon with no
# ammunition in it.
func _a_shot_announces_itself_and_a_dry_hand_does_not() -> bool:
	var lane: String = "FIRED"
	var w: Variant = _bare_world()
	var armed: Dictionary = _arm_both_hands(w)
	if armed.is_empty():
		push_error("%s: could not arm the shooter" % lane)
		return false
	var pistol: int = int(armed["pistol"])
	var fired: Array = _fire_and_collect(w, 3)
	if fired.size() < 1:
		push_error("%s: three trigger pulls produced no weapon.fired at all" % lane)
		return false
	for e in fired:
		if int((e as Dictionary).get("item", -1)) != pistol:
			push_error("%s: weapon.fired named %d, not the pistol %d" % [lane, int((e as Dictionary).get("item", -1)), pistol])
			return false

	# TN: the same actor, the same commands, no ammunition. `_fire_shot` refuses before the round
	# leaves, so the event must not appear -- and if it does, every wear number above is a lie.
	var w2: Variant = _bare_world()
	var armed2: Dictionary = _arm_both_hands(w2, false)
	if armed2.is_empty():
		push_error("%s: could not arm the dry shooter" % lane)
		return false
	var dry: Array = _fire_and_collect(w2, 3)
	if not dry.is_empty():
		push_error("%s: a pistol with no ammunition published %d weapon.fired" % [lane, dry.size()])
		return false

	print("  FIRED OK %d shots announced the pistol, an empty one announced nothing" % fired.size())
	return true


# --- helpers for the two lanes above ---

# A bare world with only the modules these lanes exercise, rather than SimBoot.playable: the boot
# colony arrives already holding things, and a lane about which of two hands wore needs to know
# exactly what is in both of them.
func _bare_world() -> Variant:
	var f: Dictionary = {"seed": 41, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 12.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	SimBoot.attach_kernel(w, SimTileMap.blank_map(24, 24))
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	return w


## A knife in `primary` and a pistol in `secondary` -- the exact arrangement the old guess got
## wrong. Returns {} rather than half a hand if either equip refuses.
func _arm_both_hands(w: Variant, with_ammo: bool = true) -> Dictionary:
	var knife: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, knife, "primary"):
		return {}
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, pistol, "secondary"):
		return {}
	if with_ammo:
		var rounds: int = SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 12})
		if not SimInventory.stow(w, w.player, rounds):
			w.components.set_component(rounds, "stored", {"container": w.player})
	w.events.drain()
	return {"knife": knife, "pistol": pistol}


func _condition(w: Variant, item: int) -> float:
	var c: Variant = w.components.get_component(item, "condition")
	return float((c as Dictionary).get("current", 1.0)) if c is Dictionary else 1.0


## Drives one shot to completion. Steps rather than publishing by hand, because `events.publish`
## only queues until `drain()` at the end of `world.step()` -- a lane that published `fire` and
## read a condition back on the same line would see nothing and blame correct code.
func _fire_once(w: Variant) -> bool:
	return _fire_and_collect(w, 1).size() > 0


func _fire_and_collect(w: Variant, shots: int) -> Array:
	var seen: Array = []
	for s in shots:
		w.commands.push({"type": "fire"})
		for i in 60:
			w.step()
			for e in w.events.drained:
				if String((e as Dictionary).get("type", "")) == "weapon.fired":
					seen.append(e)
			var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary)["state"]) == SimRanged.FireState.Idle:
				break
	return seen


func _swing_once(w: Variant) -> bool:
	if not SimMelee.try_begin_swing(w, w.player):
		return false
	var landed: bool = false
	for i in 60:
		w.step()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "attack.connected" and int((e as Dictionary).get("attacker", -1)) == w.player:
				landed = true
		if landed:
			break
	return landed
