class_name SimScreamer
extends RefCounted

# alarm_on_sight: one noise.emitted 300 when detail != Unseen, then cooldown.
# Visibility lives on world.vision (kernel). Missing vision = no alarm (tests without eyes).

const SimVisibility = preload("res://sim/vision/visibility.gd")
# `is_person`, shared with shambler.gd and bloater.gd. A screamer raises the district over
# anybody it can see, and a raider is somebody: the alarm does not check whose side you are on.
const SimAllegiance = preload("res://sim/modules/allegiance.gd")


static func register_module(world: Variant) -> void:
	world.systems.register("screamer.alarm", "combat", -10, func(w: Variant) -> void:
		if w.vision == null:
			return
		var survivors: Array = []
		for entity in w.components.query(["position"]):
			if not SimAllegiance.is_person(w, int(entity)):
				continue
			# A corpse keeps identity (gear stays on the body per ADR 0013), so is_person alone
			# would leave a dead colonist ringing the alarm forever. enemies_of already excludes
			# corpses for the same reason (allegiance.gd:72-74); mirrored here rather than
			# widened into is_person, which shambler.gd and bloater.gd also share.
			if w.components.has_component(int(entity), "corpse"):
				continue
			var at: Variant = w.components.get_component(int(entity), "position")
			if at == null:
				continue
			survivors.append({"x": float((at as Dictionary)["x"]), "y": float((at as Dictionary)["y"])})
		if survivors.is_empty():
			return
		for entity in w.components.query(["position", "observer", "alarm"]):
			var alarm: Variant = w.components.get_component(int(entity), "alarm")
			if alarm == null:
				continue
			var ad: Dictionary = alarm as Dictionary
			var left: int = int(ad.get("ticksUntilReady", 0))
			if left > 0:
				ad["ticksUntilReady"] = left - 1
				continue
			var seen: bool = false
			for s in survivors:
				var sd: Dictionary = s as Dictionary
				if int(w.vision.call("detail", int(entity), float(sd["x"]), float(sd["y"]))) != SimVisibility.Detail.Unseen:
					seen = true
					break
			if not seen:
				continue
			var pos: Variant = w.components.get_component(int(entity), "position")
			if pos == null:
				continue
			var mag: float = float(ad.get("magnitude", 300))
			w.events.publish({
				"type": "noise.emitted",
				"x": float((pos as Dictionary)["x"]),
				"y": float((pos as Dictionary)["y"]),
				"magnitude": mag,
				"source": int(entity),
			})
			ad["ticksUntilReady"] = int(ad.get("cooldownTicks", 600))
	)
