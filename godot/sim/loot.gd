extends RefCounted
# Rolling a location loot table. One canonical place, because two callers need it and the
# alternative is two copies that drift: SimBoot.place_loot scatters a site at boot, and
# SimContainers.search rolls one when somebody opens a cupboard. What a place yields must not
# depend on which of those asked.
#
# The tables themselves are content -- `content/loot/*.json` against `loot.schema.json`, per
# docs/12: "Resources, location loot tables, and spoilage rules are JSON. A loot table declares
# location type, resource weights, tier weights, and quantity ranges." Nothing here decides what
# a place holds; it decides how a declaration becomes items.
#
# Deterministic by construction: every draw comes from a caller-supplied stream, and the stream
# both callers use is `lootTable` -- deliberately not the `loot` stream SimItems.spawn_item draws
# tiers from. New randomness gets its own stream, or every table edit shifts the tier sequence for
# everything spawned afterwards.
#
# check_loot.gd is the gate. It carries more than usual because content_validator.gd is shallow:
# it checks top-level types and rejects unexpected top-level keys but does not recurse, so nothing
# inside `entries`, `rolls` or `tierWeights` is schema-enforced at load.

const SimItems = preload("res://sim/modules/items.gd")

# The RNG stream every loot draw comes from. Named here rather than at each call site so the two
# callers cannot end up on different streams.
const STREAM: String = "lootTable"

# How far apart two items from one site are laid out, in metres. Cosmetic: a site is a scatter
# rather than a pile of coincident sprites.
const SPREAD_METRES: float = 0.4


static func stream(world: Variant) -> Variant:
	return world.rng.stream(STREAM)


# The content table for a location, or null. `location` is the bare name a map site or a container
# carries ("residential"); the content id is always "loot.<location>", which check_loot.gd pins.
static func table_for(world: Variant, location: String) -> Variant:
	var entry: Variant = SimItems.content_entry(world, "loot", "loot.%s" % location)
	return entry if entry is Dictionary else null


# Rolls one site and lays what it yields on the ground around (x, y). Returns the item entities
# created, so a caller that wants to say how much it found does not have to count them again.
static func scatter(world: Variant, table: Dictionary, rng: Variant, x: float, y: float) -> Array:
	var out: Array = []
	var entries: Array = table.get("entries", []) as Array
	if entries.is_empty():
		return out
	var picks: int = roll_range(rng, table.get("rolls", {}) as Dictionary, 1)
	var offset: float = 0.0
	for _i in picks:
		var pick: Variant = weighted_pick(rng, entries, "weight")
		if not (pick is Dictionary):
			continue
		var chosen: Dictionary = pick as Dictionary
		var opts: Dictionary = {"tier": roll_tier(rng, table)}
		if chosen.get("count") is Dictionary:
			# spawn_item clamps to the base's own stack limit, so a range wider than the base
			# allows is a table being generous rather than a bug to guard against here.
			opts["count"] = roll_range(rng, chosen["count"] as Dictionary, 1)
		var item: int = SimItems.spawn_item(world, String(chosen.get("item", "")), opts)
		world.components.set_component(item, "position", {"x": x + offset, "y": y})
		offset += SPREAD_METRES
		out.append(item)
	return out


# Inclusive on both ends. SimRngStream.int_range is inclusive on both ends too --
# min + floor(next() * (max - min + 1)) -- so the range is passed as authored. Writing `hi + 1`
# here is the obvious mistake and it rolls one over every declared maximum; QUANTITY in
# check_loot.gd caught exactly that and is what keeps it caught.
#
# Tolerant of min > max rather than looping on it: the schema forbids neither, and check_loot.gd
# is what asserts the shipped tables are ordered.
static func roll_range(rng: Variant, spec: Dictionary, fallback: int) -> int:
	if not spec.has("min") or not spec.has("max"):
		return fallback
	var lo: int = int(spec["min"])
	var hi: int = maxi(int(spec["max"]), lo)
	return int(rng.call("int_range", lo, hi))


# The tier a place yields, falling back to SimItems.roll_tier's global distribution when a table
# declares no weights. This is what makes docs/12's risk gradient mean anything: the tier stops
# being a property of the world and becomes one of the place, so a military cache comes out better
# than a kitchen drawer.
static func roll_tier(rng: Variant, table: Dictionary) -> String:
	var weights: Variant = table.get("tierWeights")
	if not (weights is Dictionary) or (weights as Dictionary).is_empty():
		return SimItems.roll_tier(rng)
	var pool: Array = []
	for tier_id in (weights as Dictionary).keys():
		pool.append({"id": String(tier_id), "weight": int((weights as Dictionary)[tier_id])})
	var hit: Variant = weighted_pick(rng, pool, "weight")
	return String((hit as Dictionary)["id"]) if hit is Dictionary else SimItems.roll_tier(rng)


# One weighted draw, shaped exactly like SimItems.roll_tier's: sum, one float in [0, total), walk
# it down. Returns null on an empty pool or an all-zero one rather than picking arbitrarily.
static func weighted_pick(rng: Variant, pool: Array, weight_key: String) -> Variant:
	var total: int = 0
	for candidate in pool:
		total += maxi(0, int((candidate as Dictionary).get(weight_key, 0)))
	if total <= 0:
		return null
	var roll: float = float(rng.call("float_range", 0.0, float(total)))
	for candidate in pool:
		roll -= float(maxi(0, int((candidate as Dictionary).get(weight_key, 0))))
		if roll < 0.0:
			return candidate
	return pool[pool.size() - 1]
