class_name SimCamp
extends RefCounted

# The camp the player establishes -- the runtime half of the owner's "the colony can be established
# anywhere".
#
# The generation-time half landed with the region assembler: every cell generates colonyless and the
# annex is ranked across all four. At runtime there was still exactly one colony, fixed where the
# generator put it, because "where is home" was four entries in `map.anchors` (`annex`, `gate_a`,
# `gate_b`, `player_start`) written by `SimTemplates.stamp` and read independently by seven modules
# across 24 call sites. `sim/home.gd` is the one answer they read now; this file is what gives that
# answer something to prefer.
#
# **A camp is a prop entity, not a place.** There is no place-emitter in this sim and no field-level
# source registry: the only recurring emission comes from the two per-entity systems in
# `attention_emitter.gd`. So a camp is shaped like the campfire, the latrine and the noisemaker
# before it -- a position and a marker component -- and two things fall out of that rather than
# being built:
#
#   * it round-trips through a save for free, because `component_store.save()` is generic over every
#     component table. **No `SAVE_VERSION` bump**: `kernel/serialize.gd`'s ledger states the rule for
#     treatment ("it changed no existing component's shape... component_store.save() is generic"),
#     and a new component is exactly the case it names;
#   * there can be more than one, which is the owner's "camps can be used as outposts too" with no
#     extra machinery. Exactly one is `home` at a time; the rest are outposts.
#
# **It deliberately carries no emitter of its own**, which the plan for this slice had assumed it
# would. An emitter whose every channel is zero is a dead socket of the exact shape CLAUDE.md lists
# eleven of, and there is nothing honest to put in it: what emits at a camp is the fire, the light
# and the people standing there, and all three already emit. That is also why this slice changes
# nothing in the director's placement -- `_emit_packet` never targeted the colony, it places at the
# map edge and lets the noise/scent/light gradients in `shambler.gd` pull. A camp that is used gets
# visited because that is how the dead already work. Camp-local *signals as director inputs* is the
# deferred slice, and it is about numbers rather than plumbing.
#
# The owner's shape for a camp, 2026-09-10: **temporary, evolvable later, usable as an outpost.** So
# this is not a second annex -- no indoor floor, no stockpile, no walls, and `SimNeeds` deliberately
# still reads the annex for the stockpile. Giving a camp those is the "evolve a camp" work.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimRegionRes = preload("res://sim/map/region.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")

# The camp's own footprint: the tile it stands on and everything touching it. Radius 1 rather than an
# invented square, because the 32 m keep-off that actually holds the dead at arm's length is
# `SimDirector.GATE_EXCLUSION`, applied through `SimHome.gate_a`. This rect only answers "how loud is
# it *at* the camp", which is a question about the ground you can reach from the fire.
const FOOTPRINT_RADIUS: int = 1


## Every camp on the map, live or abandoned, in id order. Abandoned ones stay in the list on
## purpose: Task 8 says an abandoned camp's "location persists as a known empty site".
static func camps(world: Variant) -> Array[int]:
	var out: Array[int] = []
	if world == null:
		return out
	for e in world.components.query(["camp"]):
		out.append(int(e))
	out.sort()
	return out


## The camp that answers "where is home", or -1 when the colony is still the stamped annex.
## Highest id wins a tie, so two camps somehow flagged home resolve the same way on every machine.
static func home_of(world: Variant) -> int:
	if world == null:
		return -1
	# The fast path, and it is the one that matters. `SimJobs._near_home` calls `SimHome.centre` for
	# every Haul and Scavenge candidate, which lands here -- and on the shipped game there is no camp
	# at all, so this has to cost about what the `map.anchors` dictionary lookup it replaced cost.
	# `count` is one dictionary lookup and a size; `camps()` below allocates and sorts.
	if world.components.count("camp") == 0:
		return -1
	var best: int = -1
	for e in camps(world):
		var rec: Variant = world.components.get_component(int(e), "camp")
		if not (rec is Dictionary):
			continue
		var d: Dictionary = rec as Dictionary
		if int(d.get("abandonedAtTick", -1)) >= 0:
			continue
		if not bool(d.get("home", false)):
			continue
		if int(e) > best:
			best = int(e)
	return best


static func tile_of(world: Variant, camp: int) -> Vector2i:
	if world == null:
		return Vector2i(-1, -1)
	var rec: Variant = world.components.get_component(camp, "camp")
	if not (rec is Dictionary):
		return Vector2i(-1, -1)
	var d: Dictionary = rec as Dictionary
	return Vector2i(int(d.get("tx", -1)), int(d.get("ty", -1)))


static func is_abandoned(world: Variant, camp: int) -> bool:
	var rec: Variant = world.components.get_component(camp, "camp")
	if not (rec is Dictionary):
		return false
	return int((rec as Dictionary).get("abandonedAtTick", -1)) >= 0


# Task 8, word for word: "Any location can host a camp. There are no hard suitability restrictions;
# danger, exposure, and time-to-establish are the cost." So this refuses only what is not *ground* --
# a wall, a window, the deep channel of a river -- and never anything about whether the spot is a
# good idea. Standing in the worst place on the map and camping there is allowed, and is supposed to
# be how you find out it was the worst place.
static func can_establish(world: Variant, tx: int, ty: int) -> bool:
	if world == null:
		return false
	var map: Variant = world.tilemap
	if map == null:
		return false
	if tx < 0 or ty < 0 or tx >= int(map.w) or ty >= int(map.h):
		return false
	if SimTileMap.tile_at(map, tx, ty) != SimTileMap.Tile.Floor:
		return false
	if SimTileMap.is_solid(map, tx, ty):
		return false
	for e in camps(world):
		if is_abandoned(world, int(e)):
			continue
		if tile_of(world, int(e)) == Vector2i(tx, ty):
			return false
	return true


## Establish a camp and make it home. Returns the camp entity, or -1 when the tile refuses.
## Deterministic: no RNG, so the same commands on the same seed put the camp in the same place.
static func create(world: Variant, tx: int, ty: int) -> int:
	if not can_establish(world, tx, ty):
		return -1
	# Only one camp is home at a time. A new one takes it over and the old one stays on the map as
	# an outpost rather than being deleted -- the owner's "camps can be used as outposts too", and
	# Task 8's "establish a different camp elsewhere rather than moving camp identity".
	for e in camps(world):
		var prev: Variant = world.components.get_component(int(e), "camp")
		if prev is Dictionary:
			(prev as Dictionary)["home"] = false
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": float(tx) + 0.5, "y": float(ty) + 0.5})
	world.components.set_component(
		ent,
		"camp",
		{
			"tx": tx,
			"ty": ty,
			"home": true,
			"establishedAtTick": int(world.tick),
			"abandonedAtTick": -1,
		}
	)
	world.events.publish({"type": "camp.established", "entity": ent, "tx": tx, "ty": ty})
	sync_map(world)
	return ent


## Abandon a camp. Free, per Task 8 -- the cost of moving is paid establishing the next one, which
## is how this squares with docs/15's "relocating is possible, brutally expensive". The record stays
## behind with a tick on it rather than being despawned, because the site is meant to persist as a
## known empty one.
static func abandon(world: Variant, camp: int) -> void:
	var rec: Variant = world.components.get_component(camp, "camp")
	if not (rec is Dictionary):
		return
	var d: Dictionary = rec as Dictionary
	if int(d.get("abandonedAtTick", -1)) >= 0:
		return
	d["abandonedAtTick"] = int(world.tick)
	d["home"] = false
	world.events.publish({"type": "camp.abandoned", "entity": camp})
	sync_map(world)


# The night band follows home.
#
# On a district `spawn_edges` stays empty and `SimDirector._edges_by_side` runs the perimeter scan
# exactly as it always has -- the band is the map's own outer edge there, which is already the right
# question and is what every measured director band was calibrated against.
#
# On a **region** the band is one cell's inner wall, and a camp in another cell would otherwise leave
# night pressure arriving at the cell the player has left: the same 215-432 m dilution the flip slice
# measured, in a new place. So the band moves to the camp's cell, by the owner's 2026-09-10 answer.
#
# Derived rather than saved, because `spawn_edges` is never serialised. That is the
# `SimFortify.sync_map` / `SimVehicles.sync_map` precedent, and this is called from the same three
# places they are: after a restore, and after each of the two writes above.
static func sync_map(world: Variant) -> void:
	if world == null:
		return
	var map: Variant = world.tilemap
	if map == null or int(map.region_cells) <= 0:
		return
	var stride: int = int(map.region_cell_stride)
	var cell: int = int(map.region_cell_tiles)
	if stride <= 0 or cell <= 0:
		return
	# Where the band belongs: the home camp, or the stamped annex when there is none. Falling back
	# to the annex is what makes this safe to call unconditionally -- with no camp it rewrites the
	# band to the cell the generator already chose, which is the band it already had.
	var anchor: Vector2i = SimTileMap.annex_rect(map).position
	var camp: int = home_of(world)
	if camp >= 0:
		var t: Vector2i = tile_of(world, camp)
		if t.x >= 0:
			anchor = t
	if anchor.x < 0 or anchor.y < 0:
		return
	var last: int = maxi(0, (int(map.w) - cell) / stride)
	var cx: int = clampi(anchor.x / stride, 0, last)
	var cy: int = clampi(anchor.y / stride, 0, last)
	SimRegionRes.write_band(map, Rect2i(cx * stride, cy * stride, cell, cell))


## One line for the HUD, in words. Empty when there is no camp, which is the correct amount of HUD
## for a run that has not made one. No digits: `check_hud` allows none but the day counter, and the
## bearing vocabulary is `SimSightings`' rather than a second copy of the same eight words.
static func hud_clause(world: Variant, actor: int) -> String:
	var camp: int = home_of(world)
	if camp < 0:
		return ""
	var t: Vector2i = tile_of(world, camp)
	if t.x < 0:
		return ""
	var pos: Variant = world.components.get_component(actor, "position")
	if not (pos is Dictionary):
		return ""
	var px: float = float((pos as Dictionary).get("x", 0.0))
	var py: float = float((pos as Dictionary).get("y", 0.0))
	var here := Rect2i(
		t.x - FOOTPRINT_RADIUS,
		t.y - FOOTPRINT_RADIUS,
		FOOTPRINT_RADIUS * 2 + 1,
		FOOTPRINT_RADIUS * 2 + 1
	)
	if here.has_point(Vector2i(floori(px), floori(py))):
		return "your camp is here"
	return "your camp lies %s" % SimSightings.bearing_word((float(t.x) + 0.5) - px, (float(t.y) + 0.5) - py)
