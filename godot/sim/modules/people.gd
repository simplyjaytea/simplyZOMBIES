class_name SimPeople
extends RefCounted

# One roll for everybody: the draw that makes a generated person, lifted out of `recruits.gd`
# so that a stranger in a building, a raider with a name and a settler at a camp all come off
# the same shape as a recruit at the gate (docs/30, "The pause lifted", 2026-09-14).
#
# The draw order is the contract. `rng` is the caller's identity stream and its order -- name,
# surname, story, traits, composition, features -- is measured by the balance harness; the age
# and the visual look come off `look_rng`, a second stream, so that a new draw threaded into
# either never lands a later call on a different byte (CLAUDE.md, "new randomness gets its own
# named RNG stream"). `check_m2_people.gd` pins the canonical seed's first two rolls as
# literals taken from the pre-extraction code, so a reordered draw here goes red on the same
# bytes it would move in a campaign.
#
# This file deliberately preloads nothing but `aptitudes.gd`: `recruits.gd` preloads
# `survivors.gd`, `survivors.gd` cannot preload `recruits.gd` back, and both may preload this
# without a cycle -- which is what lets one `pool` scan replace the two private copies they each
# used to carry.

const SimAptitudes = preload("res://sim/modules/aptitudes.gd")

const SURVIVORS_POOL_ID: String = "colony.generator.survivors"


# The generator block with this id, found by scanning the content tree's values. `content/colony/`
# has no schema and no validator type, so nothing keys it by path; the id is the only handle.
# An unknown id returns an empty Dictionary, and `roll` then falls back to one of everything.
static func pool(world: Variant, id: String) -> Dictionary:
	if world == null or world.content == null:
		return {}
	var c: Variant = world.content
	if c is Dictionary:
		for v in (c as Dictionary).values():
			if v is Dictionary and String((v as Dictionary).get("id", "")) == id:
				return v as Dictionary
	return {}


# Removes every id conflicting with `picked_id` from `bag`, per `traitConflicts` -- content, not
# a GDScript constant (docs/30). `bag` is a plain Array (a reference type in GDScript, unlike a
# PackedStringArray -- CLAUDE.md's packed-array trap), so the erase is visible to the caller's
# copy of the same array; `Array.erase` matches Strings by value, which is exactly what a trait id
# needs (the by-value/by-reference trap only bites Dictionaries and other composite elements).
# Called both after the backstory `bias` pre-pick (before the loop starts) and after every loop
# pick -- the bias case is the one a naive implementation misses, since it runs before `bag` is
# ever touched by the loop.
static func _erase_conflicts_of(bag: Array, picked_id: String, conflicts: Array) -> void:
	for pair in conflicts:
		var p: Array = pair as Array
		if p.size() != 2:
			continue
		var a: String = String(p[0])
		var b: String = String(p[1])
		if a == picked_id:
			bag.erase(b)
		elif b == picked_id:
			bag.erase(a)


static func roll(rng: Variant, look_rng: Variant, pool: Dictionary) -> Dictionary:
	var given: Array = pool.get("given", ["Sam"]) as Array
	var surnames: Array = pool.get("surnames", ["Doe"]) as Array
	var traits: Array = pool.get("traits", ["optimist"]) as Array
	var stories: Array = pool.get("backstories", [{"id": "cyclist", "label": "cyclist", "kit": []}]) as Array
	var features: Array = pool.get("features", ["tired eyes"]) as Array
	var g: String = String(given[int(rng.call("int_range", 0, given.size() - 1))])
	var s: String = String(surnames[int(rng.call("int_range", 0, surnames.size() - 1))])
	var story: Dictionary = stories[int(rng.call("int_range", 0, stories.size() - 1))] as Dictionary
	var conflicts: Array = pool.get("traitConflicts", []) as Array
	var picked: Array = []
	var bag: Array = traits.duplicate()
	var bias: String = String(story.get("bias", ""))
	if bias != "" and bag.has(bias):
		picked.append(bias)
		bag.erase(bias)
		_erase_conflicts_of(bag, bias, conflicts)
	var want: int = int(rng.call("int_range", 2, 3))
	while picked.size() < want and not bag.is_empty():
		var i: int = int(rng.call("int_range", 0, bag.size() - 1))
		var picked_id: String = String(bag[i])
		picked.append(picked_id)
		bag.remove_at(i)
		_erase_conflicts_of(bag, picked_id, conflicts)
	var apt: Dictionary = {"str": 5, "dex": 5, "con": 5}
	var comps: Array[Dictionary] = SimAptitudes.compositions()
	apt = comps[int(rng.call("int_range", 0, comps.size() - 1))]
	var feat: Array = []
	var fbag: Array = features.duplicate()
	var fn: int = int(rng.call("int_range", 2, 3))
	while feat.size() < fn and not fbag.is_empty():
		var fi: int = int(rng.call("int_range", 0, fbag.size() - 1))
		feat.append(String(fbag[fi]))
		fbag.remove_at(fi)
	# Age and visual look draw from `look_rng` -- never from `rng` above. See the file comment.
	var bands: Array = pool.get("ageBands", [{"id": "adult", "min": 25, "max": 44, "prose": "", "nudge": {}}]) as Array
	var band: Dictionary = bands[int(look_rng.call("int_range", 0, bands.size() - 1))] as Dictionary
	var age: int = int(look_rng.call("int_range", int(band.get("min", 18)), int(band.get("max", 60))))
	var looks: Array = pool.get("looks", []) as Array
	var look_id: String = ""
	if not looks.is_empty():
		look_id = String(looks[int(look_rng.call("int_range", 0, looks.size() - 1))])
	# Both nudges feed the one clamp-and-rebalance-to-15 loop below, applied before it runs
	# rather than each getting its own pass, so a backstory and an age band pulling the same
	# stat land as one combined push, not a push-then-push that could overshoot and silently
	# clamp twice.
	for nudge in [story.get("nudge", {}), band.get("nudge", {})]:
		if nudge is Dictionary:
			for k in (nudge as Dictionary).keys():
				apt[k] = clampi(int(apt.get(k, 5)) + int((nudge as Dictionary)[k]), 3, 8)
	var sum: int = int(apt["str"]) + int(apt["dex"]) + int(apt["con"])
	while sum != 15:
		var k2: String = "con"
		if sum > 15:
			if int(apt["str"]) >= int(apt["dex"]) and int(apt["str"]) >= int(apt["con"]):
				k2 = "str"
			elif int(apt["dex"]) >= int(apt["con"]):
				k2 = "dex"
			apt[k2] = maxi(3, int(apt[k2]) - 1)
		else:
			if int(apt["str"]) <= int(apt["dex"]) and int(apt["str"]) <= int(apt["con"]):
				k2 = "str"
			elif int(apt["dex"]) <= int(apt["con"]):
				k2 = "dex"
			apt[k2] = mini(8, int(apt[k2]) + 1)
		sum = int(apt["str"]) + int(apt["dex"]) + int(apt["con"])
	return {
		"name": g + " " + s,
		"backstory": String(story.get("label", "")),
		"backstoryId": String(story.get("id", "")),
		"traits": picked,
		"aptitudes": apt,
		"kit": (story.get("kit", []) as Array).duplicate(),
		"features": feat,
		"age": age,
		"look": look_id,
	}
