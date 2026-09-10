class_name SimHome
extends RefCounted

# Where home is -- one answer, for the readers that each used to derive their own.
#
# Until this file, "the colony is here" was four entries in `map.anchors` (`annex`, `gate_a`,
# `gate_b`, `player_start`), written by `SimTemplates.stamp` at generation time and read
# independently by seven modules across 24 call sites. Nothing relocated them, and `map.anchors` is
# **never serialised** -- the map is regenerated from the seed at load -- so an anchor written at
# runtime would vanish on the next restore with no error and no wrong number. That is the whole
# reason the owner's "the colony can be established anywhere" had only ever landed as a
# *generation-time* answer: the region assembler ranks the annex across every cell, and then it is
# fixed for the run.
#
# Every resolver below is a ladder whose last rung is exactly what the calling code did before, so a
# world with no camp answers identically. `check_m2_camp.gd`'s HOME lane asserts that against a
# freshly booted district rather than trusting this paragraph, and its READS lane asserts that the
# callers actually consult this file -- a read model nothing reads being the dead socket this
# milestone has now paid for twelve times.
#
# Shape is `attention_read.gd`'s and `condition.gd`'s: static, no state of its own. Per-world state
# on a `static var` is the two-worlds trap docs/30 records twice, and this is read by two worlds in
# the same process on every gate that boots more than one.
#
# What a camp *is* belongs to `sim/modules/camp.gd`; this file only knows how to prefer one.

const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimCampRes = preload("res://sim/modules/camp.gd")


static func _map(world: Variant) -> Variant:
	if world == null:
		return null
	return world.tilemap


## The colony's footprint. A camp's is `SimCamp.FOOTPRINT_RADIUS` around its tile; otherwise the
## stamped annex, and an empty rect where a fixture map has no annex at all -- which is what
## `SimDirector._legal_tile` and `_annex_peak` both already read as "no colony".
static func rect(world: Variant) -> Rect2i:
	var camp: int = SimCampRes.home_of(world)
	if camp >= 0:
		var t: Vector2i = SimCampRes.tile_of(world, camp)
		if t.x >= 0 and t.y >= 0:
			var r: int = SimCampRes.FOOTPRINT_RADIUS
			return Rect2i(t.x - r, t.y - r, r * 2 + 1, r * 2 + 1)
	return SimTileMap.annex_rect(_map(world))


## Where home is, as a point. This is `SimJobs._home_centre` promoted verbatim with a camp rung on
## top -- annex centre, else the player's start where a map has no annex.
static func centre(world: Variant) -> Vector2:
	var camp: int = SimCampRes.home_of(world)
	if camp >= 0:
		var t: Vector2i = SimCampRes.tile_of(world, camp)
		if t.x >= 0 and t.y >= 0:
			return Vector2(float(t.x) + 0.5, float(t.y) + 0.5)
	var map: Variant = _map(world)
	var annex: Rect2i = SimTileMap.annex_rect(map)
	if annex.size.x > 0 and annex.size.y > 0:
		return Vector2(
			float(annex.position.x) + float(annex.size.x) * 0.5,
			float(annex.position.y) + float(annex.size.y) * 0.5
		)
	var start: Vector2i = SimTileMap.player_start(map)
	return Vector2(float(start.x) + 0.5, float(start.y) + 0.5)


## The way in. A camp is its own gate -- you walk to the fire, there is no wall to find a hole in.
static func gate_a(world: Variant) -> Vector2i:
	var camp: int = SimCampRes.home_of(world)
	if camp >= 0:
		var t: Vector2i = SimCampRes.tile_of(world, camp)
		if t.x >= 0 and t.y >= 0:
			return t
	return SimTileMap.gate_a(_map(world))


## A camp has one way in -- itself -- so the second gate is absent while a camp is home. Absent is
## `(-1, -1)`, the sentinel `tilemap.gd` chose precisely so a caller cannot mistake it for a real
## tile, and `SimDirector._legal_tile` already skips an absent gate rather than measuring a 32 m
## disc around the map's corner.
static func gate_b(world: Variant) -> Vector2i:
	if SimCampRes.home_of(world) >= 0:
		return Vector2i(-1, -1)
	return SimTileMap.gate_b(_map(world))


## Where somebody who means to reach the colony walks to. The gate, because that is how a colony is
## entered; the centre when the map carries no gate anchor; nothing at all when it carries no colony
## either, which is what an unstamped fixture map honestly is. This is `SimRaiders._objective`'s own
## ladder, moved here so that the camp answer is not a third copy of it.
static func approach(world: Variant) -> Vector2i:
	var g: Vector2i = gate_a(world)
	if g.x >= 0 and g.y >= 0:
		return g
	var r: Rect2i = rect(world)
	if r.size.x <= 0 or r.size.y <= 0:
		return Vector2i(-1, -1)
	return r.position + r.size / 2
