class_name SimBloater
extends RefCounted

# blooms_on_death: scent 30 at corpse + a gas cloud over a disc, one roll a cloud a body.
# The cloud is a tile status field with a decay (docs/23, "The gassed bloater"): the burst writes a
# gas level of 1.0 into the cloud's component, the system decays it per tick, and the cloud is gone
# when the level reaches its threshold. Its numbers are the bloater's `gas` block in content; the
# module constants below are what a kind with no such block gets, and they are today's numbers.
# ponytail: replace the disc with a diffusive plume when scent floor/ceiling tuned; upgrade path is scent channel write + timed decay.

const SimRosterRes = preload("res://sim/modules/roster.gd")
const SimInfectionRes = preload("res://sim/modules/infection.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
# `is_person`, shared with shambler.gd and screamer.gd. A bloater's plume gets into any open
# wound in reach of it, and a raider standing in one has open wounds like anybody else.
const SimAllegiance = preload("res://sim/modules/allegiance.gd")

const SCENT_BURST: float = 30.0
const FLAG_RADIUS: float = 6.0
const FLAG_TICKS: int = 90 * 20
# A level at or under this is no gas. A millionth, not zero, so a level that is the sum of 1800
# subtractions of 1/1800 reads as gone on the tick it should, whatever the rounding.
const GAS_THRESHOLD: float = 0.000001
const EXTRA_CHANCE: float = 0.4
const STREAM: String = "contamination"


static func register_module(world: Variant) -> void:
	world.events.subscribe({"id": "bloater.bloom", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		var ent: int = int(event["entity"])
		var type_id: String = String(event.get("zombieType", ""))
		if type_id == "":
			var zt: Variant = world.components.get_component(ent, "zombieType")
			if zt is Dictionary:
				type_id = String((zt as Dictionary).get("id", ""))
		if type_id == "" or not SimRosterRes.has_behavior(world, type_id, "blooms_on_death"):
			return
		var x: float = float(event.get("x", 0.0))
		var y: float = float(event.get("y", 0.0))
		if not event.has("x") or not event.has("y"):
			var pos: Variant = world.components.get_component(ent, "position")
			if pos is Dictionary:
				x = float((pos as Dictionary)["x"])
				y = float((pos as Dictionary)["y"])
		world.events.publish({"type": "scent.accumulated", "x": x, "y": y, "magnitude": SCENT_BURST})
		var gas: Dictionary = gas_of(world, type_id)
		var flag: int = int(world.entities.spawn())
		world.components.set_component(flag, "position", {"x": x, "y": y})
		# The level starts at 1.0 and is what the reader judges. `expiresAtTick` is the nominal end
		# of a cloud born now at the decay rate, kept so anything that reads an end tick still does.
		world.components.set_component(flag, "contamination", {
			"radius": float(gas["radius"]),
			"expiresAtTick": int(world.tick) + int(gas["lingerTicks"]),
			"source": ent,
			"level": 1.0,
			"bornAtTick": int(world.tick),
			"decayPerTick": float(gas["decayPerTick"]),
			"threshold": float(gas["threshold"]),
			"hurtEvery": int(gas["hurtEvery"]),
		})
	})

	world.systems.register("bloater.contamination", "infection", 20, func(w: Variant) -> void:
		var rng: Variant = w.rng.stream(STREAM)
		var flags: Array = []
		for entity in w.components.query(["contamination", "position"]):
			var c: Variant = w.components.get_component(int(entity), "contamination")
			if c == null:
				continue
			var cd: Dictionary = c as Dictionary
			var level: float = _level_now(cd, int(w.tick))
			if level <= float(cd.get("threshold", GAS_THRESHOLD)):
				w.despawn(int(entity))
				continue
			flags.append({"entity": int(entity), "x": float((w.components.get_component(int(entity), "position") as Dictionary)["x"]), "y": float((w.components.get_component(int(entity), "position") as Dictionary)["y"]), "radius": float(cd.get("radius", FLAG_RADIUS)), "source": int(cd.get("source", 0)), "born": _born_of(cd), "hurtEvery": maxi(1, int(cd.get("hurtEvery", FLAG_TICKS)))})
		if flags.is_empty():
			return
		for survivor in w.components.query(["position"]):
			if not SimAllegiance.is_person(w, int(survivor)):
				continue
			if not _has_open_wound(w, int(survivor)):
				continue
			# One roll a cloud, not one a survivor for the whole campaign: `contaminationRolled`
			# was a single flag set on the first cloud and never cleared, so every bloater after
			# the first bloomed over a body that could not be exposed again. The rolls are an
			# Array of `{flag, atTick, window}` records keyed by the cloud's entity (never an id-keyed
			# Dictionary -- CLAUDE.md's save trap), scanned by index.
			#
			# `window` is which `hurtEvery` span of the cloud's life the roll falls in. Its default is
			# the whole life, so a cloud rolls once, as it always did; a record with no window was
			# written before there was one and is window 0.
			var rolls_comp: Variant = w.components.get_component(int(survivor), "contaminationRolls")
			if not rolls_comp is Dictionary:
				rolls_comp = {"rolls": []}
				w.components.set_component(int(survivor), "contaminationRolls", rolls_comp)
			var rolls: Array = (rolls_comp as Dictionary)["rolls"] as Array
			var pos: Variant = w.components.get_component(int(survivor), "position")
			if pos == null:
				continue
			var px: float = float((pos as Dictionary)["x"])
			var py: float = float((pos as Dictionary)["y"])
			for f in flags:
				var fd: Dictionary = f as Dictionary
				var dx: float = px - float(fd["x"])
				var dy: float = py - float(fd["y"])
				var r: float = float(fd["radius"])
				if dx * dx + dy * dy > r * r:
					continue
				var window: int = int((int(w.tick) - int(fd["born"])) / int(fd["hurtEvery"]))
				var rolled: bool = false
				for row in rolls:
					if int((row as Dictionary).get("flag", -1)) == int(fd["entity"]) and int((row as Dictionary).get("window", 0)) == window:
						rolled = true
						break
				if rolled:
					continue
				rolls.append({"flag": int(fd["entity"]), "atTick": int(w.tick), "window": window})
				# The mask that filters, the owner's call of 2026-09-12. What the survivor has on
				# is read here, at the roll, and folded into the chance the plume gets in: best
				# worn wins, composed by max, the same way `armor_coverage_of` composes what turns
				# a tooth. Before this the roll was flat proximity and a cloth mask was worth
				# exactly a bike helmet against a cloud.
				#
				# The draw is spent either way. `record_extra_exposure` takes exactly one number
				# off the `contamination` stream whatever the chance is, so a filtered survivor and
				# a bare one stay in step on the same seed -- which is what lets check_m2_filter's
				# CLOUD lane compare them roll for roll instead of sampling twice and hoping.
				#
				# Extra exposure. Do not flip an existing transmitted flag.
				var got_through: float = EXTRA_CHANCE * (1.0 - SimInfectionRes.filter_of(w, int(survivor)))
				SimInfectionRes.record_extra_exposure(w, int(survivor), int(fd["source"]), rng, got_through)
	)


# The gas numbers a kind's cloud is built with: its content `gas` block where it declares one, and
# the module's constants where it does not. A key the block omits keeps its constant.
static func gas_of(world: Variant, type_id: String) -> Dictionary:
	var out: Dictionary = {
		"radius": FLAG_RADIUS,
		"lingerTicks": FLAG_TICKS,
		"decayPerTick": 1.0 / float(FLAG_TICKS),
		"threshold": GAS_THRESHOLD,
		"hurtEvery": FLAG_TICKS,
	}
	var entry: Variant = SimRosterRes.content_entry(world, type_id)
	if entry is Dictionary and (entry as Dictionary).get("gas") is Dictionary:
		var block: Dictionary = (entry as Dictionary)["gas"] as Dictionary
		for key in out.keys():
			if block.has(key):
				out[key] = float(block[key]) if typeof(out[key]) == TYPE_FLOAT else int(block[key])
	return out


# The gas level a cloud has now. A cloud that carries a level decays it once per tick, here, and
# stores the result. A cloud that does not (a fixture written before the field, or a save from
# before it) reads its level off its nominal end: what is left of its life over its lingering.
# The two agree: a cloud born at 1.0 and decayed 1/lingering a tick reaches the same value as one
# whose end is `lingering` ticks off.
static func _level_now(cd: Dictionary, tick: int) -> float:
	if cd.has("level"):
		var level: float = float(cd["level"]) - float(cd.get("decayPerTick", 1.0 / float(FLAG_TICKS)))
		cd["level"] = level
		return level
	var lingering: float = float(FLAG_TICKS)
	return float(int(cd.get("expiresAtTick", 0)) - tick) / lingering


# The tick a cloud was born on. A cloud with no birth tick (before the field) is taken as born
# `FLAG_TICKS` before its nominal end.
static func _born_of(cd: Dictionary) -> int:
	if cd.has("bornAtTick"):
		return int(cd["bornAtTick"])
	return int(cd.get("expiresAtTick", 0)) - FLAG_TICKS


# An open wound is one whose kind bleeds: a bite, a cut, a burn. The kind table says which, because
# severity cannot -- a fracture is hurt badly and its skin is shut. Matching "bite" alone kept a
# plume out of a laceration and a burn.
static func _has_open_wound(world: Variant, entity: int) -> bool:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if inj == null:
		return false
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	for w in wounds:
		var wd: Dictionary = w as Dictionary
		if bool(SimWounds.kind_spec(String(wd.get("kind", "cut"))).get("bleeds", false)):
			return true
	return false
