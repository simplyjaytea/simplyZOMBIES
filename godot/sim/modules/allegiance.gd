class_name SimAllegiance
extends RefCounted

# Which side of a fight somebody is on, and the one place that answers "is that one my enemy".
#
# The raiders slice needed three separate questions answered consistently and had three separate
# places tempted to answer them: the colony's defence AI picking a target, a raider picking one,
# and a zombie picking prey. Written three times they would drift -- `npc_combat.gd` would learn
# about raiders and `shambler.gd` would not, which is the shape of a raider nothing eats.
#
# So there are exactly three questions here, and the third arrived with the settlers.
#
#   `hostile` -- human against human is decided by `allegiance.faction`, and that field is what a
#   raider content entry declares. A zombie is nobody's ally and everybody's enemy, so it short
#   circuits before the factions are ever compared; that is not a special case bolted on, it is
#   the reason zombies need no allegiance component at all.
#
#   `is_colony` -- one of *yours*, which stopped being the same question as "not an enemy" the
#   moment a third side existed. Succession is the reader: the player's body goes to a colonist.
#
#   `is_person` -- what a zombie considers prey and what a screamer raises an alarm about. A
#   raider is a person: they walk, they sweat, they make noise, and nothing about being hostile to
#   the colony makes them less edible.
#
# An entity with no `allegiance` component reads as COLONY. That default is deliberate and it is
# what keeps every existing gate fixture -- a hand-built NPC with `needs` and a body and nothing
# else -- on the side it has always been on. Only something that declares otherwise is an enemy.
#
# docs/18's factions are Milestone 3. This is still not that: it is one string, three values and a
# table of which pairs fight, with no standing, reputation, trade or diplomacy anywhere. The
# settlers slice widened the seam exactly as far as the settlers need it and no further.

const COLONY: String = "colony"
const RAIDERS: String = "raiders"
# A third side, and the whole reason the comparison below stopped being `!=`: somebody who is not
# the colony and is not hostile to it. Nothing in the tree spawns one yet -- this slice lands the
# seam and its gate, and the settlers' camp stands on it afterwards.
const SETTLERS: String = "settlers"

const FACTIONS: Array[String] = [COLONY, RAIDERS, SETTLERS]

# Who fights whom, declared once and in one direction only. `factions_hostile` tries a pair both
# ways round, so symmetry is a property of the *lookup* rather than of the data: there is no
# second direction to forget to write, and no way to edit this list into a table where the colony
# is at war with the raiders while the raiders are at peace with the colony. Every pair not
# listed is peace, and a faction against itself is peace before the list is consulted at all.
#
# `check_m2_allegiance.gd`'s SYMMETRY lane asserts the property anyway, over every ordered pair,
# and proves the assertion can fail by running it against a deliberately one-way lookup.
const HOSTILE_PAIRS: Array[Array] = [
	[COLONY, RAIDERS],
	[RAIDERS, SETTLERS],
]


static func attach(world: Variant, entity: int, faction: String = COLONY) -> void:
	world.components.set_component(entity, "allegiance", {"faction": faction})


static func faction_of(world: Variant, entity: int) -> String:
	var a: Variant = world.components.get_component(entity, "allegiance")
	if a is Dictionary:
		var f: String = String((a as Dictionary).get("faction", ""))
		if not f.is_empty():
			return f
	return COLONY


# Zombies first, and before the faction comparison rather than after it: a shambler carries no
# allegiance component, so `faction_of` would call it a colonist and the colony would stop
# defending itself. The one true short circuit in this file.
static func hostile(world: Variant, a: int, b: int) -> bool:
	if a == b:
		return false
	if world.components.has_component(a, "shambler") or world.components.has_component(b, "shambler"):
		return true
	return factions_hostile(faction_of(world, a), faction_of(world, b))


# The table itself, on two faction names rather than two bodies -- the zombie short circuit above
# is the only thing that needs to know what an entity is, and a lookup that takes strings is one
# a gate can walk exhaustively.
static func factions_hostile(a: String, b: String) -> bool:
	if a == b:
		return false
	for pair in HOSTILE_PAIRS:
		if (String(pair[0]) == a and String(pair[1]) == b) \
			or (String(pair[0]) == b and String(pair[1]) == a):
			return true
	return false


# Membership of the player's own colony, which is a narrower question than "not an enemy" and the
# reason this exists: a settler is not hostile, and is still not one of yours. Read by
# `SimRecruits._succession_pick`, where the difference is whose body the player wakes up in --
# a settler is a person with an `identity`, and an identity used to be all that scan asked for.
static func is_colony(world: Variant, entity: int) -> bool:
	return faction_of(world, entity) == COLONY


# Somebody a zombie would chase. Three markers, because the colony grew three ways of saying
# "person" before this existed: `controlled` is whoever the player is driving, `identity` is a
# named survivor, and `raider` is the band at the gate. Corpses are deliberately *not* filtered
# here -- shambler.gd has always skipped them and screamer.gd has always not, and quietly
# changing either while adding raiders would be a behaviour change smuggled in beside a slice.
static func is_person(world: Variant, entity: int) -> bool:
	return world.components.has_component(entity, "controlled") \
		or world.components.has_component(entity, "identity") \
		or world.components.has_component(entity, "raider")


# Every body this entity would fight, unfiltered by distance, sightline or health -- callers own
# those, and both of them already had to. Sorted, because `components.query` sorts and a target
# preference that depended on table iteration order would not survive a save/load.
#
# Corpses are excluded: a colonist who spun to face a dead body and declined to swing at it would
# look broken, and `npc_combat._nearest_threat` would have preferred the corpse over the shambler
# standing over it whenever the corpse was nearer.
static func enemies_of(world: Variant, entity: int) -> Array[int]:
	var out: Array[int] = []
	for other in world.components.query(["body", "position"]):
		var o: int = int(other)
		if o == entity:
			continue
		if world.components.has_component(o, "corpse"):
			continue
		if not hostile(world, entity, o):
			continue
		out.append(o)
	return out
