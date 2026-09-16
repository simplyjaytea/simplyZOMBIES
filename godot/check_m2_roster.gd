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
# `zombie_speed` -- so the KINDS lane compares the component against the same conversion
# `make_shambler` used rather than against a multiplier copied into this file.
const SimLocomotion = preload("res://sim/locomotion.gd")

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
	ok = _the_new_kinds_are_content() and ok
	ok = _the_new_senses_are_read() and ok
	if ok:
		print("M2_ROSTER_OK mix alarm bloom exhausted, every zombie has eyes, extends resolved, senses and waves are content, the screamer sees what is lit at night, the dead write to the field from content, residue in every state, one roll a cloud, four wave kinds are JSON entries a body reads")
		quit(0)
	else:
		push_error("M2_ROSTER_FAIL")
		quit(1)

func _fixture(seed_val: int, w: int = 24, h: int = 24) -> Dictionary:
	return {"seed": seed_val, "tick_hz": 20, "map": {"width": w, "height": h, "walls": []}, "player": {"id": 0, "x": 12.0, "y": 12.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}

# --- MIX: the mix is content -------------------------------------------------------------------
#
# `pick_type` held 80/12/8 as three constants; each type now carries a `weight` and the draw is
# one roll over the summed weights of the kinds whose wave has arrived. Five assertions, each run
# red on purpose before it was trusted:
#
#  * PINNED -- the shipped tree on seed 20260805 draws exactly one sequence, fifty draws deep on
#    day 7 with every kind due, off its own `mixProbe` stream, pinned here as a literal. It fails
#    the moment a roll, the order of the pool or a shipped weight moves, and with it the
#    `placement` and `director` streams every campaign draws its bodies from.
#
#    **Re-pinned twice on 2026-09-15, both times deliberately.** First by the stalker-and-runner
#    slice and then by the armoured-and-heavy one, and the reasoning is the same both times: the
#    literal the first of them replaced was the sequence the hard-coded 80/12/8 drew, and that
#    byte-identity claim belonged to the mix slice, which changed *what content could say* and
#    nothing about what spawns. A slice that puts new kinds on the table changes what spawns **by
#    design**, so the day-7 sequence must move -- a re-pin that left it unchanged would mean the
#    new kinds were never in the pool. The armoured and the heavy are both wave 2, so they join
#    the pool on day 5 and the day-7 draw is over seven kinds summing to 128. The balance record
#    carries the campaign half of the same change (docs/23). What the pin still guarantees, and
#    why it is worth keeping: days 1 and 2 are untouched (QUIET below), and from here on any
#    *unintended* movement of the draw is red again.
#  * SILENCED -- a fixture tree with the shambler at `weight: 0` never draws one in 200 draws,
#    where the shipped tree draws it two times in three. PINNED alone would pass against code
#    that still had the constants in it; this is what says the number in the JSON is read.
#  * HEAVY -- a fixture with the bloater at 100 against 1 apiece draws bloaters overwhelmingly.
#    The dead-socket half of SILENCED, which on its own is satisfied by code that only ever looks
#    for a zero: here the weight has to be *summed*, not merely noticed.
#  * QUIET -- fifty day-1 calls leave the stream's state exactly where it was, and the same fifty
#    on day 7 move it. The short-circuit is what keeps days 1 and 2 byte-identical, and a state
#    that crept would have shifted every later draw of every campaign. Still true with five kinds
#    on the roster, because the stalker is wave 1 and the runner wave 3: on day 1 the shambler is
#    still the only thing due, and the pool still answers without a draw.
#  * SHARES -- the lane the re-pin owes. A literal sequence says "this did not move"; it does not
#    say the shipped mix is *what content asked for*. Two thousand day-7 draws, every kind's count
#    inside ±25% of `weight / summed weight`, computed from the resolved entries rather than from
#    a number copied into this file. Its negative is a tree with the runner at 1: that draw falls
#    outside the shipped runner band while the shambler stays inside the shipped shambler band, so
#    the band is narrow enough to notice a weight and wide enough not to be noise.
#
# The four ids the stalker-and-runner and armoured-and-heavy slices added are named **here** and
# not in `sim/modules/roster.gd` beside `TYPE_SHAMBLER` and the rest, on purpose: the first
# slice's whole claim is docs/14's "adding a zombie type is one JSON entry with zero code", and a
# `const TYPE_STALKER` in the sim would have been the first line of code it cost. The second slice
# did cost code -- a body may now wear a `worn` list -- but what that code reads is a *key*, never
# an id, so the rule survives intact. Nothing under `godot/sim/` names any of these four; they
# exist only so the lanes below can spell them.
const TYPE_STALKER: String = "zombie.stalker"
const TYPE_RUNNER: String = "zombie.runner"
const TYPE_ARMORED: String = "zombie.armored"
const TYPE_HEAVY: String = "zombie.heavy"

const PINNED_SEED: int = 20260805
const PINNED_STREAM: String = "mixProbe"
# h shambler, c screamer, b bloater, t stalker, r runner, a armored, y heavy -- the first fifty
# draws on day 7, where all seven kinds are due.
const PINNED_DRAWS: String = "hhhthaabhhbcrchhahchhhthhaayhhthhhhchhhthcrhhhhhhh"
# The share each kind's 2000-draw count may stray from its content weight, either way.
const SHARE_TOLERANCE: float = 0.25
const SHARE_DRAWS: int = 2000


func _mix() -> bool:
	var day7: int = Clock.tick_on_day(7, 0.5)
	var day1: int = Clock.tick_on_day(1, 0.5)
	var code: Dictionary = {SimRoster.TYPE_SHAMBLER: "h", SimRoster.TYPE_SCREAMER: "c", SimRoster.TYPE_BLOATER: "b", TYPE_STALKER: "t", TYPE_RUNNER: "r", TYPE_ARMORED: "a", TYPE_HEAVY: "y"}

	# PINNED.
	var world: Variant = World.new(_fixture(PINNED_SEED))
	var rng: Variant = world.rng.stream(PINNED_STREAM)
	var drawn: String = ""
	for i in PINNED_DRAWS.length():
		drawn += String(code.get(SimRoster.pick_type(world, rng, day7), "?"))
	if drawn != PINNED_DRAWS:
		push_error("MIX: seed %d no longer draws the pinned day-7 sequence\n  was %s\n  now %s" % [PINNED_SEED, PINNED_DRAWS, drawn])
		return false

	# QUIET: day 1, where only the shambler is due, answers without touching the stream.
	var quiet_world: Variant = World.new(_fixture(PINNED_SEED))
	var quiet_rng: Variant = quiet_world.rng.stream(PINNED_STREAM)
	var before: int = int(quiet_rng.call("save"))
	for i in 50:
		if SimRoster.pick_type(quiet_world, quiet_rng, day1) != SimRoster.TYPE_SHAMBLER:
			push_error("MIX: day 1 drew something other than a shambler")
			return false
	var after: int = int(quiet_rng.call("save"))
	if after != before:
		push_error("MIX: fifty day-1 calls moved the stream %d -> %d; the short-circuit is gone and every later draw has shifted" % [before, after])
		return false
	for i in 50:
		SimRoster.pick_type(quiet_world, quiet_rng, day7)
	if int(quiet_rng.call("save")) == before:
		# The negative half of QUIET: a `save()` that never moves would pass the check above
		# whatever pick_type did with the stream.
		push_error("MIX: fifty day-7 calls left the stream where it was -- `save()` is not reporting the draw")
		return false

	# SILENCED and HEAVY, against the shipped tree over the same seed and stream. Every kind but
	# the one under test is flattened to 1, so the fixtures stay comparable as the roster grows.
	var shipped: Dictionary = _draw_counts(null, day7, 200)
	var silenced: Dictionary = _draw_counts(_tree_with_weights({SimRoster.TYPE_SHAMBLER: 0}), day7, 200)
	var heavy: Dictionary = _draw_counts(_tree_with_weights({SimRoster.TYPE_BLOATER: 100, SimRoster.TYPE_SHAMBLER: 1, SimRoster.TYPE_SCREAMER: 1, TYPE_STALKER: 1, TYPE_RUNNER: 1, TYPE_ARMORED: 1, TYPE_HEAVY: 1}), day7, 200)
	if int(shipped.get(SimRoster.TYPE_SHAMBLER, 0)) < 110:
		push_error("MIX: the shipped tree should still be mostly shamblers (%s)" % str(shipped))
		return false
	if int(silenced.get(SimRoster.TYPE_SHAMBLER, 0)) != 0:
		push_error("MIX: a shambler at weight 0 was drawn %d times in 200 (%s)" % [int(silenced[SimRoster.TYPE_SHAMBLER]), str(silenced)])
		return false
	var silenced_rest: int = 0
	for kind in silenced.keys():
		if String(kind) != SimRoster.TYPE_SHAMBLER:
			silenced_rest += int(silenced[kind])
	if silenced_rest != 200:
		push_error("MIX: silencing the shambler should leave every other kind drawing (%s)" % str(silenced))
		return false
	if int(heavy.get(SimRoster.TYPE_BLOATER, 0)) < 180:
		push_error("MIX: a bloater at 100 against 1 apiece drew only %d of 200 -- the weight is counted, not summed (%s)" % [int(heavy.get(SimRoster.TYPE_BLOATER, 0)), str(heavy)])
		return false
	if int(heavy.get(SimRoster.TYPE_BLOATER, 0)) <= int(shipped.get(SimRoster.TYPE_BLOATER, 0)) * 3:
		push_error("MIX: weighting the bloater up changed nothing much (heavy %s vs shipped %s)" % [str(heavy), str(shipped)])
		return false
	if not _shares(day7):
		return false
	print("MIX OK pinned %d draws on seed %d unchanged; day-1 stream untouched (%d); shipped %s, shambler silenced %s, bloater at 100 %s" % [PINNED_DRAWS.length(), PINNED_SEED, before, str(shipped), str(silenced), str(heavy)])
	return true


# SHARES. Every kind due on `tick` is drawn at the share its own `weight` asks for, against a
# total this lane sums from the resolved entries rather than from a number written here -- so the
# assertion follows a content edit instead of having to be chased after one. The band is
# SHARE_TOLERANCE either way over SHARE_DRAWS draws.
#
# The negative is the discrimination question, which a band alone cannot answer: a tree with the
# runner at `weight: 1` must put the runner *outside* the shipped runner band while the shambler
# stays inside the shipped shambler band. A band wide enough to pass anything would fail that.
func _shares(tick: int) -> bool:
	var probe: Variant = World.new(_fixture(1))
	var weights: Dictionary = {}
	var total: int = 0
	for entry in SimRoster.types(probe):
		var type_id: String = String(entry.get("id", ""))
		if not SimRoster.wave_allows(probe, type_id, tick):
			continue
		weights[type_id] = SimRoster.weight_of(probe, type_id)
		total += int(weights[type_id])
	if weights.size() < 2 or total <= 0:
		push_error("SHARES: %d kind(s) due on the day under test -- nothing to judge a mix against" % weights.size())
		return false
	var drawn: Dictionary = _draw_counts(null, tick, SHARE_DRAWS)
	var bands: Dictionary = {}
	var report: Array[String] = []
	for type_id in weights.keys():
		var expected: float = float(SHARE_DRAWS) * float(weights[type_id]) / float(total)
		var low: float = expected * (1.0 - SHARE_TOLERANCE)
		var high: float = expected * (1.0 + SHARE_TOLERANCE)
		bands[type_id] = [low, high]
		var got: int = int(drawn.get(type_id, 0))
		report.append("%s w%d %d/%.0f" % [String(type_id).trim_prefix("zombie."), int(weights[type_id]), got, expected])
		if float(got) < low or float(got) > high:
			push_error("SHARES: %s carries weight %d of %d, so %d draws should be %.0f +/-%d%%, got %d (%s)" % [type_id, int(weights[type_id]), total, SHARE_DRAWS, expected, int(SHARE_TOLERANCE * 100.0), got, str(drawn)])
			return false
	if not bands.has(TYPE_RUNNER) or not bands.has(SimRoster.TYPE_SHAMBLER):
		push_error("SHARES: the negative needs the runner and the shambler both due on the day under test")
		return false
	var quieter: Dictionary = _draw_counts(_tree_with_weights({TYPE_RUNNER: 1}), tick, SHARE_DRAWS)
	var runner_band: Array = bands[TYPE_RUNNER] as Array
	var shambler_band: Array = bands[SimRoster.TYPE_SHAMBLER] as Array
	var quiet_runner: int = int(quieter.get(TYPE_RUNNER, 0))
	var quiet_shambler: int = int(quieter.get(SimRoster.TYPE_SHAMBLER, 0))
	if float(quiet_runner) >= float(runner_band[0]):
		push_error("SHARES: a runner dropped to weight 1 still drew %d, inside the shipped band [%.0f, %.0f] -- the band cannot see a weight" % [quiet_runner, float(runner_band[0]), float(runner_band[1])])
		return false
	if float(quiet_shambler) < float(shambler_band[0]) or float(quiet_shambler) > float(shambler_band[1]):
		push_error("SHARES: dropping the runner moved the shambler to %d, outside its shipped band [%.0f, %.0f] -- the band is too narrow to be about the runner" % [quiet_shambler, float(shambler_band[0]), float(shambler_band[1])])
		return false
	print("SHARES OK %d draws over %d kinds summing to %d: %s (+/-%d%%); the runner at weight 1 falls to %d, under its shipped floor %.0f, and the shambler stays at %d" % [
		SHARE_DRAWS, weights.size(), total, ", ".join(report), int(SHARE_TOLERANCE * 100.0), quiet_runner, float(runner_band[0]), quiet_shambler,
	])
	return true


# `count` draws on day `tick`, off the pinned seed and stream so the three trees are compared on
# the same rolls. `tree` null is the shipped content.
func _draw_counts(tree: Variant, tick: int, count: int) -> Dictionary:
	var f: Dictionary = _fixture(PINNED_SEED)
	if tree is Dictionary:
		f["content_tree"] = tree
	var world: Variant = World.new(f)
	var rng: Variant = world.rng.stream(PINNED_STREAM)
	var out: Dictionary = {}
	for i in count:
		var t: String = SimRoster.pick_type(world, rng, tick)
		out[t] = int(out.get(t, 0)) + 1
	return out


# The shipped tree with `weight` overridden per type id -- the fixture shape `_tree_with_emits`
# uses, and the reason `pick_type` tolerates a 0 the schema refuses.
func _tree_with_weights(weights: Dictionary) -> Dictionary:
	var src: Variant = World.new(_fixture(1))
	var tree: Dictionary = {}
	for path in src.content.keys():
		var entry: Variant = src.content[path]
		if entry is Dictionary and weights.has(String((entry as Dictionary).get("id", ""))):
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			copy["weight"] = int(weights[String(copy["id"])])
			tree[path] = copy
		else:
			tree[path] = entry
	return tree

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

	# The two kinds the stalker-and-runner slice added, each asked the same pair of questions:
	# absent on the day before its wave opens, present on the day it does. The stalker is wave 1
	# (day 3), the runner wave 3 (day 7) -- `first_day_of_wave` is 1 + wave * WAVE_DAY_STRIDE, and
	# the numbers are spelled out here rather than computed from it so a stride edit is visible.
	var day7: int = Clock.tick_on_day(7, 0.5)
	if SimRoster.wave_allows(w, TYPE_STALKER, day1) or not SimRoster.wave_allows(w, TYPE_STALKER, day3):
		push_error("WAVE: the stalker is wave 1 and belongs on day 3, not day 1")
		return false
	if SimRoster.wave_allows(w, TYPE_RUNNER, day5) or not SimRoster.wave_allows(w, TYPE_RUNNER, day7):
		push_error("WAVE: the runner is wave 3 and belongs on day 7, not day 5")
		return false
	# And `pick_type` honours it, which is the half that matters: a schedule nothing draws against
	# is a number in a file. Same tree, same stream, three days.
	var sched: Variant = World.new(_fixture(47))
	var srng: Variant = sched.rng.stream("placement")
	var on1: Dictionary = {}
	var on3: Dictionary = {}
	var on7: Dictionary = {}
	for i in 400:
		var t1: String = SimRoster.pick_type(sched, srng, day1)
		on1[t1] = int(on1.get(t1, 0)) + 1
	for i in 400:
		var t3: String = SimRoster.pick_type(sched, srng, day3)
		on3[t3] = int(on3.get(t3, 0)) + 1
	for i in 400:
		var t7: String = SimRoster.pick_type(sched, srng, day7)
		on7[t7] = int(on7.get(t7, 0)) + 1
	if on1.has(TYPE_STALKER) or on1.has(TYPE_RUNNER):
		push_error("WAVE: a day-1 draw produced a stalker or a runner (%s)" % str(on1))
		return false
	if not on3.has(TYPE_STALKER):
		push_error("WAVE: 400 day-3 draws produced no stalker, and it is wave 1 (%s)" % str(on3))
		return false
	if on3.has(TYPE_RUNNER):
		push_error("WAVE: a day-3 draw produced a wave-3 runner (%s)" % str(on3))
		return false
	if not on7.has(TYPE_RUNNER) or not on7.has(TYPE_STALKER):
		push_error("WAVE: 400 day-7 draws are missing one of the two new kinds (%s)" % str(on7))
		return false
	print("WAVE OK shipped screamer day 3; moved to wave 2 it waits for day 5; day-3 draws %s; stalker day 3 and runner day 7, 400 draws a day: %s / %s / %s" % [str(drew), str(on1), str(on3), str(on7)])
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


# --- The stalker and the runner, slice 5 of the procedural-population arc ---------------------
#
# docs/14 ends with a claim: "adding a zombie type is one JSON entry with zero code, provided its
# behavior composes from existing tags". The stalker and the runner are that claim put on trial
# -- two files under `content/zombies/`, nothing under `godot/sim/` touched, which is why the two
# ids are spelled at the top of *this* file and nowhere in the sim.
#
# KINDS is the two halves of "the entry is real". First, `resolved_entry` answers for each id
# with `extends zombie.base` applied, so a child that declares neither `spread` nor `grab` nor
# `behaviors` nor `emits` still has all four. Second -- and this is the half that matters -- the
# `sensory` and `locomotion` numbers land on the **spawned body's `shambler` component**, because
# that is what `shambler.think` reads every tick. A lane that stopped at the resolved dictionary
# would pass against a `make_shambler` that ignored content entirely, which is the dead-socket
# shape CLAUDE.md names; so each kind is spawned and its component read, and the negative is the
# same spawn against a tree carrying different numbers, which must produce the fixture's values
# rather than the shipped ones.
#
# The armoured and the heavy joined the table on 2026-09-15 and are held to exactly the same
# standard. The armoured kind is the one that did cost a line of sim -- a body may now wear a
# `worn` list -- but nothing about *this* lane changes for it: what its gear does is
# check_m2_armored.gd's business, and what this lane asks is the same question it asks of the
# other three, that the JSON is real and its numbers reach the component the brain reads.
const NEW_KIND_PROFILES: Dictionary = {
	"zombie.stalker": {"noise": 0.9, "light": 0.4, "scent": 0.4, "speed": 1.0, "wander": 0.45, "mill": 0.5},
	"zombie.runner": {"noise": 0.9, "light": 0.9, "scent": 0.4, "speed": 1.4, "wander": 0.3, "mill": 0.3},
	"zombie.armored": {"noise": 0.5, "light": 0.15, "scent": 0.5, "speed": 0.8, "wander": 0.3, "mill": 0.25},
	"zombie.heavy": {"noise": 0.9, "light": 0.1, "scent": 0.2, "speed": 0.6, "wander": 0.25, "mill": 0.2},
}
# The fixture profile the negative writes over each kind. Every number differs from both shipped
# rows above, so a component built from a constant cannot match it by accident.
const FIXTURE_PROFILE: Dictionary = {"noise": 0.15, "light": 0.05, "scent": 0.65, "speed": 0.55, "wander": 0.9, "mill": 0.8}


func _the_new_kinds_are_content() -> bool:
	var probe: Variant = _daylight_world(73)
	for type_id in NEW_KIND_PROFILES.keys():
		var entry: Variant = SimRoster.content_entry(probe, String(type_id))
		if not entry is Dictionary:
			push_error("KINDS: %s does not resolve -- its content file is not in the tree" % type_id)
			return false
		var e: Dictionary = entry as Dictionary
		for inherited in ["spread", "grab", "behaviors", "emits"]:
			if not e.has(inherited):
				push_error("KINDS: %s resolved without the base's `%s` -- `extends` did not apply (%s)" % [type_id, inherited, str(e.keys())])
				return false
		if not SimRoster.has_behavior(probe, String(type_id), "grab"):
			push_error("KINDS: %s cannot grab -- it did not inherit the base's behaviours" % type_id)
			return false
		for declared in ["introducedInWave", "weight", "appearance", "body", "sensory", "locomotion", "variance"]:
			if not e.has(declared):
				push_error("KINDS: %s declares no `%s`, which every shipped kind declares" % [type_id, declared])
				return false
		if String((e["appearance"] as Dictionary).get("sprite", "")) == "":
			push_error("KINDS: %s names no sprite key, so it has no picture at all" % type_id)
			return false
		var tints: Variant = (e["variance"] as Dictionary).get("tints")
		if not tints is Array or (tints as Array).size() < 2:
			push_error("KINDS: %s declares no palette of its own, so every body of it is the same body again" % type_id)
			return false

	# The component, from the shipped tree and then from a tree that disagrees with it.
	for type_id in NEW_KIND_PROFILES.keys():
		var shipped: Dictionary = NEW_KIND_PROFILES[type_id] as Dictionary
		if not _component_carries(_daylight_world(73), String(type_id), shipped, "the shipped tree"):
			return false
		var tree: Dictionary = _tree_with_profile(String(type_id), FIXTURE_PROFILE)
		if not _component_carries(_daylight_world(73, tree), String(type_id), FIXTURE_PROFILE, "a fixture tree"):
			return false
	print("KINDS OK %d kinds (%s) resolve with the base's spread, grab, behaviours and emits; their senses and speeds reach the spawned body's component, and a fixture tree's numbers reach it instead" % [NEW_KIND_PROFILES.size(), ", ".join(_kind_names())])
	return true


func _kind_names() -> Array[String]:
	var out: Array[String] = []
	for id in NEW_KIND_PROFILES.keys():
		out.append(String(id).trim_prefix("zombie."))
	return out


# One spawn, and every number the profile names read back off the `shambler` component.
# `seekSpeed` is the content multiplier through `SimLocomotion.zombie_speed`, and `wanderSpeed`
# and `millSpeed` are fractions of it -- the schema's "a faster type is faster in every state
# without four numbers to keep in agreement", asked of the component rather than of the schema.
func _component_carries(world: Variant, type_id: String, want: Dictionary, label: String) -> bool:
	var zed: int = SimRoster.spawn_zombie(world, 12.5, 12.5, type_id, world.rng.stream("shambler"))
	var comp: Variant = world.components.get_component(zed, "shambler")
	if not comp is Dictionary:
		push_error("KINDS: a spawned %s has no shambler component at all" % type_id)
		return false
	var sd: Dictionary = comp as Dictionary
	var seek: float = SimLocomotion.zombie_speed(float(want["speed"]))
	var checks: Array = [
		["noiseSense", float(want["noise"])],
		["lightSense", float(want["light"])],
		["scentSense", float(want["scent"])],
		["seekSpeed", seek],
		["wanderSpeed", seek * float(want["wander"])],
		["millSpeed", seek * float(want["mill"])],
	]
	for row in checks:
		var key: String = String((row as Array)[0])
		var expected: float = float((row as Array)[1])
		var got: float = float(sd.get(key, -999.0))
		if absf(got - expected) > 0.0001:
			push_error("KINDS: %s from %s carries %s %.4f, want %.4f -- the component is not built from the entry" % [type_id, label, key, got, expected])
			return false
	return true


# The shipped tree with one kind's `sensory` and `locomotion` blocks replaced outright.
# `_tree_with_emits` is the precedent; `crawl` is carried over from the shipped entry because the
# profile does not name one and a block that dropped it would inherit the base's instead, which
# is a second thing changing at once.
func _tree_with_profile(type_id: String, profile: Dictionary) -> Dictionary:
	var src: Variant = World.new(_fixture(1))
	var tree: Dictionary = {}
	for path in src.content.keys():
		var entry: Variant = src.content[path]
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == type_id:
			var copy: Dictionary = (entry as Dictionary).duplicate(true)
			var crawl: float = float(((copy.get("locomotion", {})) as Dictionary).get("crawl", 0.25))
			copy["sensory"] = {"noise": float(profile["noise"]), "light": float(profile["light"]), "scent": float(profile["scent"])}
			copy["locomotion"] = {"speed": float(profile["speed"]), "wander": float(profile["wander"]), "mill": float(profile["mill"]), "crawl": crawl}
			tree[path] = copy
		else:
			tree[path] = entry
	return tree


# READER -- the dead-socket half, asked of behaviour rather than of a number in a file. Each new
# kind is given the one stimulus its docs/14 row is about, with the shambler beside it in the
# same fixture on the same tick as the negative.
#
#  * **The runner is led by what it can see.** `sight_reach` is the observer's 12 m times
#    sqrt(`lightSense`), so a survivor ten metres off is inside a runner's 11.4 m and well
#    outside a shambler's 3.8 m: the runner closes on them and the shambler never leaves Wander.
#    SIGHT_ENABLED is pinned on and put back, the convention EYES already follows -- one gate
#    process shares the static across every world it boots.
#  * **The stalker hunts by sound.** `shambler.think`'s `heard` is
#    `noise_at >= own_noise + floor / noiseSense`, and neither kind emits noise, so a sound at
#    three times the field floor is over a stalker's 0.9 threshold (1.11x floor) and under a
#    shambler's 0.2 (5x floor): the stalker goes to Seek on the tick it arrives and the shambler
#    does not. The survivor is parked fifteen metres away, past a stalker's 7.6 m of sight, so
#    the only stimulus in that fixture is the sound.
func _the_new_senses_are_read() -> bool:
	var was: bool = SimShambler.SIGHT_ENABLED
	SimShambler.SIGHT_ENABLED = true
	var seen: Dictionary = {}
	for type_id in [TYPE_RUNNER, SimRoster.TYPE_SHAMBLER]:
		var w: Variant = _daylight_world(79)
		w.components.set_component(w.player, "position", {"x": 16.5, "y": 12.5})
		var z: int = SimRoster.spawn_zombie(w, 6.5, 12.5, String(type_id), w.rng.stream("shambler"))
		w.components.set_component(z, "facing", {"radians": 0.0})
		var sd: Dictionary = w.components.get_component(z, "shambler") as Dictionary
		var sought: bool = false
		for i in 40:
			w.step()
			var st: int = int(sd["state"])
			if st == SimShambler.ShamblerState["Seek"] or st == SimShambler.ShamblerState["Pursue"]:
				sought = true
		seen[type_id] = {"sought": sought, "reach": SimShambler.sight_reach(w, z, sd)}
	SimShambler.SIGHT_ENABLED = was
	var runner_saw: Dictionary = seen[TYPE_RUNNER] as Dictionary
	var shambler_saw: Dictionary = seen[SimRoster.TYPE_SHAMBLER] as Dictionary
	if not bool(runner_saw["sought"]) or float(runner_saw["reach"]) < 10.0:
		push_error("READER: a runner (light 0.9, reach %.2f m) did not close on a survivor 10 m away" % float(runner_saw["reach"]))
		return false
	if bool(shambler_saw["sought"]) or float(shambler_saw["reach"]) >= 10.0:
		push_error("READER: a shambler (light 0.1, reach %.2f m) saw a survivor 10 m away -- the negative has nothing to separate" % float(shambler_saw["reach"]))
		return false

	var heard: Dictionary = {}
	var floor_v: float = 0.0
	for type_id in [TYPE_STALKER, SimRoster.TYPE_SHAMBLER]:
		var w2: Variant = _daylight_world(83)
		w2.components.set_component(w2.player, "position", {"x": 1.5, "y": 22.5})
		floor_v = float(w2.field.calibration["floor"])
		var z2: int = SimRoster.spawn_zombie(w2, 12.5, 12.5, String(type_id), w2.rng.stream("shambler"))
		w2.components.set_component(z2, "facing", {"radians": 0.0})
		var sd2: Dictionary = w2.components.get_component(z2, "shambler") as Dictionary
		w2.field.emit_noise(12.5, 12.5, floor_v * 3.0)
		w2.step()
		var sense: float = float(sd2.get("noiseSense", 0.0))
		heard[type_id] = {"state": int(sd2["state"]), "sense": sense, "needs": floor_v / sense if sense > 0.0 else INF}
	var stalker_heard: Dictionary = heard[TYPE_STALKER] as Dictionary
	var shambler_heard: Dictionary = heard[SimRoster.TYPE_SHAMBLER] as Dictionary
	if absf(float(stalker_heard["sense"]) - 0.9) > 0.0001 or absf(float(shambler_heard["sense"]) - 0.2) > 0.0001:
		push_error("READER: noiseSense did not come from content (stalker %s, shambler %s)" % [str(stalker_heard), str(shambler_heard)])
		return false
	if int(stalker_heard["state"]) != SimShambler.ShamblerState["Seek"]:
		push_error("READER: a stalker (noise 0.9, needs %.5f) did not hear a sound at 3x the floor %.5f (%s)" % [float(stalker_heard["needs"]), floor_v * 3.0, str(stalker_heard)])
		return false
	if int(shambler_heard["state"]) == SimShambler.ShamblerState["Seek"]:
		push_error("READER: a shambler (noise 0.2, needs %.5f) heard the same sound -- the negative has nothing to separate (%s)" % [float(shambler_heard["needs"]), str(shambler_heard)])
		return false
	print("READER OK sight at 10 m: runner reach %.2f m closes, shambler reach %.2f m does not; sound at 3x floor %.5f: stalker needs %.5f and seeks, shambler needs %.5f and does not" % [
		float(runner_saw["reach"]), float(shambler_saw["reach"]), floor_v * 3.0, float(stalker_heard["needs"]), float(shambler_heard["needs"]),
	])
	return true
