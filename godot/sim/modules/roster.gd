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
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
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

# Every per-body look roll comes off this stream and nothing else does. It has its own name for
# the reason CLAUDE.md gives: `spawn_zombie` is handed `placement` at boot and `director` at
# night, and a draw threaded into either would shift every roll after it and move every campaign
# that already exists. `check_m2_variance.gd` STREAM holds that -- the placement state after a
# boot is pinned to the number the tree printed before a line of this was written.
const LOOK_STREAM: String = "zombieLook"

# The ceiling `zombie.schema.json` documents, said once here as well so a content edit that
# somehow got past the schema still cannot make a kind stop being one kind.
const MAX_BODY_VARIANCE: float = 0.3


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


# The type's `variance` block (`extends` applied), or {} for a kind that declares none.
static func _variance_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = content_entry(world, type_id)
	if entry is Dictionary:
		var v: Variant = (entry as Dictionary).get("variance")
		if v is Dictionary:
			return v as Dictionary
	return {}


# What makes one body itself rather than another of its kind: {tint, scale, crawler}, rolled once
# at spawn on `LOOK_STREAM`.
#
# A kind with no `variance` block draws **nothing at all** and gets {} back -- the uniform body
# every kind was before this landed, and the half of the STREAM claim a gate can drive from
# content instead of from a flag.
#
# Draw order is fixed -- tint, then size, then the crawler roll -- because it is the order every
# saved campaign replays. The tint draw is skipped when there is nothing to pick from (`rng.pick`
# asserts on an empty array); the other two are always made, so a kind declaring `body: 0` costs
# the same two rolls as one declaring 0.15 and retuning a number cannot reshuffle the bodies
# spawned after it.
static func roll_look(world: Variant, type_id: String) -> Dictionary:
	var variance: Dictionary = _variance_of(world, type_id)
	if variance.is_empty():
		return {}
	var rng: Variant = world.rng.stream(LOOK_STREAM)
	var tint: String = ""
	var tints: Variant = variance.get("tints")
	if tints is Array and not (tints as Array).is_empty():
		tint = String(rng.call("pick", tints as Array))
	var spread: float = clampf(float(variance.get("body", 0.0)), 0.0, MAX_BODY_VARIANCE)
	var scale: float = float(rng.call("float_range", 1.0 - spread, 1.0 + spread))
	var crawler: bool = bool(rng.call("bool_chance", clampf(float(variance.get("crawlers", 0.0)), 0.0, 1.0)))
	return {"tint": tint, "scale": scale, "crawler": crawler}


# Every part of a body times one scale, whole numbers, never under 1.
#
# Both `body` and `bodyMax` are built from this, and that is the whole point: the CLAUDE.md trap
# is that body parts do not share a scale -- a whole head is 25 where a whole torso is 60 -- and
# `SimHealth.part_state_of` is the one normaliser. Scale the current integrity without scaling
# the maximum beside it and a big body is born Hurt while a small one is hard to hurt at all.
static func _scaled_body(body: Dictionary, scale: float) -> Dictionary:
	if is_equal_approx(scale, 1.0):
		return body
	var out: Dictionary = {}
	for part in body.keys():
		out[part] = maxf(1.0, round(float(body[part]) * scale))
	return out


static func spawn_zombie(world: Variant, x: float, y: float, type_id: String, rng: Variant) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "facing", {"radians": 0.0})
	# Never off `rng`, which is `placement` at boot and `director` at night -- see `roll_look`.
	var look: Dictionary = roll_look(world, type_id)
	# `tint` is always on the component, "" when the kind names no palette, so a save round-trips
	# one shape rather than two. Read by main.gd's entity pass and resolved by
	# `Appearance.for_entity`, which takes a non-empty stored tint over the content block's.
	# A pass-through, the way a colonist's `identity.look` already is: the draw loop carries a
	# value content decided and decides nothing itself, so there is still no branch on an id in
	# it. The difference from `identity.look`, and the reason it is a hex rather than an id, is
	# in docs/30 -- one content entry per body is a registry that grows with the population.
	world.components.set_component(ent, "zombieType", {"id": type_id, "tint": String(look.get("tint", ""))})
	var body: Dictionary = _scaled_body(_body_of(world, type_id), float(look.get("scale", 1.0)))
	# The type's own maxima, so `part_state_of` judges a screamer's torso against its 40 and
	# not the shared table's 60 (health.gd) -- and, since the size roll, so a body scaled up is
	# judged against its *own* bigger torso rather than being born two thirds hurt.
	world.components.set_component(ent, "bodyMax", body.duplicate())
	# The legs are destroyed after the maxima are taken, deliberately: a crawler is a body whose
	# legs are gone, not a body that never had any, so `bodyMax` keeps the number `part_state_of`
	# reads Unusable against and `SimHealth.is_crawling` answers exactly as it does for a shambler
	# whose legs were shot out. No second locomotion path -- `SimShambler._speed_of` applies
	# `crawlFactor` to what this leaves behind, which is the reader `crawlFactor` waited a
	# milestone for.
	if bool(look.get("crawler", false)) and body.has("legs"):
		body["legs"] = 0.0
	world.components.set_component(ent, "body", body)
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
	_wear_the_kit(world, ent, type_id, x, y)
	return ent


# What a body of this kind is wearing, from the resolved entry's `worn` list. A kind that
# declares none gets [] and the block below is skipped entirely, so nothing about a shambler
# changed: no inventory, no equipment, no `lootKit`.
static func worn_of(world: Variant, type_id: String) -> Array[String]:
	var out: Array[String] = []
	var entry: Variant = content_entry(world, type_id)
	if entry is Dictionary and (entry as Dictionary).get("worn") is Array:
		for id in (entry as Dictionary)["worn"] as Array:
			var s: String = String(id)
			if not s.is_empty():
				out.append(s)
	return out


# Armour on something that is not a survivor -- docs/23's open defect, closed here, and closed
# with no new arithmetic anywhere. `SimInfection.armor_coverage_of` reads the target's
# `equipment` and has never asked whose body it is; `SimHealth.armor_damage_factor` multiplies
# by it inside `damage_part`, the one closure in the sim that moves integrity. What was missing
# was only that a zombie had no `equipment` component to read, so an armoured kind could not
# exist. Giving one an inventory and equipping its `worn` list is the whole mechanism.
#
# `SimRecruits._turn_with_kit` is the precedent and the shape is deliberately its shape: an
# inventory, the gear on the body, and `lootKit` so `SimRecruits._drop_kit` puts it on the floor
# when the body goes down -- which is already what the shambler arm of `handle_death` calls. So
# the armour a kind wears is armour the colony can take off it, which is what keeps an armoured
# kind a loot source rather than only a wall. check_m2_armored.gd WORN and DROP.
#
# A piece that will not go on (a slot `EQUIP_SLOTS` does not know, two things wanting one slot)
# is dropped at the body's feet rather than silently despawned, because an item that reaches
# neither a slot nor the ground is an entity nothing can ever find -- and the gate's WORN lane
# reads the slots, so a piece that quietly failed to fit would be caught rather than hidden.
#
# Determinism: this makes no draw of its own, and `SimItems.spawn_item` touches only the `loot`
# stream -- never `placement` or `director`, the two streams `spawn_zombie` is handed.
# check_m2_variance.gd's STREAM pin is what holds that.
static func _wear_the_kit(world: Variant, ent: int, type_id: String, x: float, y: float) -> void:
	var worn: Array[String] = worn_of(world, type_id)
	if worn.is_empty():
		return
	SimInventoryRes.make_inventory(world, ent)
	for item_id in worn:
		var item: int = SimItemsRes.spawn_item(world, item_id, {"tier": "scavenged"})
		if not SimInventoryRes.equip(world, ent, item):
			world.components.set_component(item, "position", {"x": x, "y": y})
	world.components.set_component(ent, "lootKit", {})


# The bodies the generator left asleep indoors, made into entities -- `SimVehicles.spawn_from_manifest`
# for zombies, and deliberately the same shape: the manifest says where, this says what, and from
# here on the entity is the truth and the record is only where it started. Called by
# `SimBoot.playable` straight after the parked cars and before the outdoor scatter, so a dormant
# body is in the district before the first tick rather than conjured when somebody opens a door.
#
# Why a manifest at all, since a lazy spawn would have been less code: the owner's call of
# 2026-09-14. A body that appears when the player walks in makes the district's population a
# function of where the player has been -- docs/17's "the director is not a spawner" refuses that,
# and the balance harness, which counts bodies and never walks anywhere, could not see them at all.
#
# Determinism: its own `dormant` stream, and `pick_type` is asked at the **day-1 tick** rather than
# at `world.tick`, because these bodies have been lying there since before the game started and the
# wave schedule is about what the nights bring. On day 1 nothing but the shambler is due, so
# `pick_type` short-circuits without a draw and every one of them is a shambler -- which is what
# the gate asserts, and what keeps this pass free to grow a mix later without re-rolling the past.
# A record refused below has already cost its type draw (the vehicles rule); a refusal here means a
# malformed manifest, which is a code bug rather than a content one, so it is loud.
static func spawn_dormant_from_manifest(world: Variant, map: Variant) -> Array[int]:
	var spawned: Array[int] = []
	if map == null:
		return spawned
	var records: Variant = map.get("dormant")
	if not (records is Array):
		return spawned
	if (records as Array).is_empty():
		return spawned
	var rng: Variant = world.rng.stream("dormant")
	var day_one: int = Clock.tick_on_day(1, Clock.DAY_BEGINS)
	for rec in records as Array:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec as Dictionary
		var type_id: String = pick_type(world, rng, day_one)
		if not (r.has("x") and r.has("y")):
			push_error("dormant: record %s names no tile, so nothing was put to sleep in it" % str(r))
			continue
		var ent: int = spawn_zombie(world, float(r["x"]) + 0.5, float(r["y"]) + 0.5, type_id, rng)
		SimShamblerRes.make_dormant(world, ent)
		spawned.append(ent)
	return spawned
