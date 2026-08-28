extends SceneTree
# Roster: fake-wave mix, screamer alarm_on_sight, bloater blooms_on_death, exhausted swings degrade.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimScreamer = preload("res://sim/modules/screamer.gd")
const SimBloater = preload("res://sim/modules/bloater.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimCombat = preload("res://sim/combat.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _mix() and ok
	ok = _screamer_alarms() and ok
	ok = _screamer_ignores_corpse() and ok
	ok = _bloater_blooms() and ok
	ok = _exhausted_degrades() and ok
	if ok:
		print("M2_ROSTER_OK mix alarm bloom exhausted")
		quit(0)
	else:
		push_error("M2_ROSTER_FAIL")
		quit(1)

func _fixture(seed_val: int, w: int = 24, h: int = 24) -> Dictionary:
	return {"seed": seed_val, "tick_hz": 20, "map": {"width": w, "height": h, "walls": []}, "player": {"id": 0, "x": 12.0, "y": 12.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}

func _mix() -> bool:
	var world: Variant = World.new(_fixture(7))
	var rng: Variant = world.rng.stream("placement")
	var early: Dictionary = {}
	for i in 40:
		var t: String = SimRoster.pick_type(world, rng, 0)
		early[t] = int(early.get(t, 0)) + 1
	if int(early.get(SimRoster.TYPE_SHAMBLER, 0)) != 40:
		push_error("day 1 mix should be shambler-only %s" % str(early))
		return false
	var late_tick: int = Clock.DAY_TICKS * 2
	var counts: Dictionary = {SimRoster.TYPE_SHAMBLER: 0, SimRoster.TYPE_SCREAMER: 0, SimRoster.TYPE_BLOATER: 0}
	for i in 200:
		var t2: String = SimRoster.pick_type(world, rng, late_tick)
		counts[t2] = int(counts[t2]) + 1
	if int(counts[SimRoster.TYPE_SHAMBLER]) < 140 or int(counts[SimRoster.TYPE_SCREAMER]) < 10 or int(counts[SimRoster.TYPE_BLOATER]) < 5:
		push_error("day 3 mix off %s" % str(counts))
		return false
	print("MIX OK early=40 shambler late=%s" % str(counts))
	return true

func _screamer_alarms() -> bool:
	var world: Variant = World.new(_fixture(11))
	world.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(world, map)
	SimScreamer.register_module(world)
	world.components.set_component(world.player, "facing", {"radians": 0.0})
	var rng: Variant = world.rng.stream("shambler")
	var zed: int = SimRoster.spawn_zombie(world, 8.0, 12.0, SimRoster.TYPE_SCREAMER, rng)
	world.components.set_component(zed, "facing", {"radians": 0.0})
	world.step()
	var alarmed: bool = false
	var mag: float = 0.0
	for e in world.events.drained:
		if String((e as Dictionary).get("type", "")) == "noise.emitted" and int((e as Dictionary).get("source", -1)) == zed:
			alarmed = true
			mag = float((e as Dictionary).get("magnitude", 0))
	if not alarmed or mag < 299.0:
		push_error("screamer did not alarm mag=%s" % mag)
		return false
	if world.field.peak_noise() < 1.0:
		push_error("alarm did not reach field peak=%s" % world.field.peak_noise())
		return false
	var alarm: Dictionary = world.components.get_component(zed, "alarm") as Dictionary
	if int(alarm.get("ticksUntilReady", 0)) <= 0:
		push_error("cooldown not armed")
		return false
	world.step()
	var second: int = 0
	for e2 in world.events.drained:
		if String((e2 as Dictionary).get("type", "")) == "noise.emitted" and int((e2 as Dictionary).get("source", -1)) == zed:
			second += 1
	if second != 0:
		push_error("screamer re-alarmed during cooldown")
		return false
	print("ALARM OK mag=%s peak=%s" % [mag, world.field.peak_noise()])
	return true

# `is_person` (allegiance.gd) checks `controlled`/`identity`/`raider`, and none of those is
# stripped by `SimRecruits._make_corpse` -- gear stays on the body (ADR 0013), and so, until this
# lane, did the alarm. `_screamer_alarms` above is the true-positive proof the alarm can fire at
# all; this is the negative half of the same scenario, with the one visible survivor turned into
# a corpse before the screamer ever looks. Stepped past the alarm's own cooldown window (not just
# once) so a bug that alarmed on the very first sighting and then sat quiet for unrelated reasons
# could not slip past a single-tick check.
#
# Confirmed to fail against the bug it targets: with the `corpse` skip reverted out of
# screamer.gd, this lane alarms on the corpse exactly like `_screamer_alarms` does.
func _screamer_ignores_corpse() -> bool:
	var world: Variant = World.new(_fixture(11))
	world.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(world, map)
	SimScreamer.register_module(world)
	world.components.set_component(world.player, "facing", {"radians": 0.0})
	# Same body `_screamer_alarms` uses, turned into a corpse the way a dead colonist actually
	# becomes one -- the real path, not a hand-rolled component dict standing in for it.
	SimRecruits._make_corpse(world, world.player)
	var rng: Variant = world.rng.stream("shambler")
	var zed: int = SimRoster.spawn_zombie(world, 8.0, 12.0, SimRoster.TYPE_SCREAMER, rng)
	world.components.set_component(zed, "facing", {"radians": 0.0})
	var cooldown: int = int((world.components.get_component(zed, "alarm") as Dictionary).get("cooldownTicks", 600))
	var span: int = cooldown + 50
	var alarmed: bool = false
	var mag: float = 0.0
	for _i in span:
		world.step()
		for e in world.events.drained:
			if String((e as Dictionary).get("type", "")) == "noise.emitted" and int((e as Dictionary).get("source", -1)) == zed:
				alarmed = true
				mag = float((e as Dictionary).get("magnitude", 0))
	if alarmed:
		push_error("screamer alarmed over a corpse mag=%s" % mag)
		return false
	print("CORPSE OK no alarm over %d ticks (past the %d-tick cooldown)" % [span, cooldown])
	return true


func _bloater_blooms() -> bool:
	var world: Variant = World.new(_fixture(13))
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(world, map)
	SimHealth.register_module(world)
	SimBloater.register_module(world)
	var rng: Variant = world.rng.stream("shambler")
	var zed: int = SimRoster.spawn_zombie(world, 12.0, 10.0, SimRoster.TYPE_BLOATER, rng)
	world.events.publish({"type": "attack.connected", "attacker": world.player, "target": zed, "bodyPart": "head", "damage": 200})
	world.events.drain()
	var scent: bool = false
	var flags: int = 0
	for e in world.events.drained:
		if String((e as Dictionary).get("type", "")) == "scent.accumulated" and float((e as Dictionary).get("magnitude", 0)) >= 29.0:
			scent = true
	for entity in world.components.query(["contamination"]):
		flags += 1
	if not scent:
		push_error("bloater death lacked scent burst")
		return false
	if flags != 1:
		push_error("bloater contamination flags=%d" % flags)
		return false
	if world.field.peak_scent() < 1.0:
		push_error("scent did not reach field peak=%s" % world.field.peak_scent())
		return false
	print("BLOOM OK flags=1 scent=%s" % world.field.peak_scent())
	return true

func _exhausted_degrades() -> bool:
	var full: Variant = World.new(_fixture(17, 12, 10))
	var empty: Variant = World.new(_fixture(17, 12, 10))
	for w in [full, empty]:
		SimHealth.register_module(w)
		SimMelee.register_module(w)
		SimMelee.make_melee_armed(w, w.player)
		w.components.set_component(w.player, "facing", {"radians": 0.0})
		SimHealth.make_stamina(w, w.player, 100)
	(empty.components.get_component(empty.player, "stamina") as Dictionary)["current"] = 0
	full.commands.push({"type": "swing"})
	empty.commands.push({"type": "swing"})
	full.step()
	empty.step()
	var sf: Dictionary = full.components.get_component(full.player, "swing") as Dictionary
	var se: Dictionary = empty.components.get_component(empty.player, "swing") as Dictionary
	if int(se["state"]) != SimMelee.SwingState.WindUp:
		push_error("exhausted swing refused state=%s" % se["state"])
		return false
	if int(se["ticksLeft"]) <= int(sf["ticksLeft"]):
		push_error("exhausted windup %s should exceed full %s" % [se["ticksLeft"], sf["ticksLeft"]])
		return false
	print("EXHAUSTED OK full=%s empty=%s" % [sf["ticksLeft"], se["ticksLeft"]])
	return true
