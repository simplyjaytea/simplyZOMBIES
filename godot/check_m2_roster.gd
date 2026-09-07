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
const SimLight = preload("res://sim/modules/light.gd")
const SimAttentionEmitter = preload("res://sim/modules/attention_emitter.gd")
const SimInfection = preload("res://sim/modules/infection.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _mix() and ok
	ok = _screamer_alarms() and ok
	ok = _screamer_ignores_corpse() and ok
	ok = _bloater_blooms() and ok
	ok = _exhausted_degrades() and ok
	ok = _every_zombie_has_eyes_and_sight_is_a_stimulus() and ok
	ok = _extends_is_resolved() and ok
	ok = _senses_are_content() and ok
	ok = _waves_are_content() and ok
	ok = _the_screamer_sees_a_lit_survivor_at_night() and ok
	ok = _the_dead_write_to_the_field_from_content() and ok
	ok = _residue_is_laid_in_every_state() and ok
	ok = _a_second_cloud_rolls_again() and ok
	if ok:
		print("M2_ROSTER_OK mix alarm bloom exhausted, every zombie has eyes, extends resolved, senses and waves are content, the screamer sees what is lit at night, the dead write to the field from content, residue in every state, one roll a cloud")
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


# --- The playable state, slice 5: eyes, senses, extends, waves ------------------------------

func _daylight_world(seed_val: int, tree: Variant = null, emitting: bool = false) -> Variant:
	var f: Dictionary = _fixture(seed_val)
	if tree is Dictionary:
		f["content_tree"] = tree
	var world: Variant = World.new(f)
	world.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(world, map)
	SimShambler.register_module(world, map)
	if emitting:
		SimAttentionEmitter.register_module(world, map)
	return world


# The shipped tree with one type's `emits` replaced -- the shape the WAVE lane uses.
func _tree_with_emits(type_id: String, emits: Array) -> Dictionary:
	var src: Variant = World.new(_fixture(1))
	var tree: Dictionary = {}
	for path in src.content.keys():
		var entry: Variant = src.content[path]
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == type_id:
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			copy["emits"] = emits
			tree[path] = copy
		else:
			tree[path] = entry
	return tree


# Every zombie gets eyes, and what it sees is a stimulus: a shambler with a survivor three
# metres ahead of it in daylight -- nothing to hear, nothing to smell, and well past the 1.6 m
# contact that used to be its only way of noticing anybody -- goes to Seek and closes. The
# negative is the same body with its `observer` stripped, which is what every shambler was
# before this slice: it never leaves Wander. That is the dead-socket half -- `shambler_eyes()`
# on a component nothing read would pass a "has observer" check just as well. Then the reach:
# the same survivor eight metres off is beyond a shambler's `sensory.light` 0.1 (3.8 m of its
# 12 m eyes) and inside a screamer's 0.9 (11.4 m), so the shambler wanders and the screamer
# seeks -- `sight_reach` read from content, with the other type as the negative.
func _every_zombie_has_eyes_and_sight_is_a_stimulus() -> bool:
	# The flag is pinned on for the lane and restored after, whatever the shipped default is
	# (the GRABS_ENABLED convention, check_m2_contact.gd): one gate process shares the static
	# across every world it boots.
	var was: bool = SimShambler.SIGHT_ENABLED
	SimShambler.SIGHT_ENABLED = true
	var ok: bool = _sight_lane()
	SimShambler.SIGHT_ENABLED = was
	if not ok:
		return false
	# The shipped default is read: with the flag off (as it ships), the same 3 m survivor draws
	# no seek -- the negative that proves the flag reaches the stimulus rather than decorating it.
	SimShambler.SIGHT_ENABLED = false
	var off_world: Variant = _daylight_world(23)
	off_world.components.set_component(off_world.player, "position", {"x": 9.5, "y": 12.5})
	var off_zed: int = SimRoster.spawn_zombie(off_world, 6.5, 12.5, SimRoster.TYPE_SHAMBLER, off_world.rng.stream("shambler"))
	off_world.components.set_component(off_zed, "facing", {"radians": 0.0})
	var off_sought: bool = false
	for i in 80:
		off_world.step()
		var st: int = int((off_world.components.get_component(off_zed, "shambler") as Dictionary)["state"])
		if st == SimShambler.ShamblerState["Seek"] or st == SimShambler.ShamblerState["Pursue"]:
			off_sought = true
	SimShambler.SIGHT_ENABLED = was
	if off_sought:
		push_error("EYES: with SIGHT_ENABLED false a shambler still sought by sight -- the flag is not read")
		return false
	print("EYES OK the flag off draws no seek at 3 m; shipped default SIGHT_ENABLED=%s" % str(was))
	return true


func _sight_lane() -> bool:
	var seen_states: Dictionary = {}
	for eyes in [true, false]:
		var world: Variant = _daylight_world(23)
		world.components.set_component(world.player, "position", {"x": 9.5, "y": 12.5})
		var rng: Variant = world.rng.stream("shambler")
		var zed: int = SimRoster.spawn_zombie(world, 6.5, 12.5, SimRoster.TYPE_SHAMBLER, rng)
		world.components.set_component(zed, "facing", {"radians": 0.0})
		if not world.components.has_component(zed, "observer"):
			push_error("EYES: a spawned shambler has no observer")
			return false
		if not eyes:
			world.components.remove_component(zed, "observer")
		var start_x: float = 6.5
		var reached: int = -1
		for i in 80:
			world.step()
			var sd: Dictionary = world.components.get_component(zed, "shambler") as Dictionary
			var st: int = int(sd["state"])
			if reached < 0 and (st == SimShambler.ShamblerState["Seek"] or st == SimShambler.ShamblerState["Pursue"]):
				reached = i
		var end_x: float = float((world.components.get_component(zed, "position") as Dictionary)["x"])
		seen_states[eyes] = {"reached": reached, "moved": end_x - start_x}
	var with: Dictionary = seen_states[true]
	var without: Dictionary = seen_states[false]
	if int(with["reached"]) < 0 or float(with["moved"]) <= 0.5:
		push_error("EYES: a shambler with eyes never sought the survivor in front of it (%s)" % str(with))
		return false
	if int(without["reached"]) >= 0:
		push_error("EYES: a shambler with no eyes sought a survivor it could neither hear nor smell (%s)" % str(without))
		return false
	for type_id in [SimRoster.TYPE_BLOATER, SimRoster.TYPE_SCREAMER]:
		var w2: Variant = _daylight_world(29)
		var z2: int = SimRoster.spawn_zombie(w2, 6.5, 6.5, type_id, w2.rng.stream("shambler"))
		if not w2.components.has_component(z2, "observer"):
			push_error("EYES: %s spawned without an observer" % type_id)
			return false
		var sd2: Dictionary = w2.components.get_component(z2, "shambler") as Dictionary
		if not bool(sd2["canGrab"]):
			push_error("EYES: %s cannot grab -- `behaviors` lost its inherited grab" % type_id)
			return false
	# The reach, from content: eight metres is past a shambler's eyes and inside a screamer's.
	var far: Dictionary = {}
	for type_id in [SimRoster.TYPE_SHAMBLER, SimRoster.TYPE_SCREAMER]:
		var w3: Variant = _daylight_world(23)
		w3.components.set_component(w3.player, "position", {"x": 14.5, "y": 12.5})
		var z3: int = SimRoster.spawn_zombie(w3, 6.5, 12.5, type_id, w3.rng.stream("shambler"))
		w3.components.set_component(z3, "facing", {"radians": 0.0})
		var sd3: Dictionary = w3.components.get_component(z3, "shambler") as Dictionary
		var sought: bool = false
		for i in 40:
			w3.step()
			var st3: int = int(sd3["state"])
			if st3 == SimShambler.ShamblerState["Seek"] or st3 == SimShambler.ShamblerState["Pursue"]:
				sought = true
		far[type_id] = {"sought": sought, "reach": SimShambler.sight_reach(w3, z3, sd3)}
	var sh: Dictionary = far[SimRoster.TYPE_SHAMBLER]
	var sc: Dictionary = far[SimRoster.TYPE_SCREAMER]
	if bool(sh["sought"]) or absf(float(sh["reach"]) - 12.0 * sqrt(0.1)) > 0.01:
		push_error("EYES: a shambler (light 0.1) sought a survivor 8 m off -- its reach should be 3.8 m (%s)" % str(sh))
		return false
	if not bool(sc["sought"]) or absf(float(sc["reach"]) - 12.0 * sqrt(0.9)) > 0.01:
		push_error("EYES: a screamer (light 0.9) did not seek a survivor 8 m off -- its reach should be 11.4 m (%s)" % str(sc))
		return false
	print("EYES OK 3 m: seek at tick %d, moved %.1f m; blind never; bloater and screamer have eyes and grab; 8 m: shambler (reach %.1f) wanders, screamer (reach %.1f) seeks" % [int(with["reached"]), float(with["moved"]), float(sh["reach"]), float(sc["reach"])])
	return true


# `extends`, resolved the way the frozen oracle resolves it (src/sim/content/registry.ts):
# child wins, objects merge, arrays replace. Two worlds with two trees prove the memo is
# per-world -- the shared-static trap, CLAUDE.md -- and the shipped tree proves the three
# types inherit `spread`, `grab` and the base's `behaviors` shape rather than triplicating it.
func _extends_is_resolved() -> bool:
	var parent_a: Dictionary = {"id": "zombie.p", "sensory": {"noise": 0.5, "light": 0.5, "scent": 0.5}, "spread": {"radians": 0.3}, "behaviors": ["a", "b"]}
	var parent_b: Dictionary = {"id": "zombie.p", "sensory": {"noise": 0.5, "light": 0.5, "scent": 0.5}, "spread": {"radians": 0.9}, "behaviors": ["a", "b"]}
	var child: Dictionary = {"id": "zombie.c", "extends": "zombie.p", "sensory": {"noise": 0.1}, "behaviors": ["c"]}
	var wa: Variant = World.new(_fixture(31)) 
	wa.content = {"zombies/p.json": parent_a, "zombies/c.json": child}
	var wb: Variant = World.new(_fixture(31))
	wb.content = {"zombies/p.json": parent_b, "zombies/c.json": child}
	var ra: Variant = SimRoster.content_entry(wa, "zombie.c")
	var rb: Variant = SimRoster.content_entry(wb, "zombie.c")
	if not ra is Dictionary or not rb is Dictionary:
		push_error("EXTENDS: the child did not resolve (%s / %s)" % [str(ra), str(rb)])
		return false
	var sa: Dictionary = (ra as Dictionary)["sensory"] as Dictionary
	if absf(float(sa["noise"]) - 0.1) > 0.0001 or absf(float(sa["light"]) - 0.5) > 0.0001 or absf(float(sa["scent"]) - 0.5) > 0.0001:
		push_error("EXTENDS: objects did not merge child-wins (%s)" % str(sa))
		return false
	if (ra as Dictionary)["behaviors"] != ["c"]:
		push_error("EXTENDS: arrays should replace, got %s" % str((ra as Dictionary)["behaviors"]))
		return false
	if absf(float(((ra as Dictionary)["spread"] as Dictionary)["radians"]) - 0.3) > 0.0001:
		push_error("EXTENDS: world A's child did not inherit A's spread (%s)" % str((ra as Dictionary)["spread"]))
		return false
	if absf(float(((rb as Dictionary)["spread"] as Dictionary)["radians"]) - 0.9) > 0.0001:
		push_error("EXTENDS: world B's child resolved against world A's parent -- the memo is shared (%s)" % str((rb as Dictionary)["spread"]))
		return false
	if String((ra as Dictionary)["id"]) != "zombie.c":
		push_error("EXTENDS: the child lost its id (%s)" % str((ra as Dictionary)["id"]))
		return false
	# A second ask is the memo, not a second resolve: same object back.
	if not is_same(SimRoster.content_entry(wa, "zombie.c"), ra):
		push_error("EXTENDS: the resolver is not memoised per world")
		return false
	# The shipped tree.
	var w: Variant = World.new(_fixture(31))
	var bloater: Dictionary = SimRoster.content_entry(w, SimRoster.TYPE_BLOATER) as Dictionary
	var screamer: Dictionary = SimRoster.content_entry(w, SimRoster.TYPE_SCREAMER) as Dictionary
	var shambler: Dictionary = SimRoster.content_entry(w, SimRoster.TYPE_SHAMBLER) as Dictionary
	if not bloater.has("spread") or not screamer.has("spread") or not shambler.has("spread"):
		push_error("EXTENDS: the shipped types do not inherit the base's spread")
		return false
	if not shambler.has("grab") or absf(float((shambler["grab"] as Dictionary)["strength"]) - 0.5) > 0.0001:
		push_error("EXTENDS: the shambler did not inherit the base grab (%s)" % str(shambler.get("grab")))
		return false
	if not SimRoster.has_behavior(w, SimRoster.TYPE_BLOATER, "grab") or not SimRoster.has_behavior(w, SimRoster.TYPE_SCREAMER, "grab"):
		push_error("EXTENDS: the bloater or screamer does not declare grab")
		return false
	if SimRoster.has_behavior(w, SimRoster.TYPE_BLOATER, "alarm_on_sight") or SimRoster.has_behavior(w, SimRoster.TYPE_SHAMBLER, "blooms_on_death"):
		push_error("EXTENDS: behaviours leaked across types")
		return false
	print("EXTENDS OK child-wins merge, arrays replace, spread inherited per world (0.3 / 0.9), shipped types carry spread, grab and their own tags")
	return true


# Senses are content. Noise: `sensory.noise` scales what a body can hear, so one field level
# sits above the shambler's threshold (0.2) and below the bloater's (0.1). Light: `sensory.light`
# scales how far a wandering body leans toward a fire it can see, so the screamer (0.9) turns
# further than the shambler (0.1) from the same heading. Both from the shipped JSON, both with
# the other type as the negative.
func _senses_are_content() -> bool:
	var floor_v: float = 0.0
	var states: Dictionary = {}
	for type_id in [SimRoster.TYPE_SHAMBLER, SimRoster.TYPE_BLOATER]:
		var world: Variant = _daylight_world(37)
		world.components.set_component(world.player, "position", {"x": 1.5, "y": 22.5})
		floor_v = float(world.field.calibration["floor"])
		var zed: int = SimRoster.spawn_zombie(world, 12.5, 12.5, type_id, world.rng.stream("shambler"))
		world.components.set_component(zed, "facing", {"radians": 0.0})
		var sd: Dictionary = world.components.get_component(zed, "shambler") as Dictionary
		# Between floor/0.2 and floor/0.1: the shambler's ear reaches it, the bloater's does not.
		world.field.emit_noise(12.5, 12.5, floor_v * 7.0)
		world.step()
		states[type_id] = {"state": int(sd["state"]), "sense": float(sd.get("noiseSense", -1.0))}
	var sh: Dictionary = states[SimRoster.TYPE_SHAMBLER]
	var bl: Dictionary = states[SimRoster.TYPE_BLOATER]
	if absf(float(sh["sense"]) - 0.2) > 0.0001 or absf(float(bl["sense"]) - 0.1) > 0.0001:
		push_error("SENSES: noiseSense not read from content (%s / %s)" % [str(sh), str(bl)])
		return false
	if int(sh["state"]) != SimShambler.ShamblerState["Seek"]:
		push_error("SENSES: the shambler did not hear a noise at 7x floor (%s)" % str(sh))
		return false
	if int(bl["state"]) == SimShambler.ShamblerState["Seek"]:
		push_error("SENSES: the bloater heard a noise below its threshold (%s)" % str(bl))
		return false
	var turns: Dictionary = {}
	for type_id in [SimRoster.TYPE_SHAMBLER, SimRoster.TYPE_SCREAMER]:
		var world: Variant = _daylight_world(41)
		world.components.set_component(world.player, "position", {"x": 1.5, "y": 22.5})
		var zed: int = SimRoster.spawn_zombie(world, 12.5, 12.5, type_id, world.rng.stream("shambler"))
		world.components.set_component(zed, "facing", {"radians": 0.0})
		var lamp: int = int(world.entities.spawn())
		world.components.set_component(lamp, "position", {"x": 12.5, "y": 4.5})
		SimLight.make_light_source(world, lamp, 12.0)
		world.step()
		var sd: Dictionary = world.components.get_component(zed, "shambler") as Dictionary
		sd["state"] = SimShambler.ShamblerState["Wander"]
		sd["ticksToTurn"] = 1000
		var vel: Dictionary = world.components.get_component(zed, "velocity") as Dictionary
		vel["dx"] = 0.4
		vel["dy"] = 0.0
		world.step()
		turns[type_id] = atan2(float(vel["dy"]), float(vel["dx"]))
	var lean_shambler: float = float(turns[SimRoster.TYPE_SHAMBLER])
	var lean_screamer: float = float(turns[SimRoster.TYPE_SCREAMER])
	if lean_screamer >= 0.0 or lean_shambler >= 0.0:
		push_error("SENSES: nobody leaned toward the lamp to the north (shambler %.3f screamer %.3f)" % [lean_shambler, lean_screamer])
		return false
	if absf(lean_screamer) <= absf(lean_shambler) * 2.0:
		push_error("SENSES: the screamer (light 0.9) did not lean further than the shambler (0.1): %.3f vs %.3f" % [lean_screamer, lean_shambler])
		return false
	print("SENSES OK 7x floor: shambler seeks, bloater does not; lean to a lamp shambler %.3f screamer %.3f rad" % [lean_shambler, lean_screamer])
	return true


# `introducedInWave` is read. The shipped screamer is wave 1 (day 3); a tree that moves it to
# wave 2 moves its first day to 5, and `pick_type` on that tree never draws it on day 3.
func _waves_are_content() -> bool:
	var w: Variant = World.new(_fixture(43))
	var day1: int = Clock.tick_on_day(1, 0.5)
	var day3: int = Clock.tick_on_day(3, 0.5)
	var day5: int = Clock.tick_on_day(5, 0.5)
	if SimRoster.wave_allows(w, SimRoster.TYPE_SCREAMER, day1) or not SimRoster.wave_allows(w, SimRoster.TYPE_SCREAMER, day3):
		push_error("WAVE: the shipped screamer should arrive on day 3, not day 1")
		return false
	if not SimRoster.wave_allows(w, SimRoster.TYPE_SHAMBLER, day1):
		push_error("WAVE: the shambler is wave 0 and should be allowed from day 1")
		return false
	var late: Variant = World.new(_fixture(43))
	var tree: Dictionary = {}
	for path in late.content.keys():
		var entry: Variant = late.content[path]
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == SimRoster.TYPE_SCREAMER:
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			copy["introducedInWave"] = 2
			tree[path] = copy
		else:
			tree[path] = entry
	late.content = tree
	if SimRoster.wave_allows(late, SimRoster.TYPE_SCREAMER, day3) or not SimRoster.wave_allows(late, SimRoster.TYPE_SCREAMER, day5):
		push_error("WAVE: a wave-2 screamer should arrive on day 5, not day 3")
		return false
	var rng: Variant = late.rng.stream("placement")
	var drew: Dictionary = {}
	for i in 300:
		var t: String = SimRoster.pick_type(late, rng, day3)
		drew[t] = int(drew.get(t, 0)) + 1
	if drew.has(SimRoster.TYPE_SCREAMER):
		push_error("WAVE: pick_type drew a wave-2 screamer on day 3 (%s)" % str(drew))
		return false
	if not drew.has(SimRoster.TYPE_BLOATER):
		push_error("WAVE: the wave-1 bloater should still be drawn on day 3 (%s)" % str(drew))
		return false
	print("WAVE OK shipped screamer day 3; moved to wave 2 it waits for day 5; day-3 draws %s" % str(drew))
	return true


# The screamer sees at night what is lit at the target. Ambient 0.04 gave it 0.48 m of sight
# after dark, so the type built to punish being seen could not see a survivor under a floodlight.
func _the_screamer_sees_a_lit_survivor_at_night() -> bool:
	var alarms: Dictionary = {}
	for lit in [true, false]:
		var world: Variant = World.new(_fixture(47))
		world.tick = Clock.tick_at_time_of_day(0.95)
		if Clock.ambient_light_at(int(world.tick)) > 0.1:
			push_error("SCREAMER-NIGHT: the fixture is not at night")
			return false
		var map: Variant = SimTileMap.blank_map(24, 24)
		SimBoot.attach_kernel(world, map)
		SimScreamer.register_module(world)
		world.components.set_component(world.player, "facing", {"radians": 0.0})
		world.components.set_component(world.player, "position", {"x": 16.5, "y": 12.5})
		if lit:
			var lamp: int = int(world.entities.spawn())
			world.components.set_component(lamp, "position", {"x": 16.5, "y": 12.5})
			SimLight.make_light_source(world, lamp, 6.0)
		var zed: int = SimRoster.spawn_zombie(world, 8.5, 12.5, SimRoster.TYPE_SCREAMER, world.rng.stream("shambler"))
		world.components.set_component(zed, "facing", {"radians": 0.0})
		var alarmed: bool = false
		for i in 5:
			world.step()
			for e in world.events.drained:
				if String((e as Dictionary).get("type", "")) == "noise.emitted" and int((e as Dictionary).get("source", -1)) == zed:
					alarmed = true
		alarms[lit] = alarmed
	if not bool(alarms[true]):
		push_error("SCREAMER-NIGHT: no alarm over a lit survivor 8 m away after dark")
		return false
	if bool(alarms[false]):
		push_error("SCREAMER-NIGHT: an alarm over an unlit survivor 8 m away after dark -- the night is not dark")
		return false
	print("SCREAMER-NIGHT OK lit at 8 m alarms, unlit does not")
	return true


# --- The playable state, slice 7: the dead write to the field from content ------------------

# `emits` builds the emitter. The shipped screamer (noise 4) standing still raises the field's
# noise; the shipped shambler (no noise) raises none -- the negative from the same tree; and a
# fabricated light emit makes the body a light source the index can see, which is the third
# channel's dead-socket half. The screamer does not seek its own groan: after the step it is
# still Wandering, because a body cannot hear below its own noise.
func _the_dead_write_to_the_field_from_content() -> bool:
	var peaks: Dictionary = {}
	var states: Dictionary = {}
	for type_id in [SimRoster.TYPE_SCREAMER, SimRoster.TYPE_SHAMBLER]:
		var w: Variant = _daylight_world(59, null, true)
		w.components.set_component(w.player, "position", {"x": 1.5, "y": 22.5})
		var z: int = SimRoster.spawn_zombie(w, 12.5, 12.5, type_id, w.rng.stream("shambler"))
		var em: Variant = w.components.get_component(z, "attention_emitter")
		if not em is Dictionary:
			push_error("EMITS: %s spawned without an attention_emitter" % type_id)
			return false
		for i in 3:
			w.step()
		peaks[type_id] = float(w.field.peak_noise())
		states[type_id] = int((w.components.get_component(z, "shambler") as Dictionary)["state"])
	if float(peaks[SimRoster.TYPE_SCREAMER]) < 1.0:
		push_error("EMITS: a standing screamer (noise 4) raised no noise (peak %.3f)" % float(peaks[SimRoster.TYPE_SCREAMER]))
		return false
	if float(peaks[SimRoster.TYPE_SHAMBLER]) > 0.0:
		push_error("EMITS: a shambler with no noise emit raised %.3f" % float(peaks[SimRoster.TYPE_SHAMBLER]))
		return false
	if int(states[SimRoster.TYPE_SCREAMER]) != SimShambler.ShamblerState["Wander"]:
		push_error("EMITS: the screamer sought its own groan (state %d)" % int(states[SimRoster.TYPE_SCREAMER]))
		return false
	var lit: Variant = _daylight_world(61, _tree_with_emits(SimRoster.TYPE_SHAMBLER, [{"channel": "light", "magnitude": 6}]), true)
	var zl: int = SimRoster.spawn_zombie(lit, 12.5, 12.5, SimRoster.TYPE_SHAMBLER, lit.rng.stream("shambler"))
	lit.step()
	var src: Variant = lit.light.source_at(zl)
	if not src is Dictionary or absf(float((src as Dictionary)["magnitude"]) - 6.0) > 0.001:
		push_error("EMITS: a light emit of 6 did not make the body a 6 m light source (%s)" % str(src))
		return false
	if lit.light.lit_metres(13.5, 12.5) <= 0.0:
		push_error("EMITS: the glowing body lights nothing beside it")
		return false
	print("EMITS OK screamer noise peak %.2f and still Wandering, shambler %.2f, a light emit of 6 is a source the index reads" % [float(peaks[SimRoster.TYPE_SCREAMER]), float(peaks[SimRoster.TYPE_SHAMBLER])])
	return true


# Residue in every state: a Wandering shambler raises the scent field within an emit interval
# (the base entry's scent 8, inherited); the same type with scent 0 raises nothing. This is what
# `field_memory.gd` laid only while Investigating, and why it is gone.
func _residue_is_laid_in_every_state() -> bool:
	var w: Variant = _daylight_world(67, null, true)
	w.components.set_component(w.player, "position", {"x": 1.5, "y": 22.5})
	var z: int = SimRoster.spawn_zombie(w, 12.5, 12.5, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))
	var sd: Dictionary = w.components.get_component(z, "shambler") as Dictionary
	for i in 40:
		w.step()
	if int(sd["state"]) != SimShambler.ShamblerState["Wander"]:
		push_error("RESIDUE: the shambler left Wander (%d), so the lane is not judging a wandering body" % int(sd["state"]))
		return false
	var laid: float = float(w.field.peak_scent())
	if laid <= 0.0:
		push_error("RESIDUE: a wandering shambler laid no scent in 40 ticks")
		return false
	var quiet: Variant = _daylight_world(67, _tree_with_emits(SimRoster.TYPE_BASE, []), true)
	quiet.components.set_component(quiet.player, "position", {"x": 1.5, "y": 22.5})
	SimRoster.spawn_zombie(quiet, 12.5, 12.5, SimRoster.TYPE_SHAMBLER, quiet.rng.stream("shambler"))
	for i in 40:
		quiet.step()
	if float(quiet.field.peak_scent()) > 0.0:
		push_error("RESIDUE: with the base emits emptied a shambler still laid %.3f" % float(quiet.field.peak_scent()))
		return false
	print("RESIDUE OK a wandering shambler laid scent (peak %.2f) within 40 ticks; with no scent emit, none" % laid)
	return true


# One roll a cloud: a bitten survivor standing in one bloater's cloud rolls once, keeps that one
# roll however long the cloud lasts, and rolls again when a second bloater blooms over them.
func _a_second_cloud_rolls_again() -> bool:
	var world: Variant = World.new(_fixture(71))
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(world, map)
	SimHealth.register_module(world)
	SimBloater.register_module(world)
	SimHealth.make_survivor_body(world, world.player)
	world.components.set_component(world.player, "injuries", {"wounds": [{"kind": "bite", "part": "arm_left", "severity": 1}]})
	var rng: Variant = world.rng.stream("shambler")
	var first: int = SimRoster.spawn_zombie(world, 12.5, 10.5, SimRoster.TYPE_BLOATER, rng)
	world.events.publish({"type": "attack.connected", "attacker": world.player, "target": first, "bodyPart": "head", "damage": 200})
	for i in 3:
		world.step()
	var rolls: Variant = world.components.get_component(world.player, "contaminationRolls")
	if not rolls is Dictionary or ((rolls as Dictionary)["rolls"] as Array).size() != 1:
		push_error("BLOOM-TWICE: one cloud should be one roll, got %s" % str(rolls))
		return false
	for i in 40:
		world.step()
	if ((rolls as Dictionary)["rolls"] as Array).size() != 1:
		push_error("BLOOM-TWICE: the same cloud rolled again over 40 ticks (%s)" % str(rolls))
		return false
	var second: int = SimRoster.spawn_zombie(world, 12.5, 14.5, SimRoster.TYPE_BLOATER, rng)
	world.events.publish({"type": "attack.connected", "attacker": world.player, "target": second, "bodyPart": "head", "damage": 200})
	for i in 3:
		world.step()
	if ((rolls as Dictionary)["rolls"] as Array).size() != 2:
		push_error("BLOOM-TWICE: a second cloud should be a second roll, got %s" % str(rolls))
		return false
	var exposures: Variant = world.components.get_component(world.player, "zombieInfection")
	var n: int = ((exposures as Dictionary)["exposures"] as Array).size() if exposures is Dictionary else 0
	if n != 2:
		push_error("BLOOM-TWICE: two rolls should be two recorded exposures, got %d" % n)
		return false
	print("BLOOM-TWICE OK one cloud one roll (held over 40 ticks), a second cloud a second roll, two exposures recorded")
	return true
