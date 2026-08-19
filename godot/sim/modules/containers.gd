extends RefCounted
# World containers: a car boot, a kitchen cupboard, a supply locker. Something that stands in the
# district holding a loot table until somebody opens it, and is empty afterwards.
#
# docs/12 asks for exactly this and rules out the easy version in the same breath: scavenged
# resources are "finite, risk-gated, off-site", and **resource respawn timers are on the cut
# list** because they "would defuse the expanding-radius pressure, which is load-bearing". So a
# container is searched once. `searched` is set and never cleared, by anything, ever -- that is
# what site depletion *is* here, and it is why there is no timer, no counter and no refill path
# below to go looking for.
#
# The difference between a container and a scattered loot site is *when* the table is rolled, and
# nothing else. SimBoot.place_loot scatters a plain site at boot and stands a container for a site
# that declares `container`; both go through SimLoot with the same table and the same `lootTable`
# stream. A player who walks into a room of loose tins and a player who opens the cupboard those
# tins were in are drawing from one distribution.
#
# What this module deliberately does NOT do:
#
#  - **No channel.** Searching is instant. treatment.gd's channel machinery exists for things you
#    can be interrupted out of, and the interesting risk in a scavenging run is the walk there and
#    the noise on the way back, not a progress bar in an empty room. If a search ever needs to be
#    interruptible, fortify.gd's channel is the template to copy and this comment is the record
#    that it was a decision rather than an omission.
#  - **No numbers to the player.** `hud_clause` says there is something here and whether it has
#    been through; it never says how much came out. godot:check:hud allows no digits on the player
#    HUD but the day counter, and information staying scarce is a standing ban, not a preference.

const SimLoot = preload("res://sim/loot.gd")
const SimItems = preload("res://sim/modules/items.gd")

# How close you have to stand. SimInventory.PICKUP_REACH, deliberately the same number: reaching
# into a cupboard and picking a tin off the floor are the same gesture, and two constants a metre
# apart would read as a bug the first time one of them moved.
const SEARCH_REACH: float = 1.5

# What a container is called when the map does not say. Kinds are free text from content -- they
# are prose, read only by hud_clause -- so this is a fallback rather than an enum.
const DEFAULT_KIND: String = "container"


static func register_module(world: Variant) -> void:
	# Order 9 in "input", after fortify.intake at 5: fortify's `use.context` already owns the E
	# key and its priority list, and this module answers the explicit verb only. A container is
	# reached through that list (see the `container.search` branch fortify._use_context routes
	# here), not by racing it.
	world.systems.register("containers.intake", "input", 9, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			if String((cmd as Dictionary).get("type", "")) != "container.search":
				continue
			for actor in w.components.query(["controlled", "position"]):
				var res: Dictionary = search_nearest(w, int(actor))
				if not bool(res.get("ok", false)):
					# Same channel treatment.gd refuses on, so a screen that already listens for
					# one refusal vocabulary hears this one too.
					w.events.publish({"type": "container.refused", "entity": int(actor), "reason": String(res.get("reason", "unknown"))})
	)


# Stands a container. `location` is the loot table's bare name ("residential"); `kind` is what the
# thing is called out loud ("cupboard", "car boot").
static func make_container(world: Variant, x: float, y: float, kind: String, location: String) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "searchable", {
		"kind": kind if kind != "" else DEFAULT_KIND,
		"table": location,
		"searched": false,
	})
	return ent


# The nearest container in reach, searched or not, or -1. Searched ones are included on purpose:
# `context()` needs to be able to say "you have already been through it" rather than silently
# skipping a cupboard the player is standing in front of and doing something else instead.
static func nearest(world: Variant, actor: int, only_unsearched: bool = false) -> int:
	var here: Variant = world.components.get_component(actor, "position")
	if not (here is Dictionary):
		return -1
	var best: int = -1
	var best_sq: float = SEARCH_REACH * SEARCH_REACH
	for ent in world.components.query(["searchable", "position"]):
		var s: Dictionary = world.components.get_component(int(ent), "searchable") as Dictionary
		if only_unsearched and bool(s.get("searched", false)):
			continue
		var p: Dictionary = world.components.get_component(int(ent), "position") as Dictionary
		var dx: float = float(p["x"]) - float((here as Dictionary)["x"])
		var dy: float = float(p["y"]) - float((here as Dictionary)["y"])
		var sq: float = dx * dx + dy * dy
		if sq <= best_sq:
			best_sq = sq
			best = int(ent)
	return best


# Opens the nearest unsearched container in reach. Returns {ok, reason} in the shape treatment.gd
# and SimInfection's five responses already use, so the screen never has to invent a second
# vocabulary for the same refusal.
static func search_nearest(world: Variant, actor: int) -> Dictionary:
	var target: int = nearest(world, actor, true)
	if target < 0:
		# Distinguish the two failures: nothing here at all, versus a cupboard already emptied.
		# They read identically from a distance and mean completely different things to a player
		# deciding whether this building is worth the walk.
		return {"ok": false, "reason": "nothing-here" if nearest(world, actor, false) < 0 else "already-searched"}
	return search(world, actor, target)


static func search(world: Variant, actor: int, container: int) -> Dictionary:
	var s: Variant = world.components.get_component(container, "searchable")
	if not (s is Dictionary):
		return {"ok": false, "reason": "not-a-container"}
	var state: Dictionary = s as Dictionary
	if bool(state.get("searched", false)):
		return {"ok": false, "reason": "already-searched"}
	if not _in_reach(world, actor, container):
		return {"ok": false, "reason": "out-of-reach"}

	var location: String = String(state.get("table", ""))
	var table: Variant = SimLoot.table_for(world, location)
	if not (table is Dictionary):
		# A container naming a table nobody wrote would otherwise empty itself for nothing, which
		# is the worst of both: the site is spent and the player got nothing. Refuse and stay
		# unsearched. check_loot.gd asserts no shipped container can reach this.
		push_error("containers: %s names unknown loot table \"%s\"" % [String(state.get("kind", "?")), location])
		return {"ok": false, "reason": "unknown-table"}

	var at: Dictionary = world.components.get_component(container, "position") as Dictionary
	var yielded: Array = SimLoot.scatter(world, table as Dictionary, SimLoot.stream(world), float(at["x"]), float(at["y"]))
	# Set AFTER the scatter, so a scatter that somehow throws leaves the container openable rather
	# than spending it for nothing. Never cleared -- see the header: depletion is the whole point.
	state["searched"] = true
	world.events.publish({
		"type": "container.searched",
		"entity": container,
		"actor": actor,
		"kind": String(state.get("kind", DEFAULT_KIND)),
		"table": location,
		"yielded": yielded.size(),
	})
	return {"ok": true, "reason": "", "yielded": yielded.size()}


# What the survivor would say about what they are standing next to. Prose, no digits: the HUD ban
# is mechanical (godot:check:hud) and this is a player-facing read model. Empty string when there
# is nothing worth mentioning, which is the same silence needs.hud_clause keeps when you are well.
static func hud_clause(world: Variant, actor: int) -> String:
	var target: int = nearest(world, actor, false)
	if target < 0:
		return ""
	var s: Dictionary = world.components.get_component(target, "searchable") as Dictionary
	var kind: String = String(s.get("kind", DEFAULT_KIND))
	if bool(s.get("searched", false)):
		return "You have already been through this %s." % kind
	return "There's a %s here worth going through." % kind


static func _in_reach(world: Variant, actor: int, other: int) -> bool:
	var a: Variant = world.components.get_component(actor, "position")
	var b: Variant = world.components.get_component(other, "position")
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var dx: float = float((b as Dictionary)["x"]) - float((a as Dictionary)["x"])
	var dy: float = float((b as Dictionary)["y"]) - float((a as Dictionary)["y"])
	return dx * dx + dy * dy <= SEARCH_REACH * SEARCH_REACH
