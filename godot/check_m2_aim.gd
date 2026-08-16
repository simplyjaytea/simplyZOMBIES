extends SceneTree
# Aiming sway: cone half-angle tightens on Steady, widens when moving (ADR 0012).

const SimBoot = preload("res://sim/boot.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var boot: Dictionary = SimBoot.playable(20260805, 64)
	var w: Variant = boot["world"]
	var player: int = int(w.player)
	var bow: int = SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"})
	if not SimInventory.equip(w, player, bow):
		push_error("equip failed")
		quit(1)
		return
	w.events.drain()
	var rw: Variant = w.components.get_component(player, "rangedWeapon")
	if not rw is Dictionary:
		# Fallback: profile attach (equip event may be gated by kit)
		var profile: Variant = SimItems.ranged_profile_of(w, bow)
		if profile == null:
			push_error("no ranged profile")
			quit(1)
			return
		SimRanged.make_ranged_armed(w, player, profile as Dictionary)
		rw = w.components.get_component(player, "rangedWeapon")
	if not rw is Dictionary:
		push_error("no rangedWeapon")
		quit(1)
		return
	(rw as Dictionary)["state"] = SimRanged.FireState.Raise
	(rw as Dictionary)["ticksLeft"] = SimRanged.RAISE_TICKS
	var vel: Variant = w.components.get_component(player, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0
	SimRanged._refresh_cone(w, player, rw as Dictionary)
	var raise_half: float = float((rw as Dictionary)["coneHalf"])
	(rw as Dictionary)["state"] = SimRanged.FireState.Steady
	(rw as Dictionary)["ticksLeft"] = 1
	SimRanged._refresh_cone(w, player, rw as Dictionary)
	var steady_half: float = float((rw as Dictionary)["coneHalf"])
	if steady_half >= raise_half:
		push_error("steady should tighten: raise=%s steady=%s" % [raise_half, steady_half])
		quit(1)
		return
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 2.0
	SimRanged._refresh_cone(w, player, rw as Dictionary)
	var move_half: float = float((rw as Dictionary)["coneHalf"])
	if move_half < SimRanged.WIDE_HALF - 0.001:
		push_error("moving should widen to WIDE: %s" % move_half)
		quit(1)
		return
	print("AIM OK raise %.3f steady %.3f move %.3f" % [raise_half, steady_half, move_half])
	print("M2_AIM_OK cone sway")
	quit(0)
