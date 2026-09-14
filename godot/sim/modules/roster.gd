class_name SimRoster
extends RefCounted

# Composition. The mix is content: every zombie type carries a `weight`, and one roll over the
# summed weights of the types whose `introducedInWave` has arrived picks the kind -- wave 0 from
# day 1, and each later wave `WAVE_DAY_STRIDE` days after the one before it (wave 1 on day
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
# A type that declares no `weight` counts as one share, the way a raider archetype does
# (`raider.schema.json`). The three shipped kinds declare 80 / 12 / 8, which is the mix that used
# to live here as three constants.
const DEFAULT_WEIGHT: int = 1


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


# Every zombie kind that can be drawn, as resolved entries (`extends` applied), sorted by id
# **descending**. The base is a template and not a kind -- it spawns nowhere and gets no art
# either, which is what `check_appearance.gd`'s ROSTER_EXEMPT says about the same id.
#
# Descending rather than ascending is deliberate and not decoration: any total order draws the
# same distribution, and this is the one that lists the shipped kinds shambler, screamer, bloater
# -- the order the three constants used to be written in -- so on the shipped 80 / 12 / 8 a roll
# of 0..79 is still a shambler, 80..91 still a screamer and 92..99 still a bloater. Every
# campaign therefore draws the same kind for the same roll as the hard-coded mix did.
# `check_m2_roster.gd`'s MIX lane pins the first fifty draws of seed 20260805 as a literal.
static func types(world: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.content == null or not (world.content is Dictionary):
		return out
	var ids: Array[String] = []
	for path in (world.content as Dictionary).keys():
		var raw: Variant = (world.content as Dictionary)[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry in entries:
			if not entry is Dictionary:
				continue
			var id: String = String((entry as Dictionary).get("id", ""))
			if not id.begins_with("zombie.") or id == TYPE_BASE or ids.has(id):
				continue
			ids.append(id)
	ids.sort()
	ids.reverse()
	for type_id in ids:
		var resolved: Variant = content_entry(world, type_id)
		if resolved is Dictionary:
			out.append(resolved as Dictionary)
	return out


# A type's share of the mix, and the one place the `weight` key is read. Omitted counts as
# `DEFAULT_WEIGHT`, and a declared **0 silences the type**: it is skipped and contributes nothing
# to the total, so it can never be drawn. The schema's `minimum: 1` keeps a 0 out of shipped
# content -- it is here so a fixture tree can take a kind off the table, which is how the MIX lane
# proves the weight is read at all. (`SimRaiders.pick_type` clamps with `maxi(1, ...)` instead and
# so cannot silence an archetype; the two differ on purpose, and only the zombie mix has a gate
# that needs the zero.)
static func weight_of(world: Variant, type_id: String) -> int:
	var entry: Variant = content_entry(world, type_id)
	if entry is Dictionary:
		return maxi(0, int((entry as Dictionary).get("weight", DEFAULT_WEIGHT)))
	return DEFAULT_WEIGHT


static func pick_type(world: Variant, rng: Variant, at_tick: int = -1) -> String:
	var tick: int = int(world.tick) if at_tick < 0 else at_tick
	var pool: Array[Dictionary] = []
	var total: int = 0
	for entry in types(world):
		var type_id: String = String(entry.get("id", ""))
		if not wave_allows(world, type_id, tick):
			continue
		var share: int = weight_of(world, type_id)
		if share <= 0:
			continue
		pool.append({"id": type_id, "weight": share})
		total += share
	# Nothing but the shambler on the table -- days 1 and 2, where the screamer and the bloater
	# are both wave 1 -- answers without a draw at all, which is what leaves the placement stream
	# on those days byte-identical to the stream before the mix was content.
	if total <= 0 or (pool.size() == 1 and String(pool[0]["id"]) == TYPE_SHAMBLER):
		return TYPE_SHAMBLER
	var roll: int = int(rng.call("int_range", 0, total - 1))
	for record in pool:
		roll -= int(record["weight"])
		if roll < 0:
			return String(record["id"])
	return String(pool[pool.size() - 1]["id"])


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
