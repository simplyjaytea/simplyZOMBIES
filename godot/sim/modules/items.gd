class_name SimItems
extends RefCounted

# The only preload in this file, and it is a leaf: combat.gd preloads nothing, so it cannot be the
# far end of a cycle. Everything else this file reaches -- inventory, attachments, needs -- is
# lazily `load()`ed precisely because those *do* preload this one. Wanted for
# MELEE_CONNECT_NOISE, the default a melee base's `connectNoise` falls back to.
const SimCombatRes = preload("res://sim/combat.gd")

const FULL_CONDITION: float = 1.0
const CONDITION_FLOOR: float = 0.55
# ponytail: flat wear per hit; jam/miss wear later.
const WEAR_PER_HIT: float = 0.005
# A firearm wears from being fired, not from connecting: the barrel does not know whether the
# round found anything. Sized so a weapon reaches "worn" (0.8) after ~133 rounds and "failing"
# (0.5) after ~333 -- tens of rounds is a firefight, so a gun goes noticeably off after about ten
# of them, which is the pressure docs/09's jam clause wants and the reason WEAR_PER_HIT's comment
# said "jam/miss wear later".
const WEAR_PER_SHOT: float = 0.0015
# A reload is gentler than a shot and mostly costs the magazine, which slice 2 charges separately.
const WEAR_PER_RELOAD: float = 0.0005
# What one repair gives back, and what it costs. docs/10 and docs/11: repair never restores the
# full ceiling -- each one lowers the most a thing can ever be again, so a weapon is repaired
# many times and is then scrap forever. The gain is clamped to the lowered ceiling. The drop is
# what `repair_cost` scales (see `repair_item`); the gain and the floor are not read by any stat.
const REPAIR_GAIN: float = 0.25
const REPAIR_CEILING_DROP: float = 0.05
const REPAIR_CEILING_FLOOR: float = 0.2
# A blade's edge is its own number, apart from the item's condition. A connecting blow takes a little
# off it, and a club has no edge to take. Damage reads it through EDGE_DAMAGE_FLOOR, so a fully dull
# blade hits for at most a fifth less. First cut, docs/30's "Melee wear, 2026-10-27".
const EDGE_DULL_PER_HIT: float = 0.025
const EDGE_DAMAGE_FLOOR: float = 0.8
# Honing takes the edge back to its ceiling and costs the ceiling a little, as repair does.
const HONE_CEILING_DROP: float = 0.02
const HONE_CEILING_FLOOR: float = 0.5
const WHETSTONE: String = "item.whetstone"
# A blade's edge in words, for the inspect pane: the inventory screen's `condition` arrangement
# applied to the edge (docs/01 clause 4, a word and never a fraction). Read over the edge's current
# share, not against its ceiling, because the word says how well it cuts, which is what
# `edge_factor` reads. First-cut bands, docs/30's "Hone on the pack, 2026-10-27".
const EDGE_BANDS: Array[Dictionary] = [
	{"atLeast": 0.75, "name": "keen"},
	{"atLeast": 0.4, "name": "dulling"},
	{"atLeast": 0.0, "name": "dull"},
]
const CONDITION_BANDS: Array[Dictionary] = [
	{"atLeast": 0.8, "name": "sound"},
	{"atLeast": 0.5, "name": "worn"},
	{"atLeast": 0.2, "name": "failing"},
	{"atLeast": 0.01, "name": "barely holding"},
	{"atLeast": 0.0, "name": "broken"},
]
# docs/10's four tiers. The first three are rolled; the fourth is written.
#
# `named` carries two fields the others do not need, and they are not the same statement.
# `weight: 0` keeps it out of roll_tier's global distribution -- the world at large does not hand
# these out, a place that stocks them does, which is why the six named bases sit in
# `loot.military_cache`'s `entries` and in no table's `tierWeights`. Naming it in a tierWeights
# instead would have meant "roll an *ordinary* base at named tier", and since `affixes: 0` that is
# a strictly worse scavenged: a Named Steel Pipe with nothing on it.
#
# `authored: true` keeps it off the *upgrade ladder*. SimModification's Salvage Rights walks TIERS
# by index and steps up one; without this flag a Scrap Kit would step a field-tested axe into
# "named" and manufacture a named item with no name, no author and no drawback -- the tier's whole
# point inverted by a consumable. `rollable_tiers()` is the one place that distinction is made, and
# both readers come through it.
#
# `affixes: 0` is the "fixed, hand-authored" half: a named item draws no random affixes at all. Its
# prefixes and suffixes are written into the base's own `named` block and `spawn_item` copies them
# verbatim, so the same Siren's Bell comes out of every seed.
const TIERS: Array[Dictionary] = [
	{"id": "scavenged", "affixes": 0, "weight": 100},
	{"id": "modified", "affixes": 2, "weight": 35},
	{"id": "field_tested", "affixes": 4, "weight": 6},
	{"id": "named", "affixes": 0, "weight": 0, "authored": true},
]
# The tier id a base's own `named` block puts on it. Named here rather than spelled as a literal at
# each place that tests for it, because a tier id is content's vocabulary as much as code's.
const NAMED_TIER: String = "named"

static func condition_band(cond: Dictionary) -> String:
	for band in CONDITION_BANDS:
		if float(cond.get("current", 0.0)) >= float(band["atLeast"]):
			return String(band["name"])
	return "broken"

static func base_size(base: Dictionary) -> Dictionary:
	var s: Variant = base.get("size")
	if s is Dictionary:
		return {"w": int((s as Dictionary).get("w", 1)), "h": int((s as Dictionary).get("h", 1))}
	return {"w": 1, "h": 1}

static func base_mass_kg(base: Dictionary) -> float:
	var m: Variant = base.get("massKg")
	return float(m) if m is float or m is int else 0.0

static func base_stack_limit(base: Dictionary) -> int:
	var st: Variant = base.get("stack")
	if st is int or st is float:
		return maxi(1, int(st))
	return 1

static func base_class(base: Dictionary) -> String:
	var c: Variant = base.get("class")
	return String(c) if c is String else "material"

static func base_container_grid(base: Dictionary) -> Variant:
	var g: Variant = base.get("container")
	if g is Dictionary:
		return {"w": int((g as Dictionary).get("w", 0)), "h": int((g as Dictionary).get("h", 0))}
	return null

static func base_equip_slot(base: Dictionary) -> Variant:
	var s: Variant = base.get("equipSlot")
	return String(s) if s is String else null


# What the gear on this body smells of, in the same scent magnitudes docs/03's spine already
# carries -- `attention_emitter.gd`'s emit-scent system adds this to the body's own before it
# publishes `scent.accumulated`, so a smell a survivor is wearing reaches the dead by the one
# channel every other smell reaches them by.
#
# **Summed, not maxed**, which is the opposite of how `armor_coverage_of` composes the same walk
# over the same equipped items, and the difference is not an oversight: two helmets do not armour
# one head twice, and two filthy things do smell worse than one.
#
# Read at emission time rather than cached onto the `attention_emitter` component. A cache would be
# a fifth thing equip and unequip had to remember to refresh, and the failure mode of forgetting is
# a survivor who goes on smelling of an apron they took off two days ago -- silent, and exactly the
# class of bug this milestone keeps paying for. The walk is over one person's equipment slots.
static func worn_scent_of(world: Variant, entity: int) -> float:
	var Inv: GDScript = load("res://sim/modules/inventory.gd") as GDScript
	if Inv == null:
		return 0.0
	var total: float = 0.0
	for item in Inv.call("equipped_items", world, entity) as Array:
		var base: Variant = item_base_of(world, int(item))
		if base is Dictionary:
			total += maxf(0.0, float((base as Dictionary).get("scent", 0.0)))
	return total

# How much of the ceiling a repair costs, as a multiple of `REPAIR_CEILING_DROP`: the repairer's
# `repair_cost` times the item's own. An item's own is its scoped value over the unscoped one --
# a division, because the stat multiplies -- so a global modifier, which sits inside both scoped
# resolves, is counted once and not twice (the `capacity_of` argument in inventory.gd, for a
# stat that adds). No repairer, or no modifier table, reads as plain hands.
static func repair_cost_factor(world: Variant, item: int, repairer: int = -1) -> float:
	if world.modifiers == null or not (world.modifiers as Object).has_method("resolve"):
		return 1.0
	var factor: float = 1.0
	if repairer >= 0:
		factor *= float(world.modifiers.call("resolve", "repair_cost", repairer))
	var unscoped: float = float(world.modifiers.call("resolve", "repair_cost"))
	if unscoped > 0.0:
		factor *= float(world.modifiers.call("resolve", "repair_cost", item)) / unscoped
	return maxf(0.0, factor)


# How loud the thing does what it does: a shot, a connect. The item's own `noise_emission`, read
# through the item's scope, so a quiet hand on one pistol does not quiet the next one holstered.
# No item (a bare hand, a zombie's bite) and no modifier table read as plain: 1.0. The item's own
# share is its scoped value over the unscoped one -- the division `repair_cost_factor` does -- so a
# global modifier, which sits inside both resolves, is counted once by whoever reads the stat and not
# twice. The stat names stay literal at each resolve, because godot:m2:web's READERS lane finds a
# reader by that literal.
static func noise_emission_of(world: Variant, item: int) -> float:
	if item < 0 or world.modifiers == null or not (world.modifiers as Object).has_method("resolve"):
		return 1.0
	var unscoped: float = float(world.modifiers.call("resolve", "noise_emission"))
	var scoped: float = float(world.modifiers.call("resolve", "noise_emission", item))
	return scoped / unscoped if unscoped > 0.0 else scoped


# What share of a wear event's amount this item takes: its own `condition_loss`, item-scoped. An
# "of Ruin" gun wears faster from the same round; a reinforced part wears slower. Same no-item and
# no-table reading as `noise_emission_of`, so every caller that has no item is left exactly as it was.
static func condition_loss_of(world: Variant, item: int) -> float:
	if item < 0 or world.modifiers == null or not (world.modifiers as Object).has_method("resolve"):
		return 1.0
	var unscoped: float = float(world.modifiers.call("resolve", "condition_loss"))
	var scoped: float = float(world.modifiers.call("resolve", "condition_loss", item))
	return scoped / unscoped if unscoped > 0.0 else scoped


# The gun's own share of the three clocks the ladder runs on: how long it takes to settle on the aim
# (`steady_ticks`), to come back down after a shot (`recover_ticks`) and to reload (`reload_ticks`).
# Each is the same division as `noise_emission_of`, and ranged.gd multiplies its clock by it on every
# read rather than caching it on the profile, so an affix that moves one takes effect on the next
# rung without a refit. A bare gun reads exactly 1.0 on all three, so every clock is unchanged.
static func steady_share_of(world: Variant, item: int) -> float:
	if item < 0 or world.modifiers == null or not (world.modifiers as Object).has_method("resolve"):
		return 1.0
	var unscoped: float = float(world.modifiers.call("resolve", "steady_ticks"))
	var scoped: float = float(world.modifiers.call("resolve", "steady_ticks", item))
	return scoped / unscoped if unscoped > 0.0 else scoped


static func recover_share_of(world: Variant, item: int) -> float:
	if item < 0 or world.modifiers == null or not (world.modifiers as Object).has_method("resolve"):
		return 1.0
	var unscoped: float = float(world.modifiers.call("resolve", "recover_ticks"))
	var scoped: float = float(world.modifiers.call("resolve", "recover_ticks", item))
	return scoped / unscoped if unscoped > 0.0 else scoped


static func reload_share_of(world: Variant, item: int) -> float:
	if item < 0 or world.modifiers == null or not (world.modifiers as Object).has_method("resolve"):
		return 1.0
	var unscoped: float = float(world.modifiers.call("resolve", "reload_ticks"))
	var scoped: float = float(world.modifiers.call("resolve", "reload_ticks", item))
	return scoped / unscoped if unscoped > 0.0 else scoped


# The gun's own share of `ranged_accuracy`: the same division as `noise_emission_of`. The shooter's
# accuracy is resolved on the entity (`ranged.gd:_refresh_cone`), so a Trued barrel on the bench
# would otherwise move nothing; the cone multiplies this in beside the person's own value. A
# weapon with no affix reads exactly 1.0, so every bare gun's cone is unchanged.
static func accuracy_of(world: Variant, item: int) -> float:
	if item < 0 or world.modifiers == null or not (world.modifiers as Object).has_method("resolve"):
		return 1.0
	var unscoped: float = float(world.modifiers.call("resolve", "ranged_accuracy"))
	var scoped: float = float(world.modifiers.call("resolve", "ranged_accuracy", item))
	return scoped / unscoped if unscoped > 0.0 else scoped


# The stats an item's own affix can move and some reader resolves through the item's scope: the
# melee profile (`melee_profile_of`) and the four readers above. An affix on any other stat is a
# dead socket: it loads, rolls, and changes nothing a player can see. The RANGED lane in
# godot:m2:attach holds the ranged prefixes to this list. Grow it only with a reader that is gated
# to move.
const ITEM_SCOPED_READS: Array[String] = [
	"melee_damage", "melee_reach", "melee_stagger", "swing_recovery", "swing_speed", "swing_stamina",
	"condition_loss", "noise_emission", "ranged_accuracy", "repair_cost",
	"steady_ticks", "recover_ticks", "reload_ticks",
]


static func reads_through_item(stat: String) -> bool:
	return ITEM_SCOPED_READS.has(stat)


# ---- content helpers (supports both registry object and flat Dict from ContentLoader) ----

static func _content_get(world: Variant, type_id: String, id: String) -> Variant:
	if world == null:
		return null
	var c: Variant = null
	if world is Dictionary:
		c = (world as Dictionary).get("content")
	elif "content" in world:
		c = world.content
	else:
		c = world
	if c == null:
		return null
	# Flat Dictionary from ContentLoader.load_tree(): path -> JSON value
	if c is Dictionary:
		# Indexed map form type->id->entry if someone pre-indexed
		if (c as Dictionary).has(type_id):
			var by_id: Variant = (c as Dictionary)[type_id]
			if by_id is Dictionary:
				var hit: Variant = (by_id as Dictionary).get(id)
				if hit != null:
					return hit
		if not (world is Dictionary) and "content_index" in world:
			return _indexed(world, c as Dictionary, id)
		return _scan_for_id(c as Dictionary, id)
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", type_id, id)
	return null


# The first entry in tree order whose `id` matches, or null. The one definition of which entry an id
# names; `_indexed` below is a memo of exactly this answer and must never disagree with it.
static func _scan_for_id(c: Dictionary, id: String) -> Variant:
	for v in c.values():
		if v is Array:
			for entry in v as Array:
				if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
					return entry
		elif v is Dictionary:
			var d: Dictionary = v as Dictionary
			if String(d.get("id", "")) == id:
				return d
	return null


# `_scan_for_id`, memoised on the world. The scan walks every file in the tree and sat under nearly
# every item read -- `item_base_of` alone ran about a hundred times a tick in the shipped world at
# roughly 0.12 ms apiece, which was 12.7 of the tick's 32 ms (A3's first slice, docs/22).
#
# Each row remembers where its entry lives (`p` the tree key, `i` the array index or -1), and a hit
# is only trusted while the tree still holds that same object there with that same id. A gate that
# swaps an entry for an edited copy (check_m2_weather's pinned storm) or a reload that replaces the
# tree therefore misses the memo and rebuilds, rather than reading a stale entry. A miss also
# rebuilds once, because an entry added after the build is not in the memo yet. Insertion order is
# the scan's order, and the build keeps the first row per id, so the two agree on duplicates too.
static func _indexed(world: Variant, c: Dictionary, id: String) -> Variant:
	if not is_same(world.content_index_of, c):
		_build_index(world, c)
	var row: Variant = (world.content_index as Dictionary).get(id)
	if row != null and _row_live(c, row as Dictionary, id):
		return (row as Dictionary)["e"]
	_build_index(world, c)
	row = (world.content_index as Dictionary).get(id)
	if row != null:
		return (row as Dictionary)["e"]
	return null


static func _row_live(c: Dictionary, row: Dictionary, id: String) -> bool:
	var at: Variant = c.get(row["p"])
	var entry: Variant = row["e"]
	var i: int = int(row["i"])
	if i < 0:
		if not is_same(at, entry):
			return false
	elif not (at is Array) or (at as Array).size() <= i or not is_same((at as Array)[i], entry):
		return false
	return String((entry as Dictionary).get("id", "")) == id


static func _build_index(world: Variant, c: Dictionary) -> void:
	var index: Dictionary = {}
	for path in c.keys():
		var v: Variant = c[path]
		if v is Array:
			var arr: Array = v as Array
			for i in arr.size():
				var entry: Variant = arr[i]
				if entry is Dictionary:
					var eid: String = String((entry as Dictionary).get("id", ""))
					if not index.has(eid):
						index[eid] = {"p": path, "i": i, "e": entry}
		elif v is Dictionary:
			var did: String = String((v as Dictionary).get("id", ""))
			if not index.has(did):
				index[did] = {"p": path, "i": -1, "e": v}
	world.content_index = index
	world.content_index_of = c

static func _content_has(world: Variant, type_id: String, id: String) -> bool:
	return _content_get(world, type_id, id) != null

# The one canonical content accessor, made public. _content_get above already handles every shape
# a world's `content` can take -- the flat path->JSON dictionary ContentLoader.load_tree returns, a
# pre-indexed type->id map, and a registry object -- and other modules reaching for content need
# exactly that and should not each grow their own copy of it. SimBoot.place_loot is the first
# caller outside this file.
static func content_entry(world: Variant, type_id: String, id: String) -> Variant:
	return _content_get(world, type_id, id)

# Content types found by their directory rather than by a field they carry. See `_all_entries`.
const TYPE_DIRS: Dictionary = {"container": "containers/"}
static func _all_entries(world: Variant, type_id: String) -> Array:
	var out: Array = []
	if world == null:
		return out
	var c: Variant = null
	if world is Dictionary:
		c = (world as Dictionary).get("content")
	elif "content" in world:
		c = world.content
	else:
		c = world
	if c == null:
		return out
	if c is Object and (c as Object).has_method("all"):
		return (c as Object).call("all", type_id) as Array
	if c is Dictionary:
		# flat tree path -> json
		for path in (c as Dictionary).keys():
			var v: Variant = (c as Dictionary)[path]
			if not (v is Array):
				continue
			# A type this tree can be *asked* for by where it lives. `affix` and `item` are
			# recognised below by a field they happen to carry, which was fine while they were the
			# only two anything asked for; an entry of a type with no distinctive field -- a
			# container's `kind` and `grid`, say -- is invisible to a duck-type and has to be found
			# by its directory, the same path-to-type mapping content_validator._type_of_path makes.
			var dir: Variant = TYPE_DIRS.get(type_id)
			if dir != null:
				if String(path).begins_with(String(dir)):
					for entry in v as Array:
						if entry is Dictionary:
							out.append(entry)
				continue
			for entry in v as Array:
				if entry is Dictionary:
					if type_id == "affix" and (entry as Dictionary).has("slot"):
						out.append(entry)
					elif type_id == "item" and (entry as Dictionary).has("massKg"):
						out.append(entry)
		if (c as Dictionary).has(type_id):
			var by_id: Variant = (c as Dictionary)[type_id]
			if by_id is Dictionary:
				for e in (by_id as Dictionary).values():
					out.append(e)
			elif by_id is Array:
				out.append_array(by_id as Array)
	return out

# Every loaded entry of a content type, in id order. `_all_entries` with a name a caller outside
# this file can say: check_m2_attach.gd asks "does any shipped base declare the slot this
# attachment fits", which is a question only the whole content tree can answer.
static func content_entries(world: Variant, type_id: String) -> Array:
	return _all_entries(world, type_id)


## The content entry for a base id, or null. For a caller that holds a recipe's id and not an item.
static func base_by_id(world: Variant, base_id: String) -> Variant:
	return _content_get(world, "item", base_id)


static func item_base_of(world: Variant, item: int) -> Variant:
	var b: Variant = world.components.get_component(item, "itemBase")
	if b == null:
		return null
	var base_id: String = String((b as Dictionary).get("baseId", ""))
	var entry: Variant = _content_get(world, "item", base_id)
	if entry == null:
		# TS throws here; in Godot push_error so verify_content_references can catch batch
		push_error("Item %d references item base \"%s\", which is not loaded" % [item, base_id])
		return null
	return entry

static func size_of_item(world: Variant, item: int) -> Dictionary:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return {"w": 1, "h": 1}
	return base_size(base as Dictionary)

static func item_mass_kg(world: Variant, item: int, contents_of: Callable) -> float:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return 0.0
	var stack: Variant = world.components.get_component(item, "stack")
	var mass: float = base_mass_kg(base as Dictionary) * float(1 if stack == null else int((stack as Dictionary).get("count", 1)))
	for child in contents_of.call(item) as Array:
		mass += item_mass_kg(world, int(child), contents_of)
	# What is bolted to it, too -- docs/10 charges weight for an extended magazine and the mass of
	# a barrel does not stop being carried because the barrel is in a gun. Each base's own massKg
	# is the receiver alone, so an assembled weapon comes out at the figure it was authored at;
	# check_m2_attach.gd's MASS lane holds that against a table of the pre-assembly masses.
	for rec in _Attachments().call("parts_of", world, item) as Array:
		mass += item_mass_kg(world, int((rec as Dictionary)["item"]), contents_of)
	return mass

static func condition_factor(world: Variant, item: int) -> float:
	var c: Variant = world.components.get_component(item, "condition")
	if c == null:
		return 1.0
	var cur: float = float((c as Dictionary).get("current", 1.0))
	if cur <= 0.0:
		return 0.0
	return CONDITION_FLOOR + (1.0 - CONDITION_FLOOR) * clampf(cur, 0.0, 1.0)


## The raw condition of this item *as assembled*: the worst of its own and every structural part's.
## A weapon is only as good as the barrel in it, which is what makes fitting a sound barrel to a
## tired gun a repair -- and one that costs no ceiling, because nothing was mended.
static func assembly_condition(world: Variant, item: int) -> float:
	var c: Variant = world.components.get_component(item, "condition")
	var own: float = float((c as Dictionary).get("current", 1.0)) if c is Dictionary else 1.0
	return float(_Attachments().call("assembly_condition", world, item, own))


## `condition_factor` asked of the whole assembly. This is what the weapon profiles scale by, so a
## worn barrel takes the edge off the gun exactly as a worn gun does.
static func assembly_condition_factor(world: Variant, item: int) -> float:
	var cur: float = assembly_condition(world, item)
	if cur <= 0.0:
		return 0.0
	return CONDITION_FLOOR + (1.0 - CONDITION_FLOOR) * clampf(cur, 0.0, 1.0)


# docs/10's condition table, as a jam chance per band: "100-80% nominal / 79-50% noticeable
# performance loss / 49-20% serious; firearms jam regularly / 19-1% barely functional". The bands
# are CONDITION_BANDS, so this cannot drift from the words the inventory screen shows for the same
# item -- a weapon the player is told is "failing" is the one that jams often.
#
# A broken firearm reads 1.0, but no trigger pull reaches it: apply_wear unequips a weapon at zero
# condition, and an internal held at zero by `staysWhenWornOut` blocks the weapon before a pull
# (SimAttachments.blocked_reason, `broken:<slot>`). It is here so the table is total rather than
# relying on either ordering.
const JAM_CHANCE_BY_BAND: Dictionary = {
	"sound": 0.0,
	"worn": 0.02,
	"failing": 0.12,
	"barely holding": 0.30,
	"broken": 1.0,
}


static func jam_chance(world: Variant, item: int) -> float:
	var c: Variant = world.components.get_component(item, "condition")
	if not (c is Dictionary):
		return 0.0
	# Banded off the assembly rather than the receiver: what stovepipes a gun is a tired action or
	# a bent magazine, and both are parts now. A player told the action is "failing" is the one
	# whose gun jams, which is the same promise JAM_CHANCE_BY_BAND already makes about the weapon.
	return float(JAM_CHANCE_BY_BAND.get(condition_band({"current": assembly_condition(world, item)}), 0.0))


static func apply_wear(world: Variant, item: int, amount: float = WEAR_PER_HIT) -> void:
	if item < 0 or amount <= 0.0:
		return
	var c: Variant = world.components.get_component(item, "condition")
	if not c is Dictionary:
		return
	var before: float = float((c as Dictionary).get("current", 1.0))
	if before <= 0.0:
		return
	var after: float = maxf(0.0, before - amount * condition_loss_of(world, item))
	(c as Dictionary)["current"] = after
	if after <= 0.0:
		world.events.publish({"type": "item.broke", "item": item})
		# Dropped at the holder's feet, not lost: `unequip_item` alone left the item with no
		# position and no container -- gone from the world with nothing reporting it (docs/23's
		# "worn out is lost, not dropped"). A broken weapon on the ground is something the
		# re-arm skips and the player can still pick up and repair.
		var Inv: GDScript = load("res://sim/modules/inventory.gd") as GDScript
		if Inv != null:
			var holder: int = -1
			for actor in world.components.query(["equipment"]):
				var eq: Variant = world.components.get_component(int(actor), "equipment")
				if eq is Dictionary and ((eq as Dictionary).get("slots", {}) as Dictionary).values().has(item):
					holder = int(actor)
					break
			if holder >= 0 and world.components.has_component(holder, "position"):
				Inv.call("drop_at_feet", world, holder, item)
			else:
				Inv.call("unequip_item", world, item)
		return
	refresh_armed(world, item)


# Mend a thing, at a cost to its ceiling. The cost is `REPAIR_CEILING_DROP` scaled by
# `repair_cost` -- the repairer's own (the Craft nodes, entity-scoped: practised hands take less
# off a thing) times the item's own (the "of Salvage" affix, item-scoped: some things are made
# to be mended). Both had been written since the web and the affix roster landed and read by
# nobody; docs/30's 2026-09-06 entry left the stat dead on purpose because the scrap a repair
# spends is one whole unit and 0.9 of an integer is a design, not a reader. The ceiling is a
# float, so it is the honest reader, and the scrap stays whole (the wider-web arc, 2026-09-13).
# The repair span is the build-speed piece's, not this stat's. With no repairer named (an
# older caller, a fixture) the hands are plain and only the item's own factor applies.
static func repair_item(world: Variant, item: int, repairer: int = -1) -> bool:
	var c: Variant = world.components.get_component(item, "condition")
	if not c is Dictionary:
		return false
	var cur: float = float((c as Dictionary).get("current", 1.0))
	var ceil: float = float((c as Dictionary).get("ceiling", FULL_CONDITION))
	if cur >= ceil:
		return false
	ceil = maxf(REPAIR_CEILING_FLOOR, ceil - REPAIR_CEILING_DROP * repair_cost_factor(world, item, repairer))
	(c as Dictionary)["ceiling"] = ceil
	(c as Dictionary)["current"] = minf(ceil, cur + REPAIR_GAIN)
	refresh_armed(world, item)
	world.events.publish({"type": "item.repaired", "item": item})
	return true


# Whether this item is a blade: an edge a blow can dull and a whetstone can bring back. A club
# or a zombie's body is not, and neither has an edge to lose.
static func _is_blade(world: Variant, item: int) -> bool:
	if not is_melee_item(world, item):
		return false
	return String((item_base_of(world, item) as Dictionary).get("family", "")) == "blade"


# The edge a blade carries, as {current, ceiling}. A blade that has never been dulled has no `edge`
# component, so the missing one reads as keen, and a save from before this piece loads unchanged.
static func edge_of(world: Variant, item: int) -> Dictionary:
	var e: Variant = world.components.get_component(item, "edge")
	if e is Dictionary:
		return (e as Dictionary).duplicate()
	return {"current": FULL_CONDITION, "ceiling": FULL_CONDITION}


# What share of its damage a blade's edge keeps: 1.0 keen, EDGE_DAMAGE_FLOOR fully dull. Anything
# with no edge keeps all of it.
static func edge_factor(world: Variant, item: int) -> float:
	if item < 0 or not _is_blade(world, item):
		return 1.0
	var cur: float = clampf(float(edge_of(world, item)["current"]), 0.0, 1.0)
	return EDGE_DAMAGE_FLOOR + (1.0 - EDGE_DAMAGE_FLOOR) * cur


# A connecting blow takes a little off a blade's edge, by the same condition loss the item wears by.
static func dull_edge(world: Variant, item: int) -> void:
	if not _is_blade(world, item):
		return
	var e: Dictionary = edge_of(world, item)
	e["current"] = maxf(0.0, float(e["current"]) - EDGE_DULL_PER_HIT * condition_loss_of(world, item))
	world.components.set_component(item, "edge", e)
	refresh_armed(world, item)


# A blade's edge as a word ("keen", "dulling", "dull"), or "" for anything with no edge, the way
# `fuel_clause` is "" for anything that is not a lamp.
static func edge_word(world: Variant, item: int) -> String:
	if item < 0 or not _is_blade(world, item):
		return ""
	var cur: float = float(edge_of(world, item)["current"])
	for band in EDGE_BANDS:
		if cur >= float(band["atLeast"]):
			return String(band["name"])
	return String(EDGE_BANDS[EDGE_BANDS.size() - 1]["name"])


# Why `hone` would refuse, asked without spending anything: "not-a-blade", "keen" (already at its
# ceiling), "no-whetstone", or "" when it would hone. The one predicate both the command and the
# pack's `hone` verb ask, so the menu can never offer a hone the command then drops.
static func hone_refusal(world: Variant, actor: int, item: int) -> String:
	if item < 0 or not _is_blade(world, item):
		return "not-a-blade"
	var e: Dictionary = edge_of(world, item)
	if float(e["current"]) >= float(e["ceiling"]):
		return "keen"
	if not _carries_base(world, actor, WHETSTONE):
		return "no-whetstone"
	return ""


static func _carries_base(world: Variant, actor: int, base_id: String) -> bool:
	for carried in (load("res://sim/modules/inventory.gd") as GDScript).call("carried_items", world, actor):
		var b: Variant = world.components.get_component(int(carried), "itemBase")
		if b is Dictionary and String((b as Dictionary).get("baseId", "")) == base_id:
			return true
	return false


# Hones a blade's edge back to its ceiling, spending a whetstone the actor carries. Returns why it
# refused, or "" when it honed (see `hone_refusal`). Each refusal is checked before anything is
# spent, so a refused hone costs nothing.
static func hone(world: Variant, actor: int, item: int) -> String:
	var refusal: String = hone_refusal(world, actor, item)
	if refusal != "":
		return refusal
	var e: Dictionary = edge_of(world, item)
	if not bool(_Needs().call("consume_base", world, actor, WHETSTONE)):
		return "no-whetstone"
	e["ceiling"] = maxf(HONE_CEILING_FLOOR, float(e["ceiling"]) - HONE_CEILING_DROP)
	e["current"] = float(e["ceiling"])
	world.components.set_component(item, "edge", e)
	refresh_armed(world, item)
	world.events.publish({"type": "item.honed", "actor": actor, "item": item})
	return ""


# Loaded lazily, as attachments.gd loads its own reach-outs: needs.gd's graph leads back here.
static func _Needs() -> GDScript:
	return load("res://sim/modules/needs.gd") as GDScript


# Rebuilds the weapon profile of anybody holding this item, after something about the item has
# changed -- wear, a repair, an affix edit, an attachment fitted or taken off. Public because
# attachments.gd is the fourth caller and a fourth private-by-convention reach-in would be worse
# than naming it.
static func refresh_armed(world: Variant, item: int) -> void:
	for actor in world.components.query(["equipment"]):
		var eq: Variant = world.components.get_component(int(actor), "equipment")
		if not eq is Dictionary:
			continue
		var slots: Dictionary = (eq as Dictionary).get("slots", {}) as Dictionary
		var found := false
		for slot in slots.keys():
			if int(slots[slot]) == item:
				found = true
				break
		if not found:
			continue
		var melee: Variant = melee_profile_of(world, item)
		if melee is Dictionary:
			world.components.set_component(int(actor), "meleeWeapon", melee as Dictionary)
			continue
		var ranged: Variant = ranged_profile_of(world, item)
		if ranged is Dictionary:
			# Wear changes the weapon, not the shot already in flight. This used to overwrite the
			# whole component, which dropped the runtime keys `make_ranged_armed` puts there --
			# `state`, `mag`, `ticksLeft`, `flashTicks`, `coneHalf` -- and left `ranged.resolve`
			# reading a `state` that no longer existed. Merge the refreshed numbers into the live
			# weapon instead; the equip subscription stays the only thing that creates one.
			var live: Variant = world.components.get_component(int(actor), "rangedWeapon")
			if live is Dictionary:
				for key in (ranged as Dictionary).keys():
					(live as Dictionary)[key] = (ranged as Dictionary)[key]


## Whether this item is a melee weapon, asked of its base rather than by building a profile.
## The wear-on-hit subscription needs the answer for every landed blow, including a zombie's.
static func is_melee_item(world: Variant, item: int) -> bool:
	if item < 0:
		return false
	var base: Variant = item_base_of(world, item)
	return base is Dictionary and (base as Dictionary).get("melee") is Dictionary


# Three channels, not one, because three different things wear a weapon and they do not wear it
# equally. Each carries the acting item on the event itself -- `source`, stamped by the profile
# builders -- so none of them has to guess which hand acted. That guess was `_weapon_for_attacker`,
# and it was wrong in a way nothing reported: it walked ["primary","secondary"] and took the first
# with a profile, so a survivor carrying a knife and a pistol wore the knife on every gunshot and
# the pistol never degraded at all, which meant its jam chance never rose off zero.
static func register_module(world: Variant) -> void:
	# One intake for the item commands a survivor sends from the sheet.
	# `item.hone {actor, item}`: the actor hones the blade, or the refusal is published.
	# `item.name {item, name}`: whoever carries the weapon names it -- the sheet can be any
	# colonist's, the way `item.drop` finds its actor. Every refusal is `name_refusal`'s, so the
	# screen that asked first and the command that checks again agree; carried by nobody is
	# refused like any other.
	world.systems.register("items.intake", "input", 10, func(w: Variant) -> void:
		var Inv: GDScript = load("res://sim/modules/inventory.gd") as GDScript
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			var kind: String = String(c.get("type", ""))
			var item: int = int(c.get("item", -1))
			if kind == "item.hone":
				var reason: String = hone(w, int(c.get("actor", w.player)), item)
				if reason != "":
					w.events.publish({"type": "item.hone_refused", "item": item, "reason": reason})
			elif kind == "item.name":
				var holder: int = -1
				for actor in w.components.query(["equipment"]):
					if bool(Inv.call("owns", w, int(actor), item)):
						holder = int(actor)
						break
				give_name(w, holder, item, String(c.get("name", "")))
	)
	world.events.subscribe({"id": "items.wear-on-hit", "type": "attack.connected", "handler": func(event: Dictionary) -> void:
		# A melee weapon wears where it lands. A firearm does not wear here -- it wore when it
		# fired, on the channel below -- and a zombie's bite publishes this event carrying no item
		# at all, which is the -1 both cases fall through on.
		var weapon: int = int(event.get("item", -1))
		if is_melee_item(world, weapon):
			apply_wear(world, weapon, WEAR_PER_HIT)
			dull_edge(world, weapon)
	})
	world.events.subscribe({"id": "items.wear-on-shot", "type": "weapon.fired", "handler": func(event: Dictionary) -> void:
		apply_wear(world, int(event.get("item", -1)), WEAR_PER_SHOT)
	})
	world.events.subscribe({"id": "items.wear-on-reload", "type": "weapon.reloaded", "handler": func(event: Dictionary) -> void:
		apply_wear(world, int(event.get("item", -1)), WEAR_PER_RELOAD)
	})

# Loaded lazily rather than preloaded: attachments.gd preloads *this* file, and a preload cycle
# in GDScript is a parse error rather than something the engine resolves.
static func _Attachments() -> GDScript:
	return load("res://sim/modules/attachments.gd") as GDScript


static func melee_profile_of(world: Variant, item: int) -> Variant:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return null
	var melee: Variant = (base as Dictionary).get("melee")
	if not melee is Dictionary:
		return null
	var wear: float = assembly_condition_factor(world, item)
	var resolve := func(stat: String) -> float:
		if world.modifiers != null and (world.modifiers as Object).has_method("resolve"):
			return float(world.modifiers.call("resolve", stat, item))
		return 1.0
	var m: Dictionary = melee as Dictionary
	var profile: Dictionary = {
		"reachMetres": float(m.get("reachMetres", 1.4)) * resolve.call("melee_reach"),
		"weight": float(m.get("weight", 1.0)),
		"damage": float(m.get("damage", 11)) * resolve.call("melee_damage") * wear * edge_factor(world, item),
		"staggerTicks": maxi(0, int(round(float(m.get("staggerTicks", 8)) * resolve.call("melee_stagger")))),
		"speed": resolve.call("swing_speed") * wear,
		"recovery": resolve.call("swing_recovery"),
		"stamina": resolve.call("swing_stamina"),
		# How loud a landed swing is, in the attention spine's own magnitudes. melee.gd published
		# SimCombat.MELEE_CONNECT_NOISE as a literal until this existed, so a weapon had no way to
		# be louder than any other weapon; the default here *is* that literal, which leaves every
		# shipped melee base byte-identical and lets a weapon that wants to be heard say so.
		# docs/10's Siren's Bell is the reason: "enormous noise on every connect" is a drawback
		# only if the weapon owns the number.
		"connectNoise": float(m.get("connectNoise", float(SimCombatRes.MELEE_CONNECT_NOISE))),
		# Which item this profile was built from. The live `meleeWeapon`/`rangedWeapon` components
		# sit on the *actor*, so before this key existed nothing could say which of the two hands
		# had acted -- `_weapon_for_attacker` guessed by walking ["primary","secondary"] and
		# returning the first with a profile, which wore a knife every time a pistol fired. An
		# entity id as a *value*, never a Dictionary key, so it survives the JSON round trip a
		# save makes.
		"source": item,
		# Why this weapon cannot be used, or "" -- one field, computed once, read by every path
		# that can start an attack. See SimAttachments.blocked_reason.
		"blocked": String(_Attachments().call("blocked_reason", world, item)),
	}
	return _Attachments().call("fold", world, item, "melee", profile)

## The spent case a round of `caliber` leaves, as a base id, or "" for a caliber with none: the .22,
## a bow's arrow. Where two cases name one caliber the lower id wins, so the answer is stable
## whatever order the content was read in (the rule `SimRanged.handload_of` keeps for recipes).
static func brass_of(world: Variant, caliber: String) -> String:
	var found: String = ""
	if caliber == "":
		return found
	for base_v in content_entries(world, "item") as Array:
		var brass: Variant = (base_v as Dictionary).get("brass")
		if not brass is Dictionary or String((brass as Dictionary).get("caliber", "")) != caliber:
			continue
		var id: String = String((base_v as Dictionary).get("id", ""))
		if found == "" or id < found:
			found = id
	return found


static func ranged_profile_of(world: Variant, item: int) -> Variant:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return null
	var ranged: Variant = (base as Dictionary).get("ranged")
	if not ranged is Dictionary:
		return null
	var wear: float = assembly_condition_factor(world, item)
	var r: Dictionary = ranged as Dictionary
	var jams: bool = bool(r.get("jams", false))
	var profile: Dictionary = {
		"damage": float(r.get("damage", 12)) * wear,
		# docs/09: "degraded firearms jam". Derived here rather than at the trigger so it rides
		# refresh_armed -- apply_wear merges this profile into the live weapon on every hit, so a
		# jam chance computed here tracks a degrading weapon without anything else remembering to
		# recompute it. Bows and crossbows declare no `jams` and so never jam, which is the whole
		# reason it is a content flag: docs/09 and docs/11's Gun Oil both say *firearms*.
		"jams": jams,
		"jamChance": jam_chance(world, item) if jams else 0.0,
		"noise": float(r.get("noise", 4)),
		# Muzzle speed, the barrel's to set (sim/barrel.gd). A base leaves its round at full speed; a
		# barrel that slows it folds a number under 1 through the fold like every other multiplier.
		"muzzle": 1.0,
		"flash": float(r.get("flash", 0)),
		"ammo": String(r.get("ammo", "")),
		# What else will chamber. `ammo` is the round the weapon prefers and this is the set it
		# belongs to, so a survivor out of soft points fires the match rounds in the same pocket
		# rather than standing there holding a loaded rifle. Rides the profile beside `ammo`
		# because both are overridable by a conversion part and the fold has to see them
		# together -- a barrel that changes the round without changing the caliber would build a
		# weapon that prefers a round it cannot take.
		"caliber": String(r.get("caliber", "")),
		# A revolver keeps its spent cases in the cylinder until its next reload (SimRanged._eject_case).
		"cylinder": bool(r.get("cylinder", false)),
		"recoverable": float(r.get("recoverable", 0.0)),
		"magSize": int(r.get("magSize", 0)),
		"reloadTicks": int(r.get("reloadTicks", 24)),
		"rangeMetres": float(r.get("rangeMetres", 30)),
		# Heft, and the multiplier that fights it. `weight` is content-declared and mirrors
		# melee's -- a weapon's clocks come from what it is, and docs/10 rule 4 wants melee and
		# ranged to have the same item depth. It rides the profile rather than being read off the
		# item at each rung, so `_refresh_cone` and the ladder both have it in hand. Not scaled by
		# condition: a worn rifle is not a lighter rifle.
		"weight": float(r.get("weight", 1.0)),
		# The scalable half, folded below like every other multiplier. Above 1 is quicker to the
		# shoulder; see SimCombat.raise_ticks for why one field covers all three rungs. Seeded from
		# the base rather than hardcoded to 1.0 since the named tier: a weapon whose whole
		# character is that it is slow to bring up -- docs/10's Quietkeeper -- has to be able to
		# say so itself, and every base that declares nothing still starts at exactly 1.0.
		"handling": float(r.get("handling", 1.0)),
		# An accuracy multiplier carried by the weapon rather than by the person. An optic is a
		# property of the gun, and `ranged_accuracy` -- the stat an affix or a trait moves --
		# resolves on the *entity*, so a scope with nothing in it was the wrong place to put one.
		# `ranged.gd:_refresh_cone` folds this in with everything else that decides sway. Seeded
		# from the base for the same reason `handling` is: below 1 is a weapon that shoots tighter
		# than its class does, which is docs/10's Grandfather's Deer Rifle, and a base that
		# declares nothing is still exactly 1.0.
		"cone": float(r.get("cone", 1.0)),
		# See melee_profile_of: the item this profile was built from, so wear can reach the
		# weapon that actually fired.
		"source": item,
		"blocked": String(_Attachments().call("blocked_reason", world, item)),
		# Whether the weapon may fire from a vehicle seat: a folding stock's word, read off every fitted
		# part (SimAttachments.fires_from_vehicle). Rides the profile so the trigger and the HUD read
		# one field; a bare receiver and a full stock do not declare it, so both are refused a seat.
		"fromVehicle": bool(_Attachments().call("fires_from_vehicle", world, item)),
	}
	var built: Dictionary = _Attachments().call("fold", world, item, "ranged", profile) as Dictionary
	# `jamChance` was derived above, from the base's own `jams`. A part may *replace* `jams` --
	# a match action that will not stovepipe -- and the fold runs after, so the chance would be
	# left describing a weapon that no longer exists. Re-derived here rather than inside `fold`,
	# which has no business knowing that two of these fields are related.
	if not bool(built.get("jams", false)):
		built["jamChance"] = 0.0
	elif float(built.get("jamChance", 0.0)) <= 0.0:
		built["jamChance"] = jam_chance(world, item)
	return built

# ---- affixes ----

# The tiers a roll or an upgrade may produce: TIERS minus the hand-authored ones. Every caller that
# treats TIERS as a *ladder* -- roll_tier here, SimModification's Salvage Rights -- comes through
# this; every caller that treats it as a *lookup* ("how many affixes does this id allow") reads
# TIERS directly, because a named item still has to be able to find its own row.
static func rollable_tiers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in TIERS:
		if not bool((t as Dictionary).get("authored", false)):
			out.append(t as Dictionary)
	return out


static func roll_tier(rng: Variant) -> String:
	var pool: Array[Dictionary] = rollable_tiers()
	var total: int = 0
	for t in pool:
		total += int(t["weight"])
	var roll: float = float(rng.call("float_range", 0.0, float(total)))
	for t in pool:
		roll -= float(t["weight"])
		if roll < 0.0:
			return String(t["id"])
	return "scavenged"


# The hand-authored affix roll on a base, or null when the base is an ordinary one. Shaped exactly
# like the `affixes` component `roll_affixes` produces -- {prefixes, suffixes} of {id, tier} -- so
# `affix_modifiers`, the reader that already turns a rolled affix into a scoped modifier, resolves a
# named item's fixed rolls with no second code path. "Fixed rolls rather than random affixes" is a
# statement about where the rolls come from, not about what they are, and a parallel modifier system
# would have been the wrong shape for it.
static func named_block(base: Variant) -> Variant:
	if not base is Dictionary:
		return null
	var n: Variant = (base as Dictionary).get("named")
	return n if n is Dictionary else null


# Whether this item is one of docs/10's named items. Asks the base, not the `itemTier` component:
# the tier is a *consequence* of the base being named, so a hand-built fixture that never set a
# tier is still holding a Siren's Bell.
static func is_named(world: Variant, item: int) -> bool:
	return named_block(item_base_of(world, item)) != null


# A deep copy of an authored roll, in the affixes component's shape. A copy, built out of fresh
# plain Arrays and Dictionaries, because the component is mutable -- the bench edits prefixes in
# place -- and handing every Siren's Bell the registry's own arrays would let one item's
# modification rewrite the content tree for every one spawned after it.
static func _named_affixes(block: Dictionary) -> Dictionary:
	var out: Dictionary = {"prefixes": [], "suffixes": []}
	for slot in ["prefixes", "suffixes"]:
		for rolled_v in block.get(slot, []) as Array:
			if not (rolled_v is Dictionary):
				continue
			var r: Dictionary = rolled_v as Dictionary
			(out[slot] as Array).append({"id": String(r.get("id", "")), "tier": int(r.get("tier", 0))})
	return out

static func affix_pool(world: Variant, item_class: String, slot: String) -> Array:
	var pool: Array = []
	for affix in _all_entries(world, "affix"):
		var d: Dictionary = affix as Dictionary
		if String(d.get("slot", "")) != slot:
			continue
		var applies: Variant = d.get("appliesTo")
		if applies is Array and (applies as Array).has(item_class):
			pool.append(d)
	return pool

static func _roll_affix_tier(affix: Dictionary, rng: Variant) -> int:
	var tiers: Variant = affix.get("tiers")
	if not tiers is Array or (tiers as Array).is_empty():
		return 0
	var arr: Array = tiers as Array
	var total: float = 0.0
	for t in arr:
		total += float((t as Dictionary).get("weight", 0))
	var roll: float = float(rng.call("float_range", 0.0, total))
	for i in arr.size():
		roll -= float((arr[i] as Dictionary).get("weight", 0))
		if roll < 0.0:
			return i
	return arr.size() - 1

static func roll_affixes(world: Variant, item_class: String, tier: String, rng: Variant) -> Dictionary:
	var wanted: int = 0
	for t in TIERS:
		if String(t["id"]) == tier:
			wanted = int(t["affixes"])
			break
	var out: Dictionary = {"prefixes": [], "suffixes": []}
	if wanted == 0:
		return out
	var split: Dictionary = {"prefix": int(ceil(float(wanted) / 2.0)), "suffix": int(floor(float(wanted) / 2.0))}
	for slot in ["prefix", "suffix"]:
		var available: Array = affix_pool(world, item_class, slot)
		# draw without replacement — copy to avoid mutating registry
		var bag: Array = available.duplicate()
		for _i in range(int(split[slot])):
			if bag.is_empty():
				break
			var pick: int = int(rng.call("int_range", 0, bag.size() - 1))
			var affix: Dictionary = bag[pick] as Dictionary
			bag.remove_at(pick)
			var rolled: Dictionary = {"id": String(affix["id"]), "tier": _roll_affix_tier(affix, rng)}
			if slot == "prefix":
				(out["prefixes"] as Array).append(rolled)
			else:
				(out["suffixes"] as Array).append(rolled)
	(out["prefixes"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["id"]) != String(b["id"]): return String(a["id"]) < String(b["id"])
		return int(a["tier"]) < int(b["tier"]))
	(out["suffixes"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["id"]) != String(b["id"]): return String(a["id"]) < String(b["id"])
		return int(a["tier"]) < int(b["tier"]))
	return out

static func affix_modifiers(world: Variant, item: int) -> Array:
	var aff: Variant = world.components.get_component(item, "affixes")
	if aff == null:
		return []
	var out: Array = []
	var d: Dictionary = aff as Dictionary
	var all: Array = []
	all.append_array(d.get("prefixes", []) as Array)
	all.append_array(d.get("suffixes", []) as Array)
	for rolled_v in all:
		var rolled: Dictionary = rolled_v as Dictionary
		var affix: Variant = _content_get(world, "affix", String(rolled["id"]))
		if affix == null:
			push_error("Item %d references affix \"%s\", which is not loaded" % [item, String(rolled["id"])])
			continue
		var tiers: Variant = (affix as Dictionary).get("tiers")
		if not tiers is Array:
			continue
		var tier_idx: int = int(rolled["tier"])
		if tier_idx < 0 or tier_idx >= (tiers as Array).size():
			push_error("Item %d rolled tier %d of affix \"%s\" which declares %d" % [item, tier_idx, String(rolled["id"]), (tiers as Array).size()])
			continue
		var tier_data: Dictionary = (tiers as Array)[tier_idx] as Dictionary
		for mod in tier_data.get("modifiers", []) as Array:
			var m: Dictionary = (mod as Dictionary).duplicate(true)
			m["source"] = String(rolled["id"])
			out.append(m)
	return out

# The item's tier id, or "scavenged" for anything spawned before tiers were recorded (and for a
# fixture that builds an item by hand). Never null: every caller wants a tier to look up in TIERS,
# and the untiered floor is the honest default.
static func tier_of(world: Variant, item: int) -> String:
	var band: Variant = world.components.get_component(item, "itemTier")
	if band is Dictionary:
		var id: String = String((band as Dictionary).get("id", ""))
		if id != "":
			return id
	return "scavenged"


# How many affixes this item's tier permits in total. One reader of TIERS rather than each caller
# walking it, because "what a tier allows" is the same question at generation and at the bench.
static func affix_capacity(world: Variant, item: int) -> int:
	var tier: String = tier_of(world, item)
	for t in TIERS:
		if String((t as Dictionary)["id"]) == tier:
			return int((t as Dictionary)["affixes"])
	return 0


# Re-derives an item's affix modifiers after its affixes have been edited. Removes by source
# first -- each affix contributes modifiers tagged with its own id (see affix_modifiers) -- rather
# than clearing the item's whole modifier scope, because the scope may hold modifiers this module
# did not put there and clearing it would silently drop them.
static func reapply_affix_modifiers(world: Variant, item: int) -> void:
	for entry in _all_entries(world, "affix"):
		world.modifiers.remove_by_source(String((entry as Dictionary).get("id", "")), item)
	for mod in affix_modifiers(world, item):
		world.modifiers.add(mod as Dictionary, item)
	refresh_armed(world, item)


# What a thing is, in one sentence, for the inspect pane on the inventory sheet. Content when the
# base carries a `description` and a built sentence when it does not, so a base added tomorrow is
# never blank on the screen -- and so the gate has something to compare an authored line against.
#
# Never a number. docs/01 clause 4 bans a UI that collapses uncertainty into one, and a
# description saying "18 damage" would be exactly that with a full stop after it; the condition
# *word* beside it in the pane is how well the thing is holding up, and that is the whole readout.
static func description_of(world: Variant, base_id: String) -> String:
	var entry: Variant = content_entry(world, "item", base_id)
	if entry is Dictionary:
		var authored: String = String((entry as Dictionary).get("description", ""))
		if not authored.is_empty():
			return authored
		return generated_description(entry as Dictionary)
	return "Something."


# The fallback, keyed by what the base says about itself rather than by its id -- a per-id table
# here would be the `if id ==` branch the appearance pipeline exists to have deleted. The slot is
# consulted first because "worn on the head" says more than "armour", and the class carries the
# rest.
const CLASS_SENTENCES: Dictionary = {
	"weapon.melee": "Something to swing.",
	"weapon.ranged": "Something that fires.",
	"container": "Something to put things in.",
	"consumable": "Something to use up.",
	"material": "Raw material.",
	"armor": "Something to wear.",
	"tool": "A tool.",
	"attachment": "Something that fits onto a weapon.",
}
const SLOT_SENTENCES: Dictionary = {
	"head": "Worn on the head.",
	"eyes": "Worn over the eyes.",
	"face": "Worn over the face.",
	"vest": "Worn over the chest.",
	"torso": "Worn on the body.",
	"gloves": "Worn on the hands.",
	"belt": "Worn at the waist.",
	"legs": "Worn on the legs.",
	"feet": "Worn on the feet.",
	"back": "Carried on the back.",
	"primary": "Carried in the hands.",
	"secondary": "Carried as a sidearm.",
}
static func generated_description(base: Dictionary) -> String:
	var slot: Variant = base_equip_slot(base)
	if slot != null and SLOT_SENTENCES.has(String(slot)):
		return String(SLOT_SENTENCES[String(slot)])
	var cls: String = base_class(base)
	if CLASS_SENTENCES.has(cls):
		return String(CLASS_SENTENCES[cls])
	return "Something."


static func item_name(world: Variant, item: int) -> String:
	if item_base_of(world, item) == null:
		return "something"
	# A name the player gave it is the whole name: no base noun and no affix words around it. That
	# is the point of naming a thing you rebuilt -- "Old Faithful", not "Sturdy Old Faithful".
	var given: String = given_name(world, item)
	return given if not given.is_empty() else plain_name(world, item)


## How a sentence names this item: "the hunting rifle" for a thing, or the name the player gave it,
## as typed. A given name is a proper noun -- "pick up Old Faithful", never "pick up the old
## faithful" -- so every line that puts an item in a sentence asks here rather than lowering
## `item_name` and putting "the" in front of it.
static func the_item(world: Variant, item: int) -> String:
	var given: String = given_name(world, item)
	return given if not given.is_empty() else "the %s" % item_name(world, item).to_lower()


## The name the item would have with no name given: the base's noun with its affix words. What the
## name field offers back when it is emptied, since an empty name gives this name back.
static func plain_name(world: Variant, item: int) -> String:
	var base: Variant = item_base_of(world, item)
	if base == null:
		return "something"
	var plain: String = String((base as Dictionary).get("name", (base as Dictionary).get("id", "something")))
	var aff: Variant = world.components.get_component(item, "affixes")
	if aff == null:
		return plain
	var d: Dictionary = aff as Dictionary
	var name_of: Callable = func(rolled: Dictionary) -> String:
		var affix: Variant = _content_get(world, "affix", String(rolled["id"]))
		if affix is Dictionary and (affix as Dictionary).has("name"):
			return String((affix as Dictionary)["name"])
		return ""
	var prefixes: Array = []
	for r in d.get("prefixes", []) as Array:
		var n: String = String(name_of.call(r as Dictionary))
		if n != "":
			prefixes.append(n)
	var suffixes: Array = []
	for r in d.get("suffixes", []) as Array:
		var n: String = String(name_of.call(r as Dictionary))
		if n != "":
			suffixes.append(n)
	var parts: Array = []
	parts.append_array(prefixes)
	parts.append(plain)
	parts.append_array(suffixes)
	# GDScript join via String
	var out: String = ""
	for i in parts.size():
		if i > 0:
			out += " "
		out += String(parts[i])
	return out


# --- a weapon you named --------------------------------------------------------------------------
#
# docs/38's melee arc: "a weapon past its modifications may be named by the player, which is how
# bespoke reads on a screen with no stat line". What counts as bespoke is derived from what is
# fitted (`SimAttachments.modifications_of`), so nothing is saved for it; the name is the one new
# thing a save carries, in its own component.
#
# The component is `givenName`, not `named`: "named" already means docs/10's hand-authored fourth
# tier (`is_named`, `NAMED_TIER`, the base's `named` block), and a second meaning on the same word
# is how a `has_component(item, "named")` ends up asking the wrong question.
const GIVEN_NAME: String = "givenName"
# How many of a weapon's slots have to hold a part it did not come with before it takes a name.
# Three, by the owner's call of 2026-10-27 (docs/33 item 23): the wooden bat has three slots, so a
# bat with nails, a weight and a wrap is the arc's example of a thing worth naming.
const BESPOKE_PARTS: int = 3
# The longest name the field takes. The field shows the cap by refusing the next key, never by a
# counter: a counter would be a digit on the screen.
const NAME_MAX: int = 24


## Whether this item has been rebuilt enough to take a name. Any item with slots, melee or
## firearm alike; a thing with no slots is never bespoke.
static func nameable(world: Variant, item: int) -> bool:
	if item < 0 or not (item_base_of(world, item) is Dictionary):
		return false
	var Att: GDScript = _Attachments()
	if (Att.call("slots_of", world, item) as Array).is_empty():
		return false
	return int(Att.call("modifications_of", world, item)) >= BESPOKE_PARTS


## The digit ban's item-name clause (CLAUDE.md, Standing bans; docs/30, "The cartridge on the
## label"), as one predicate. An item's `name` may carry a digit -- `.308 Winchester Match` -- but a
## name with no word in it is a quantity, not a name. `check_inventory.gd`'s `_name_is_allowed`
## calls this, so the gate and the `item.name` command ask the same question.
##
## A name needs a letter. The clause used to read "not every character a digit", which let "4 2"
## and "1.000" through as names; neither is a noun, and a player typing one is the first time the
## clause met text nobody authored.
static func name_is_allowed(text: String) -> bool:
	for ch in text.strip_edges():
		if ch.to_lower() != ch.to_upper():
			return true
	return false


## Whether a typed character may stand in a name: printable Latin (Basic, Latin-1 and Extended-A,
## which is what the screens' pixel face draws) and the few marks it carries beyond them -- the euro,
## the dashes, the curly quotes and the ellipsis. No control, no invisible space or soft hyphen, no
## direction mark, and nothing the face would hand to a smooth fallback or draw as a box on the web
## build, where there are no system fonts. A fixed list rather than a font question: the sim reads
## no fonts, and a command or a save is held to the same rule as the field.
const NAME_MARKS: Array[int] = [0x20AC, 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026]
static func name_char_allowed(code: int) -> bool:
	if code >= 0x20 and code <= 0x7E:
		return true
	if code >= 0xA1 and code <= 0x17E and code != 0xAD:
		return true
	return NAME_MARKS.has(code)


## Why this survivor may not give this item this name, or "" when they may. An empty name is
## allowed: it gives back the plain name. Asked by the command and by the screen before it sends,
## so the field can say what is wrong and stay open.
static func name_refusal(world: Variant, actor: int, item: int, text: String) -> String:
	var Inv: GDScript = load("res://sim/modules/inventory.gd") as GDScript
	if item < 0 or not bool(Inv.call("owns", world, actor, item)):
		return "not-carried"
	if not nameable(world, item):
		return "not-bespoke"
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.length() > NAME_MAX:
		return "too-long"
	for ch in trimmed:
		if not name_char_allowed(ch.unicode_at(0)):
			return "not-a-letter"
	if not name_is_allowed(trimmed):
		return "not-a-name"
	return ""


## The refusal in words, for the field to say.
static func name_refusal_words(reason: String) -> String:
	match reason:
		"not-carried":
			return "you are not holding it"
		"not-bespoke":
			return "only a weapon you rebuilt takes a name"
		"too-long":
			return "that name is too long"
		"not-a-name":
			return "a name needs a word in it"
		"not-a-letter":
			return "it will not take a letter like that"
		_:
			return "it will not take that name"


## Gives an item a name, or gives back its plain one for an empty name. Returns the refusal reason,
## or "" when it took.
static func give_name(world: Variant, actor: int, item: int, text: String) -> String:
	var reason: String = name_refusal(world, actor, item, text)
	if reason != "":
		world.events.publish({"type": "item.nameRefused", "item": item, "reason": reason})
		return reason
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		world.components.remove_component(item, GIVEN_NAME)
	else:
		world.components.set_component(item, GIVEN_NAME, {"name": trimmed})
	world.events.publish({"type": "item.named", "item": item, "name": trimmed})
	return ""


## The name the player gave this item, or "" when it has none.
static func given_name(world: Variant, item: int) -> String:
	var given: Variant = world.components.get_component(item, GIVEN_NAME)
	return String((given as Dictionary).get("name", "")) if given is Dictionary else ""

static func spawn_item(world: Variant, base_id: String, options: Dictionary = {}) -> int:
	var item: int = int(world.entities.spawn())
	world.components.set_component(item, "itemBase", {"baseId": base_id})
	# tier roll — needs world.rng.stream("loot")
	var rng: Variant = null
	if "rng" in world and world.rng != null and world.rng.has_method("stream"):
		rng = world.rng.call("stream", "loot")
	var base: Variant = _content_get(world, "item", base_id)
	# A named base is its own tier, whatever the caller asked for. docs/10's fourth tier is
	# hand-authored, so the tier is a property of *which base this is* rather than of the roll that
	# found it: a table rolling "scavenged" and then picking the Siren's Bell must not produce a
	# scavenged Siren's Bell, and neither must a kit, a debug spawn or a fixture passing a tier by
	# hand. Fetched before the tier is decided for exactly that reason -- it used to be read after.
	var named: Variant = named_block(base)
	var tier: String = String(options.get("tier", "")) if options.has("tier") else ""
	if named != null:
		tier = NAMED_TIER
	elif tier == "" and rng != null:
		tier = roll_tier(rng)
	elif tier == "":
		tier = "scavenged"
	# The tier is a permanent property of the item, not a step in generating it. It was previously
	# rolled here, used to decide how many affixes to draw, and thrown away -- so nothing could
	# afterwards ask how many affix slots an item has, which is exactly what a Scrap Kit needs to
	# know. Stored as its own component so it serialises with everything else.
	world.components.set_component(item, "itemTier", {"id": tier})
	var cls: String = base_class(base as Dictionary) if base is Dictionary else "material"
	var aff: Dictionary = {"prefixes": [], "suffixes": []}
	if named != null:
		# Fixed rolls: copied, never drawn. Deliberately touches no RNG at all -- that is what
		# makes one named item the same object on every seed, and it is the difference between
		# "hand-authored" and "rolled at a tier that happens to be rare".
		aff = _named_affixes(named as Dictionary)
	elif rng != null and base != null:
		aff = roll_affixes(world, cls, tier, rng)
	world.components.set_component(item, "affixes", aff)
	world.components.set_component(item, "condition", {"current": FULL_CONDITION, "ceiling": FULL_CONDITION})
	var stack_limit: int = base_stack_limit(base as Dictionary) if base is Dictionary else 1
	if stack_limit > 1:
		var count: int = int(options.get("count", 1))
		count = clampi(count, 1, stack_limit)
		world.components.set_component(item, "stack", {"count": count})
	# scope modifiers to item
	for mod in affix_modifiers(world, item):
		world.modifiers.add(mod as Dictionary, item)
	# Delivered synchronously rather than published: the one subscriber attaches a container
	# grid, and callers stow into a just-spawned pack on the same line. This was
	# publish() + drain(), which got the synchrony by flushing the *whole* queue mid-tick --
	# every handler another system had queued this tick ran early, and since whether a spawn
	# happens can hang on an RNG roll (a recovered arrow, a cooked meal), *which* events those
	# were was not stable between runs. The frozen oracle still carries that shape; parity is
	# unaffected because the parity snapshot carries no event ordering.
	world.events.deliver({"type": "item.spawned", "item": item, "baseId": base_id})
	# Spoilage is content: mark_spoilage reads the base's own `food.spoilDays` and does nothing
	# for a base with none, or with zero. This used to name two ids -- raw and cooked -- so a third
	# perishable food would have spawned with no clock and never gone off.
	var Needs: GDScript = load("res://sim/modules/needs.gd") as GDScript
	if Needs != null and Needs.has_method("mark_spoilage"):
		Needs.call("mark_spoilage", world, item, base_id)
	# Last, and deliberately not on the `item.spawned` channel above: assembly spawns entities of
	# its own, and doing that inside `deliver` would nest a delivery in a delivery. `assemble`
	# draws no randomness -- every part is spawned at an explicit tier -- so a weapon arriving in
	# the world with four parts in it leaves the `loot` stream exactly where a bare one would.
	# Opt out with {"assemble": false} when you want the frame alone.
	if bool(options.get("assemble", true)):
		_Attachments().call("assemble", world, item, int(options.get("assembleDepth", 0)))
	return item

static func verify_content_references(world: Variant) -> void:
	var problems: Array[String] = []
	for item in world.components.query(["itemBase"]):
		var b: Variant = world.components.get_component(int(item), "itemBase")
		var bid: String = String((b as Dictionary).get("baseId", "")) if b is Dictionary else ""
		if not _content_has(world, "item", bid):
			problems.append("item %d: no item base \"%s\"" % [int(item), bid])
	for item2 in world.components.query(["affixes"]):
		var aff: Variant = world.components.get_component(int(item2), "affixes")
		if not aff is Dictionary:
			continue
		var d2: Dictionary = aff as Dictionary
		var all2: Array = []
		all2.append_array(d2.get("prefixes", []) as Array)
		all2.append_array(d2.get("suffixes", []) as Array)
		for rolled_v in all2:
			var rolled: Dictionary = rolled_v as Dictionary
			var rid: String = String(rolled["id"])
			var affix: Variant = _content_get(world, "affix", rid)
			if affix == null:
				problems.append("item %d: no affix \"%s\"" % [int(item2), rid])
				continue
			var tiers: Variant = (affix as Dictionary).get("tiers")
			var tier_idx: int = int(rolled["tier"])
			var sz: int = (tiers as Array).size() if tiers is Array else 0
			if tier_idx < 0 or tier_idx >= sz:
				problems.append("item %d: affix \"%s\" has no tier %d (it declares %d)" % [int(item2), rid, tier_idx, sz])
	if not problems.is_empty():
		var msg: String = "Content does not match this world (%d %s):\n  %s" % [problems.size(), "problem" if problems.size() == 1 else "problems", "\n  ".join(problems)]
		push_error(msg)
		assert(false, msg)
