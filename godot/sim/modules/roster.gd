class_name SimRoster
extends RefCounted

# Composition. The mix is 80/12/8 among the types whose `introducedInWave` has arrived: wave 0
# from day 1, and each later wave `WAVE_DAY_STRIDE` days after the one before it (wave 1 on day
# FAKE_WAVE_DAY, 3 -- the day the old hard-coded rule opened the mix). Clock.day_number is
# 1-indexed. A draw is only made when something other than the shambler is on the table, so the
# placement stream is untouched on the shambler-only days it was untouched on before.

const SimShamblerRes = preload("res://sim/modules/shambler.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimCombatRes = preload("res://sim/combat.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimAttentionEmitter = preload("res://sim/modules/attention_emitter.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const Clock = preload("res://sim/time/clock.gd")

const TYPE_BASE: String = "zombie.base"
const TYPE_SHAMBLER: String = "zombie.shambler"
const TYPE_SCREAMER: String = "zombie.screamer"
const TYPE_BLOATER: String = "zombie.bloater"

const FAKE_WAVE_DAY: int = 3
const WAVE_DAY_STRIDE: int = FAKE_WAVE_DAY - 1
const MIX_SHAMBLER: int = 80
const MIX_SCREAMER: int = 12
const MIX_BLOATER: int = 8


# The resolved entry -- `extends` applied, per world. See SimShambler.resolved_entry.
static func content_entry(world: Variant, type_id: String) -> Variant:
	return SimShamblerRes.resolved_entry(world, type_id)


static func first_day_of_wave(wave: int) -> int:
	return 1 + maxi(wave, 0) * WAVE_DAY_STRIDE


# Whether a type's `introducedInWave` has arrived by the day of `tick`. A type with no entry, or
# no wave, is wave 0.
static func wave_allows(world: Variant, type_id: String, tick: int) -> bool:
	var wave: int = 0
	var entry: Variant = content_entry(world, type_id)
	if entry is Dictionary:
		wave = int((entry as Dictionary).get("introducedInWave", 0))
	return Clock.day_number(tick) >= first_day_of_wave(wave)


static func has_behavior(world: Variant, type_id: String, tag: String) -> bool:
	var entry: Variant = content_entry(world, type_id)
	if entry == null:
		return false
	var behaviours: Variant = (entry as Dictionary).get("behaviors")
	return behaviours is Array and (behaviours as Array).has(tag)


static func pick_type(world: Variant, rng: Variant, at_tick: int = -1) -> String:
	var tick: int = int(world.tick) if at_tick < 0 else at_tick
	var screamer_due: bool = wave_allows(world, TYPE_SCREAMER, tick)
	var bloater_due: bool = wave_allows(world, TYPE_BLOATER, tick)
	if not screamer_due and not bloater_due:
		return TYPE_SHAMBLER
	var roll: int = int(rng.call("int_range", 0, 99))
	if roll < MIX_SHAMBLER:
		return TYPE_SHAMBLER
	if roll < MIX_SHAMBLER + MIX_SCREAMER:
		return TYPE_SCREAMER if screamer_due else TYPE_SHAMBLER
	return TYPE_BLOATER if bloater_due else TYPE_SHAMBLER


# The `emits` block as an attention emitter: `{channel, magnitude}` records, summed per channel.
static func emitter_of(world: Variant, type_id: String) -> Dictionary:
	var out: Dictionary = {"walking": 0.0, "sprinting": 0.0, "ambient": 0.0, "scent": 0.0}
	for em in _emits_of(world, type_id):
		var channel: String = String((em as Dictionary).get("channel", ""))
		var magnitude: float = float((em as Dictionary).get("magnitude", 0.0))
		if channel == "noise":
			out["walking"] = float(out["walking"]) + magnitude
			out["sprinting"] = float(out["sprinting"]) + magnitude
			out["ambient"] = float(out["ambient"]) + magnitude
		elif channel == "scent":
			out["scent"] = float(out["scent"]) + magnitude
	return out


# The `emits` block's light, as metres of reach -- the largest, since the light index takes the
# max across sources and never the sum.
static func light_of(world: Variant, type_id: String) -> float:
	var best: float = 0.0
	for em in _emits_of(world, type_id):
		if String((em as Dictionary).get("channel", "")) == "light":
			best = maxf(best, float((em as Dictionary).get("magnitude", 0.0)))
	return best


static func _emits_of(world: Variant, type_id: String) -> Array:
	var entry: Variant = content_entry(world, type_id)
	if entry is Dictionary and (entry as Dictionary).get("emits") is Array:
		var out: Array = []
		for em in (entry as Dictionary)["emits"] as Array:
			if em is Dictionary:
				out.append(em)
		return out
	return []


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
	var body: Dictionary = _body_of(world, type_id)
	world.components.set_component(ent, "body", body)
	# The type's own maxima, so `part_state_of` judges a screamer's torso against its 40 and
	# not the shared table's 60 (health.gd).
	world.components.set_component(ent, "bodyMax", body.duplicate())
	SimShamblerRes.make_shambler(world, ent, rng, type_id)
	# Every zombie has eyes (the owner's decision 3, docs/30 "The playable state"): sight is a
	# stimulus in shambler.think, and it was the screamer's alone until then.
	world.components.set_component(ent, "observer", SimVisibility.shambler_eyes())
	# And every zombie writes to the field from its resolved `emits` block (decision 11): noise
	# is what the body gives off standing or walking (the noisemaker's shape -- a groan is not
	# a footstep), scent is laid every SCENT_EMIT_INTERVAL in every state, which is the residue
	# `field_memory.gd` used to lay only while Investigating, and light makes the body a source.
	# A type with no `emits` carries an emitter of zeros -- present, so a save round-trips one
	# shape, and silent. `check_m2_roster.gd` EMITS and RESIDUE.
	SimAttentionEmitter.make_emitter(world, ent, emitter_of(world, type_id))
	var glow: float = light_of(world, type_id)
	if glow > 0.0:
		SimLightMod.make_light_source(world, ent, glow)
	if has_behavior(world, type_id, "alarm_on_sight"):
		var alarm: Dictionary = {}
		var entry: Variant = content_entry(world, type_id)
		if entry != null and (entry as Dictionary).has("alarm"):
			alarm = ((entry as Dictionary)["alarm"] as Dictionary).duplicate()
		if alarm.is_empty():
			alarm = {"magnitude": 300, "relay": true, "cooldownTicks": 600}
		alarm["ticksUntilReady"] = 0
		world.components.set_component(ent, "alarm", alarm)
	return ent
