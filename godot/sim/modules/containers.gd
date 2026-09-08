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
# --- what a container *is*, since 2026-09-08 -----------------------------------------------
#
# It is a grid, the same `container {w, h, items}` component a pack carries, so taking something
# out of a cupboard is an ordinary `item.move` and every piece of machinery the inventory already
# has -- footprints, rotation, nesting depth, stacking -- works on it for free. That is the whole
# reason the shape was reused rather than invented: a second kind of container would have needed
# its own fit test, and two fit tests is one of them being wrong.
#
# What it costs is a reach guard. `item.move` had no actor and no distance check, which was safe
# while the only reachable containers were the ones on your own body; a cupboard across the room
# is not. `SimInventory` refuses a move touching a `searchable` unless the actor is *opening*
# that box and standing in reach of it -- the `opening` component is what says so.
#
# What did NOT change: `searched` is still set once and cleared by nothing, so depletion is
# exactly what it was; the table is still rolled once, on the first open; NPCs still reach a box
# through `search`, which opens it and tips the contents onto the floor where the Haul job has
# always looked for them.
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
const SimInventory = preload("res://sim/modules/inventory.gd")

# How close you have to stand. SimInventory.PICKUP_REACH, deliberately the same number: reaching
# into a cupboard and picking a tin off the floor are the same gesture, and two constants a metre
# apart would read as a bug the first time one of them moved.
const SEARCH_REACH: float = 1.5

# What a container is called when the map does not say. Kinds are free text from content -- they
# are prose, read by hud_clause and by `grid_for_kind` -- so this is a fallback rather than an enum.
const DEFAULT_KIND: String = "container"

# The grid a kind opens at when `content/containers/` has no entry for it. Small on purpose: a
# district is free to name a container nobody has sized yet, and the honest default is "not much
# fits", not "as much as a wardrobe". check_loot.gd asserts every kind a shipped district or
# template names *does* have an entry, so this is reachable only by content added without one.
const DEFAULT_GRID: Dictionary = {"w": 3, "h": 2}


static func register_module(world: Variant) -> void:
	# Order 9 in "input", after fortify.intake at 5: fortify's `use.context` already owns the E
	# key and its priority list, and this module answers the explicit verb only. A container is
	# reached through that list (see the `container.search` branch fortify._use_context routes
	# here), not by racing it.
	world.systems.register("containers.intake", "input", 9, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			match String(c.get("type", "")):
				"container.search":
					# The old verb, kept: it empties a box onto the floor without opening a screen,
					# which is what an NPC does and what a player got before the window existed.
					for actor in w.components.query(["controlled", "position"]):
						var res: Dictionary = search_nearest(w, int(actor))
						if not bool(res.get("ok", false)):
							# Same shape treatment.gd refuses in, so a screen that already listens
							# for one refusal vocabulary hears this one too.
							w.events.publish({"type": "container.refused", "entity": int(actor), "reason": String(res.get("reason", "unknown"))})
				"container.open":
					for actor2 in w.components.query(["controlled", "position"]):
						var res2: Dictionary = open_nearest(w, int(actor2))
						if not bool(res2.get("ok", false)):
							w.events.publish({"type": "container.refused", "entity": int(actor2), "reason": String(res2.get("reason", "unknown"))})
				"container.close":
					for actor3 in w.components.query(["controlled"]):
						close(w, int(actor3))
				"container.takeAll":
					for actor4 in w.components.query(["controlled", "position"]):
						take_all(w, int(actor4))
	)


# Stands a container. `location` is the loot table's bare name ("residential"); `kind` is what the
# thing is called out loud ("cupboard", "car boot").
static func make_container(world: Variant, x: float, y: float, kind: String, location: String) -> int:
	var ent: int = int(world.entities.spawn())
	var named: String = kind if kind != "" else DEFAULT_KIND
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "searchable", {
		"kind": named,
		"table": location,
		"searched": false,
	})
	# The same component a pack has, so everything the inventory can already do to a grid it can
	# do to a cupboard. Empty until somebody opens it: the table is rolled at that moment and not
	# before, which is what a container *is* (see the header).
	var grid: Dictionary = grid_for_kind(world, named)
	world.components.set_component(ent, "container", {"w": int(grid["w"]), "h": int(grid["h"]), "items": []})
	return ent


# How big a kind opens. Content, in `content/containers/`, matched on the kind word the district
# or the map site already uses -- so sizing a new container is a data edit and naming one nobody
# has sized is a small box rather than an error.
static func grid_for_kind(world: Variant, kind: String) -> Dictionary:
	for entry in SimItems.content_entries(world, "container"):
		var d: Dictionary = entry as Dictionary
		if String(d.get("kind", "")) != kind:
			continue
		var g: Variant = d.get("grid")
		if g is Dictionary:
			return {"w": int((g as Dictionary).get("w", DEFAULT_GRID["w"])), "h": int((g as Dictionary).get("h", DEFAULT_GRID["h"]))}
	return DEFAULT_GRID.duplicate()


# The nearest container in reach, or -1. Three modes, because three questions get asked of this
# and they have different answers about an emptied box:
#
#   ANY         includes a box that has been through, so `hud_clause` can say "you have already
#               been through this cupboard" rather than silently ignoring the thing in front of
#               you and doing something else instead.
#   UNSEARCHED  the roll has not happened yet -- what `search` wants.
#   OPENABLE    unsearched, *or* searched with something still in it. What the E ladder wants:
#               a cupboard you left half-full is still worth opening, and an empty one has to
#               fall through to the door behind it rather than swallowing the key.
enum Want { Any = 0, Unsearched = 1, Openable = 2 }
static func nearest(world: Variant, actor: int, only_unsearched: bool = false, want: int = -1) -> int:
	var mode: int = want if want >= 0 else (Want.Unsearched if only_unsearched else Want.Any)
	var here: Variant = world.components.get_component(actor, "position")
	if not (here is Dictionary):
		return -1
	var best: int = -1
	var best_sq: float = SEARCH_REACH * SEARCH_REACH
	for ent in world.components.query(["searchable", "position"]):
		var s: Dictionary = world.components.get_component(int(ent), "searchable") as Dictionary
		if mode == Want.Unsearched and bool(s.get("searched", false)):
			continue
		if mode == Want.Openable and bool(s.get("searched", false)) and contents_of(world, int(ent)).is_empty():
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


# What is in a container's grid, as entity ids. The pack's own accessor, so there is one answer to
# "what is in this box" for a cupboard and a rucksack alike.
static func contents_of(world: Variant, container: int) -> Array[int]:
	return SimInventory.contents_of(world, container)


# Empties a container onto the floor beside it. The verb NPCs use and the one the E ladder used
# before the transfer window existed: it opens the box (rolling the table if this is the first
# time) and then tips every cell out where the Haul job has always looked.
#
# The draw order is the one `SimLoot.scatter` made when this called it directly -- `open` uses
# `SimLoot.roll`, which is `scatter` minus the position writes -- so a seeded run yields exactly
# what it yielded before the grid existed. check_loot.gd's CONTAINER lane is what says so.
static func search(world: Variant, actor: int, container: int) -> Dictionary:
	var res: Dictionary = open(world, actor, container)
	if not bool(res.get("ok", false)):
		return res
	var at: Dictionary = world.components.get_component(container, "position") as Dictionary
	var spilt: int = 0
	var offset: float = 0.0
	# A duplicate, because `stow`/`remove_from_container` mutate the placement array this is
	# walking -- and by index rather than by handing an element back, because Array.erase on a
	# Dictionary matches by *value* and two identical records are indistinguishable to it
	# (CLAUDE.md's traps).
	for item in contents_of(world, container).duplicate():
		SimInventory.remove_from_container(world, int(item))
		world.components.set_component(int(item), "position", {"x": float(at["x"]) + offset, "y": float(at["y"])})
		offset += SimLoot.SPREAD_METRES
		spilt += 1
	close(world, actor)
	return {"ok": true, "reason": "", "yielded": spilt}


# Opens a container: rolls its table on the first open and never again, and marks the actor as
# standing at it so the screen can draw the grid and `item.move` will accept a transfer.
static func open(world: Variant, actor: int, container: int) -> Dictionary:
	var s: Variant = world.components.get_component(container, "searchable")
	if not (s is Dictionary):
		return {"ok": false, "reason": "not-a-container"}
	var state: Dictionary = s as Dictionary
	if not _in_reach(world, actor, container):
		return {"ok": false, "reason": "out-of-reach"}
	if not (world.components.get_component(container, "container") is Dictionary):
		# A container standing before this slice, restored from a save or built by an older
		# fixture, has no grid. Give it one rather than refusing: the alternative is a cupboard
		# that can never be opened and no way to tell why.
		var grid: Dictionary = grid_for_kind(world, String(state.get("kind", DEFAULT_KIND)))
		world.components.set_component(container, "container", {"w": int(grid["w"]), "h": int(grid["h"]), "items": []})

	if not bool(state.get("searched", false)):
		var location: String = String(state.get("table", ""))
		var table: Variant = SimLoot.table_for(world, location)
		if not (table is Dictionary):
			# A container naming a table nobody wrote would otherwise empty itself for nothing,
			# which is the worst of both: the site is spent and the player got nothing. Refuse and
			# stay unsearched. check_loot.gd asserts no shipped container can reach this.
			push_error("containers: %s names unknown loot table \"%s\"" % [String(state.get("kind", "?")), location])
			return {"ok": false, "reason": "unknown-table"}
		var at: Dictionary = world.components.get_component(container, "position") as Dictionary
		var rolled: Array = SimLoot.roll(world, table as Dictionary, SimLoot.stream(world))
		var offset: float = 0.0
		for item in rolled:
			# Into the grid, and onto the floor beside the box when it will not fit -- a table
			# generous enough to overflow a kitchen drawer must not silently lose what it rolled.
			if not SimInventory.store_anywhere(world, int(item), container):
				world.components.set_component(int(item), "position", {"x": float(at["x"]) + offset, "y": float(at["y"])})
				offset += SimLoot.SPREAD_METRES
		# Set AFTER the roll, so a roll that somehow throws leaves the container openable rather
		# than spending it for nothing. Never cleared -- see the header: depletion is the point.
		state["searched"] = true
		world.events.publish({
			"type": "container.searched",
			"entity": container,
			"actor": actor,
			"kind": String(state.get("kind", DEFAULT_KIND)),
			"table": location,
			"yielded": rolled.size(),
		})
	# An entity id stored as a *value*, not as a key: a Dictionary keyed by an entity id does not
	# survive the save round trip, because JSON has no integer keys (CLAUDE.md's traps).
	world.components.set_component(actor, "opening", {"container": container})
	world.events.publish({"type": "container.opened", "entity": container, "actor": actor, "kind": String(state.get("kind", DEFAULT_KIND))})
	return {"ok": true, "reason": "", "yielded": contents_of(world, container).size()}


# The nearest container worth opening, or a refusal that says which nothing it is.
static func open_nearest(world: Variant, actor: int) -> Dictionary:
	var target: int = nearest(world, actor, false, Want.Openable)
	if target < 0:
		return {"ok": false, "reason": "nothing-here" if nearest(world, actor, false) < 0 else "already-searched"}
	return open(world, actor, target)


static func close(world: Variant, actor: int) -> void:
	world.components.remove(actor, "opening")


# Which container this actor has open, or -1. Also the enforcement: a box that has gone out of
# reach is closed here rather than left open behind the player, so walking away from a cupboard
# ends the transfer the same way stepping back from a wound ends a bandage.
static func opened_by(world: Variant, actor: int) -> int:
	var o: Variant = world.components.get_component(actor, "opening")
	if not (o is Dictionary):
		return -1
	var container: int = int((o as Dictionary).get("container", -1))
	if container < 0 or not (world.components.get_component(container, "searchable") is Dictionary) or not _in_reach(world, actor, container):
		close(world, actor)
		return -1
	return container


# What the transfer window draws: the open container, or {} when there is none. Grid dimensions
# and cell coordinates are the only numbers in it, and they are a *shape* rather than a
# measurement -- docs/10's whole argument for a grid over a capacity bar.
static func open_view(world: Variant, actor: int) -> Dictionary:
	var container: int = opened_by(world, actor)
	if container < 0:
		return {}
	var box: Variant = world.components.get_component(container, "container")
	if not (box is Dictionary):
		return {}
	var state: Dictionary = world.components.get_component(container, "searchable") as Dictionary
	var items: Array = []
	for placement in (box as Dictionary).get("items", []) as Array:
		var p: Dictionary = placement as Dictionary
		items.append(SimInventory.view_of(world, int(p["item"]), p))
	return {
		"container": container,
		"label": String(state.get("kind", DEFAULT_KIND)),
		"w": int((box as Dictionary)["w"]),
		"h": int((box as Dictionary)["h"]),
		"items": items,
	}


# Everything that fits, into whatever the actor is carrying. What does not fit stays where it is,
# which is the honest answer and the one the grid already gives: you can see that the axe will not
# go in. Returns how many moved.
static func take_all(world: Variant, actor: int) -> int:
	var container: int = opened_by(world, actor)
	if container < 0:
		return 0
	var moved: int = 0
	# The duplicate, and the reason: `stow` mutates the array being walked.
	for item in contents_of(world, container).duplicate():
		if SimInventory.stow(world, actor, int(item)):
			moved += 1
	return moved


# What the survivor would say about what they are standing next to. Prose, no digits: the HUD ban
# is mechanical (godot:check:hud) and this is a player-facing read model. Empty string when there
# is nothing worth mentioning, which is the same silence needs.hud_clause keeps when you are well.
static func hud_clause(world: Variant, actor: int) -> String:
	var target: int = nearest(world, actor, false)
	if target < 0:
		return ""
	var s: Dictionary = world.components.get_component(target, "searchable") as Dictionary
	var kind: String = String(s.get("kind", DEFAULT_KIND))
	if not bool(s.get("searched", false)):
		return "There's a %s here worth going through." % kind
	# Three states rather than two since a container became a grid: a box you opened and did not
	# empty is not the same as one you finished, and telling the player they have "already been
	# through" a half-full cupboard is a lie the screen used to have no way to avoid.
	if not contents_of(world, target).is_empty():
		return "There's still something in this %s." % kind
	return "You have already been through this %s." % kind


static func _in_reach(world: Variant, actor: int, other: int) -> bool:
	var a: Variant = world.components.get_component(actor, "position")
	var b: Variant = world.components.get_component(other, "position")
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var dx: float = float((b as Dictionary)["x"]) - float((a as Dictionary)["x"])
	var dy: float = float((b as Dictionary)["y"]) - float((a as Dictionary)["y"])
	return dx * dx + dy * dy <= SEARCH_REACH * SEARCH_REACH
