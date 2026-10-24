extends RefCounted
# What the colony keeps in its stockpile, in words: the Colony screen's stockpile block (stockpile
# and hauling plan, slice S5). A read model like `work_read.gd` and `condition.gd`: it reads
# components and never writes one, so the screen can ask it every frame and the sim is no different
# for having been asked.
#
# The answer is a word per group and up to three names, never a count (JT's card 4 default: "a few",
# "plenty"). The colony knows its own stockpile, so this reads what is on the stockpile's tiles now,
# not what anybody saw there; a tin on the ground outside the stockpile is not the colony's stores
# and is not counted. What sits inside a bag on the pile is the bag's, and is not counted either:
# the bag is what lies on the tile.
#
# A group is read off fields the content already carries (the item's `class` and the blocks that
# make it what it is), so no content key was added for this. The first rule that matches wins:
#   food        a `food` block
#   drink       a `drink` block, or `purifies` (what makes water drinkable)
#   medicine    any care field the treatment code reads (MEDICINE_KEYS)
#   ammunition  an `ammo` block
#   weapons     class weapon.melee or weapon.ranged
#   clothing and armour   class armor, or a container you wear (a pack, a rig)
#   tools and materials   class tool, material, attachment or container
#   other       anything else (books, soap, comfort)

const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")

# The groups in the order the screen draws them.
const GROUPS: Array[String] = [
	"food", "drink", "medicine", "ammunition",
	"weapons", "clothing and armour", "tools and materials", "other",
]
const MEDICINE_KEYS: Array[String] = ["bandageTier", "painTier", "cleanTier", "closeKind", "antibioticTier", "illnessTier"]
const TOOL_CLASSES: Array[String] = ["tool", "material", "attachment", "container"]
const MAX_NAMES: int = 3

const NONE: String = "none"


## Every amount word `amount_word` can say, in rising order.
static func amount_words() -> Array[String]:
	return [NONE, "one", "a few", "some", "plenty"]


## How much, as a word: none, one, a few (2 to 4), some (5 to 9), plenty (10 or more).
static func amount_word(n: int) -> String:
	if n <= 0:
		return NONE
	if n == 1:
		return "one"
	if n <= 4:
		return "a few"
	if n <= 9:
		return "some"
	return "plenty"


## The group an item base belongs to (see the header for the rules, first match wins).
static func group_of(base: Dictionary) -> String:
	if base.has("food"):
		return "food"
	if base.has("drink") or base.has("purifies"):
		return "drink"
	for k in MEDICINE_KEYS:
		if base.has(k):
			return "medicine"
	if base.has("ammo"):
		return "ammunition"
	var cls: String = SimItems.base_class(base)
	if cls.begins_with("weapon."):
		return "weapons"
	if cls == "armor" or (cls == "container" and base.get("equipSlot") != null):
		return "clothing and armour"
	if TOOL_CLASSES.has(cls):
		return "tools and materials"
	return "other"


## One row per group, in GROUPS order: {group, words, names}. `words` is the amount word for every
## item of the group on the stockpile's tiles, a stack counted as its count; `names` is up to
## MAX_NAMES item names, most numerous first, a tie broken by the name. An item's name may carry a
## digit (the cartridge amendment); nothing else here does.
static func summary(world: Variant) -> Array[Dictionary]:
	var counts: Dictionary = {}
	var by_name: Dictionary = {}
	for g in GROUPS:
		counts[g] = 0
		by_name[g] = {}
	if world != null:
		for item in SimNeeds.stockpile_items(world):
			var base: Variant = SimItems.item_base_of(world, item)
			if not base is Dictionary:
				continue
			var n: int = 1
			var st: Variant = world.components.get_component(item, "stack")
			if st is Dictionary:
				n = maxi(1, int((st as Dictionary).get("count", 1)))
			var g: String = group_of(base as Dictionary)
			counts[g] = int(counts[g]) + n
			var nm: String = SimItems.item_name(world, item)
			var names: Dictionary = by_name[g] as Dictionary
			names[nm] = int(names.get(nm, 0)) + n
	var out: Array[Dictionary] = []
	for g in GROUPS:
		var names: Dictionary = by_name[g] as Dictionary
		var order: Array = names.keys()
		order.sort_custom(func(a: Variant, b: Variant) -> bool:
			var na: int = int(names[a])
			var nb: int = int(names[b])
			return na > nb or (na == nb and String(a) < String(b))
		)
		var shown: Array[String] = []
		for i in mini(MAX_NAMES, order.size()):
			shown.append(String(order[i]))
		out.append({"group": g, "words": amount_word(int(counts[g])), "names": shown})
	return out
