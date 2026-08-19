class_name SimAttachments
extends RefCounted

# Attachment slots -- docs/10-items.md#attachment-slots.
#
#   "The mechanism that lets a build survive an upgrade -- PoE's 'your gems come with you'.
#    Attachments are found, not crafted, and move freely between compatible bases. Finding a
#    better rifle upgrades your numbers without discarding the suppressor, optic, and extended
#    magazine you spent two months assembling."
#
# The backlog said this needed "content, a reader, and attachment items", and was half wrong about
# which half was missing: every weapon base under `content/items/` has declared its `slots` since
# the item pipeline landed. What did not exist was anything that *fits into* one and anything that
# *reads* one. Both are here.
#
# **An attachment declares what it multiplies, and this module knows what an optic is only in the
# sense that the content does.** `attachment.ranged` and `attachment.melee` are tables keyed by
# the profile field they scale -- `{"noise": 0.22, "cone": 1.2}` is a suppressor -- so adding a
# kind of attachment is a data edit, which is the rule docs/10 states for bases and affixes and
# has no reason to stop holding here. Nothing in this file names a suppressor, a sight or a
# magazine.
#
# **Multipliers, never adders, and that is a decision.** An extended magazine is 1.5x rather than
# +4 rounds, so two attachments compose the same way in either order and neither has to know the
# host's numbers. It costs the ability to say "+1 round on anything", which nothing has asked for.
#
# Storage: the host carries `attachments {slots: {slot_name: item}}` -- keyed by slot *name*, a
# String, so it survives the JSON round-trip a save makes; see CLAUDE.md on entity-keyed
# dictionaries. The attachment carries `attachedTo {host, slot}`, which is what keeps a fitted
# suppressor from also sitting loose in a pack.

const SimItemsRes = preload("res://sim/modules/items.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")

# Profile fields an attachment is allowed to scale, per kind. A table rather than "multiply
# anything present in both dictionaries", because that would let a typo -- `magsize`, `range` --
# be silently ignored *and* let a content edit reach a field the profile builder does not treat as
# scalable. check_m2_attach.gd asserts every declared key is in here.
const SCALABLE: Dictionary = {
	"melee": ["damage", "reachMetres", "staggerTicks", "speed"],
	"ranged": ["damage", "noise", "flash", "magSize", "reloadTicks", "rangeMetres", "cone"],
}


# Reachable the way a bench operation is reachable -- `item.modify` is the precedent, and an
# attachment that could only be fitted by a gate would be the seventh dead socket of the
# milestone. Two commands rather than one toggle, because "put this in that slot" and "take that
# off" carry different arguments and a toggle would have to guess which was meant.
static func register_module(world: Variant) -> void:
	world.systems.register("attachments.intake", "input", 10, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			var kind: String = String(c.get("type", ""))
			if kind == "item.attach":
				if not attach(w, int(c.get("host", -1)), int(c.get("item", -1)), String(c.get("slot", ""))):
					w.events.publish({"type": "attachment.refused", "item": int(c.get("item", -1)), "slot": String(c.get("slot", ""))})
			elif kind == "item.detach":
				if not detach(w, int(c.get("item", -1))):
					w.events.publish({"type": "attachment.refused", "item": int(c.get("item", -1)), "slot": ""})
	)


## The slot names this host declares, from its base. Empty for anything that takes no attachments.
static func slots_of(world: Variant, host: int) -> Array:
	var base: Variant = SimItemsRes.item_base_of(world, host)
	if not base is Dictionary:
		return []
	var raw: Variant = (base as Dictionary).get("slots", [])
	if not raw is Array:
		return []
	var out: Array = []
	for s in raw as Array:
		out.append(String(s))
	return out


## The `attachment` block on an item's base, or null if it is not an attachment at all.
static func spec_of(world: Variant, item: int) -> Variant:
	var base: Variant = SimItemsRes.item_base_of(world, item)
	if not base is Dictionary:
		return null
	var spec: Variant = (base as Dictionary).get("attachment")
	return spec if spec is Dictionary else null


## Whether this attachment is compatible with a slot name. Compatibility is the attachment's
## business, not the host's: `fits` lists slot names and any base that declares one takes it,
## which is what "move freely between compatible bases" means mechanically.
static func fits(world: Variant, attachment: int, slot: String) -> bool:
	var spec: Variant = spec_of(world, attachment)
	if not spec is Dictionary:
		return false
	for s in (spec as Dictionary).get("fits", []) as Array:
		if String(s) == slot:
			return true
	return false


## What is in each of this host's filled slots, as {slot_name: item}. A copy.
static func attached(world: Variant, host: int) -> Dictionary:
	var comp: Variant = world.components.get_component(host, "attachments")
	if not comp is Dictionary:
		return {}
	return ((comp as Dictionary).get("slots", {}) as Dictionary).duplicate()


static func in_slot(world: Variant, host: int, slot: String) -> int:
	var slots: Dictionary = attached(world, host)
	return int(slots.get(slot, -1)) if slots.has(slot) else -1


## Fits an attachment to a host slot. Refuses -- returning false and changing nothing -- when the
## host has no such slot, the attachment does not fit it, the slot is taken, or the attachment is
## already on something else. Every refusal is silent rather than an error: this is reachable from
## a player action and a wrong click is not a bug.
static func attach(world: Variant, host: int, attachment: int, slot: String) -> bool:
	if host == attachment:
		return false
	if not slots_of(world, host).has(slot):
		return false
	if not fits(world, attachment, slot):
		return false
	if world.components.has_component(attachment, "attachedTo"):
		return false
	if in_slot(world, host, slot) >= 0:
		return false
	# Out of whatever pack it was in. An attachment on a weapon is on the weapon -- leaving it in
	# the grid as well would let one object occupy two places and be dropped from one of them.
	SimInventoryRes.remove_from_container(world, attachment)
	var comp: Variant = world.components.get_component(host, "attachments")
	if not comp is Dictionary:
		comp = {"slots": {}}
		world.components.set_component(host, "attachments", comp)
	((comp as Dictionary)["slots"] as Dictionary)[slot] = attachment
	world.components.set_component(attachment, "attachedTo", {"host": host, "slot": slot})
	_refresh(world, host)
	world.events.publish({"type": "attachment.fitted", "host": host, "item": attachment, "slot": slot})
	return true


## Takes an attachment off. It is left carried by nothing -- the caller stows it or drops it,
## exactly as `SimInventory.unequip` leaves a weapon -- because this module has no opinion about
## where a loose object should go.
static func detach(world: Variant, attachment: int) -> bool:
	var link: Variant = world.components.get_component(attachment, "attachedTo")
	if not link is Dictionary:
		return false
	var host: int = int((link as Dictionary)["host"])
	var slot: String = String((link as Dictionary)["slot"])
	var comp: Variant = world.components.get_component(host, "attachments")
	if comp is Dictionary:
		var slots: Dictionary = (comp as Dictionary)["slots"] as Dictionary
		if slots.has(slot) and int(slots[slot]) == attachment:
			slots.erase(slot)
	world.components.remove(attachment, "attachedTo")
	_refresh(world, host)
	world.events.publish({"type": "attachment.removed", "host": host, "item": attachment, "slot": slot})
	return true


## Everything fitted to this host, in slot order, as its `attachment` spec. Sorted so two hosts
## with the same attachments fold in the same order -- with multipliers that cannot change the
## result, but float multiplication is not associative and a determinism gate would eventually
## find that out the expensive way.
static func specs_of(world: Variant, host: int) -> Array:
	var slots: Dictionary = attached(world, host)
	var names: Array = slots.keys()
	names.sort()
	var out: Array = []
	for name in names:
		var spec: Variant = spec_of(world, int(slots[name]))
		if spec is Dictionary:
			out.append(spec as Dictionary)
	return out


## Folds every fitted attachment's multipliers over a built weapon profile, in place, and returns
## it. `kind` is "melee" or "ranged" -- the same word the base's own block uses.
##
## Unknown keys are dropped rather than applied. See SCALABLE: silently multiplying whatever
## happens to match would make a typo in content behave like an attachment that does nothing, and
## "it does nothing" is the hardest bug in this codebase to see.
static func fold(world: Variant, host: int, kind: String, profile: Dictionary) -> Dictionary:
	var scalable: Array = SCALABLE.get(kind, []) as Array
	for spec in specs_of(world, host):
		var table: Variant = (spec as Dictionary).get(kind)
		if not table is Dictionary:
			continue
		for key in (table as Dictionary).keys():
			var field: String = String(key)
			if not scalable.has(field):
				continue
			if not profile.has(field):
				continue
			var factor: float = float((table as Dictionary)[field])
			var current: Variant = profile[field]
			if current is int:
				profile[field] = maxi(1, int(round(float(current) * factor)))
			else:
				profile[field] = float(current) * factor
	return profile


# An attachment changes the weapon, so the weapon a survivor is holding has to be rebuilt. The
# same call `apply_wear` and `repair_item` make, and for the same reason.
static func _refresh(world: Variant, host: int) -> void:
	SimItemsRes.refresh_armed(world, host)
