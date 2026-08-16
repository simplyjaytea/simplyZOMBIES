extends SceneTree
# Wear on hit + Repair ceiling drop (ADR 0014).

const SimBoot = preload("res://sim/boot.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = _wear() and _repair() and _focus()
	if ok:
		print("M2_UPKEEP_OK wear broke repair")
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
	w.events.publish({"type": "attack.connected", "attacker": player, "target": 0, "bodyPart": "torso", "damage": 1})
	w.events.drain()
	var after: float = float((w.components.get_component(knife, "condition") as Dictionary).get("current", 1.0))
	if after >= before:
		push_error("no wear %s→%s" % [str(before), str(after)])
		return false
	# Break
	cond["current"] = SimItems.WEAR_PER_HIT
	w.events.publish({"type": "attack.connected", "attacker": player, "target": 0, "bodyPart": "torso", "damage": 1})
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
	var work: Dictionary = SimJobs._repair_work(w, mara, 46.0, 45.0)
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
