extends SceneTree
# The storm's two halves (docs/16's storm table, ADR 0016, the slice gate the spine named).
# A storm is the highest-variance sky in the game and it is the only kind that moves all three
# of these at once:
#
#  1. **Noise masking, the good half.** `noiseHalfLifeMul` 0.4 shortens the attention field's
#     noise half-life, so a gunshot, a channel or a horde is heard for four-tenths as long. The
#     field is handed a factor by `SimBoot._decay` and never learns what weather is, exactly as
#     the scent half-life is handed to `diffuse_scent`.
#  2. **Lightning, the bad half.** A strike every `intervalTicks` on an open outdoor tile,
#     published as a bare `noise.emitted` at magnitude 60 -- a district-wide bloom nobody made
#     and nobody controls -- and a `weather.lightning` for anything that wants to draw it. No
#     sound and no sim light: the owner chose noise plus a screen flash, and 60 is deliberately
#     none of `sfx.gd`'s one-shot magnitudes (180 gun, 120 shout, 4 bow).
#  3. **Outdoor work refused.** `outdoorWork: false` stops `_pick` handing out a job whose tile
#     is outdoors and drops a running one before `_advance_job`. Guard is exempt -- standing the
#     gate through a storm is watch, not work, and it is the one thing a colony most needs done
#     on the night it cannot hear anything coming. Rest is exempt, and need-seek never reaches
#     the refusal at all: this is a refusal to work in the rain, not a refusal to live in it.
#
# The dead-socket rule runs through every lane: none of these asserts that an accessor returns
# the right number, each asserts that something downstream *read* it -- the field's own decay,
# the field's own noise under a strike, and the job component on an NPC's own tick. Every
# positive carries its true negative, which is almost always the same world under `clear` or
# under `rain` (wet and loud, but work goes on).

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Clock = preload("res://sim/time/clock.gd")
const Hud = preload("res://ui/hud.gd")

const SEED: int = 20260805
const FAR: int = 1 << 40
# The window the count lane walks. Ten thousand ticks is a little over eight in-game minutes and
# holds four to sixteen strikes at the shipped 600..2400 interval -- wide enough that the lane is
# reading the content and not a coincidence, short enough that three worlds of it is under a
# minute of wall clock.
const WINDOW: int = 10000

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _a_storm_masks_noise_on_the_field() and ok
	ok = _lightning_strikes_outdoors_and_is_heard() and ok
	ok = _a_storm_sends_the_outdoor_work_in() and ok
	ok = _a_storm_wets_a_body_the_way_rain_does() and ok
	ok = _the_hud_names_the_storm() and ok
	if ok:
		print("M2_STORM_OK the storm's two halves: noise masked on the field's own decay, lightning struck outdoors as a noise nobody made, outdoor work refused and a running job dropped, Guard still standing, a wet body and one sentence")
		quit(0)
	else:
		push_error("M2_STORM_FAIL")
		quit(1)


# --- fixture ------------------------------------------------------------------------------

func _world(seed_val: int = SEED) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


# Through the one public path, so the event, the modifier, the wind and the strike clock's reset
# all follow. Writing `world.weather["kind"]` directly would skip every one of them.
func _force(w: Variant, k: String) -> void:
	SimWeather.set_kind(w, k, FAR)


func _tile_where(w: Variant, indoors: bool) -> Vector2i:
	if w.tilemap == null:
		return Vector2i(-1, -1)
	for y in 64:
		for x in 64:
			if SimTileMap.is_solid(w.tilemap, x, y):
				continue
			if SimTileMap.is_indoors(w.tilemap, x, y) == indoors:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _place(w: Variant, ent: int, tile: Vector2i) -> void:
	w.components.set_component(ent, "position", {"x": float(tile.x) + 0.5, "y": float(tile.y) + 0.5})


# An Array and not an int: a handler assigning to a captured primitive mutates its own copy
# (CLAUDE.md's lambda-capture trap), which is exactly how a gate goes red and blames correct code.
func _watch_strikes(w: Variant) -> Array:
	var log: Array = []
	w.events.subscribe({"id": "check.storm.lightning", "type": "weather.lightning", "handler": func(event: Dictionary) -> void:
		log.append({"x": float(event["x"]), "y": float(event["y"]), "tick": int(event["tick"])})
	})
	return log


# Nothing to seek, nothing to sulk about: the only thing deciding this NPC's job is the sky.
func _willing(w: Variant, ent: int, cols: Dictionary) -> void:
	var n: Dictionary = SimNeeds.of(w, ent)
	for pool in SimNeeds.POOLS:
		n[String(pool)] = 100.0
	n["temperature"] = "comfortable"
	n["hygiene"] = "clean"
	n["crisis"] = "none"
	w.components.set_component(ent, "jobPriorities", {"focus": "Custom", "cols": cols})
	w.components.remove(ent, "job")


func _mara(w: Variant) -> int:
	for e in w.components.query(["identity"]):
		var ident: Variant = w.components.get_component(int(e), "identity")
		if ident is Dictionary and String((ident as Dictionary).get("id", "")) == "survivor.unique.mara":
			return int(e)
	return -1


# Every strike in a log landed on a tile that is neither wall nor roof. The rejection loop in
# `_strike` is the only thing that makes this true, and it is cheap enough to assert on every
# bolt every run rather than on a sample.
func _all_outdoors(w: Variant, log: Array) -> bool:
	for rec in log:
		var r: Dictionary = rec as Dictionary
		var tx: int = floori(float(r["x"]))
		var ty: int = floori(float(r["y"]))
		if SimTileMap.is_solid(w.tilemap, tx, ty) or SimTileMap.is_indoors(w.tilemap, tx, ty):
			push_error("LIGHTNING: a bolt landed on (%d, %d), which is solid %s / indoors %s" % [tx, ty, str(SimTileMap.is_solid(w.tilemap, tx, ty)), str(SimTileMap.is_indoors(w.tilemap, tx, ty))])
			return false
	return true


func _job_of(w: Variant, ent: int) -> Dictionary:
	var job: Variant = w.components.get_component(ent, "job")
	return job as Dictionary if job is Dictionary else {}


# --- lanes --------------------------------------------------------------------------------

# The good half. Three worlds off one seed: a storm, a clear sky, and a world whose weather
# record was emptied so no kind is read at all. The same shout at the same tile, forty ticks of
# the same decay -- the storm's field must hold strictly less, and the clear one must be
# indistinguishable from the world with no weather, or the factor is costing a dry sky something.
func _a_storm_masks_noise_on_the_field() -> bool:
	var storm: Variant = _world()
	var clear: Variant = _world()
	var none: Variant = _world()
	_force(storm, "storm")
	(none.weather as Dictionary).clear()
	var at: Vector2i = _tile_where(storm, false)
	if at.x < 0:
		push_error("NOISE: the booted district has no open outdoor tile, so this lane has nothing to judge")
		return false
	var x: float = float(at.x) + 0.5
	var y: float = float(at.y) + 0.5
	for w in [storm, clear, none]:
		w.tick = Clock.tick_on_day(1, 0.3)
		w.field.emit_noise(x, y, 200.0)
	for _i in 40:
		storm.step()
		clear.step()
		none.step()
	var n_storm: float = float(storm.field.noise_at(x, y))
	var n_clear: float = float(clear.field.noise_at(x, y))
	var n_none: float = float(none.field.noise_at(x, y))
	if n_clear <= 0.0:
		push_error("NOISE: the clear field lost all of its noise in forty ticks, so there is nothing to compare")
		return false
	if n_storm >= n_clear:
		push_error("NOISE: a storm left %.4f against a clear %.4f -- it masked nothing" % [n_storm, n_clear])
		return false
	if absf(n_clear - n_none) > 0.000001:
		push_error("NOISE: a clear sky costs the field something: %.6f with weather, %.6f with none" % [n_clear, n_none])
		return false
	if absf(SimWeather.noise_half_life_mul(clear) - 1.0) > 0.000001 or SimWeather.noise_half_life_mul(storm) >= 1.0:
		push_error("NOISE: the multipliers read clear %.3f / storm %.3f" % [SimWeather.noise_half_life_mul(clear), SimWeather.noise_half_life_mul(storm)])
		return false
	# Masked, not deleted: a storm still leaves a field. The scent's first cut was a per-step
	# factor that flattened everything inside a second, and this decay runs every tick rather
	# than every fifth, so the same mistake here would be five times worse.
	if n_storm <= 0.0:
		push_error("NOISE: a storm wiped the noise layer rather than shortening it")
		return false
	print("NOISE OK forty ticks after the same shout a storm leaves %.4f where a clear sky leaves %.4f (half-life x%.2f against x%.2f), and a clear sky equals no weather at all" % [n_storm, n_clear, SimWeather.noise_half_life_mul(storm), SimWeather.noise_half_life_mul(clear)])
	return true


# The bad half, in five parts: a pinned interval strikes where it should and is heard; the
# shipped interval strikes as often as its own arithmetic says; a clear sky never strikes; a
# fixture that never registered the module never strikes; and the whole thing is the seed's.
func _lightning_strikes_outdoors_and_is_heard() -> bool:
	# 1. A pinned interval. The content entry is duplicated onto this world alone, the way the
	#    spine's SEASONS lane pins a weight, so the shipped numbers are untouched.
	var pinned: Variant = _world()
	var storm: Dictionary = (pinned.content["weather/storm.json"] as Dictionary).duplicate(true)
	storm["lightning"] = {"intervalTicks": {"min": 100, "max": 100}, "noise": 240}
	pinned.content["weather/storm.json"] = storm
	var log: Array = _watch_strikes(pinned)
	pinned.step()
	_force(pinned, "storm")
	for _i in 350:
		pinned.step()
	# Three, not one: the shipped 600..2400 interval would have struck no more than once here,
	# so the count itself is the assertion that `intervalTicks` is read from the entry.
	if log.size() < 3:
		push_error("LIGHTNING: a storm pinned to strike every 100 ticks struck %d times in 350" % log.size())
		return false
	# Every bolt, not merely the first: with most of a district open, a rejection loop that had
	# been deleted outright would still put its first strike outdoors nine times in ten.
	if not _all_outdoors(pinned, log):
		return false
	var first: Dictionary = log[0] as Dictionary
	var tx: int = floori(float(first["x"]))
	var ty: int = floori(float(first["y"]))
	# And it was *heard*: the strike publishes a plain noise.emitted, the kernel handler blooms
	# it onto the field at drain, and the field is warm at the strike on the following tick.
	# This is the socket -- an event nothing reads would pass every assertion above.
	var heard: float = float(pinned.field.noise_at(float(first["x"]), float(first["y"])))
	if heard <= 0.0:
		push_error("LIGHTNING: the field reads %.4f at the strike, so the noise reached nothing" % heard)
		return false
	var struck: int = log.size()

	# 2. The shipped interval, over a long window, counted against its own arithmetic. Two
	#    worlds on one seed and a third on another give the determinism assertion for free.
	var r: Dictionary = ((SimWeather.spec_of(_world(), "storm").get("lightning", {}) as Dictionary).get("intervalTicks", {})) as Dictionary
	var lo: int = int(floor(float(WINDOW) / float(r.get("max", 1))))
	var hi: int = int(floor(float(WINDOW) / float(r.get("min", 1))))
	var runs: Array = []
	var worlds: Array = []
	for sd in [SEED, SEED, 404]:
		var w: Variant = _world(int(sd))
		var l: Array = _watch_strikes(w)
		w.step()
		_force(w, "storm")
		for _j in WINDOW:
			w.step()
		runs.append(l)
		worlds.append(w)
	for i in runs.size():
		if not _all_outdoors(worlds[i], runs[i] as Array):
			return false
	var counted: int = (runs[0] as Array).size()
	if counted < lo or counted > hi:
		push_error("LIGHTNING: %d strikes in %d ticks, outside the %d..%d the %s interval allows" % [counted, WINDOW, lo, hi, str(r)])
		return false
	if str(runs[0]) != str(runs[1]):
		push_error("LIGHTNING: one seed drew two different storms:\n %s\n %s" % [str(runs[0]), str(runs[1])])
		return false
	if str(runs[0]) == str(runs[2]):
		push_error("LIGHTNING: seed 404 drew seed %d's strikes exactly, so the draw is not on the stream" % SEED)
		return false
	if (runs[2] as Array).is_empty():
		push_error("LIGHTNING: seed 404's storm struck nothing at all in %d ticks" % WINDOW)
		return false

	# 3. A clear sky, twice the window, no strike. clear.json declares no `lightning`, so this
	#    is the true negative for the whole mechanism and not merely for its interval.
	var calm: Variant = _world()
	var calm_log: Array = _watch_strikes(calm)
	_force(calm, "clear")
	for _k in WINDOW * 2:
		calm.step()
	if not calm_log.is_empty():
		push_error("LIGHTNING: a clear sky struck %d times in %d ticks" % [calm_log.size(), WINDOW * 2])
		return false
	if int((calm.weather as Dictionary).get("nextLightningTick", -1)) != 0:
		push_error("LIGHTNING: a clear sky carries a strike clock of %d" % int((calm.weather as Dictionary).get("nextLightningTick", -1)))
		return false

	# 4. A fixture that never registered the module: forced to a storm by hand, stepped, and
	#    silent -- the strike is the module's tick and not something the world does by itself.
	var bare: Variant = World.new({
		"seed": SEED, "tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	})
	var bare_log: Array = _watch_strikes(bare)
	SimWeather.set_kind(bare, "storm", FAR)
	for _m in 2000:
		bare.step()
	if not bare_log.is_empty():
		push_error("LIGHTNING: a fixture that never registered the module struck %d times" % bare_log.size())
		return false
	print("LIGHTNING OK a pinned 100-tick storm struck %d times in 350, the first on open outdoor (%d, %d) and the field reads %.2f there; the shipped %s interval struck %d times in %d ticks (inside %d..%d), the same seed the same strikes and 404 %d of its own; a clear sky struck nothing in %d and a module-less fixture nothing in 2000" % [struck, tx, ty, heard, str(r), counted, WINDOW, lo, hi, (runs[2] as Array).size(), WINDOW * 2])
	return true


# Outdoor work refused, at both sites and with Guard exempt. Driven through `SimJobs._tick_one`
# -- the NPC's own tick -- rather than through the helper, because a refusal that the picker
# never consults is the dead socket this project has now paid for nine times.
func _a_storm_sends_the_outdoor_work_in() -> bool:
	var probe: Variant = _world()
	var out: Vector2i = _tile_where(probe, false)
	var inside: Vector2i = _tile_where(probe, true)
	if out.x < 0 or inside.x < 0:
		push_error("WORK: the booted district has no open outdoor tile or no indoor one, so this lane has nothing to judge")
		return false

	# 1. A haul whose item lies outdoors, one tile from the hauler so it is the nearest thing
	#    there is. Refused under a storm; taken under rain, which is just as wet and just as loud.
	var taken: Dictionary = {}
	for k in ["storm", "rain"]:
		var w: Variant = _world()
		var ent: int = _mara(w)
		if ent < 0:
			push_error("WORK: no Mara in the booted colony")
			return false
		_force(w, k)
		_willing(w, ent, {"Haul": 1})
		_place(w, ent, out)
		var drop: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged"})
		_place(w, drop, out)
		SimJobs._tick_one(w, ent)
		taken[k] = _job_of(w, ent)
	if not (taken["rain"] as Dictionary).has("kind") or int((taken["rain"] as Dictionary).get("target", -1)) < 0:
		push_error("WORK: rain refused the haul too, so this lane is measuring something other than the storm: %s" % str(taken["rain"]))
		return false
	if not (taken["storm"] as Dictionary).is_empty():
		push_error("WORK: a storm handed out %s anyway" % str(taken["storm"]))
		return false

	# 2. The indoor half of the same job: a storm is a roof problem, not a work problem, so an
	#    item lying indoors is hauled under both skies. Without this the lane above would pass
	#    just as well for a bug that refused every job under a storm.
	var indoor_taken: Dictionary = {}
	for k in ["storm", "rain"]:
		var w2: Variant = _world()
		var ent2: int = _mara(w2)
		_force(w2, k)
		_willing(w2, ent2, {"Haul": 1})
		_place(w2, ent2, inside)
		var drop2: int = SimItems.spawn_item(w2, "item.scrap.metal", {"tier": "scavenged"})
		_place(w2, drop2, inside)
		SimJobs._tick_one(w2, ent2)
		indoor_taken[k] = _job_of(w2, ent2)
	for k in ["storm", "rain"]:
		if (indoor_taken[k] as Dictionary).is_empty():
			push_error("WORK: an indoor haul was refused under %s" % k)
			return false

	# 3. A job already under way. A Construct names its tile outright, so this is the exact
	#    reading of `_job_tile` the drop site takes: outdoors under a storm it is gone within a
	#    tick; outdoors under rain and indoors under a storm it is still there.
	var running: Dictionary = {}
	for spec in [["storm", out], ["rain", out], ["storm", inside]]:
		var w3: Variant = _world()
		var ent3: int = _mara(w3)
		var tile: Vector2i = spec[1]
		_force(w3, String(spec[0]))
		_willing(w3, ent3, {"Construct": 1})
		_place(w3, ent3, tile)
		w3.components.set_component(ent3, "job", {"kind": "Construct", "verb": "window", "tx": tile.x, "ty": tile.y, "ticksLeft": 400, "path": [], "pathGen": -1})
		SimJobs._tick_one(w3, ent3)
		running[str(spec)] = w3.components.has_component(ent3, "job")
	if bool(running[str(["storm", out])]):
		push_error("WORK: a running outdoor job survived a storm")
		return false
	if not bool(running[str(["rain", out])]) or not bool(running[str(["storm", inside])]):
		push_error("WORK: the drop is not the storm's -- rain outdoors kept it %s, a storm indoors kept it %s" % [str(running[str(["rain", out])]), str(running[str(["storm", inside])])])
		return false

	# 4. Guard is watch, not work. The post is the map's gate and it is outdoors; a storm is
	#    exactly the night somebody has to be standing on it.
	var guard_world: Variant = _world()
	var guard: int = _mara(guard_world)
	var post: Vector2i = SimTileMap.gate_a(guard_world.tilemap)
	if post.x < 0:
		push_error("WORK: the booted district has no gate anchor, so the Guard exemption has nothing to judge")
		return false
	if SimTileMap.is_indoors(guard_world.tilemap, post.x, post.y):
		push_error("WORK: the gate post (%d, %d) is indoors, so the Guard exemption proves nothing here" % [post.x, post.y])
		return false
	_force(guard_world, "storm")
	_willing(guard_world, guard, {"Guard": 1})
	SimJobs._tick_one(guard_world, guard)
	if String(_job_of(guard_world, guard).get("kind", "")) != "Guard":
		push_error("WORK: a storm sent the guard off the gate: %s" % str(_job_of(guard_world, guard)))
		return false
	print("WORK OK an outdoor haul at (%d, %d) is refused under a storm and taken in the rain, an indoor one taken under both, a running outdoor Construct dropped within a tick under a storm only, and the guard still on the gate at (%d, %d)" % [out.x, out.y, post.x, post.y])
	return true


# The spine's WET fixture, re-keyed on the storm: `wets` is content and the storm declares it,
# so a body outdoors is soaked on the same climate clock as rain. The negative is the same body
# under a roof, which a storm reaches no more than rain does.
func _a_storm_wets_a_body_the_way_rain_does() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.player)
	var out: Vector2i = _tile_where(w, false)
	var inside: Vector2i = _tile_where(w, true)
	if out.x < 0 or inside.x < 0:
		push_error("WET: the booted district has no open outdoor tile or no indoor one, so this lane has nothing to judge")
		return false
	for fire in w.components.query(["campfire"]):
		SimNeeds.set_lit(w, int(fire), false)
	w.tick = Clock.tick_on_day(1, 0.3)
	_force(w, "storm")
	if not SimWeather.raining(w):
		push_error("WET: a storm does not declare `wets`, so nothing here would get wet")
		return false
	var after: int = SimWeather.wet_after_ticks(w)
	for _i in after - 1:
		_place(w, ent, out)
		w.step()
	if SimNeeds.is_wet(w, ent):
		push_error("WET: wet before %d ticks in a storm" % after)
		return false
	for _j in 2:
		_place(w, ent, out)
		w.step()
	if not SimNeeds.is_wet(w, ent):
		push_error("WET: still dry after %d ticks out in a storm" % (after + 1))
		return false
	var roofed: Variant = _world()
	var e2: int = int(roofed.player)
	roofed.tick = Clock.tick_on_day(1, 0.3)
	_force(roofed, "storm")
	for _k in after + 5:
		_place(roofed, e2, inside)
		roofed.step()
	if SimNeeds.is_wet(roofed, e2):
		push_error("WET: a survivor under a roof got wet in a storm")
		return false
	print("WET OK a body outdoors is soaked after %d ticks of storm and never under a roof" % (after + 1))
	return true


# One sentence, and it is the storm's own: rain has its own line and must not carry this one.
func _the_hud_names_the_storm() -> bool:
	var w: Variant = _world()
	w.step()
	var line: String = "A storm is over the district."
	if SimWeather.hud_clause(_world()) != "":
		push_error("HUD: a clear world's clause is not empty")
		return false
	var hud: Control = Hud.new()
	root.add_child(hud)
	_force(w, "storm")
	hud.call("refresh", w, w.player, "")
	var under_storm: Array = (hud.get("_right") as Array).duplicate()
	_force(w, "rain")
	hud.call("refresh", w, w.player, "")
	var under_rain: Array = (hud.get("_right") as Array).duplicate()
	hud.queue_free()
	if not under_storm.has(line):
		push_error("HUD: the world column does not carry '%s' under a storm: %s" % [line, str(under_storm)])
		return false
	if under_rain.has(line):
		push_error("HUD: the world column carries the storm's sentence in the rain: %s" % str(under_rain))
		return false
	for ch in line:
		if String(ch).is_valid_int():
			push_error("HUD: the storm line carries a digit: '%s'" % line)
			return false
	print("HUD OK '%s' under a storm, not under rain, no digits" % line)
	return true
