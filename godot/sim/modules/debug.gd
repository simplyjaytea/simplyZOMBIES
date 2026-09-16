class_name SimDebug
extends RefCounted
# Developer spawning, command-driven like everything else: presentation proposes
# `debug.spawn` and this module executes it inside the tick, so a spawn is ordered,
# deterministic (its randomness comes from a dedicated `debug` stream -- new randomness
# gets its own stream, per the loot-table precedent), and replayable like any other
# command. This is dev tooling for the F8 panel, not a game mechanism: nothing in
# ordinary play pushes it.
#
# The alpha shell's dev-menu piece (docs/23, "The dev menu reaches a raider band and a
# stranger") adds two kinds so a tester can reach "fight raiders" and "recruit" without
# waiting for day eight, and both go through the SAME code the director and the gate beat
# use rather than a second recipe for the same body:
#
#   * `raider` rolls a band through `SimRaiders.spawn_band` -- the one place that draws an
#     archetype and spawns a raider for it, shared with `SimDirector._emit_band` -- then
#     stamps it with `SimRaiders.stamp_band` so it is a band (it can lose men, withdraw,
#     the lot) rather than loose bodies. Refused, loudly, rather than exceeding
#     `SimDirector.RAID_LIVE_CAP`: a district already at the cap gets a `debug.refused`
#     event and nobody new.
#   * `stranger` rolls a person through `SimRecruits.roll` + `spawn_generated` -- the gate
#     beat's own two calls -- and stands them **at the gate**, the way `_tick_beats`
#     does: `SimRecruits.accept` itself asks only whether the body carries
#     `recruit.waiting`, but `SimFortify`'s E rung asks whether the *player* is standing
#     close enough (`waiting_in_reach`), and the gate is where a player goes looking for
#     one. A district with no gate anchor is refused rather than placed at (0, 0).

const SimDirector = preload("res://sim/modules/director.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRaiders = preload("res://sim/modules/raiders.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Clock = preload("res://sim/time/clock.gd")

# How far apart a debug-spawned band stands, in metres, so four bodies at once are a band
# shoulder to shoulder rather than one body repeated on top of itself. Under the melee
# reach of every shipped weapon, so a tester who spawned a band still finds it a band.
const BAND_SPACING_METRES: float = 1.2


# `"band.N"` is the id shape the F8 rows use (`"band.2"`, `"band.4"`); a bare `id` with no
# dot, or one that does not parse, is one raider -- never zero, so a malformed id from
# somewhere other than the panel still spawns something rather than silently nothing.
# A `size` field on the command wins outright, for a caller (a gate lane) that would
# rather not spell a count into an id string.
static func _band_size(c: Dictionary) -> int:
	if c.has("size"):
		return int(c["size"])
	var id: String = String(c.get("id", ""))
	var dot: int = id.rfind(".")
	if dot < 0:
		return 1
	var n: int = int(id.substr(dot + 1))
	return n if n > 0 else 1


static func register_module(world: Variant) -> void:
	world.systems.register("debug.intake", "input", 12, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			if String(c.get("type", "")) != "debug.spawn":
				continue
			var x: float = float(c.get("x", 0.0))
			var y: float = float(c.get("y", 0.0))
			var id: String = String(c.get("id", ""))
			var kind: String = String(c.get("kind", ""))
			# `stranger` names no item id and no zombie type -- it names a person, rolled the
			# way the gate beat rolls one -- so it is the one kind excused from the empty-id
			# refusal below.
			if id.is_empty() and kind != "stranger":
				continue
			match kind:
				"item":
					var item: int = SimItems.spawn_item(w, id, {})
					w.components.set_component(item, "position", {"x": x, "y": y})
					w.events.publish({"type": "debug.spawned", "kind": "item", "id": id, "entity": item})
				"zombie":
					var rng: Variant = w.rng.stream("debug")
					var ent: int = SimRoster.spawn_zombie(w, x, y, id, rng)
					w.events.publish({"type": "debug.spawned", "kind": "zombie", "id": id, "entity": ent})
				"raider":
					_spawn_raider_band(w, id, c, x, y)
				"stranger":
					_spawn_stranger(w, id)
	)


# A band, through `SimRaiders.spawn_band` -- the same call `SimDirector._emit_band` makes,
# with the positions the only thing that differs (a line ahead of the player rather than a
# district edge). `stamp_band` afterwards is what makes it a band rather than loose bodies:
# it can fall below half strength and withdraw, exactly like a drawn raid.
static func _spawn_raider_band(world: Variant, id: String, c: Dictionary, x: float, y: float) -> void:
	var size: int = _band_size(c)
	if size <= 0:
		world.events.publish({"type": "debug.refused", "kind": "raider", "reason": "size"})
		return
	var live: int = SimRaiders.live_count(world)
	if live + size > SimDirector.RAID_LIVE_CAP:
		world.events.publish({"type": "debug.refused", "kind": "raider", "reason": "cap"})
		return
	var positions: Array = []
	for i in size:
		positions.append(Vector2(x + float(i) * BAND_SPACING_METRES, y))
	var rng: Variant = world.rng.stream("debug")
	var members: Array = SimRaiders.spawn_band(world, positions, rng)
	if members.is_empty():
		world.events.publish({"type": "debug.refused", "kind": "raider", "reason": "no-archetype"})
		return
	# The night it "came" and how many -- the same two fields `_emit_band` stamps a real
	# raid with, so this band can lose men and withdraw exactly like a drawn one.
	SimRaiders.stamp_band(world, members, int(world.tick))
	world.events.publish({"type": "debug.spawned", "kind": "raider", "id": id, "entities": members})


# One person, at the gate, through the gate beat's own two calls (`SimRecruits.roll` then
# `spawn_generated`) and tagged the way `_tick_beats` tags one: `recruit {waiting: true,
# beatDay}`. `accept` itself never asks where the body is standing -- only `waiting` -- but
# `SimFortify`'s E rung asks whether the *player* is close enough, and the gate is where a
# player goes looking for someone waiting, so this is placed there rather than at the
# player's feet.
static func _spawn_stranger(world: Variant, id: String) -> void:
	if int((world.recruits as Dictionary).get("accepted", 0)) >= SimRecruits.CAP:
		world.events.publish({"type": "debug.refused", "kind": "stranger", "reason": "cap"})
		return
	var gate: Vector2i = SimTileMap.gate_a(world.tilemap)
	if gate.x < 0 or gate.y < 0:
		world.events.publish({"type": "debug.refused", "kind": "stranger", "reason": "no-gate"})
		return
	var rng: Variant = world.rng.stream("debug")
	var rolled: Dictionary = SimRecruits.roll(world, rng)
	var gx: float = float(gate.x) + 0.5
	var gy: float = float(gate.y) + 1.5
	var ent: int = SimRecruits.spawn_generated(world, rolled, gx, gy)
	world.components.set_component(ent, "recruit", {"waiting": true, "beatDay": Clock.day_number(int(world.tick))})
	world.events.publish({"type": "debug.spawned", "kind": "stranger", "id": id, "entity": ent})
