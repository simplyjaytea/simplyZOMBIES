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
#
# **A part is an item, so it has a condition, and a worn part does less rather than something
# worse.** docs/10: "suppressors wear out fast and cost accuracy". Each declared multiplier is
# interpolated toward 1.0 by the part's own condition -- see `effect_scale` -- so a failing
# suppressor buys half the quiet it used to and a dead one buys none. That shape is deliberate and
# it is symmetric: an extended magazine decays toward holding a normal magazine, not toward
# holding nothing, and neither case needs anything to know whether a multiplier is a gain or a
# cost. The polarity question belongs to the screen, not to the fold.

const SimItemsRes = preload("res://sim/modules/items.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")

# Profile fields an attachment is allowed to scale, per kind. A table rather than "multiply
# anything present in both dictionaries", because that would let a typo -- `magsize`, `range` --
# be silently ignored *and* let a content edit reach a field the profile builder does not treat as
# scalable. check_m2_attach.gd asserts every declared key is in here.
const SCALABLE: Dictionary = {
	"melee": ["damage", "reachMetres", "staggerTicks", "speed"],
	"ranged": ["damage", "noise", "flash", "magSize", "reloadTicks", "rangeMetres", "cone", "handling"],
}

# Profile fields a part may *replace* rather than scale, per kind. A multiplier cannot express a
# caliber -- `ammo` is a base id and `jams` is a boolean -- so this is the narrow exception to
# "multipliers, never adders", with its own whitelist for the same reason SCALABLE has one.
#
# There is deliberately no "melee" key: an empty array would be a socket the gate then had to
# excuse by name. Add one when something melee needs replacing rather than scaling.
#
# **Resolved by agreement, not by order.** Every part that names a field is collected; one
# distinct value wins however many parts said it (a matched set -- a conversion barrel and the
# magazine that feeds it), and two distinct values are a *mismatch* that blocks the weapon
# outright. Slot-sorted last-wins was the alternative and it is worse: it makes the answer a
# function of the alphabet, so `barrel` would silently beat `internal` for a reason no player
# could ever learn. This rule is order-independent by construction rather than by convention.
const OVERRIDABLE: Dictionary = {
	"ranged": ["ammo", "jams"],
}

# What a part can declare it wears from, as a vocabulary the content picks words out of. The same
# arrangement as SCALABLE one level out, and for the same reason: a typo in `wearsOn` must not be
# indistinguishable from a part that never wears. Not a slot-to-event table in code, because the
# `barrel` slot holds both a suppressor and a long barrel and they do not wear alike -- and
# because "adding a kind of attachment is a data edit" is the rule this module exists to keep.
const WEAR_EVENTS: Array[String] = ["shot", "reload", "hit", "jam"]

# Wear a part takes from one event it declares, before its own `wearRate` multiplies it. Set
# against SimItems.WEAR_PER_SHOT (0.0015) so a plain part outlasts the weapon it is bolted to and
# a part declaring a rate above 1 does not: the suppressor at 3.0 reaches "failing" in about 133
# rounds where the pistol carrying it takes 333, which is docs/10's "wear out fast" as a number.
const PART_WEAR_PER_EVENT: float = 0.002

# How deep `assemble` will follow `defaultParts`. Parts declare none, so one level is all any
# shipped content needs; two is the belt to the CYCLE lane's braces. Passed through `options`
# rather than held in a static var, because a static is shared between the two worlds a gate
# boots and docs/30 records that trap twice already.
const MAX_ASSEMBLE_DEPTH: int = 2


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
				if not _may(w, int(c.get("item", -1))):
					w.events.publish({"type": "attachment.refused", "item": int(c.get("item", -1)), "slot": String(c.get("slot", "")), "reason": "no-bench"})
				elif not attach(w, int(c.get("host", -1)), int(c.get("item", -1)), String(c.get("slot", ""))):
					w.events.publish({"type": "attachment.refused", "item": int(c.get("item", -1)), "slot": String(c.get("slot", ""))})
			elif kind == "item.detach":
				if not _may(w, int(c.get("item", -1))):
					w.events.publish({"type": "attachment.refused", "item": int(c.get("item", -1)), "slot": "", "reason": "no-bench"})
				elif not detach(w, int(c.get("item", -1))):
					w.events.publish({"type": "attachment.refused", "item": int(c.get("item", -1)), "slot": ""})
	)

	# The same three channels SimItems wears the weapon on, plus the jam -- a stovepipe is hard on
	# whatever fed it. Each event names the acting weapon in `item`, so a part is only ever worn by
	# the gun it is actually bolted to.
	world.events.subscribe({"id": "attachments.wear-on-shot", "type": "weapon.fired", "handler": func(event: Dictionary) -> void:
		wear_parts(world, int(event.get("item", -1)), "shot")
	})
	world.events.subscribe({"id": "attachments.wear-on-reload", "type": "weapon.reloaded", "handler": func(event: Dictionary) -> void:
		wear_parts(world, int(event.get("item", -1)), "reload")
	})
	world.events.subscribe({"id": "attachments.wear-on-hit", "type": "attack.connected", "handler": func(event: Dictionary) -> void:
		wear_parts(world, int(event.get("item", -1)), "hit")
	})
	world.events.subscribe({"id": "attachments.wear-on-jam", "type": "weapon.jammed", "handler": func(event: Dictionary) -> void:
		wear_parts(world, int(event.get("item", -1)), "jam")
	})


# Whether the player may work on this part where they are standing: at a bench, or with something
# simple enough to change by hand. The check is on the *command* and not inside `attach` on
# purpose -- `attach` is what `assemble` calls when a weapon spawns and what a save restores
# through, and requiring a workbench for those would be absurd. This is the player's way in, which
# is where the fiction lives: the job is not harder in a field, you just have not got your tools.
#
# Loaded lazily, because gunsmith.gd preloads this file and a preload cycle is a parse error.
static func _may(world: Variant, part: int) -> bool:
	var Gunsmith: GDScript = load("res://sim/modules/gunsmith.gd") as GDScript
	if Gunsmith == null:
		return true
	return bool(Gunsmith.call("may_work", world, int(Gunsmith.call("acting", world)), part))


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


## Takes an attachment off and puts it somewhere. It used to leave the part carried by nothing --
## no `stored`, no `position`, no slot -- which is not "the caller decides" but "the part is gone",
## with nothing raised and nothing to pick up (docs/23 carried it as a defect). A detach now
## re-homes the part first and **refuses** if it cannot, so there is no path through this function
## that loses one.
static func detach(world: Variant, attachment: int) -> bool:
	var link: Variant = world.components.get_component(attachment, "attachedTo")
	if not link is Dictionary:
		return false
	var host: int = int((link as Dictionary)["host"])
	var slot: String = String((link as Dictionary)["slot"])
	# Before anything is unlinked, because a failed re-home has to change nothing at all.
	if not _rehome(world, host, attachment):
		return false
	var comp: Variant = world.components.get_component(host, "attachments")
	if comp is Dictionary:
		var slots: Dictionary = (comp as Dictionary)["slots"] as Dictionary
		if slots.has(slot) and int(slots[slot]) == attachment:
			slots.erase(slot)
	world.components.remove(attachment, "attachedTo")
	_refresh(world, host)
	world.events.publish({"type": "attachment.removed", "host": host, "item": attachment, "slot": slot})
	return true


## The actor holding this item in an equipment slot, or -1. `SimInventory._holder_of` answers a
## different question -- the container an item is *stored* in -- and an equipped weapon is stored
## in nothing.
static func carrier_of(world: Variant, item: int) -> int:
	for actor in world.components.query(["equipment"]):
		var eq: Variant = world.components.get_component(int(actor), "equipment")
		if not eq is Dictionary:
			continue
		for slot in ((eq as Dictionary).get("slots", {}) as Dictionary).keys():
			if int(((eq as Dictionary)["slots"] as Dictionary)[slot]) == item:
				return int(actor)
	return -1


## A detached part goes where its host is, down a ladder that ends in a refusal rather than in the
## part vanishing: into the carrier's pack, at the carrier's feet, beside a host lying on the
## ground, or into the container the host is sitting in.
static func _rehome(world: Variant, host: int, part: int) -> bool:
	var carrier: int = carrier_of(world, host)
	if carrier >= 0:
		if SimInventoryRes.stow(world, carrier, part):
			return true
		if world.components.has_component(carrier, "position"):
			return SimInventoryRes.drop_at_feet(world, carrier, part)
	var pos: Variant = world.components.get_component(host, "position")
	if pos is Dictionary:
		world.components.set_component(part, "position", {
			"x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"]),
		})
		return true
	var stored: Variant = world.components.get_component(host, "stored")
	if stored is Dictionary:
		var box: int = int((stored as Dictionary).get("container", -1))
		if box >= 0 and SimInventoryRes.store_anywhere(world, part, box):
			return true
	return false


## Wears every part on this host that declares the event, then rebuilds the host. Called from the
## three channels SimItems publishes; the host itself is worn there, not here.
static func wear_parts(world: Variant, host: int, event_word: String) -> void:
	if host < 0 or not WEAR_EVENTS.has(event_word):
		return
	for rec in parts_of(world, host):
		var spec: Dictionary = (rec as Dictionary)["spec"] as Dictionary
		var declared: Variant = spec.get("wearsOn", [])
		if not declared is Array:
			continue
		var wears: bool = false
		for word in declared as Array:
			if String(word) == event_word:
				wears = true
				break
		if not wears:
			continue
		_wear_one(world, host, int((rec as Dictionary)["item"]), PART_WEAR_PER_EVENT * float(spec.get("wearRate", 1.0)))


# A part is not equipped, so SimItems.apply_wear cannot help here twice over: its refresh finds no
# holder for a fitted part, and its break path calls `unequip_item` on something that was never
# equipped -- which is exactly the way a broken part would go missing. Wear is applied here and the
# *host* is what gets rebuilt.
static func _wear_one(world: Variant, host: int, part: int, amount: float) -> void:
	if part < 0 or amount <= 0.0:
		return
	var c: Variant = world.components.get_component(part, "condition")
	if not c is Dictionary:
		return
	var before: float = float((c as Dictionary).get("current", 1.0))
	if before <= 0.0:
		return
	var after: float = maxf(0.0, before - amount)
	(c as Dictionary)["current"] = after
	if after > 0.0:
		_refresh(world, host)
		return
	# Worn through: off it comes, and `detach` is what puts it somewhere. Announced on its own
	# event rather than `item.broke`, because a part falling off a weapon in your hands is a
	# different thing happening to the player than a weapon breaking.
	var slot: String = ""
	var link: Variant = world.components.get_component(part, "attachedTo")
	if link is Dictionary:
		slot = String((link as Dictionary).get("slot", ""))
	if detach(world, part):
		world.events.publish({"type": "attachment.broke", "host": host, "item": part, "slot": slot})


## Everything fitted to this host, in slot order, as {slot, item, spec}. Sorted so two hosts with
## the same attachments fold in the same order -- with multipliers that cannot change the result,
## but float multiplication is not associative and a determinism gate would eventually find that
## out the expensive way.
##
## This carries the part's *entity*, not just its spec, because the fold has to ask each part what
## condition it is in and wear has to reach each part individually. It replaced a `specs_of` that
## returned bare spec dictionaries and had exactly one caller.
static func parts_of(world: Variant, host: int) -> Array:
	var slots: Dictionary = attached(world, host)
	var names: Array = slots.keys()
	names.sort()
	var out: Array = []
	for name in names:
		var item: int = int(slots[name])
		var spec: Variant = spec_of(world, item)
		if spec is Dictionary:
			out.append({"slot": String(name), "item": item, "spec": spec as Dictionary})
	return out


## One declared multiplier, softened by the state the part is actually in.
##
##     effective = 1.0 + (declared - 1.0) * k,  k = SimItems.condition_factor(part)
##
## `condition_factor` is 1.0 at full condition and floors at CONDITION_FLOOR (0.55) for anything
## still alive, so a fitted part's multiplier travels at most 45% of the way back toward doing
## nothing before it breaks off entirely -- `_wear_one` detaches at zero, so the 0.0 case
## `condition_factor` returns for a dead item is not reachable through a fitted part. It is
## written to be total anyway rather than relying on that ordering.
##
## Chosen over `pow(declared, k)`, which trends to 1.0 as well and composes more prettily: this is
## one multiply, it is legible in a gate's error message, and the asymmetry it costs is invisible
## at the scale content authors.
static func effect_scale(world: Variant, part: int, declared: float) -> float:
	var k: float = SimItemsRes.condition_factor(world, part)
	return 1.0 + (declared - 1.0) * k


## Folds every fitted attachment's multipliers over a built weapon profile, in place, and returns
## it. `kind` is "melee" or "ranged" -- the same word the base's own block uses.
##
## Unknown keys are dropped rather than applied. See SCALABLE: silently multiplying whatever
## happens to match would make a typo in content behave like an attachment that does nothing, and
## "it does nothing" is the hardest bug in this codebase to see.
static func fold(world: Variant, host: int, kind: String, profile: Dictionary) -> Dictionary:
	var scalable: Array = SCALABLE.get(kind, []) as Array
	for rec in parts_of(world, host):
		var part: int = int((rec as Dictionary)["item"])
		var table: Variant = ((rec as Dictionary)["spec"] as Dictionary).get(kind)
		if not table is Dictionary:
			continue
		for key in (table as Dictionary).keys():
			var field: String = String(key)
			if not scalable.has(field):
				continue
			if not profile.has(field):
				continue
			# Read at fold time, never cached on the host: the profile is rebuilt from the base on
			# every refresh_armed, so a condition remembered here would be a condition from before
			# the last shot.
			var factor: float = effect_scale(world, part, float((table as Dictionary)[field]))
			var current: Variant = profile[field]
			if current is int:
				profile[field] = maxi(1, int(round(float(current) * factor)))
			else:
				profile[field] = float(current) * factor
	# Replacements last, and only where the parts agree. A field two parts disagree about keeps
	# the base's own value and blocks the weapon instead -- see blocked_reason -- because guessing
	# which part wins would be a rule with no way for a player to learn it.
	# Collected once: `fold` runs on every refresh_armed, which runs on every wear event, and
	# overrides_for walks every fitted part.
	var replacements: Dictionary = overrides_for(world, host, kind)
	for field_v in replacements.keys():
		var values: Array = replacements[field_v] as Array
		if values.size() == 1:
			profile[String(field_v)] = values[0]
	return profile


## The parts a base comes built with, as {slot: baseId}. Empty for anything that is one object.
static func default_parts_of(world: Variant, host: int) -> Dictionary:
	var base: Variant = SimItemsRes.item_base_of(world, host)
	if not base is Dictionary:
		return {}
	var raw: Variant = (base as Dictionary).get("defaultParts", {})
	return (raw as Dictionary).duplicate() if raw is Dictionary else {}


## Fits this host's default parts, spawning each one. Called by `spawn_item` on the way out, so a
## weapon arrives in the world already an assembly -- the base template is the receiver and the
## parts are real items with their own condition.
##
## Two things about it are load-bearing and neither is obvious:
##
## **It is not a subscriber on `item.spawned`.** `spawn_item` publishes and drains, and a handler
## that spawned entities during delivery would nest `deliver` inside `deliver` -- the determinism
## bug spawn_item's own comment records having already paid for once.
##
## **It draws no randomness.** Each part is spawned with an explicit `"scavenged"` tier, which
## skips `roll_tier` and returns before `roll_affixes` draws anything, so assembling a weapon
## cannot shift the `loot` stream for everything spawned after it. That is asserted, not assumed:
## check_m2_attach.gd's QUIET lane compares the stream position of a world that spawns assembled
## weapons against one that does not.
static func assemble(world: Variant, host: int, depth: int = 0) -> int:
	if depth >= MAX_ASSEMBLE_DEPTH:
		return 0
	var defaults: Dictionary = default_parts_of(world, host)
	if defaults.is_empty():
		return 0
	var slots: Array = slots_of(world, host)
	var names: Array = defaults.keys()
	names.sort()
	var fitted: int = 0
	for slot_v in names:
		var slot: String = String(slot_v)
		if not slots.has(slot) or in_slot(world, host, slot) >= 0:
			continue
		var part: int = SimItemsRes.spawn_item(world, String(defaults[slot]), {"tier": "scavenged", "assembleDepth": depth + 1})
		if part < 0:
			continue
		if attach(world, host, part, slot):
			fitted += 1
	return fitted


## The worst condition in this assembly: the host's own, and every *structural* part's. A gun is
## only as good as the barrel in it, which is what makes fitting a fresh barrel a repair -- and a
## repair that costs no ceiling, unlike `SimItems.repair_item`, because nothing was mended.
##
## Only structural parts count. An optic wearing out does not stop the rifle working; it simply
## stops helping, which `effect_scale` already says.
static func assembly_condition(world: Variant, host: int, own: float) -> float:
	var worst: float = own
	for rec in parts_of(world, host):
		var spec: Dictionary = (rec as Dictionary)["spec"] as Dictionary
		if not bool(spec.get("structural", false)):
			continue
		var c: Variant = world.components.get_component(int((rec as Dictionary)["item"]), "condition")
		if c is Dictionary:
			worst = minf(worst, float((c as Dictionary).get("current", 1.0)))
	return worst


## The slots this host cannot work without. A subset of `slots`, declared on the base -- a pistol
## needs a barrel and an action, a spear with no head is a stick.
static func required_slots_of(world: Variant, host: int) -> Array:
	var base: Variant = SimItemsRes.item_base_of(world, host)
	if not base is Dictionary:
		return []
	var raw: Variant = (base as Dictionary).get("requiredSlots", [])
	if not raw is Array:
		return []
	var out: Array = []
	for s in raw as Array:
		out.append(String(s))
	return out


# Which way is up, per profile field. +1 means more is better, -1 means less is. It lives here
# beside SCALABLE because it is a statement about the sim's own profile fields, not about a
# screen: a panel owning this would be presentation deciding what a number means, which is the one
# thing `ui/README.md` forbids.
#
# It is deliberately *not* read by `fold`. `effect_scale` walks a multiplier toward 1.0 without
# ever asking whether it was a gain or a cost, and keeping polarity out of that is what makes the
# decay symmetric.
const POLARITY: Dictionary = {
	"melee": {"damage": 1, "reachMetres": 1, "staggerTicks": 1, "speed": 1},
	"ranged": {
		"damage": 1, "noise": -1, "flash": -1, "magSize": 1, "reloadTicks": -1, "rangeMetres": 1,
		"cone": -1, "handling": 1,
	},
}

# What each field is called when a person reads it. The screen prints these; nothing computes with
# them. `cone` is the felt aim cone, so less of it is a steadier gun -- which is why the word is
# "steadiness" and the polarity is -1, and why neither is obvious enough to leave unwritten.
const FIELD_WORD: Dictionary = {
	"melee": {
		"damage": "stopping power", "reachMetres": "reach",
		"staggerTicks": "how hard it rocks them", "speed": "swing speed",
	},
	"ranged": {
		"damage": "stopping power", "noise": "how far it is heard", "flash": "muzzle flash",
		"magSize": "rounds it holds", "reloadTicks": "reload time", "rangeMetres": "reach",
		"cone": "steadiness", "handling": "how fast it comes up",
		"ammo": "the round it takes", "jams": "how it feeds",
	},
}


## Whether moving this field from `before` to `after` is an improvement. A pure predicate over the
## polarity table, so a gate can ask it about every field in both directions with no fixture at all.
static func better(kind: String, field: String, before: float, after: float) -> bool:
	var table: Variant = POLARITY.get(kind)
	if not table is Dictionary or not (table as Dictionary).has(field):
		return false
	return (after - before) * float((table as Dictionary)[field]) > 0.0


## The multiplier a part contributes to one field, softened by its condition, or 1.0 if it says
## nothing about that field. The arithmetic `fold` does, asked about one part.
static func multiplier_of(world: Variant, part: int, kind: String, field: String) -> float:
	if part < 0:
		return 1.0
	var spec: Variant = spec_of(world, part)
	if not spec is Dictionary:
		return 1.0
	var table: Variant = (spec as Dictionary).get(kind)
	if not table is Dictionary or not (table as Dictionary).has(field):
		return 1.0
	return effect_scale(world, part, float((table as Dictionary)[field]))


## What swapping the part in `slot` for `candidate` would change, as words and a direction. Never a
## magnitude: there is no delta in this view to print, so "no digits" is structural rather than a
## rule somebody has to remember. `change` is "better", "worse" or "different" -- the third for a
## replacement like a caliber, where the word improvement does not apply.
##
## Computed rather than simulated. Attaching the candidate to see what happens would mutate the
## world inside a read model; the fold is multiplicative, so the ratio between the two parts' own
## contributions is the whole answer.
static func compare_view(world: Variant, host: int, slot: String, candidate: int) -> Array:
	var out: Array = []
	var sitting: int = in_slot(world, host, slot)
	for kind_v in SCALABLE.keys():
		var kind: String = String(kind_v)
		if not _host_is(world, host, kind):
			continue
		for field_v in SCALABLE[kind] as Array:
			var field: String = String(field_v)
			var now: float = multiplier_of(world, sitting, kind, field)
			var then: float = multiplier_of(world, candidate, kind, field)
			if is_equal_approx(now, then):
				continue
			out.append({
				"field": field,
				"word": String((FIELD_WORD[kind] as Dictionary).get(field, field)),
				"change": "better" if better(kind, field, now, then) else "worse",
			})
	# Replacements are a change of kind, not of degree: a different round is neither an upgrade
	# nor a downgrade, and saying otherwise would be the screen inventing an opinion.
	for kind_v in OVERRIDABLE.keys():
		var kind2: String = String(kind_v)
		if not _host_is(world, host, kind2):
			continue
		for field_v in OVERRIDABLE[kind2] as Array:
			var field2: String = String(field_v)
			var now2: Variant = _override_of(world, sitting, kind2, field2)
			var then2: Variant = _override_of(world, candidate, kind2, field2)
			if str(now2) == str(then2):
				continue
			out.append({
				"field": field2,
				"word": String((FIELD_WORD[kind2] as Dictionary).get(field2, field2)),
				"change": "different",
			})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["field"]) < String(b["field"]))
	return out


static func _override_of(world: Variant, part: int, kind: String, field: String) -> Variant:
	if part < 0:
		return null
	var spec: Variant = spec_of(world, part)
	if not spec is Dictionary:
		return null
	var block: Variant = (spec as Dictionary).get("overrides")
	if not block is Dictionary:
		return null
	var table: Variant = (block as Dictionary).get(kind)
	return (table as Dictionary).get(field) if table is Dictionary else null


static func _host_is(world: Variant, host: int, kind: String) -> bool:
	var base: Variant = SimItemsRes.item_base_of(world, host)
	return base is Dictionary and (base as Dictionary).get(kind) is Dictionary


# What each slot is called when a sentence has to name it. `internal` is a slot name; "action" is
# what a person would say. Code-owned like WEAR_EVENTS, and asserted total against the slots any
# shipped base actually requires -- a missing noun would read as "has no ", which is worse than
# saying nothing.
const SLOT_NOUN: Dictionary = {
	"barrel": "barrel", "internal": "action", "magazine": "magazine", "furniture": "stock",
	"muzzle": "muzzle device", "optic": "sight", "sight": "sight",
	"limb": "limbs", "string": "string", "head": "head", "edge": "edge", "haft": "haft",
	"wrap": "grip wrap", "underbarrel": "underbarrel",
}


## Every override this host's parts declare for one kind, as {field: [distinct values]}. Values are
## kept in a plain Array and compared by their string form, because a distinct-value set must not
## depend on the order the parts were read in.
static func overrides_for(world: Variant, host: int, kind: String) -> Dictionary:
	var allowed: Array = OVERRIDABLE.get(kind, []) as Array
	var out: Dictionary = {}
	if allowed.is_empty():
		return out
	for rec in parts_of(world, host):
		var block: Variant = ((rec as Dictionary)["spec"] as Dictionary).get("overrides")
		if not block is Dictionary:
			continue
		var table: Variant = (block as Dictionary).get(kind)
		if not table is Dictionary:
			continue
		for key in (table as Dictionary).keys():
			var field: String = String(key)
			if not allowed.has(field):
				continue
			var value: Variant = (table as Dictionary)[field]
			if not out.has(field):
				out[field] = []
			var known: Array = out[field] as Array
			var seen: bool = false
			for v in known:
				if str(v) == str(value):
					seen = true
					break
			if not seen:
				known.append(value)
	return out


## Fields two fitted parts disagree about, sorted. A conversion barrel that takes one round and a
## cylinder that takes another is a weapon nobody can load, and saying so is better than picking
## one and leaving the player to work out why the ammunition vanishes.
static func override_conflicts(world: Variant, host: int) -> Array[String]:
	var bad: Array[String] = []
	for kind in OVERRIDABLE.keys():
		var table: Dictionary = overrides_for(world, host, String(kind))
		for field in table.keys():
			if (table[field] as Array).size() > 1:
				bad.append(String(field))
	bad.sort()
	return bad


## Why this weapon does not work, or `""` when it does. One computation, one field on the profile,
## read by every path that can start an attack -- see SimRanged.can_fire. A reason id rather than a
## sentence, because prose about a weapon belongs to the screen and this is sim state.
static func blocked_reason(world: Variant, host: int) -> String:
	var fitted: Dictionary = attached(world, host)
	var missing: Array = []
	for slot in required_slots_of(world, host):
		if not fitted.has(String(slot)):
			missing.append(String(slot))
	if not missing.is_empty():
		missing.sort()
		return "missing:%s" % String(missing[0])
	var clash: Array[String] = override_conflicts(world, host)
	if not clash.is_empty():
		return "mismatch:%s" % clash[0]
	return ""


## One sentence about the weapon in this entity's hands that will not work, or "" when both do.
## A read model: prose about sim state, built in the sim, no digits, and the screen only prints it.
## Read straight off the built profile rather than off a refusal event, so it is true whenever the
## HUD asks rather than only on the tick somebody pulled a trigger.
static func refusal_clause(world: Variant, entity: int) -> String:
	for comp in ["rangedWeapon", "meleeWeapon"]:
		var w: Variant = world.components.get_component(entity, comp)
		if not w is Dictionary:
			continue
		var reason: String = String((w as Dictionary).get("blocked", ""))
		if reason == "":
			continue
		if reason.begins_with("mismatch:"):
			return "Nothing in it will chamber the same round."
		if not reason.begins_with("missing:"):
			continue
		var slot: String = reason.substr("missing:".length())
		var noun: String = String(SLOT_NOUN.get(slot, ""))
		if noun == "":
			continue
		var name: String = "weapon"
		var base: Variant = SimItemsRes.item_base_of(world, int((w as Dictionary).get("source", -1)))
		if base is Dictionary:
			name = String((base as Dictionary).get("name", "weapon")).to_lower()
		return "The %s has no %s." % [name, noun]
	return ""


# An attachment changes the weapon, so the weapon a survivor is holding has to be rebuilt. The
# same call `apply_wear` and `repair_item` make, and for the same reason.
static func _refresh(world: Variant, host: int) -> void:
	SimItemsRes.refresh_armed(world, host)
