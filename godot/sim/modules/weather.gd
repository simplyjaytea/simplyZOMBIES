class_name SimWeather
extends RefCounted
# A minimal rain state, the owner's decision of 2026-09-06 (docs/adr/0015, superseding the
# "weather is a second game" line of ADR 0002 in part). One state -- it is raining or it is not --
# drawn as spans off its own RNG stream from content ranges, and read by exactly three things,
# each gated: bodies outdoors get wet and read one band colder (needs.gd), scent decays faster on
# the field (attention.gd through SimBoot._diffuse), and the rain layer draws only while it rains
# (presentation/main.gd). docs/16's rule -- every weather state moves at least two systems in
# opposing directions -- is met by the first two: rain hides you and rain chills you.
#
# What it deliberately is not: no wind (still the four calibration weights), no fog, no seasons, no
# accuracy penalty, no thirst relief. Those are docs/16's Milestone 3 and each is its own slice.
#
# Statics only, and no static state: a gate boots two worlds in one process (the kernel trap
# CLAUDE.md records), so the state lives on `world.weather` -- a Dictionary of scalars the world
# snapshots the way it snapshots the director's -- and the schedule lives on the world's own
# `weather` stream.

const SimClock = preload("res://sim/time/clock.gd")

const STREAM: String = "weather"
const CONTENT_PATH: String = "weather/rain.json"

# The shipped first cuts, mirrored from content so a fixture world with no content tree still has
# a schedule to draw and a gate can tell the two apart.
const DEFAULTS: Dictionary = {
	"dryTicks": {"min": 144000, "max": 432000},
	"wetTicks": {"min": 24000, "max": 72000},
	"scentHalfLifeMul": 0.5,
	"wetAfterTicks": 200,
	"dryAfterTicks": 12000,
	"dryByFireTicks": 2400,
}


static func blank() -> Dictionary:
	return {"raining": false, "untilTick": 0, "spans": 0}


# The content entry, or the defaults. Read by path off the tree rather than through
# SimItems.content_entry, whose type resolver knows items and affixes and nothing else.
static func spec(world: Variant) -> Dictionary:
	if world == null or not ("content" in world) or not (world.content is Dictionary):
		return DEFAULTS
	var entry: Variant = (world.content as Dictionary).get(CONTENT_PATH)
	if not (entry is Dictionary):
		return DEFAULTS
	return entry as Dictionary


static func register_module(world: Variant) -> void:
	if not (world.weather is Dictionary) or (world.weather as Dictionary).is_empty():
		world.weather = blank()
	# input/-2: before wounds.impair (input/-1) and long before the needs phase and the
	# attention-propagate phase read `raining`, so the tick a span flips is the tick every
	# reader sees the new sky.
	world.systems.register("weather.tick", "input", -2, func(w: Variant) -> void:
		_tick(w)
	)


# The first span is dry, drawn on the first tick from the dry range, so every gate world boots
# under a clear sky and stays that way for at least the dry minimum -- a fixture that never asks
# about the weather never meets it. Each later flip draws the next span from the other range.
static func _tick(world: Variant) -> void:
	var st: Dictionary = world.weather as Dictionary
	var until: int = int(st.get("untilTick", 0))
	if int(world.tick) < until:
		return
	var s: Dictionary = spec(world)
	var was: bool = bool(st.get("raining", false))
	var first: bool = int(st.get("spans", 0)) == 0
	var raining: bool = false if first else not was
	var range_key: String = "wetTicks" if raining else "dryTicks"
	var r: Dictionary = s.get(range_key, DEFAULTS[range_key]) as Dictionary
	var span: int = int(world.rng.stream(STREAM).call("int_range", int(r.get("min", 0)), int(r.get("max", 0))))
	st["raining"] = raining
	st["untilTick"] = int(world.tick) + maxi(1, span)
	st["spans"] = int(st.get("spans", 0)) + 1
	if raining != was or first:
		world.events.publish({"type": "weather.changed", "raining": raining, "untilTick": int(st["untilTick"])})


static func raining(world: Variant) -> bool:
	if world == null or not ("weather" in world) or not (world.weather is Dictionary):
		return false
	return bool((world.weather as Dictionary).get("raining", false))


# What rain multiplies the scent half-life by this tick: below one while it rains, exactly one
# when dry, so a dry world costs nothing the old one did not. A half-life factor rather than a
# per-step one: the first cut was 0.85 a step, which compounded 240 times a minute and flattened
# the whole field inside a second of rain -- the balance harness read that as a colony wipe on
# seed 90210, and the variant driver in docs/23's record pinned it on the scent, not the wet.
static func scent_half_life_mul(world: Variant) -> float:
	if not raining(world):
		return 1.0
	return clampf(float(spec(world).get("scentHalfLifeMul", 1.0)), 0.01, 1.0)


static func wet_after_ticks(world: Variant) -> int:
	return int(spec(world).get("wetAfterTicks", DEFAULTS["wetAfterTicks"]))


static func dry_after_ticks(world: Variant) -> int:
	return int(spec(world).get("dryAfterTicks", DEFAULTS["dryAfterTicks"]))


static func dry_by_fire_ticks(world: Variant) -> int:
	return int(spec(world).get("dryByFireTicks", DEFAULTS["dryByFireTicks"]))


# The world column's sentence: one line while it rains, nothing when it does not. No digits, and
# no forecast -- docs/16: you read the sky.
static func hud_clause(world: Variant) -> String:
	if raining(world):
		return "It's raining."
	return ""
