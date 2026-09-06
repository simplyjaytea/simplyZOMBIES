class_name SimWeather
extends RefCounted
# The sky has kinds (docs/adr/0016, the owner's decision of 2026-09-06, widening docs/adr/0015's
# one rain flag): at any tick the world is under exactly one weather kind -- clear, rain, storm,
# cold_snap, snow, heat_wave -- drawn as spans on the sim's own `weather` stream from one content
# entry per kind (`content/weather/<kind>.json`), against a calendar (`content/climate/`) whose
# seasons weight which kind comes next. A non-clear span is always followed by clear, and the
# first span is always clear, so every gate world boots under a clear sky and stays that way for
# at least the clear minimum.
#
# What a kind moves is content: each entry declares its modifiers and this file exposes one
# accessor per modifier, every one an identity under clear. Readers, each gated by
# `godot:m2:weather` or the slice gate that wired it: needs.gd (wet, the temperature shift,
# thirst), attention.gd through SimBoot (scent and noise half-lives, the wind), shambler.gd
# (`_speed_of`), the modifier store (a global move_speed under source `weather`, applied here),
# jobs.gd (outdoor work), attention_emitter.gd (corpse scent), and presentation/main.gd (the
# rain layer, the snow cover). docs/16's rule -- every state moves at least two systems in
# opposing directions -- is met kind by kind in docs/adr/0016's table.
#
# Wind is a persistent variable rather than a kind (docs/16): a direction re-rolled every
# `windDriftDays` at the climate's strength, times the kind's `windMul`, handed to the attention
# field's four diffusion weights through `set_wind`. The field remembers what it was handed and
# this tick re-applies on any mismatch, which is how a restore (the field's `restore` copies only
# noise and scent), an `adopt_map` (a fresh field) and a gate's `set_kind` all heal themselves
# without world.gd learning what weather is.
#
# Statics only, and no static state: a gate boots two worlds in one process (the kernel trap
# CLAUDE.md records), so the state lives on `world.weather` -- a Dictionary of scalars the world
# snapshots the way it snapshots the director's -- and the schedule lives on the world's own
# `weather` stream. Every content read is by path off the tree, O(1), so nothing here caches.

const SimClock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")

const STREAM: String = "weather"
const CONTENT_DIR: String = "weather/"
const CLIMATE_PATH: String = "climate/temperate.json"
const CLEAR: String = "clear"
const SOURCE: String = "weather"
const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
# How many tiles a strike tries before it gives up for this interval. A district is mostly open
# ground, so sixteen draws miss everything only if the map is nearly all wall or all roof -- in
# which case there is nothing outdoors to strike and giving up silently is the right answer.
const LIGHTNING_TRIES: int = 16

# The shipped first cuts, mirrored from content so a fixture world with no content tree still has
# a schedule to draw and a gate can tell the two apart (the CONTENT lane compares them).
const DEFAULTS: Dictionary = {
	"clear": {"durationTicks": {"min": 144000, "max": 432000}, "weights": {"spring": 3, "summer": 6, "autumn": 4, "winter": 2}},
	"rain": {"durationTicks": {"min": 24000, "max": 72000}, "weights": {"spring": 5, "summer": 2, "autumn": 3, "winter": 1}, "wets": true, "scentHalfLifeMul": 0.5},
	"storm": {"durationTicks": {"min": 12000, "max": 36000}, "weights": {"spring": 1, "summer": 2, "autumn": 2, "winter": 0}, "wets": true, "scentHalfLifeMul": 0.35, "noiseHalfLifeMul": 0.4, "outdoorWork": false, "windMul": 2.0, "lightning": {"intervalTicks": {"min": 600, "max": 2400}, "noise": 240}},
	"cold_snap": {"durationTicks": {"min": 288000, "max": 864000}, "weights": {"spring": 1, "summer": 0, "autumn": 2, "winter": 5}, "tempShift": -1, "zombieMoveMul": 0.7, "spoilageMul": 0.5, "scentHalfLifeMul": 0.7},
	"snow": {"durationTicks": {"min": 48000, "max": 120000}, "weights": {"spring": 0, "summer": 0, "autumn": 1, "winter": 4}, "tempShift": -1, "zombieMoveMul": 0.9, "spoilageMul": 0.5, "scentHalfLifeMul": 0.6, "coverPerTick": 0.0000069444},
	"heat_wave": {"durationTicks": {"min": 288000, "max": 864000}, "weights": {"spring": 0, "summer": 4, "autumn": 1, "winter": 0}, "tempShift": 1, "thirstMul": 1.5, "spoilageMul": 2.0, "corpseScentMul": 2.0},
}
const CLIMATE_DEFAULTS: Dictionary = {
	"seasonDays": 5,
	"seasonOrder": ["spring", "summer", "autumn", "winter"],
	"startSeason": "spring",
	"wetAfterTicks": 200,
	"dryAfterTicks": 12000,
	"dryByFireTicks": 2400,
	"windDriftDays": 1,
	"windStrength": 0.6,
	"meltPerTick": 0.0000011574,
	"snowCoverMoveMul": 0.8,
	"snowCoverThreshold": 0.5,
}


static func blank() -> Dictionary:
	return {
		"kind": CLEAR, "untilTick": 0, "spans": 0,
		"windX": 0.0, "windY": 0.0, "windUntilTick": 0,
		"appliedMoveMul": 1.0, "snowCover": 0.0, "nextLightningTick": 0,
	}


# --- content --------------------------------------------------------------------------------

static func _content(world: Variant) -> Dictionary:
	if world == null or not ("content" in world) or not (world.content is Dictionary):
		return {}
	return world.content as Dictionary


# One kind's entry, or its mirrored default, or an empty record for a kind nobody declared --
# whose every accessor then answers the identity. Read by path rather than through
# SimItems.content_entry, whose type resolver knows items and affixes and nothing else.
static func spec_of(world: Variant, k: String) -> Dictionary:
	var entry: Variant = _content(world).get(CONTENT_DIR + k + ".json")
	if entry is Dictionary:
		return entry as Dictionary
	return DEFAULTS.get(k, {}) as Dictionary


static func spec(world: Variant) -> Dictionary:
	return spec_of(world, kind(world))


static func climate(world: Variant) -> Dictionary:
	var entry: Variant = _content(world).get(CLIMATE_PATH)
	if entry is Dictionary:
		return entry as Dictionary
	return CLIMATE_DEFAULTS


# Every kind the tree declares (the file stems under weather/), or the defaults' when there is
# no tree. Scans the tree, so it is called at a span flip and by gates, never per tick.
static func kinds(world: Variant) -> Array[String]:
	var out: Array[String] = []
	var c: Dictionary = _content(world)
	for p in c.keys():
		var path: String = String(p)
		if path.begins_with(CONTENT_DIR) and path.ends_with(".json"):
			out.append(path.trim_prefix(CONTENT_DIR).trim_suffix(".json"))
	if out.is_empty():
		for k in DEFAULTS.keys():
			out.append(String(k))
	out.sort()
	return out


static func _num(world: Variant, key: String, identity: float) -> float:
	var v: Variant = spec(world).get(key)
	if v is float or v is int:
		return float(v)
	return identity


# --- registration and the tick ----------------------------------------------------------------

static func register_module(world: Variant) -> void:
	if not (world.weather is Dictionary) or (world.weather as Dictionary).is_empty():
		world.weather = blank()
	# input/-2: before wounds.impair (input/-1) and long before the needs phase and the
	# attention-propagate phase read the kind, so the tick a span flips is the tick every
	# reader sees the new sky.
	world.systems.register("weather.tick", "input", -2, func(w: Variant) -> void:
		_tick(w)
	)


static func _tick(world: Variant) -> void:
	var st: Dictionary = world.weather as Dictionary
	var tick: int = int(world.tick)
	if tick >= int(st.get("untilTick", 0)):
		_next_span(world, st)
	_tick_lightning(world, st)
	if tick >= int(st.get("windUntilTick", 0)):
		_next_wind(world, st)
	_tick_cover(world, st)
	_apply(world, st)


# The bad half of a storm: a strike every `intervalTicks` somewhere outdoors, published as a
# plain `noise.emitted` the kernel handler turns into a bloom on the attention field, plus a
# `weather.lightning` for anything that wants to draw it. No light of its own and no sound --
# the owner chose noise plus a screen flash (ADR 0016's "considered and not taken"), and there
# is no thunder sample; 240 is deliberately none of `sfx.gd`'s one-shot magnitudes (180 gun,
# 120 shout, 4 bow), so the dispatcher plays nothing for it rather than a gunshot.
#
# `nextLightningTick` is 0 whenever the sky is not a storm (`set_kind` resets it), so the first
# tick of a storm draws an interval rather than striking on the spot: a storm announces itself
# with the HUD line and the rain, not with a strike on tick one. The draws only ever run under
# a kind that declares `lightning`, so a clear world's schedule is bit-identical to one drawn
# before this existed and the spine gate's DETERMINISM lane still walks the same spans.
static func _tick_lightning(world: Variant, st: Dictionary) -> void:
	var bolt: Variant = lightning_of(world)
	if not (bolt is Dictionary):
		return
	var next: int = int(st.get("nextLightningTick", 0))
	if int(world.tick) < next:
		return
	if next > 0:
		_strike(world, float((bolt as Dictionary).get("noise", 0.0)))
	_draw_interval(world, st, (bolt as Dictionary).get("intervalTicks", {}) as Dictionary)


static func _draw_interval(world: Variant, st: Dictionary, r: Dictionary) -> void:
	var span: int = int(world.rng.stream(STREAM).call("int_range", int(r.get("min", 1)), int(r.get("max", 1))))
	st["nextLightningTick"] = int(world.tick) + maxi(1, span)


# Picks an open outdoor tile by rejection -- x and y each on the weather stream, retried up to
# LIGHTNING_TRIES times -- rather than by walking the map, which would be thousands of tile
# reads a strike. A world with no tilemap has nowhere to strike and silently does not.
static func _strike(world: Variant, magnitude: float) -> void:
	if world == null or not ("tilemap" in world) or world.tilemap == null:
		return
	if not ("events" in world) or world.events == null:
		return
	var cols: int = int(world.tilemap.w)
	var rows: int = int(world.tilemap.h)
	if cols <= 0 or rows <= 0:
		return
	var stream: Variant = world.rng.stream(STREAM)
	for _try in LIGHTNING_TRIES:
		var tx: int = int(stream.call("int_range", 0, cols - 1))
		var ty: int = int(stream.call("int_range", 0, rows - 1))
		if SimTileMap.is_solid(world.tilemap, tx, ty) or SimTileMap.is_indoors(world.tilemap, tx, ty):
			continue
		var x: float = float(tx) + 0.5
		var y: float = float(ty) + 0.5
		# No `source`: the kernel's `kernel.attention-noise` handler reads x, y and magnitude
		# only, and nothing in the game may investigate the sky as though it were a survivor.
		world.events.publish({"type": "noise.emitted", "x": x, "y": y, "magnitude": magnitude})
		world.events.publish({"type": "weather.lightning", "x": x, "y": y, "tick": int(world.tick)})
		return


# The first span is clear, drawn on the first tick from the clear range. A non-clear span is
# followed by clear; a clear span rolls the next kind among the non-clear kinds by the current
# season's weights, and stays clear when nothing in the season has weight. Draw order on the
# stream is fixed -- the kind's roll, then the duration -- so the schedule is a function of the
# seed and the content alone.
static func _next_span(world: Variant, st: Dictionary) -> void:
	var was: String = String(st.get("kind", CLEAR))
	var first: bool = int(st.get("spans", 0)) == 0
	var next: String = CLEAR
	if not first and was == CLEAR:
		next = _roll_kind(world)
	var r: Dictionary = spec_of(world, next).get("durationTicks", {}) as Dictionary
	var span: int = int(world.rng.stream(STREAM).call("int_range", int(r.get("min", 1)), int(r.get("max", 1))))
	set_kind(world, next, int(world.tick) + maxi(1, span))


static func _roll_kind(world: Variant) -> String:
	var season: String = season_of(world)
	var names: Array[String] = kinds(world)
	var total: float = 0.0
	for k in names:
		if k != CLEAR:
			total += weight_of(world, k, season)
	if total <= 0.0:
		return CLEAR
	var roll: float = float(world.rng.stream(STREAM).call("float_range", 0.0, total))
	var acc: float = 0.0
	for k in names:
		if k == CLEAR:
			continue
		acc += weight_of(world, k, season)
		if roll < acc:
			return k
	return CLEAR


static func weight_of(world: Variant, k: String, season: String) -> float:
	var ws: Variant = spec_of(world, k).get("weights")
	if not (ws is Dictionary):
		return 0.0
	return maxf(0.0, float((ws as Dictionary).get(season, 0.0)))


# The one path a span flip and a gate's forcing both take, so the side effects -- the event, the
# modifier and the wind re-applied on the next `_apply` -- can never be skipped by writing the
# dictionary directly.
static func set_kind(world: Variant, k: String, until_tick: int) -> void:
	var st: Dictionary = world.weather as Dictionary
	var was: String = String(st.get("kind", CLEAR))
	st["kind"] = k
	st["untilTick"] = until_tick
	st["spans"] = int(st.get("spans", 0)) + 1
	# A sky that does not strike carries no strike clock, so the first tick of the next storm
	# draws its own first interval rather than inheriting a stale one from the last.
	if not (spec_of(world, k).get("lightning") is Dictionary):
		st["nextLightningTick"] = 0
	if "events" in world and world.events != null:
		world.events.publish({"type": "weather.changed", "kind": k, "previous": was, "raining": raining(world), "untilTick": until_tick})
	_apply(world, st)


static func _next_wind(world: Variant, st: Dictionary) -> void:
	var c: Dictionary = climate(world)
	var angle: float = float(world.rng.stream(STREAM).call("float_range", 0.0, TAU))
	var strength: float = clampf(float(c.get("windStrength", 0.0)), 0.0, 1.0)
	st["windX"] = cos(angle) * strength
	st["windY"] = sin(angle) * strength
	var drift: int = int(round(float(c.get("windDriftDays", 1.0)) * float(SimClock.DAY_TICKS)))
	st["windUntilTick"] = int(world.tick) + maxi(1, drift)


static func _tick_cover(world: Variant, st: Dictionary) -> void:
	var lay: float = _num(world, "coverPerTick", 0.0)
	var cover: float = float(st.get("snowCover", 0.0))
	if lay > 0.0:
		cover += lay
	else:
		cover -= float(climate(world).get("meltPerTick", 0.0))
	st["snowCover"] = clampf(cover, 0.0, 1.0)


# Re-applies whatever the world's own state says to the two things outside this file that hold a
# copy of it: the attention field's wind and the modifier store's global move_speed. Idempotent
# and cheap -- two float compares a tick -- and run every tick on purpose (see the header).
static func _apply(world: Variant, st: Dictionary) -> void:
	if "field" in world and world.field != null and (world.field as Object).has_method("set_wind"):
		var w: Dictionary = wind(world)
		if absf(float(world.field.wind_x) - float(w["x"])) > 0.000001 or absf(float(world.field.wind_y) - float(w["y"])) > 0.000001:
			world.field.set_wind(float(w["x"]), float(w["y"]))
	if "modifiers" in world and world.modifiers != null and (world.modifiers as Object).has_method("remove_by_source"):
		var want: float = survivor_move_mul(world)
		if absf(want - float(st.get("appliedMoveMul", 1.0))) > 0.000001:
			world.modifiers.call("remove_by_source", SOURCE)
			if absf(want - 1.0) > 0.000001:
				world.modifiers.call("add", {"stat": "move_speed", "op": "mul", "value": want, "source": SOURCE}, null)
			st["appliedMoveMul"] = want


# --- the calendar --------------------------------------------------------------------------

static func season_of(world: Variant) -> String:
	return season_at(world, int(world.tick))


static func season_at(world: Variant, tick: int) -> String:
	var c: Dictionary = climate(world)
	var order: Array = c.get("seasonOrder", SEASONS) as Array
	if order.is_empty():
		return "spring"
	var days: int = maxi(1, int(c.get("seasonDays", 1)))
	var start: int = maxi(0, order.find(String(c.get("startSeason", "spring"))))
	var index: int = (SimClock.day_number(tick) - 1) / days
	return String(order[(start + index) % order.size()])


# --- the readers ----------------------------------------------------------------------------

static func kind(world: Variant) -> String:
	if world == null or not ("weather" in world) or not (world.weather is Dictionary):
		return CLEAR
	return String((world.weather as Dictionary).get("kind", CLEAR))


# Whether a body outdoors is getting wet: rain and storm say so in content.
static func raining(world: Variant) -> bool:
	if world == null or not ("weather" in world) or not (world.weather is Dictionary):
		return false
	return bool(spec(world).get("wets", false))


# A half-life factor rather than a per-step one: the first cut was 0.85 a step, which compounded
# 240 times a minute and flattened the whole field inside a second of rain -- the balance harness
# read that as a colony wipe on seed 90210, and the variant driver in docs/23's record pinned it
# on the scent, not the wet. Exactly 1.0 under clear, so a clear world costs nothing.
static func scent_half_life_mul(world: Variant) -> float:
	return clampf(_num(world, "scentHalfLifeMul", 1.0), 0.01, 1.0)


static func noise_half_life_mul(world: Variant) -> float:
	return clampf(_num(world, "noiseHalfLifeMul", 1.0), 0.01, 1.0)


static func temp_shift(world: Variant) -> int:
	return clampi(int(_num(world, "tempShift", 0.0)), -2, 2)


static func zombie_move_mul(world: Variant) -> float:
	return clampf(_num(world, "zombieMoveMul", 1.0), 0.01, 1.0)


# The living slow under a kind's own multiplier and under snow on the ground, whichever is the
# harder; the cover is read rather than the fall so the snow underfoot outlives the snowfall.
static func survivor_move_mul(world: Variant) -> float:
	var mul: float = clampf(_num(world, "survivorMoveMul", 1.0), 0.01, 1.0)
	var c: Dictionary = climate(world)
	if snow_cover(world) >= float(c.get("snowCoverThreshold", 2.0)):
		mul = minf(mul, clampf(float(c.get("snowCoverMoveMul", 1.0)), 0.01, 1.0))
	return mul


static func spoilage_mul(world: Variant) -> float:
	return maxf(0.0, _num(world, "spoilageMul", 1.0))


static func thirst_mul(world: Variant) -> float:
	return maxf(0.0, _num(world, "thirstMul", 1.0))


static func corpse_scent_mul(world: Variant) -> float:
	return maxf(0.0, _num(world, "corpseScentMul", 1.0))


static func outdoor_work_allowed(world: Variant) -> bool:
	var v: Variant = spec(world).get("outdoorWork")
	return true if v == null else bool(v)


static func lightning_of(world: Variant) -> Variant:
	var v: Variant = spec(world).get("lightning")
	return v if v is Dictionary else null


static func snow_cover(world: Variant) -> float:
	if world == null or not ("weather" in world) or not (world.weather is Dictionary):
		return 0.0
	return clampf(float((world.weather as Dictionary).get("snowCover", 0.0)), 0.0, 1.0)


# The wind as the field should feel it: the stored direction times the kind's multiplier.
static func wind(world: Variant) -> Dictionary:
	if world == null or not ("weather" in world) or not (world.weather is Dictionary):
		return {"x": 0.0, "y": 0.0}
	var st: Dictionary = world.weather as Dictionary
	var mul: float = maxf(0.0, _num(world, "windMul", 1.0))
	return {"x": float(st.get("windX", 0.0)) * mul, "y": float(st.get("windY", 0.0)) * mul}


static func wet_after_ticks(world: Variant) -> int:
	return int(climate(world).get("wetAfterTicks", CLIMATE_DEFAULTS["wetAfterTicks"]))


static func dry_after_ticks(world: Variant) -> int:
	return int(climate(world).get("dryAfterTicks", CLIMATE_DEFAULTS["dryAfterTicks"]))


static func dry_by_fire_ticks(world: Variant) -> int:
	return int(climate(world).get("dryByFireTicks", CLIMATE_DEFAULTS["dryByFireTicks"]))


# The world column's sentence: one line per kind, nothing under clear. No digits, and no
# forecast -- docs/16: you read the sky. Wind gets no sentence; you read it off the plume.
static func hud_clause(world: Variant) -> String:
	match kind(world):
		"rain":
			return "It's raining."
		"storm":
			return "A storm is over the district."
		"cold_snap":
			return "It's bitterly cold."
		"snow":
			return "It's snowing."
		"heat_wave":
			return "The heat is brutal."
	return ""
