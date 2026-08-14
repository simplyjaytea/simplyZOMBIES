class_name SimAptitudes
extends RefCounted

# Stats MVP per .scratch/simplyzombies/issues/02-stats-mvp.md and docs/23.
# STR/CON/DEX only. Missing keys default to midpoint 5 so alpha saves survive the six-stat upgrade.
# Consumers read SimModifiers sources attr.str / attr.dex / attr.con — never raw arithmetic on bodies.

const MIN: int = 3
const MAX: int = 8
const DEFAULT: int = 5
const BUDGET: int = 15
const SOURCE_STR: String = "attr.str"
const SOURCE_DEX: String = "attr.dex"
const SOURCE_CON: String = "attr.con"

# Ticket 04 / shipped oracle: P = power / (power + ΣgrabStrength), baseline 1.0 → 2/3 vs one shambler 0.5.
# Ticket 02's 0.50 figure was the shambler term, not the numerator; STR adds ±0.10/pt around 5.
const STR_CARRY_PER: float = 3.0
const STR_ESCAPE_PER: float = 0.10
const CON_INFECTION_PER: float = 0.05
const CON_DAMAGE_PER: float = 0.04
const DEX_SPEED_PER: float = 0.06


static func normalize(raw: Variant) -> Dictionary:
	var d: Dictionary = raw as Dictionary if raw is Dictionary else {}
	return {
		"str": _clamp_stat(d.get("str", DEFAULT)),
		"dex": _clamp_stat(d.get("dex", DEFAULT)),
		"con": _clamp_stat(d.get("con", DEFAULT)),
	}


static func _clamp_stat(v: Variant) -> int:
	return clampi(int(v) if v != null else DEFAULT, MIN, MAX)


static func apply(world: Variant, entity: int, raw: Variant = null) -> Dictionary:
	var apt: Dictionary = normalize(raw)
	world.components.set_component(entity, "aptitudes", apt)
	var mods: Variant = world.modifiers
	if mods != null and (mods as Object).has_method("remove_by_source"):
		mods.call("remove_by_source", SOURCE_STR, entity)
		mods.call("remove_by_source", SOURCE_DEX, entity)
		mods.call("remove_by_source", SOURCE_CON, entity)
	var str_n: int = int(apt["str"])
	var dex_n: int = int(apt["dex"])
	var con_n: int = int(apt["con"])
	# High CON lengthens the timeline (docs/06, docs/23): infection_progression is a rate, duration = base/rate.
	# ponytail: ticket 02 table wrote +0.05 which would shorten; sign follows "lengthens" prose.
	if mods != null and (mods as Object).has_method("add"):
		mods.call("add", {"stat": "carry_capacity", "op": "add", "value": STR_CARRY_PER * float(str_n - DEFAULT), "source": SOURCE_STR}, entity)
		mods.call("add", {"stat": "grab_escape", "op": "add", "value": STR_ESCAPE_PER * float(str_n - DEFAULT), "source": SOURCE_STR}, entity)
		mods.call("add", {"stat": "move_speed", "op": "add", "value": DEX_SPEED_PER * float(dex_n - DEFAULT), "source": SOURCE_DEX}, entity)
		mods.call("add", {"stat": "infection_progression", "op": "add", "value": -CON_INFECTION_PER * float(con_n - DEFAULT), "source": SOURCE_CON}, entity)
		mods.call("add", {"stat": "damage_taken", "op": "add", "value": -CON_DAMAGE_PER * float(con_n - DEFAULT), "source": SOURCE_CON}, entity)
	return apt


static func of(world: Variant, entity: int) -> Dictionary:
	var raw: Variant = world.components.get_component(entity, "aptitudes")
	return normalize(raw)


static func escape_chance(world: Variant, entity: int, total_grab_strength: float) -> float:
	var power: float = 1.0
	if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
		power = float(world.modifiers.call("resolve", "grab_escape", entity))
	if power <= 0.0:
		return 0.0
	return power / (power + maxf(0.0, total_grab_strength))


static func compositions() -> Array[Dictionary]:
	# Every integer triple in [3,8] summing to 15, sorted for deterministic roll.
	var out: Array[Dictionary] = []
	for s in range(MIN, MAX + 1):
		for d in range(MIN, MAX + 1):
			var c: int = BUDGET - s - d
			if c < MIN or c > MAX:
				continue
			out.append({"str": s, "dex": d, "con": c})
	return out


static func roll(world: Variant) -> Dictionary:
	var pool: Array[Dictionary] = compositions()
	var rng: Variant = world.rng.stream("attributes")
	var idx: int = int(rng.call("int_range", 0, pool.size() - 1))
	return pool[idx]
