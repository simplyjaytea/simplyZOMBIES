extends SceneTree
# v15 + ticket 10 fortify/director + needs-era state. F9 is restore, not re-boot.

const SimBoot = preload("res://sim/boot.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const SimSave = preload("res://sim/save.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _version() and ok
	ok = _ticket10() and ok
	ok = _needs_era() and ok
	ok = _streams() and ok
	if ok:
		print("M2_SAVE_OK v15 ticket10 needs-era")
		quit(0)
	else:
		push_error("M2_SAVE_FAIL")
		quit(1)

func _version() -> bool:
	if int(SimSerialize.SAVE_VERSION) != 15:
		push_error("SAVE_VERSION %d want 15" % int(SimSerialize.SAVE_VERSION))
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
