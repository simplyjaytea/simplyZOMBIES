class_name SimRoster
extends RefCounted

# Fake-wave composition for early alpha. Ticket 01: day 0–2 shambler-only, then 80/12/8.
# Clock.day_number is 1-indexed; shambler-only while day_number < FAKE_WAVE_DAY.

const SimShamblerRes = preload("res://sim/modules/shambler.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimCombatRes = preload("res://sim/combat.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const Clock = preload("res://sim/time/clock.gd")

const TYPE_SHAMBLER: String = "zombie.shambler"
const TYPE_SCREAMER: String = "zombie.screamer"
const TYPE_BLOATER: String = "zombie.bloater"

const FAKE_WAVE_DAY: int = 3
const MIX_SHAMBLER: int = 80
const MIX_SCREAMER: int = 12
const MIX_BLOATER: int = 8


static func content_entry(world: Variant, type_id: String) -> Variant:
	return SimShamblerRes._get_content_entry(world, "zombie", type_id)


static func has_behavior(world: Variant, type_id: String, tag: String) -> bool:
	var entry: Variant = content_entry(world, type_id)
	if entry == null:
		return false
	var behaviours: Variant = (entry as Dictionary).get("behaviors")
	return behaviours is Array and (behaviours as Array).has(tag)


static func pick_type(world: Variant, rng: Variant, at_tick: int = -1) -> String:
	var tick: int = int(world.tick) if at_tick < 0 else at_tick
	if Clock.day_number(tick) < FAKE_WAVE_DAY:
		return TYPE_SHAMBLER
	var roll: int = int(rng.call("int_range", 0, 99))
	if roll < MIX_SHAMBLER:
		return TYPE_SHAMBLER
	if roll < MIX_SHAMBLER + MIX_SCREAMER:
		return TYPE_SCREAMER
	return TYPE_BLOATER


static func _body_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = content_entry(world, type_id)
	if entry != null:
		var b: Variant = (entry as Dictionary).get("body")
		if b is Dictionary:
			return (b as Dictionary).duplicate()
	return SimCombatRes.ZOMBIE_BODY.duplicate()


static func spawn_zombie(world: Variant, x: float, y: float, type_id: String, rng: Variant) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "facing", {"radians": 0.0})
	world.components.set_component(ent, "zombieType", {"id": type_id})
	world.components.set_component(ent, "body", _body_of(world, type_id))
	SimShamblerRes.make_shambler(world, ent, rng, type_id)
	if has_behavior(world, type_id, "alarm_on_sight"):
		var eyes: Dictionary = SimVisibility.shambler_eyes()
		world.components.set_component(ent, "observer", eyes)
		var alarm: Dictionary = {}
		var entry: Variant = content_entry(world, type_id)
		if entry != null and (entry as Dictionary).has("alarm"):
			alarm = ((entry as Dictionary)["alarm"] as Dictionary).duplicate()
		if alarm.is_empty():
			alarm = {"magnitude": 300, "relay": true, "cooldownTicks": 600}
		alarm["ticksUntilReady"] = 0
		world.components.set_component(ent, "alarm", alarm)
	return ent
