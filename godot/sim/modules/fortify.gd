class_name SimFortify
extends RefCounted

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimCampRes = preload("res://sim/modules/camp.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimVehicles = preload("res://sim/modules/vehicles.gd")

const REACH: float = 1.5
const CHANNEL_TICKS: int = 40
const CONSTRUCT_NOISE: float = 30.0
const ALARM_NOISE: float = 8.0
const NOISEMAKER_MAG: float = 45.0
const NOISEMAKER_TICKS: int = 12000
const CONTACT_PER_STAGE: int = 40
const WINDOW_PROSE: Array[String] = ["intact", "scratched", "splintering", "gaps, light leaking"]

# --- build materials -----------------------------------------------------------------------
#
# docs/12-resources.md's gathered and refined tiers, and the owner's decision of 2026-09-12:
# **typed materials, uniform cost**. Until this slice one id -- `item.scrap.metal` -- was welded
# into a `SCRAP_ID` constant here and into a second copy of the same constant in jobs.gd, and it
# was the only substance in the game that could raise anything. Eleven `material`-class bases sat
# beside it in the roster able to build nothing at all. A recipe now names a *kind* and content
# declares which kind a thing is (`buildMaterial`, item.schema.json), so a timber wall can want
# wood and a scrap barricade metal without either of them being a code change.
#
# MATERIAL_KINDS is the vocabulary. It is code rather than content for the reason
# SimModification.OPERATIONS is: the registry is the authority and a duplicated list would drift
# from it. Neither this array nor the schema's enum can see the other, so
# check_m2_materials.gd's KINDS lane asserts both directions -- every kind here is declared by
# some shipped base, and every kind some shipped base declares is one of these. A kind that is
# not in this list is not a build material as far as `material_of` is concerned, which is what
# keeps a typo in content from quietly becoming a thirteenth substance.
const MATERIAL_KINDS: Array[String] = [
	"metal", "wood", "plank", "stone", "fiber", "cordage",
	"fixings", "ingot", "charcoal", "clay", "wire", "circuit",
]

# What each recipe is made of, keyed by the verb `_complete` dispatches on -- plus `repair`,
# which is SimJobs' Repair job rather than a channel here, and which was the second home of the
# deleted weld. One table, so a recipe's substance is written down once.
#
# A verb absent from this table is free and stays free: boarding a window, laying an alarm line,
# setting a noisemaker, winding it and establishing a camp all cost nothing today, and this slice
# is additive, so they cost nothing after it. How *much* a recipe costs is not here either -- one
# unit a stage, and the owner kept per-recipe quantity closed; the bench's standing three is
# still SimGunsmith.BENCH_SCRAP, exactly where it already was.
const RECIPES: Dictionary = {"scrap": "metal", "bench": "metal", "repair": "metal"}


## What a recipe is built out of. An unknown verb answers "" -- and "" is not a kind, so
## `carried_material` finds nothing for it and a verb nobody wrote a recipe for cannot be built
## by accident rather than being built out of the first thing in the pack.
static func recipe_kind(verb: String) -> String:
	return String(RECIPES.get(verb, ""))


## The build material this item is made of, or "" when it is not one. The single reader of the
## `buildMaterial` content key: a whetstone is a `material` by class and is not a build material,
## and a base declaring a kind MATERIAL_KINDS has never heard of is not one either.
static func material_of(world: Variant, item: int) -> String:
	var base: Variant = SimItems.item_base_of(world, item)
	if not base is Dictionary:
		return ""
	var kind: String = String((base as Dictionary).get("buildMaterial", ""))
	return kind if MATERIAL_KINDS.has(kind) else ""


## The first unit of `kind` this actor is carrying, or -1. `SimInventory.best_by_content_key` is
## the shared flat-content-key scan the medical grades landed; a kind is matched exactly rather
## than ranked, so the order handed to it is the one kind asked for and nothing else qualifies.
static func carried_material(world: Variant, actor: int, kind: String) -> int:
	if not MATERIAL_KINDS.has(kind):
		return -1
	var order: Array[String] = [kind]
	var found: Dictionary = SimInventory.best_by_content_key(world, actor, "buildMaterial", order, "material")
	return int(found.get("item", -1))


## How many units of `kind` this actor is carrying, counting stacks. `carried_material` answers
## "any"; a bench costs more than one.
static func material_count(world: Variant, actor: int, kind: String) -> int:
	if not MATERIAL_KINDS.has(kind):
		return 0
	var n: int = 0
	for item in SimInventory.carried_items(world, actor):
		if material_of(world, int(item)) != kind:
			continue
		var stack: Variant = world.components.get_component(int(item), "stack")
		n += int((stack as Dictionary).get("count", 1)) if stack is Dictionary else 1
	return n


## Spend one unit of `kind`. A stack loses a count; a single is removed from wherever it was
## stowed and despawned.
static func consume_material(world: Variant, actor: int, kind: String) -> bool:
	var item: int = carried_material(world, actor, kind)
	if item < 0:
		return false
	var stack: Variant = world.components.get_component(item, "stack")
	if stack is Dictionary and int((stack as Dictionary).get("count", 1)) > 1:
		(stack as Dictionary)["count"] = int((stack as Dictionary)["count"]) - 1
		return true
	SimInventory.remove_from_container(world, item)
	world.despawn(item)
	return true

# Pressing (the owner's decision 8, second half; docs/15's crowd). A barrier takes pressure from
# the dead whose wanted move it stopped this tick -- the kernel's `pressX`/`pressY` -- and a
# crowd presses harder than its number: n bodies press n x (1 + 0.5 x (n - 1)), so one is 1,
# two 3, three 6, four 10. Each kind has a cost per stage; four stages and it gives: a board or a
# barricade is gone, a door hangs off its hinges (stage DOOR_BROKEN, a doorway for good).
# `fortify.breached` says which kind. A body standing beside a barrier with nowhere it wants to
# go presses nothing -- the old passive adjacency wear is gone with this.
const STAGE_COST: Dictionary = {"board": 40, "door": 160, "scrap": 90}
const DOOR_PROSE: Array[String] = ["shut", "rattling", "splintering", "hanging off its hinges"]


static func register_module(world: Variant) -> void:
	world.systems.register("fortify.intake", "input", 5, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			var kind: String = String(c.get("type", ""))
			for actor in w.components.query(["controlled", "position"]):
				# A body mid-channel is inert to E: mid-board, and mid-pour (SimVehicles' refuel
				# channel), a refusal is a no-op rather than a fall through to the rungs below.
				if w.components.has_component(int(actor), "construct") or w.components.has_component(int(actor), "refuel"):
					continue
				if kind == "use.context":
					_use_context(w, int(actor))
				else:
					_intake_verb(w, int(actor), c)
	)
	world.systems.register("fortify.channel", "structures", 0, func(w: Variant) -> void:
		for entity in w.components.query(["construct", "position"]):
			_tick_channel(w, int(entity))
	)
	world.systems.register("fortify.alarm", "structures", 10, func(w: Variant) -> void:
		_tick_alarm(w)
	)
	world.systems.register("fortify.bait", "structures", 20, func(w: Variant) -> void:
		_tick_noisemaker(w)
	)
	world.systems.register("fortify.contact", "structures", 30, func(w: Variant) -> void:
		_tick_contact(w)
	)
	world.systems.register("fortify.doors", "structures", 5, func(w: Variant) -> void:
		_tick_doors(w)
	)
	world.events.subscribe({"id": "fortify.stagger-interrupts", "type": "entity.staggered", "handler": func(event: Dictionary) -> void:
		_cancel(world, int(event.get("entity", -1)))
	})
	world.events.subscribe({"id": "fortify.grab-interrupts", "type": "grab.started", "handler": func(event: Dictionary) -> void:
		_cancel(world, int(event.get("victim", -1)))
	})


# --- doors ---------------------------------------------------------------------------------
#
# A door is a Door tile (SimTileMap.Tile.Door, the class) and a `door` entity on it (the
# state): {tx, ty, open, stage, latched, emptySinceTick}. Closed it is solid and opaque; open or
# broken (stage DOOR_BROKEN) it is a doorway. People open a closed one as the step through it
# (SimJobs._walk, SimRaiders._walk); it swings shut DOOR_SWING_TICKS after the tile empties
# unless somebody latched it; the player's E toggles and latches. The dead never open a door --
# the pressing slice is how they get through one. The owner's decision 8, first half.
const DOOR_SWING_TICKS: int = 60
const DOOR_BROKEN: int = 4


static func spawn_doors(world: Variant, map: Variant) -> int:
	var made: int = 0
	for y in int(map.h):
		for x in int(map.w):
			if int(map.tiles[y * int(map.w) + x]) != SimTileMap.Tile.Door:
				continue
			if door_at(world, x, y) >= 0:
				continue
			# No `position`: a door is addressed by its tile (`door_at`), and a positioned entity
			# is a thing the renderer expects to draw and the look gate expects to resolve.
			var ent: int = int(world.entities.spawn())
			world.components.set_component(ent, "door", {"tx": x, "ty": y, "open": false, "stage": 0, "latched": false, "emptySinceTick": int(world.tick)})
			made += 1
	if made > 0:
		sync_map(world)
	return made


static func door_at(world: Variant, tx: int, ty: int) -> int:
	for entity in world.components.query(["door"]):
		var d: Variant = world.components.get_component(int(entity), "door")
		if d is Dictionary and int((d as Dictionary).get("tx", -1)) == tx and int((d as Dictionary).get("ty", -1)) == ty:
			return int(entity)
	return -1


static func door_state(world: Variant, tx: int, ty: int) -> Variant:
	var ent: int = door_at(world, tx, ty)
	if ent < 0:
		return null
	return world.components.get_component(ent, "door")


# Open a closed door. `latched` is the player's hand (E): a latched-open door never swings shut.
# A walker's open is unlatched, so the door closes behind them. A broken door is open already.
static func open_door(world: Variant, tx: int, ty: int, latched: bool = false) -> bool:
	var d: Variant = door_state(world, tx, ty)
	if not d is Dictionary:
		return false
	var dd: Dictionary = d as Dictionary
	if bool(dd.get("open", false)):
		if latched:
			dd["latched"] = true
		return false
	dd["open"] = true
	dd["latched"] = latched
	dd["emptySinceTick"] = int(world.tick)
	sync_map(world)
	return true


# Close an open door. Refused broken (nothing to close) and refused with a body in the doorway
# (a door does not shut on somebody). `latched` again is the hand.
static func close_door(world: Variant, tx: int, ty: int, latched: bool = false) -> bool:
	var d: Variant = door_state(world, tx, ty)
	if not d is Dictionary:
		return false
	var dd: Dictionary = d as Dictionary
	if not bool(dd.get("open", false)) or int(dd.get("stage", 0)) >= DOOR_BROKEN:
		return false
	if _tile_occupied(world, tx, ty):
		return false
	dd["open"] = false
	dd["latched"] = latched
	sync_map(world)
	return true


# E at a door: open it and latch it, or shut it and latch it. Broken: nothing to do.
static func toggle_door(world: Variant, tx: int, ty: int) -> bool:
	var d: Variant = door_state(world, tx, ty)
	if not d is Dictionary or int((d as Dictionary).get("stage", 0)) >= DOOR_BROKEN:
		return false
	if bool((d as Dictionary).get("open", false)):
		return close_door(world, tx, ty, true)
	return open_door(world, tx, ty, true)


static func _tile_occupied(world: Variant, tx: int, ty: int) -> bool:
	for entity in world.components.query(["position", "velocity"]):
		var pos: Variant = world.components.get_component(int(entity), "position")
		if not pos is Dictionary:
			continue
		if floori(float((pos as Dictionary)["x"])) == tx and floori(float((pos as Dictionary)["y"])) == ty:
			return true
	return false


# The swing: an open, unlatched door shuts DOOR_SWING_TICKS after the last body left its tile.
static func _tick_doors(world: Variant) -> void:
	var dirty: bool = false
	for entity in world.components.query(["door"]):
		var d: Variant = world.components.get_component(int(entity), "door")
		if not d is Dictionary:
			continue
		var dd: Dictionary = d as Dictionary
		if not bool(dd.get("open", false)) or bool(dd.get("latched", false)) or int(dd.get("stage", 0)) >= DOOR_BROKEN:
			continue
		var tx: int = int(dd.get("tx", 0))
		var ty: int = int(dd.get("ty", 0))
		if _tile_occupied(world, tx, ty):
			dd["emptySinceTick"] = int(world.tick)
			continue
		if int(world.tick) - int(dd.get("emptySinceTick", 0)) >= DOOR_SWING_TICKS:
			dd["open"] = false
			dirty = true
	if dirty:
		sync_map(world)


# The door in front of the actor, or the one under them: the tile E acts on.
static func _door_in_reach(world: Variant, actor: int) -> Vector2i:
	for tile in [_facing_tile(world, actor), _tile_of(world, actor)]:
		var t: Vector2i = tile as Vector2i
		if SimTileMap.tile_at(world.tilemap, t.x, t.y) == SimTileMap.Tile.Door and door_at(world, t.x, t.y) >= 0:
			return t
	return Vector2i(-1, -1)


static func sync_map(world: Variant) -> void:
	var map: Variant = world.tilemap
	if map == null:
		return
	var table: Dictionary = {}
	for entity0 in world.components.query(["door"]):
		var door: Variant = world.components.get_component(int(entity0), "door")
		if not door is Dictionary:
			continue
		var dd: Dictionary = door as Dictionary
		var stage: int = int(dd.get("stage", 0))
		# Broken is a doorway: no overlay, the class's own Clear and not-solid answer.
		if stage >= DOOR_BROKEN:
			continue
		table[int(dd.get("ty", 0)) * int(map.w) + int(dd.get("tx", 0))] = {"kind": "door", "open": bool(dd.get("open", false)), "stage": stage}
	for entity in world.components.query(["windowBoard"]):
		var board: Variant = world.components.get_component(int(entity), "windowBoard")
		if not board is Dictionary:
			continue
		var b: Dictionary = board as Dictionary
		var stage: int = int(b.get("stage", 0))
		if stage < 0 or stage >= 4:
			continue
		var tx: int = int(b.get("tx", 0))
		var ty: int = int(b.get("ty", 0))
		table[ty * int(map.w) + tx] = {"kind": "board", "stage": stage}
	for entity2 in world.components.query(["scrapBarricade", "position"]):
		var pos: Variant = world.components.get_component(int(entity2), "position")
		if not pos is Dictionary:
			continue
		var sx: int = floori(float((pos as Dictionary)["x"]))
		var sy: int = floori(float((pos as Dictionary)["y"]))
		table[sy * int(map.w) + sx] = {"kind": "scrap"}
	map.overlays = table
	if world.map_cells.size() != int(map.w) * int(map.h):
		world.map_cells.resize(int(map.w) * int(map.h))
	for y in int(map.h):
		for x in int(map.w):
			world.map_cells[y * int(world.map_width) + x] = 1 if SimTileMap.is_solid(map, x, y) else 0
	world.invalidateMap()


static func speed_after_events(speed: int, events: Array) -> int:
	if speed < 10:
		return speed
	for event in events:
		if String((event as Dictionary).get("type", "")) == "alarm.tripped":
			return 1
	return speed


static func look_at(world: Variant, actor: int) -> Dictionary:
	var out: Dictionary = {"window": "", "noisemaker": ""}
	if world.tilemap == null:
		return out
	var win: Variant = _window_in_reach(world, actor)
	if win is Vector2i:
		var board: Variant = _board_at(world, int((win as Vector2i).x), int((win as Vector2i).y))
		if board is Dictionary:
			var stage: int = clampi(int((board as Dictionary).get("stage", 0)), 0, WINDOW_PROSE.size() - 1)
			out["window"] = WINDOW_PROSE[stage]
	# The door in reach, in words: how far the pressing has got.
	var door_tile: Vector2i = _door_in_reach(world, actor)
	if door_tile.x >= 0:
		var d: Variant = door_state(world, door_tile.x, door_tile.y)
		if d is Dictionary:
			out["door"] = DOOR_PROSE[clampi(int((d as Dictionary).get("stage", 0)), 0, DOOR_PROSE.size() - 1)]
	var bait: Variant = _first(world, "noisemaker")
	if bait != null:
		var nm: Variant = world.components.get_component(int(bait), "noisemaker")
		var ticking: bool = nm is Dictionary and int(world.tick) < int((nm as Dictionary).get("expiresAtTick", 0))
		out["noisemaker"] = "ticking, south avenue" if ticking else "silent"
	return out


# The two gate tiles are read off the map the colony was stamped onto rather than off a pair of
# constants: where the gate is belongs to the district, and a map that carries no anchors answers
# with the (-1, -1) sentinel, which is why each gate is compared only after it says it exists.
static func can_scrap(map: Variant, tx: int, ty: int) -> bool:
	var here := Vector2i(tx, ty)
	var gate_a: Vector2i = SimTileMap.gate_a(map)
	if gate_a.x >= 0 and here == gate_a:
		return false
	var gate_b: Vector2i = SimTileMap.gate_b(map)
	if gate_b.x >= 0 and here == gate_b:
		return false
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return false
	if SimTileMap.is_indoors(map, tx, ty):
		return false
	if SimTileMap.overlay_at(map, tx, ty) != null:
		return false
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if SimTileMap.tile_at(map, tx + d.x, ty + d.y) == SimTileMap.Tile.Window:
			return true
	return false


static func _use_context(world: Variant, actor: int) -> void:
	# From the wheel, E means one thing: out. Nothing lower on this ladder is reachable from
	# inside a car -- the body's position is the car's centre, so "nearest ground item" would
	# be whatever the car is standing over. The door only opens once the car has stopped
	# (SimVehicles.dismount refuses at speed), and a refusal is a no-op rather than a fall
	# through to the rungs below.
	if world.components.has_component(actor, "mounted"):
		SimVehicles.dismount(world, actor)
		return
	if SimInventory.nearest_ground_item(world, actor) != null:
		SimInventory.pick_up_nearest(world, actor)
		return
	# Loose items first, then the container beside them. E *opens* a container now rather than
	# tipping it onto the floor: the transfer window draws its grid beside your pockets and you
	# take what you want, which is the 2026-09-08 overhaul's call (docs/30, "The inventory
	# sheet"). The rung wants `Openable` and not merely unsearched, so a box you opened and left
	# half full is still worth the key while an emptied one falls through to the door behind it
	# and costs nothing.
	var Containers: GDScript = load("res://sim/modules/containers.gd") as GDScript
	if Containers != null and Containers.has_method("open"):
		var box: int = int(Containers.call("nearest", world, actor, false, Containers.Want.Openable))
		if box >= 0:
			Containers.call("open", world, actor, box)
			return
	# The door before the stranger and the car: standing at one, E opens it and latches it open,
	# or shuts it and latches it shut -- the one hand on the district's doors that a walker's
	# swing does not undo. A broken door falls through: there is nothing to do with it.
	var door_tile: Vector2i = _door_in_reach(world, actor)
	if door_tile.x >= 0 and toggle_door(world, door_tile.x, door_tile.y):
		return
	var Recruits: GDScript = load("res://sim/modules/recruits.gd") as GDScript
	if Recruits != null and Recruits.has_method("waiting_in_reach"):
		var waiting: int = int(Recruits.call("waiting_in_reach", world, actor))
		if waiting >= 0:
			Recruits.call("accept", world, waiting)
			return
	# The car beside you, after the loot and the people and before the furniture: the suburb
	# stands its car-boot loot on a car's tail tile, so a boot still gets searched before the
	# door opens, and a survivor waiting at the kerb is spoken to before you drive off. The
	# owner's 2026-09-05 decision put this on E rather than on a key of its own (docs/30,
	# "Driving"); the sim decides reach and whether the wheel is free (SimVehicles.mount).
	var car: int = SimVehicles.nearest_in_reach(world, actor)
	if car != SimVehicles.NO_DRIVER:
		# The hood before the door: standing at the nose, E looks under it (fuel and condition,
		# in words -- SimVehicles.hood_view); standing anywhere else along it, E gets in. And the
		# can before the look: a body at the nose carrying fuel, at an engine with room in the
		# tank, pours (SimVehicles.begin_refuel); any refusal -- no can, full, a battery, a
		# bicycle, a wreck -- falls to the look, whose words say why.
		if SimVehicles.at_hood(world, actor, car):
			# The full can before the empty one before the look. A body carrying fuel pours it; a
			# body carrying nothing but an empty can draws ten litres out instead
			# (SimVehicles.begin_siphon); anything either of them refuses -- no can at all, a tank
			# too shallow to fill one, a battery, a bicycle, a wreck -- falls to the look, whose
			# words say why. The `carried_fuel_can` guard is the ladder's decision and not the
			# siphon's own business: somebody standing at the nose holding a full can came to fill
			# the car, so "the tank is full" must stay a look rather than quietly becoming the
			# opposite verb. `begin_siphon` itself refuses nothing on that account, which is what
			# lets a gate ask for the draw directly.
			if not SimVehicles.begin_refuel(world, actor, car):
				if SimVehicles.carried_fuel_can(world, actor) != SimVehicles.NO_DRIVER or not SimVehicles.begin_siphon(world, actor, car):
					SimVehicles.check_hood(world, actor, car)
		else:
			SimVehicles.mount(world, actor, car)
		return
	var Needs: GDScript = load("res://sim/modules/needs.gd") as GDScript
	if Needs != null:
		var here: Vector2i = _tile_of(world, actor)
		var hx: float = float(here.x) + 0.5
		var hy: float = float(here.y) + 0.5
		var bed: int = int(Needs.call("nearest_bed", world, hx, hy, false))
		var fire: int = int(Needs.call("nearest_campfire", world, hx, hy, false))
		# Same-tile bed wins so E sleeps; fire is the next reach target.
		if bed >= 0 and _same_tile(world, actor, bed):
			Needs.call("start_sleep", world, actor, bed)
			return
		if fire >= 0 and _entity_in_reach(world, actor, fire):
			# A bottle of well water at a lit fire boils before the fire is touched; at an unlit
			# one `boil` refuses and E lights it, so the next E boils -- the ladder, not a new key.
			if bool((Needs.call("boil", world, actor, fire) as Dictionary).get("ok", false)):
				return
			Needs.call("toggle_fire", world, fire)
			return
		# No fire in reach, and that is the whole point of this rung: docs/04's other two routes to
		# safe water -- filters and chemicals -- are the ones you can use standing in a stranger's
		# kitchen. It sits *below* the fire because a fire costs nothing and a filter has a finite
		# number of litres in it, and it is guarded by both halves (something untreated in the pack
		# and something that treats it), so on a body carrying neither the ladder falls through to
		# the latrine exactly as it always did.
		if bool((Needs.call("purify", world, actor) as Dictionary).get("ok", false)):
			return
		# The latrine, before the reach-bed fallback: a bed you are merely near is somewhere to
		# sleep later, and this is not something anybody is standing next to by accident.
		var latrine: int = int(Needs.call("nearest_latrine", world, hx, hy))
		if latrine >= 0 and _entity_in_reach(world, actor, latrine):
			if bool(Needs.call("relieve_at", world, actor, latrine)):
				return
		if bed >= 0 and _entity_in_reach(world, actor, bed):
			Needs.call("start_sleep", world, actor, bed)
			return
	# The bench, before the window and the traps: standing at one, E puts what is in your hands on
	# it. It is the surface `item.attach` and `item.detach` have never had, and it goes on the
	# ladder rather than on a key of its own for the reason the car did (docs/30, "Driving") --
	# the sim decides what E means where you are standing.
	var Gunsmith: GDScript = _Gunsmith()
	if int(Gunsmith.call("bench_in_reach", world, actor)) >= 0 and int(Gunsmith.call("focus_of", world, actor)) < 0:
		if bool(Gunsmith.call("open_bench", world, actor, int(Gunsmith.call("first_workpiece", world, actor)))):
			return
	var face: Vector2i = _facing_tile(world, actor)
	if SimTileMap.tile_at(world.tilemap, face.x, face.y) == SimTileMap.Tile.Window and _in_reach_tile(world, actor, face.x, face.y):
		_start(world, actor, "window", face.x, face.y)
		return
	var here: Vector2i = _tile_of(world, actor)
	var alarm: Variant = _first(world, "alarmLine")
	if alarm != null:
		var line: Variant = world.components.get_component(int(alarm), "alarmLine")
		if line is Dictionary and (_cell_in((line as Dictionary).get("cells", []), here) or _cell_in((line as Dictionary).get("cells", []), face)):
			if not bool((line as Dictionary).get("armed", false)):
				(line as Dictionary)["armed"] = true
			return
	var bait: Variant = _first(world, "noisemaker")
	if bait != null and _entity_in_reach(world, actor, int(bait)):
		var pos: Variant = world.components.get_component(int(bait), "position")
		if pos is Dictionary:
			_start(world, actor, "wind", floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
		return
	if can_scrap(world.tilemap, face.x, face.y) and carried_material(world, actor, recipe_kind("scrap")) >= 0 and world.components.query(["scrapBarricade"]).is_empty():
		_start(world, actor, "scrap", face.x, face.y)
		return
	if _empty_floor(world, face.x, face.y):
		if alarm == null:
			_start(world, actor, "alarm", face.x, face.y)
		elif bait == null:
			_start(world, actor, "noisemaker", face.x, face.y)
		elif _Gunsmith().call("bench_in_reach", world, actor) < 0 and material_count(world, actor, recipe_kind("bench")) >= int(_Gunsmith().get("BENCH_SCRAP")):
			# Last on the ladder and the only rung that is furniture: a gunsmithing bench, once
			# the trap and the bait are down and there is scrap to spare. Standing at one already
			# falls through, so E at a bench is never spent building a second.
			_start(world, actor, "bench", face.x, face.y)


static func _intake_verb(world: Variant, actor: int, c: Dictionary) -> void:
	var kind: String = String(c.get("type", ""))
	var tile: Vector2i = _facing_tile(world, actor)
	var tx: int = int(c.get("tx", tile.x))
	var ty: int = int(c.get("ty", tile.y))
	match kind:
		"barricade.window":
			if SimTileMap.tile_at(world.tilemap, tx, ty) == SimTileMap.Tile.Window:
				_start(world, actor, "window", tx, ty)
		"barricade.scrap":
			if can_scrap(world.tilemap, tx, ty) and carried_material(world, actor, recipe_kind("scrap")) >= 0 and world.components.query(["scrapBarricade"]).is_empty():
				_start(world, actor, "scrap", tx, ty)
		"trap.alarm.place":
			if _first(world, "alarmLine") == null and _empty_floor(world, tx, ty):
				_start(world, actor, "alarm", tx, ty)
		"trap.alarm.reset":
			var alarm: Variant = _first(world, "alarmLine")
			if alarm != null:
				var line: Variant = world.components.get_component(int(alarm), "alarmLine")
				if line is Dictionary:
					(line as Dictionary)["armed"] = true
		"bait.noisemaker.place":
			if _first(world, "noisemaker") == null and _empty_floor(world, tx, ty):
				_start(world, actor, "noisemaker", tx, ty)
		"bench.build":
			if _empty_floor(world, tx, ty) and material_count(world, actor, recipe_kind("bench")) >= int(_Gunsmith().get("BENCH_SCRAP")):
				_start(world, actor, "bench", tx, ty)
		"bait.noisemaker.wind":
			var bait: Variant = _first(world, "noisemaker")
			if bait != null:
				var pos: Variant = world.components.get_component(int(bait), "position")
				if pos is Dictionary:
					_start(world, actor, "wind", floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
		# Establishing a camp is a channel and not a rung on the E ladder, deliberately. Task 8 asks
		# for "a deliberate, interruptible commitment -- not a menu click", and a rung would make it
		# the thing that happens when you press E on empty ground with a trap and a bait already
		# down. Moving home by accident is worse than one more key. It channels on the tile the actor
		# is standing on rather than the one they face: you camp where you are.
		"camp.establish":
			var here: Vector2i = _tile_of(world, actor)
			var cx: int = int(c.get("tx", here.x))
			var cy: int = int(c.get("ty", here.y))
			if SimCampRes.can_establish(world, cx, cy):
				_start(world, actor, "camp", cx, cy)
		# Abandoning is free and immediate -- Task 8 again, and the cost of moving is paid
		# establishing the next one. No channel, because there is nothing to build.
		"camp.abandon":
			var home: int = SimCampRes.home_of(world)
			if home >= 0:
				SimCampRes.abandon(world, home)


static func _start(world: Variant, actor: int, verb: String, tx: int, ty: int) -> void:
	if not _can_channel(world, actor):
		return
	if not _in_reach_tile(world, actor, tx, ty) and verb != "wind":
		return
	var ticks: int = CHANNEL_TICKS
	if verb == "bench":
		ticks = int(_Gunsmith().get("BENCH_TICKS"))
	world.components.set_component(actor, "construct", {"verb": verb, "ticksLeft": ticks, "tx": tx, "ty": ty})


static func _tick_channel(world: Variant, entity: int) -> void:
	if not _can_channel(world, entity):
		_cancel(world, entity)
		return
	var pos: Variant = world.components.get_component(entity, "position")
	if pos is Dictionary:
		world.events.publish({
			"type": "noise.emitted",
			"x": float((pos as Dictionary)["x"]),
			"y": float((pos as Dictionary)["y"]),
			"magnitude": CONSTRUCT_NOISE,
			"source": entity,
		})
	var c: Variant = world.components.get_component(entity, "construct")
	if not c is Dictionary:
		return
	var state: Dictionary = c as Dictionary
	state["ticksLeft"] = int(state.get("ticksLeft", 0)) - 1
	if int(state["ticksLeft"]) > 0:
		return
	_complete(world, entity, String(state.get("verb", "")), int(state.get("tx", 0)), int(state.get("ty", 0)))
	world.components.remove(entity, "construct")


static func _complete(world: Variant, _actor: int, verb: String, tx: int, ty: int) -> void:
	match verb:
		"window":
			_board_window(world, tx, ty)
		"scrap":
			_place_scrap(world, _actor, tx, ty)
		"alarm":
			_place_alarm(world, tx, ty)
		"noisemaker":
			_place_noisemaker(world, tx, ty)
		"wind":
			_wind_noisemaker(world)
		"bench":
			_place_bench(world, _actor, tx, ty)
		# Re-derived on completion the same way, and by the same rule: `SimLightModule.plant` looks
		# the floodlight up again rather than trusting one the channel remembered, so a can that
		# left the pack mid-channel simply spends the channel and stands nothing up.
		"floodlight":
			_Light().call("plant", world, _actor, tx, ty)
		# Re-validated on completion rather than trusted from the start, the way `_place_scrap` and
		# `_place_bench` are: a channel that began on open ground and finished on a tile somebody
		# else camped on must leave nothing behind. `create` answers -1 there and the channel is
		# simply spent, which is the same shape as arriving at a window somebody already boarded.
		"camp":
			SimCampRes.create(world, tx, ty)


static func _board_window(world: Variant, tx: int, ty: int) -> void:
	if SimTileMap.tile_at(world.tilemap, tx, ty) != SimTileMap.Tile.Window:
		return
	var existing: Variant = _board_entity_at(world, tx, ty)
	if existing != null:
		var board: Variant = world.components.get_component(int(existing), "windowBoard")
		if board is Dictionary:
			(board as Dictionary)["stage"] = 0
			(board as Dictionary)["contactTicks"] = 0
		sync_map(world)
		return
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": float(tx) + 0.5, "y": float(ty) + 0.5})
	world.components.set_component(ent, "windowBoard", {"tx": tx, "ty": ty, "stage": 0, "contactTicks": 0})
	sync_map(world)


static func _place_scrap(world: Variant, actor: int, tx: int, ty: int) -> void:
	if not can_scrap(world.tilemap, tx, ty):
		return
	if not world.components.query(["scrapBarricade"]).is_empty():
		return
	if not consume_material(world, actor, recipe_kind("scrap")):
		return
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": float(tx) + 0.5, "y": float(ty) + 0.5})
	world.components.set_component(ent, "scrapBarricade", {})
	sync_map(world)


# Furniture, not a barricade: it blocks nothing and the map never hears about it. The scrap goes
# first, so a channel that finished with the material already spent leaves no bench and no hole in
# the pack -- the same order `_place_scrap` uses.
static func _place_bench(world: Variant, actor: int, tx: int, ty: int) -> void:
	var Gunsmith: GDScript = _Gunsmith()
	if int(Gunsmith.call("bench_in_reach", world, actor)) >= 0:
		return
	var cost: int = int(Gunsmith.get("BENCH_SCRAP"))
	var kind: String = recipe_kind("bench")
	if material_count(world, actor, kind) < cost:
		return
	for i in cost:
		if not consume_material(world, actor, kind):
			return
	Gunsmith.call("make_bench", world, float(tx) + 0.5, float(ty) + 0.5)


# Loaded lazily: gunsmith.gd preloads inventory and items, and a preload cycle through this file
# would be a parse error rather than something the engine resolves.
static func _Gunsmith() -> GDScript:
	return load("res://sim/modules/gunsmith.gd") as GDScript


# Loaded rather than preloaded, and deliberately in both directions: light.gd loads this file to
# start the channel and this file loads light.gd to finish it. A preload either way would be a
# cycle at parse time.
static func _Light() -> GDScript:
	return load("res://sim/modules/light.gd") as GDScript


## Whether this body could stand a light up on the tile in front of it right now.
## `item.floodlight.rigged` has sat in the military cache's loot table since lights shipped with
## **no equipSlot and no placement verb**: a player could find one, carry it, and do absolutely
## nothing with it. This is the predicate half, asked by the word menu through
## `SimLightModule.can_use` so the menu and the intake cannot disagree -- the rule every other verb
## in this file follows.
static func can_place_light(world: Variant, actor: int) -> bool:
	if world.components.has_component(actor, "construct"):
		return false
	if not _can_channel(world, actor):
		return false
	var face: Vector2i = _facing_tile(world, actor)
	if not _empty_floor(world, face.x, face.y):
		return false
	if not _in_reach_tile(world, actor, face.x, face.y):
		return false
	return int(_Light().call("carried_plantable", world, actor)) >= 0


## Begin the channel. Reached through `use` on the floodlight itself and **not through a rung on
## the E ladder**, deliberately, and for exactly the reason `camp.establish` is not one: a
## 90-metre beacon whose own description says it "tells everyone where the yard is" is not a thing
## to put down by accident because you pressed E on empty ground with a trap and a bait already
## down. The tile is the one you are facing and there is no parameter for choosing another,
## because a parameter nothing passes is a parameter nothing tests. The channel itself is the same
## `construct` every other placement here uses, so a stagger, a grab or a walk cancels it.
static func place_light(world: Variant, actor: int) -> bool:
	if not can_place_light(world, actor):
		return false
	var face: Vector2i = _facing_tile(world, actor)
	_start(world, actor, "floodlight", face.x, face.y)
	return world.components.has_component(actor, "construct")


static func _place_alarm(world: Variant, tx: int, ty: int) -> void:
	if _first(world, "alarmLine") != null:
		return
	if not _empty_floor(world, tx, ty):
		return
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "alarmLine", {"cells": [{"x": tx, "y": ty}], "armed": true})


static func _place_noisemaker(world: Variant, tx: int, ty: int) -> void:
	if _first(world, "noisemaker") != null:
		return
	if not _empty_floor(world, tx, ty):
		return
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": float(tx) + 0.5, "y": float(ty) + 0.5})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "noisemaker", {"expiresAtTick": int(world.tick) + NOISEMAKER_TICKS})
	var emitter: Dictionary = SimAttention.PERSON_EMITTER.duplicate(true)
	emitter["ambient"] = NOISEMAKER_MAG
	emitter["walking"] = 0.0
	emitter["sprinting"] = 0.0
	emitter["scent"] = 0.0
	SimAttention.make_emitter(world, ent, emitter)


static func _wind_noisemaker(world: Variant) -> void:
	var bait: Variant = _first(world, "noisemaker")
	if bait == null:
		return
	world.components.set_component(int(bait), "noisemaker", {"expiresAtTick": int(world.tick) + NOISEMAKER_TICKS})
	var emitter: Variant = world.components.get_component(int(bait), "attention_emitter")
	if emitter is Dictionary:
		(emitter as Dictionary)["ambient"] = NOISEMAKER_MAG


static func _tick_alarm(world: Variant) -> void:
	var alarm: Variant = _first(world, "alarmLine")
	if alarm == null:
		return
	var line: Variant = world.components.get_component(int(alarm), "alarmLine")
	if not line is Dictionary or not bool((line as Dictionary).get("armed", false)):
		return
	var cells: Array = (line as Dictionary).get("cells", []) as Array
	for zed in world.components.query(["shambler", "position"]):
		var pos: Variant = world.components.get_component(int(zed), "position")
		if not pos is Dictionary:
			continue
		var tile := Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))
		if not _cell_in(cells, tile):
			continue
		(line as Dictionary)["armed"] = false
		world.events.publish({"type": "alarm.tripped", "x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"])})
		world.events.publish({
			"type": "noise.emitted",
			"x": float((pos as Dictionary)["x"]),
			"y": float((pos as Dictionary)["y"]),
			"magnitude": ALARM_NOISE,
			"source": int(zed),
		})
		return


static func _tick_noisemaker(world: Variant) -> void:
	for entity in world.components.query(["noisemaker", "attention_emitter"]):
		var nm: Variant = world.components.get_component(int(entity), "noisemaker")
		var em: Variant = world.components.get_component(int(entity), "attention_emitter")
		if not nm is Dictionary or not em is Dictionary:
			continue
		if int(world.tick) >= int((nm as Dictionary).get("expiresAtTick", 0)):
			(em as Dictionary)["ambient"] = 0.0


static func pressure_of(bodies: int) -> float:
	if bodies <= 0:
		return 0.0
	return float(bodies) * (1.0 + 0.5 * float(bodies - 1))


# The dead pressing each tile this tick, keyed "tx,ty" -> count. Only the dead press: a colonist
# walking into a shut door opens it, and a raider does the same; neither is a crowd at a wall.
static func _presses(world: Variant) -> Dictionary:
	var out: Dictionary = {}
	for zed in world.components.query(["shambler", "velocity"]):
		var vel: Variant = world.components.get_component(int(zed), "velocity")
		if not vel is Dictionary:
			continue
		var px: int = int((vel as Dictionary).get("pressX", -1))
		var py: int = int((vel as Dictionary).get("pressY", -1))
		if px < 0 or py < 0:
			continue
		var key: String = "%d,%d" % [px, py]
		out[key] = int(out.get(key, 0)) + 1
	return out


static func _tick_contact(world: Variant) -> void:
	var presses: Dictionary = _presses(world)
	if presses.is_empty():
		return
	var dirty: bool = false
	for entity in world.components.query(["windowBoard"]):
		var board: Variant = world.components.get_component(int(entity), "windowBoard")
		if not board is Dictionary:
			continue
		var b: Dictionary = board as Dictionary
		var tx: int = int(b.get("tx", 0))
		var ty: int = int(b.get("ty", 0))
		if _press(b, presses, tx, ty, "board"):
			dirty = true
			if int(b["stage"]) >= 4:
				world.events.publish({"type": "fortify.breached", "tx": tx, "ty": ty, "kind": "board"})
				world.despawn(int(entity))
	for entity2 in world.components.query(["scrapBarricade", "position"]):
		var scrap: Variant = world.components.get_component(int(entity2), "scrapBarricade")
		var pos: Variant = world.components.get_component(int(entity2), "position")
		if not scrap is Dictionary or not pos is Dictionary:
			continue
		var sx: int = floori(float((pos as Dictionary)["x"]))
		var sy: int = floori(float((pos as Dictionary)["y"]))
		if _press(scrap as Dictionary, presses, sx, sy, "scrap"):
			dirty = true
			if int((scrap as Dictionary)["stage"]) >= 4:
				world.events.publish({"type": "fortify.breached", "tx": sx, "ty": sy, "kind": "scrap"})
				world.despawn(int(entity2))
	for entity3 in world.components.query(["door"]):
		var door: Variant = world.components.get_component(int(entity3), "door")
		if not door is Dictionary:
			continue
		var dd: Dictionary = door as Dictionary
		if bool(dd.get("open", false)) or int(dd.get("stage", 0)) >= DOOR_BROKEN:
			continue
		var dx: int = int(dd.get("tx", 0))
		var dy: int = int(dd.get("ty", 0))
		if _press(dd, presses, dx, dy, "door"):
			dirty = true
			if int(dd["stage"]) >= DOOR_BROKEN:
				dd["open"] = true
				dd["latched"] = false
				world.events.publish({"type": "fortify.breached", "tx": dx, "ty": dy, "kind": "door"})
	if dirty:
		sync_map(world)


# One barrier's tick of pressure: the crowd at its tile, the kind's cost a stage, and however
# many stages that buys. True when the stage moved.
static func _press(barrier: Dictionary, presses: Dictionary, tx: int, ty: int, kind: String) -> bool:
	var n: int = int(presses.get("%d,%d" % [tx, ty], 0))
	if n <= 0:
		return false
	var cost: float = float(STAGE_COST.get(kind, CONTACT_PER_STAGE))
	barrier["contactTicks"] = float(barrier.get("contactTicks", 0)) + pressure_of(n)
	var moved: bool = false
	while float(barrier["contactTicks"]) >= cost and int(barrier.get("stage", 0)) < 4:
		barrier["contactTicks"] = float(barrier["contactTicks"]) - cost
		barrier["stage"] = int(barrier.get("stage", 0)) + 1
		moved = true
	return moved


static func _cancel(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	if world.components.has_component(entity, "construct"):
		world.components.remove(entity, "construct")


static func _can_channel(world: Variant, entity: int) -> bool:
	if world.components.has_component(entity, "grabbed"):
		return false
	var posture: Variant = world.components.get_component(entity, "posture")
	if posture == null:
		return true
	var stance: int = int((posture as Dictionary).get("current", 2))
	return stance != 0 and stance != 4


static func _tile_of(world: Variant, actor: int) -> Vector2i:
	var pos: Variant = world.components.get_component(actor, "position")
	if not pos is Dictionary:
		return Vector2i.ZERO
	return Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"])))


static func _facing_tile(world: Variant, actor: int) -> Vector2i:
	var pos: Variant = world.components.get_component(actor, "position")
	if not pos is Dictionary:
		return Vector2i.ZERO
	var rad: float = 0.0
	var facing: Variant = world.components.get_component(actor, "facing")
	if facing is Dictionary:
		rad = float((facing as Dictionary).get("radians", 0.0))
	var x: float = float((pos as Dictionary)["x"]) + cos(rad) * 0.9
	var y: float = float((pos as Dictionary)["y"]) + sin(rad) * 0.9
	return Vector2i(floori(x), floori(y))


static func _in_reach_tile(world: Variant, actor: int, tx: int, ty: int) -> bool:
	var pos: Variant = world.components.get_component(actor, "position")
	if not pos is Dictionary:
		return false
	var dx: float = float(tx) + 0.5 - float((pos as Dictionary)["x"])
	var dy: float = float(ty) + 0.5 - float((pos as Dictionary)["y"])
	return dx * dx + dy * dy <= REACH * REACH


static func _same_tile(world: Variant, actor: int, other: int) -> bool:
	var a: Variant = world.components.get_component(actor, "position")
	var b: Variant = world.components.get_component(other, "position")
	if not a is Dictionary or not b is Dictionary:
		return false
	return floori(float((a as Dictionary)["x"])) == floori(float((b as Dictionary)["x"])) \
		and floori(float((a as Dictionary)["y"])) == floori(float((b as Dictionary)["y"]))


static func _entity_in_reach(world: Variant, actor: int, other: int) -> bool:
	var a: Variant = world.components.get_component(actor, "position")
	var b: Variant = world.components.get_component(other, "position")
	if not a is Dictionary or not b is Dictionary:
		return false
	var dx: float = float((b as Dictionary)["x"]) - float((a as Dictionary)["x"])
	var dy: float = float((b as Dictionary)["y"]) - float((a as Dictionary)["y"])
	return dx * dx + dy * dy <= REACH * REACH


static func _window_in_reach(world: Variant, actor: int) -> Variant:
	var face: Vector2i = _facing_tile(world, actor)
	if SimTileMap.tile_at(world.tilemap, face.x, face.y) == SimTileMap.Tile.Window and _in_reach_tile(world, actor, face.x, face.y):
		return face
	var here: Vector2i = _tile_of(world, actor)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var tx: int = here.x + dx
			var ty: int = here.y + dy
			if SimTileMap.tile_at(world.tilemap, tx, ty) == SimTileMap.Tile.Window and _in_reach_tile(world, actor, tx, ty):
				return Vector2i(tx, ty)
	return null


static func _empty_floor(world: Variant, tx: int, ty: int) -> bool:
	if SimTileMap.tile_at(world.tilemap, tx, ty) != SimTileMap.Tile.Floor:
		return false
	if SimTileMap.overlay_at(world.tilemap, tx, ty) != null:
		return false
	return not SimTileMap.is_solid(world.tilemap, tx, ty)


static func _first(world: Variant, component: String) -> Variant:
	var found: Array[int] = world.components.query([component])
	if found.is_empty():
		return null
	return found[0]


static func _board_at(world: Variant, tx: int, ty: int) -> Variant:
	var ent: Variant = _board_entity_at(world, tx, ty)
	if ent == null:
		return null
	return world.components.get_component(int(ent), "windowBoard")


static func _board_entity_at(world: Variant, tx: int, ty: int) -> Variant:
	for entity in world.components.query(["windowBoard"]):
		var board: Variant = world.components.get_component(int(entity), "windowBoard")
		if board is Dictionary and int((board as Dictionary).get("tx", -1)) == tx and int((board as Dictionary).get("ty", -1)) == ty:
			return entity
	return null


static func _cell_in(cells: Variant, tile: Vector2i) -> bool:
	if not cells is Array:
		return false
	for cell in cells as Array:
		if not cell is Dictionary:
			continue
		if int((cell as Dictionary).get("x", -999)) == tile.x and int((cell as Dictionary).get("y", -999)) == tile.y:
			return true
	return false

