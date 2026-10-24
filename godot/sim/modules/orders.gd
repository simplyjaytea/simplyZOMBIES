class_name SimOrders
extends RefCounted
# Colonist orders -- plan item A16, the colony half of the alpha. The player picks a colonist on
# the street (the click `main._selected` already holds) and right-clicks a tile or a loose item;
# the menu offers what that colonist may be told to do, and the sim decides the offer.
#
# Three orders, one command: `colonist.order` with `kind` of `go`, `hold` or `haul`, or `clear` to
# stand the colonist down. What each does while it runs lives in `jobs.gd`'s `_follow_order`, next
# to the job machinery it borrows (`_advance_job` for a haul, `SimWalk` for a walk), because the
# job module is what a colonist's feet already belong to. This file owns what may be ordered and
# what the screen says about it -- and it preloads `jobs.gd`, so `jobs.gd` must never preload this
# one (a preload ring is a parse error, see health.gd).
#
# The rule `context.gd` keeps for every row holds here too: an order is offered iff `accepts`
# would take it, so the menu never draws a thing the sim will then refuse.

const SimJobs = preload("res://sim/modules/jobs.gd")
const SimPath = preload("res://sim/path.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAllegiance = preload("res://sim/modules/allegiance.gd")
const SimHealth = preload("res://sim/modules/health.gd")

const COMMAND: String = "colonist.order"


# Takes orders at all: the same filters `SimJobs._tick` applies before it ever asks what a body
# wants, so a colonist refused a job is refused an order for the same reason. The player is never
# a colonist under orders, and a recruit (a captive, not yet a colonist) is not one either.
static func takes_orders(world: Variant, ent: int) -> bool:
	if ent < 0 or ent == int(world.player) or not world.entities.is_alive(ent):
		return false
	if not world.components.has_component(ent, "jobPriorities") or not world.components.has_component(ent, "position"):
		return false
	for c in ["controlled", "recruit", "leaving", "corpse", "grabbed"]:
		if world.components.has_component(ent, c):
			return false
	return true


static func holds(world: Variant, ent: int) -> bool:
	return world.components.has_component(ent, SimJobs.ORDER_COMPONENT)


# Whether `command` (`kind` plus its arguments) would be accepted for `ent`. The menu and the
# intake both ask this, and nothing else decides it.
static func accepts(world: Variant, ent: int, command: Dictionary) -> bool:
	if not takes_orders(world, ent):
		return false
	var kind: String = String(command.get("kind", ""))
	match kind:
		"go":
			# Walking to the tile you are standing on is not an order; there is nothing to walk.
			var tile := Vector2i(int(command.get("tx", -1)), int(command.get("ty", -1)))
			return SimPath.walkable(world, tile.x, tile.y) and tile != _tile_of(world, ent)
		"hold":
			return SimPath.walkable(world, int(command.get("tx", -1)), int(command.get("ty", -1)))
		"haul":
			return _haulable(world, ent, int(command.get("target", -1)))
		"attack":
			return _attackable(world, ent, int(command.get("target", -1)))
		"clear":
			return holds(world, ent)
	return false


# A hostile body the colonist or the player can see this instant. Zombies and raiders only: a
# colonist is never an attack target, and a corpse is never one. The scarce-information rule holds
# here too -- nobody orders a swing at a thing nobody can see.
static func _attackable(world: Variant, ent: int, target: int) -> bool:
	if target < 0 or not world.entities.is_alive(target) or world.components.has_component(target, "corpse"):
		return false
	if not world.components.has_component(target, "position"):
		return false
	var body: Variant = world.components.get_component(target, "body")
	if not (body is Dictionary) or not SimHealth.is_alive(body as Dictionary):
		return false
	if not SimAllegiance.hostile(world, ent, target):
		return false
	return _seen_by_either(world, ent, target)


static func _seen_by_either(world: Variant, ent: int, target: int) -> bool:
	var there: Variant = world.components.get_component(target, "position")
	if not (there is Dictionary) or world.vision == null:
		return false
	var x: float = float((there as Dictionary)["x"])
	var y: float = float((there as Dictionary)["y"])
	for observer in [ent, int(world.player)]:
		if int(world.vision.detail(observer, x, y)) > 0:
			return true
	return false


# A loose item on the ground that is not already where a stockpile wants it. A corpse is not an
# item to haul under an order: the corpse dump is the Haul job's own overflow rule, not a choice a
# player makes one body at a time.
static func _haulable(world: Variant, ent: int, item: int) -> bool:
	if item < 0 or not world.entities.is_alive(item):
		return false
	if not world.components.has_component(item, "itemBase") or world.components.has_component(item, "stored"):
		return false
	if world.components.has_component(item, "corpse") or not world.components.has_component(item, "position"):
		return false
	var p: Dictionary = world.components.get_component(item, "position") as Dictionary
	if SimNeeds.is_stockpile_tile(world, floori(float(p["x"])), floori(float(p["y"]))):
		return false
	return not _carried_off_by_another(world, ent, item)


# An item another living colonist's live Haul job is already carrying off (its `reserved` record
# names that colonist and the job). The row is then simply absent, so two colonists are not sent
# to one item. An order that has only reserved the item and has no job yet does not count: the
# reservation holds the item for its colonist, it does not stop someone else from being offered it.
static func _carried_off_by_another(world: Variant, ent: int, item: int) -> bool:
	var claim: Variant = world.components.get_component(item, "reserved")
	if not (claim is Dictionary):
		return false
	var by: int = int((claim as Dictionary).get("by", -1))
	if by < 0 or by == ent or not world.entities.is_alive(by) or world.components.has_component(by, "corpse"):
		return false
	var job: Variant = world.components.get_component(by, "job")
	return job is Dictionary and String((job as Dictionary).get("kind", "")) == "Haul" and int((job as Dictionary).get("target", -1)) == item


# Take one order, if it is accepted. Whatever the colonist was doing is dropped first, so the
# order starts from a clean slate and the job's claim on its item is released the usual way.
static func issue(world: Variant, command: Dictionary) -> bool:
	var ent: int = int(command.get("entity", -1))
	if not accepts(world, ent, command):
		return false
	var kind: String = String(command.get("kind", ""))
	if kind == "clear":
		SimJobs.end_order(world, ent, "stood-down")
		return true
	SimJobs.drop_job(world, ent)
	var order: Dictionary = {"kind": kind, "path": [], "pathGen": -1}
	if kind == "haul":
		order["target"] = int(command.get("target", -1))
		SimJobs.reserve_item(world, ent, int(order["target"]))
	elif kind == "attack":
		order["target"] = int(command.get("target", -1))
	else:
		order["tx"] = int(command.get("tx", 0))
		order["ty"] = int(command.get("ty", 0))
	world.components.set_component(ent, SimJobs.ORDER_COMPONENT, order)
	return true


## The command the draft key pushes for `ent`, decided here so the screen decides nothing: a colonist
## under an order is stood down (`clear`), and a free one is held on the tile they stand on. {} when
## they take no orders, or when the hold would not be accepted.
static func draft_command(world: Variant, ent: int) -> Dictionary:
	if not takes_orders(world, ent):
		return {}
	if holds(world, ent):
		return {"type": COMMAND, "entity": ent, "kind": "clear"}
	var tile: Vector2i = _tile_of(world, ent)
	if not accepts(world, ent, {"entity": ent, "kind": "hold", "tx": tile.x, "ty": tile.y}):
		return {}
	return {"type": COMMAND, "entity": ent, "kind": "hold", "tx": tile.x, "ty": tile.y}


static func register_module(world: Variant) -> void:
	# Sorted after `jobs.intake` (14), which handles the job rows a player edits. An order issued
	# on a tick is in force from the `jobs.ai` pass of that same tick.
	world.systems.register("orders.intake", "input", 15, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) == COMMAND:
				issue(w, c)
	)


## Where a colonist's order is taking them, as a tile: the spot for a walk or a hold, the item's tile
## for a haul, the target's tile for an attack. (-1, -1) when there is no order, or the item or the
## target is gone (or the item stocked already).
static func destination(world: Variant, ent: int) -> Vector2i:
	var order: Variant = world.components.get_component(ent, SimJobs.ORDER_COMPONENT)
	if not (order is Dictionary):
		return Vector2i(-1, -1)
	var d: Dictionary = order as Dictionary
	var kind: String = String(d.get("kind", ""))
	if kind != "haul" and kind != "attack":
		return Vector2i(int(d.get("tx", -1)), int(d.get("ty", -1)))
	var item: int = int(d.get("target", -1))
	if item < 0 or not world.entities.is_alive(item) or not world.components.has_component(item, "position"):
		return Vector2i(-1, -1)
	return _tile_of(world, item)


## What the HUD says about a colonist's order, in prose with no digits: the one line the player
## reads to know what a colonist is doing for them. "" when there is no order.
static func hud_clause(world: Variant, actor: int) -> String:
	var order: Variant = world.components.get_component(actor, SimJobs.ORDER_COMPONENT)
	if not (order is Dictionary):
		return ""
	var d: Dictionary = order as Dictionary
	match String(d.get("kind", "")):
		"go":
			return "On the way to the spot you picked."
		"hold":
			return "Holding the spot you picked, and taking no work."
		"haul":
			var item: int = int(d.get("target", -1))
			if item < 0 or not world.entities.is_alive(item):
				return "Hauling something to the stockpile."
			return "Hauling the %s to the stockpile." % SimItems.item_name(world, item).to_lower()
		"attack":
			return "Going after the one you pointed at."
	return ""


static func _tile_of(world: Variant, ent: int) -> Vector2i:
	var p: Variant = world.components.get_component(ent, "position")
	if not (p is Dictionary):
		return Vector2i(-1, -1)
	return Vector2i(floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"])))
