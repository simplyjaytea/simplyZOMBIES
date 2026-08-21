extends SceneTree
# v16 + ticket 10 fortify/director + needs-era state. F9 is restore, not re-boot.

const SimBoot = preload("res://sim/boot.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const SimSave = preload("res://sim/save.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _version() and ok
	ok = _ticket10() and ok
	ok = _needs_era() and ok
	ok = _streams() and ok
	ok = _a_despawn_leaves_nothing_behind() and ok
	if ok:
		print("M2_SAVE_OK v16 ticket10 needs-era despawn-clean")
		quit(0)
	else:
		push_error("M2_SAVE_FAIL")
		quit(1)

func _version() -> bool:
	if int(SimSerialize.SAVE_VERSION) != 16:
		push_error("SAVE_VERSION %d want 16" % int(SimSerialize.SAVE_VERSION))
		return false
	# 13 is stale -- it predates posture's target/ticks_left and float stamina. 15 is current
	# (Slice 2 Part A's bloodLoss/wound-severity shape change), so 13 is two versions behind
	# and must still be rejected the same way a lone-version-behind save would be.
	var stale: Dictionary = SimSave.decode_save("{\"snapshot\":{\"version\":13},\"meta\":{}}")
	if String(stale.get("__error", "")) != "StaleSaveError":
		push_error("v13 not rejected: %s" % str(stale))
		return false
	print("VERSION OK %d rejects 13" % int(SimSerialize.SAVE_VERSION))
	return true

func _restore_bare(snap: Dictionary, seed_val: int, map_size: int) -> Variant:
	var boot: Dictionary = SimBoot.bare(seed_val, map_size)
	var w: Variant = boot["world"]
	w.restore(snap)
	return w

func _ticket10() -> bool:
	var boot: Dictionary = SimBoot.playable(20260805, 64)
	var w: Variant = boot["world"]
	w.tick = Clock.tick_on_day(8, Clock.DAY_ENDS) - 1
	# two windows stage 2
	var wins: Array[Vector2i] = []
	for j in range(40, 60):
		for i in range(40, 62):
			if SimTileMap.tile_at(w.tilemap, i, j) == SimTileMap.Tile.Window:
				wins.append(Vector2i(i, j))
			if wins.size() >= 2:
				break
		if wins.size() >= 2:
			break
	if wins.size() < 2:
		push_error("need two windows")
		return false
	for win in wins:
		var e: int = int(w.entities.spawn())
		w.components.set_component(e, "position", {"x": float(win.x) + 0.5, "y": float(win.y) + 0.5})
		w.components.set_component(e, "windowBoard", {"tx": win.x, "ty": win.y, "stage": 2, "contactTicks": 0})
	SimFortify.sync_map(w)
	var scrap: int = int(w.entities.spawn())
	w.components.set_component(scrap, "position", {"x": 48.5, "y": 48.5})
	w.components.set_component(scrap, "scrapBarricade", {})
	var alarm: int = int(w.entities.spawn())
	w.components.set_component(alarm, "alarmLine", {"cells": [{"x": 47, "y": 48}], "armed": true})
	var bait: int = int(w.entities.spawn())
	w.components.set_component(bait, "position", {"x": 46.5, "y": 50.5})
	w.components.set_component(bait, "noisemaker", {"expiresAtTick": int(w.tick) + 6000})
	w.director["lullUntilTick"] = int(w.tick) + Clock.DAY_TICKS
	for e2 in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e2), "identity")
		if ident is Dictionary and bool((ident as Dictionary).get("unique", false)):
			w.despawn(int(e2))
	w.step()
	var before_mara: int = w.components.query(["identity"]).size()
	var snap: Dictionary = w.snapshot()
	var txt: String = w.serialize()
	var w2: Variant = _restore_bare(snap, 20260805, 64)
	if w2.serialize() != txt:
		push_error("ticket10 fingerprint mismatch")
		return false
	if int(SimTileMap.opacity_at(w2.tilemap, wins[0].x, wins[0].y)) != int(SimTileMap.Opacity.Opaque):
		push_error("restored window not opaque")
		return false
	if w2.components.query(["identity"]).size() != before_mara:
		push_error("restore re-booted uniques")
		return false
	if w2.components.query(["shambler"]).size() != w.components.query(["shambler"]).size():
		push_error("restore re-booted placement")
		return false
	print("TICKET10 OK fortify director no-reboot")
	return true

func _needs_era() -> bool:
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var mara: int = -1
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			mara = int(e)
	if mara < 0:
		push_error("mara missing")
		return false
	var n: Dictionary = SimNeeds.of(w, mara)
	n["hunger"] = 22.0
	var fires: Array[int] = w.components.query(["campfire"])
	if fires.is_empty():
		push_error("campfire missing")
		return false
	SimNeeds.set_lit(w, fires[0], true)
	var extra: int = SimNeeds.make_bed(w, 44.5, 44.5)
	var raw: int = SimItems.spawn_item(w, "item.food.raw", {"tier": "scavenged"})
	w.components.set_component(raw, "position", {"x": 46.5, "y": 45.5})
	var sp: Variant = w.components.get_component(raw, "spoilage")
	if sp is Dictionary:
		(sp as Dictionary)["bornTick"] = int(w.tick) - 100
	var rng: Variant = w.rng.stream("recruits")
	var rolled: Dictionary = SimRecruits.roll(w, rng)
	var rec: int = SimRecruits.spawn_generated(w, rolled, 49.5, 50.5)
	w.components.set_component(rec, "recruit", {"waiting": true, "beatDay": 8})
	(w.recruits as Dictionary)["spawned"] = [8]
	var snap: Dictionary = w.snapshot()
	var txt: String = w.serialize()
	var w2: Variant = _restore_bare(snap, 20260805, 64)
	if w2.serialize() != txt:
		push_error("needs-era fingerprint mismatch")
		return false
	var n2: Dictionary = SimNeeds.of(w2, mara)
	if absf(float(n2.get("hunger", 0)) - 22.0) > 0.01:
		push_error("hungry mara lost")
		return false
	var cf: Variant = w2.components.get_component(fires[0], "campfire")
	if not cf is Dictionary or not bool((cf as Dictionary).get("lit", false)):
		push_error("campfire lit lost")
		return false
	if not w2.components.has_component(extra, "bed"):
		push_error("construct bed lost")
		return false
	var sp2: Variant = w2.components.get_component(raw, "spoilage")
	if not sp2 is Dictionary:
		push_error("spoilage lost")
		return false
	if not w2.components.has_component(rec, "recruit"):
		push_error("recruit lost")
		return false
	if not (w2.rng.save() as Dictionary).has("recruits"):
		push_error("recruits stream missing")
		return false
	print("NEEDS-ERA OK mara fire bed spoil recruit")
	return true

func _streams() -> bool:
	var w1: Variant = SimBoot.playable(20260805, 64)["world"]
	var w2: Variant = SimBoot.playable(20260805, 64)["world"]
	var a: Variant = w1.rng.stream("infection")
	var b: Variant = w2.rng.stream("infection")
	var s1: float = float(a.call("next"))
	var s2: float = float(b.call("next"))
	w1.tick = Clock.tick_on_day(8, Clock.DAY_ENDS) - 1
	w1.step()
	var a2: float = float(w1.rng.stream("infection").call("next"))
	var b2: float = float(w2.rng.stream("infection").call("next"))
	if s1 != s2 or a2 == s1:
		pass
	if absf(s1 - s2) > 0.0:
		push_error("infection seed drift before director")
		return false
	# w2 never opened director; infection second sample must match a world that also only took one pre-packet sample
	var w3: Variant = SimBoot.playable(20260805, 64)["world"]
	w3.rng.stream("infection").call("next")
	var c2: float = float(w3.rng.stream("infection").call("next"))
	if absf(b2 - c2) > 0.0000001:
		push_error("infection sequence shifted")
		return false
	if (w2.rng.save() as Dictionary).has("director"):
		push_error("director opened without packet")
		return false
	print("STREAMS OK director isolated")
	return true


# What a save is allowed to contain: nothing belonging to a body that is gone.
#
# Two ways this was leaking, and both wrote into every save from the moment they happened.
#
#   1. `world.despawn` guarded the modifier cleanup on `has_method("removeScope")`. The method
#      is `remove_scope`, so the guard was false on every despawn that has ever run and the
#      whole line did nothing -- every dead body's affix and wound modifiers stayed in
#      `_entries` and left `_invalidate(GLOBAL, ...)` scanning a `_cache` that only grew.
#   2. Five call sites reached past `world.despawn` to `world.entities.despawn`, which retires
#      the id and touches no components at all. Measured on a two-hour seed-404 world: eight
#      arrows consumed through the shipped `_consume_ammo` path left eight ids that
#      `components.query(["itemBase"])` still returned, for entities `entities.is_alive` said
#      were dead. CLAUDE.md's trap #9, on the item path rather than the population one.
#
# The negative is the second failure reproduced deliberately: an entity retired through the
# entity store alone must still leave its records behind. Without that row this assertion would
# pass just as happily against a `component_store` that had quietly stopped storing anything.
func _a_despawn_leaves_nothing_behind() -> bool:
	var w: Variant = SimBoot.bare()["world"]

	var item: int = SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 1})
	w.components.set_component(item, "position", {"x": 4.5, "y": 4.5})
	w.modifiers.call("add", {"stat": "move_speed", "op": "mul", "value": 0.5, "source": "gate.despawn"}, item)
	if _components_of(w, item).is_empty():
		push_error("the fixture item carried no components, so the assertion below is vacuous")
		return false
	w.despawn(item)
	var left: Array[String] = _components_of(w, item)
	if not left.is_empty():
		push_error("world.despawn left %d component(s) behind: %s" % [left.size(), str(left)])
		return false
	if str(w.modifiers.call("save")).contains("gate.despawn"):
		push_error("world.despawn left the entity's modifier scope in the table, and every save carries it")
		return false

	# Negative: the entity store on its own retires the id and nothing else. If this ever comes
	# back empty, the positive above has stopped proving anything.
	var ghost: int = SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 1})
	w.components.set_component(ghost, "position", {"x": 5.5, "y": 5.5})
	w.entities.call("despawn", ghost)
	if _components_of(w, ghost).is_empty():
		push_error("entities.despawn cleaned components up by itself, so this gate cannot fail")
		return false

	# And the shipped path that was leaking: consume ammo the way firing does, then ask the
	# query the renderer and every counter ask.
	var w2: Variant = SimBoot.bare()["world"]
	var arrows: int = SimItems.spawn_item(w2, "item.ammo.arrow", {"tier": "scavenged", "count": 1})
	SimInventory.make_inventory(w2, w2.player)
	if not SimInventory.store_anywhere(w2, arrows, w2.player):
		push_error("could not store the arrow the ammo assertion needs")
		return false
	if not SimRanged._consume_ammo(w2, int(w2.player), "item.ammo.arrow"):
		push_error("the ammo path refused to consume the arrow it was given")
		return false
	var dead: int = 0
	for e in w2.components.query(["itemBase"]):
		if not bool(w2.entities.call("is_alive", int(e))):
			dead += 1
	if dead > 0:
		push_error("firing left %d itemBase record(s) that components.query still returns for dead entities" % dead)
		return false
	print("DESPAWN-CLEAN OK components and modifier scope both go, and the raw store call still leaves them")
	return true


# Every component type that still holds a record for this id.
func _components_of(w: Variant, entity: int) -> Array[String]:
	var out: Array[String] = []
	var tables: Variant = w.components.get("_tables")
	if not (tables is Dictionary):
		push_error("component store shape changed; this assertion reads _tables")
		return out
	for key in (tables as Dictionary).keys():
		if ((tables as Dictionary)[key] as Dictionary).has(entity):
			out.append(String(key))
	out.sort()
	return out
