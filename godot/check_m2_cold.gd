extends SceneTree
# The cold snap's pantry, and the snow's (docs/adr/0016, docs/23's "the sky has kinds" piece):
# the spine already ships cold_snap.json and snow.json (tempShift -1, zombieMoveMul 0.7 / 0.9,
# spoilageMul 0.5, scentHalfLifeMul 0.7 / 0.6, snow's coverPerTick), the climate's meltPerTick,
# snowCoverMoveMul 0.8 and snowCoverThreshold 0.5, the cover ramp in SimWeather._tick_cover, and
# the slowing of the living and the dead -- godot:m2:weather's own MOVE and SHIFT lanes already
# hold those down. This gate is the one reader the spine left open (the pantry's spoilage rate,
# shared verbatim with the heat slice) and the measurements docs/16 promises for the cold half of
# the ladder: the deep-night clock reached at once rather than after EXPOSURE_TICKS, the hard
# interrupt that drops a running job, the cover's climb and melt, and the scent between rain and
# clear.
#
# Every assertion carries a true negative, usually the same world under a clear sky.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimWeather = preload("res://sim/modules/weather.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const Clock = preload("res://sim/time/clock.gd")
const Hud = preload("res://ui/hud.gd")

const SEED: int = 20260805
const FAR: int = 1 << 40

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _day_cold() and ok
	ok = _night_deep() and ok
	ok = _slow_dead() and ok
	ok = _slow_living() and ok
	ok = _cover() and ok
	ok = _pantry() and ok
	ok = _scent() and ok
	ok = _hud() and ok
	if ok:
		print("M2_COLD_OK the cold snap's pantry, and the snow's: a bare body reads one band colder under either, indoors too, and a fire cancels it; the deep-night band arrives at once under a cold snap where clear needs the exposure clock, and a running job is dropped when it does; a shambler seeks slower under each and covers less ground for it; settled snow slows the living at its threshold and a restore re-applies it; cover climbs while it snows, caps at one, and melts under clear and under cold alike; the pantry keeps at half the rate; scent sits between rain and clear; and the HUD names both skies")
		quit(0)
	else:
		push_error("M2_COLD_FAIL")
		quit(1)


# --- fixture (copied from check_m2_weather.gd) --------------------------------------------

func _world(seed_val: int = SEED) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


func _force(w: Variant, k: String) -> void:
	SimWeather.set_kind(w, k, FAR)


func _tile_where(w: Variant, indoors: bool) -> Vector2i:
	if w.tilemap == null:
		return Vector2i(-1, -1)
	for y in 64:
		for x in 64:
			if SimTileMap.is_indoors(w.tilemap, x, y) == indoors:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _place(w: Variant, ent: int, tile: Vector2i) -> void:
	w.components.set_component(ent, "position", {"x": float(tile.x) + 0.5, "y": float(tile.y) + 0.5})


func _bare_body(w: Variant, ent: int) -> bool:
	for fire in w.components.query(["campfire"]):
		SimNeeds.set_lit(w, int(fire), false)
	for item in SimInventory.equipped_items(w, ent):
		var base: Variant = w.components.get_component(item, "itemBase")
		if base is Dictionary and String((base as Dictionary).get("baseId", "")) == "item.wrap.cloth":
			SimInventory.unequip_item(w, item)
	return not SimNeeds.wearing_wrap(w, ent)


func _band(w: Variant, ent: int) -> String:
	return String(SimNeeds.of(w, ent).get("temperature", ""))


# The first NPC survivor -- never the player, never a recruit, never a corpse -- the shape every
# MOVE-style lane in check_m2_weather.gd uses.
func _npc(w: Variant) -> int:
	for ent in w.components.query(["needs", "velocity"]):
		if int(ent) != int(w.player) and not w.components.has_component(int(ent), "recruit") and not w.components.has_component(int(ent), "corpse"):
			return int(ent)
	return -1


# --- lanes --------------------------------------------------------------------------------


# A bare body reads one band colder by day under either a cold snap or snow, indoors too, and a
# lit fire cancels it -- against the true negative of a clear sky reading comfortable everywhere.
func _day_cold() -> bool:
	var out: Vector2i = _tile_where(_world(), false)
	var inside: Vector2i = _tile_where(_world(), true)
	if out.x < 0 or inside.x < 0:
		push_error("DAY: no outdoor or no indoor tile")
		return false
	var got: Dictionary = {}
	var moods: Dictionary = {}
	for k in ["clear", "cold_snap", "snow"]:
		for where in ["out", "in"]:
			var w: Variant = _world()
			var e: int = int(w.player)
			_bare_body(w, e)
			w.tick = Clock.tick_on_day(1, 0.35)
			_force(w, k)
			for _i in 3:
				_place(w, e, out if where == "out" else inside)
				w.step()
			got[k + "/" + where] = _band(w, e)
			moods[k + "/" + where] = float(w.modifiers.resolve("mood", e))
	var want: Dictionary = {
		"clear/out": "comfortable", "clear/in": "comfortable",
		"cold_snap/out": "a_little_cold", "cold_snap/in": "a_little_cold",
		"snow/out": "a_little_cold", "snow/in": "a_little_cold",
	}
	for k in want.keys():
		if String(got.get(k, "")) != String(want[k]):
			push_error("DAY: %s reads %s, wanted %s (all: %s)" % [k, str(got.get(k)), str(want[k]), str(got)])
			return false
	if float(moods["cold_snap/out"]) >= float(moods["clear/out"]) or float(moods["snow/out"]) >= float(moods["clear/out"]):
		push_error("DAY: mood under cold %.2f / snow %.2f is no lower than clear %.2f" % [float(moods["cold_snap/out"]), float(moods["snow/out"]), float(moods["clear/out"])])
		return false
	# A lit fire cancels the shift for both.
	var fires: Dictionary = {}
	for k in ["cold_snap", "snow"]:
		var w: Variant = _world()
		var e: int = int(w.player)
		_bare_body(w, e)
		w.tick = Clock.tick_on_day(1, 0.35)
		_force(w, k)
		var fs: Array = w.components.query(["campfire"])
		if fs.is_empty():
			push_error("DAY: no campfire")
			return false
		SimNeeds.set_lit(w, int(fs[0]), true)
		var fp: Dictionary = w.components.get_component(int(fs[0]), "position") as Dictionary
		for _i in 3:
			w.components.set_component(e, "position", {"x": float(fp["x"]) + 1.0, "y": float(fp["y"])})
			w.step()
		fires[k] = _band(w, e)
	if String(fires["cold_snap"]) != "comfortable" or String(fires["snow"]) != "comfortable":
		push_error("DAY: by a lit fire cold snap reads %s, snow reads %s, wanted comfortable" % [str(fires["cold_snap"]), str(fires["snow"])])
		return false
	print("DAY OK cold snap and snow both read a_little_cold, outdoors and in (mood %.1f / %.1f vs clear %.1f), and a lit fire cancels both" % [float(moods["cold_snap/out"]), float(moods["snow/out"]), float(moods["clear/out"])])
	return true


# A night outdoors under a cold snap reads extremely_cold at once -- the shift landing on
# very_cold -- where the same night under a clear sky needs EXPOSURE_TICKS to deepen. The hard
# interrupt that band drives then drops a running job, and does not under clear's softer band.
func _night_deep() -> bool:
	var out: Vector2i = _tile_where(_world(), false)
	if out.x < 0:
		push_error("NIGHT: no outdoor tile")
		return false

	var cold_w: Variant = _world()
	var ce: int = int(cold_w.player)
	_bare_body(cold_w, ce)
	cold_w.tick = Clock.tick_on_day(2, 0.8)
	_force(cold_w, "cold_snap")
	var cold_reached: int = -1
	for i in 5:
		_place(cold_w, ce, out)
		cold_w.step()
		if _band(cold_w, ce) == "extremely_cold":
			cold_reached = i
			break
	if cold_reached != 0:
		push_error("NIGHT: a cold snap took %d ticks to read extremely_cold, wanted the first one" % cold_reached)
		return false

	var clear_w: Variant = _world()
	var de: int = int(clear_w.player)
	_bare_body(clear_w, de)
	clear_w.tick = Clock.tick_on_day(2, 0.8)
	var clear_reached: int = -1
	for i in SimNeeds.EXPOSURE_TICKS + 5:
		_place(clear_w, de, out)
		clear_w.step()
		if _band(clear_w, de) == "extremely_cold":
			clear_reached = i
			break
	if clear_reached < SimNeeds.EXPOSURE_TICKS - 2 or clear_reached > SimNeeds.EXPOSURE_TICKS + 2:
		push_error("NIGHT: a clear night took %d ticks to read extremely_cold, wanted ~%d (EXPOSURE_TICKS)" % [clear_reached, SimNeeds.EXPOSURE_TICKS])
		return false

	# The hard interrupt: a Patient job (ticksLeft > 0, its match arm a no-op) survives a soft
	# band and is dropped the tick the band goes hard. "ai" runs before "needs" in the phase
	# order (system_registry.gd), so a band this tick's needs phase sets is what jobs.ai reads
	# on the *next* tick -- two steps, not one, to see the interrupt land.
	var interrupted: Variant = _world()
	var ie: int = _npc(interrupted)
	if ie < 0:
		push_error("NIGHT: no NPC to interrupt")
		return false
	_bare_body(interrupted, ie)
	var n: Dictionary = SimNeeds.of(interrupted, ie)
	for pk in SimNeeds.POOLS:
		n[pk] = 100.0
	n["hygiene"] = "clean"
	interrupted.tick = Clock.tick_on_day(2, 0.8)
	_force(interrupted, "cold_snap")
	_place(interrupted, ie, out)
	interrupted.components.set_component(ie, "job", {"kind": "Patient", "target": ie, "ticksLeft": 500, "path": [], "pathGen": -1})
	interrupted.step()
	if _band(interrupted, ie) != "extremely_cold":
		push_error("NIGHT: the interrupt world reads %s after one tick, not extremely_cold -- this lane has nothing to judge" % _band(interrupted, ie))
		return false
	_place(interrupted, ie, out)
	interrupted.step()
	var job_after: Variant = interrupted.components.get_component(ie, "job")
	var still_patient: bool = job_after is Dictionary and String((job_after as Dictionary).get("kind", "")) == "Patient"
	if still_patient:
		push_error("NIGHT: a Patient job survived the tick a cold snap read extremely_cold: %s" % str(job_after))
		return false

	var held: Variant = _world()
	var he: int = _npc(held)
	if he < 0:
		push_error("NIGHT: no NPC to hold a job under clear")
		return false
	_bare_body(held, he)
	var n2: Dictionary = SimNeeds.of(held, he)
	for pk in SimNeeds.POOLS:
		n2[pk] = 100.0
	n2["hygiene"] = "clean"
	held.tick = Clock.tick_on_day(2, 0.8)
	_place(held, he, out)
	held.components.set_component(he, "job", {"kind": "Patient", "target": he, "ticksLeft": 500, "path": [], "pathGen": -1})
	held.step()
	if _band(held, he) != "very_cold":
		push_error("NIGHT: the clear-sky interrupt world reads %s after one tick, not very_cold -- this lane has nothing to judge" % _band(held, he))
		return false
	_place(held, he, out)
	held.step()
	var job_held: Variant = held.components.get_component(he, "job")
	if not (job_held is Dictionary) or String((job_held as Dictionary).get("kind", "")) != "Patient":
		push_error("NIGHT: a Patient job was dropped under clear's very_cold (soft), where nothing should interrupt it: %s" % str(job_held))
		return false

	print("NIGHT OK a cold snap reads extremely_cold on the first tick outdoors at night; clear takes %d ticks (EXPOSURE_TICKS %d); a running job is dropped the tick the cold snap goes hard and held the same tick under clear's very_cold" % [clear_reached, SimNeeds.EXPOSURE_TICKS])
	return true


# The dead: the one speed accessor reads x0.7 under a cold snap and x0.9 under snow (against
# clear's x1), and a shambler actually stepped for a hundred ticks on an open stretch covers
# proportionally less ground for it -- the effect, not the accessor alone.
func _slow_dead() -> bool:
	var muls: Dictionary = {}
	for k in ["clear", "cold_snap", "snow"]:
		var w: Variant = _world()
		_force(w, k)
		var zs: Array = w.components.query(["shambler"])
		if zs.is_empty():
			push_error("DEAD: no shambler")
			return false
		var sd: Dictionary = w.components.get_component(int(zs[0]), "shambler") as Dictionary
		muls[k] = SimShambler._speed_of(w, int(zs[0]), sd, "seekSpeed") / float(sd["seekSpeed"])
	var cold_mul: float = float(SimWeather.DEFAULTS["cold_snap"]["zombieMoveMul"])
	var snow_mul: float = float(SimWeather.DEFAULTS["snow"]["zombieMoveMul"])
	if absf(float(muls["clear"]) - 1.0) > 0.000001 or absf(float(muls["cold_snap"]) - cold_mul) > 0.000001 or absf(float(muls["snow"]) - snow_mul) > 0.000001:
		push_error("DEAD: seekSpeed multiplies x%.3f clear / x%.3f cold / x%.3f snow, wanted 1 / %.2f / %.2f" % [float(muls["clear"]), float(muls["cold_snap"]), float(muls["snow"]), cold_mul, snow_mul])
		return false

	# The effect: on an open stretch far enough from any wall that a hundred ticks cannot reach
	# its edge, hand a shambler the exact velocity `_speed_of` resolves and let the world's own
	# `_integrate_movement` (the same function every body's position moves through, and the one
	# `velocity` uses dx/dy rather than x/y for -- CLAUDE.md's trap) carry it. Straight ahead
	# rather than through `shambler.think`'s Wander/Seek state machine: this map's ambient
	# noise and scent are non-zero far from the annex (measured driving a throwaway probe), so a
	# free-roaming shambler hears something and gives chase at a different tick in each world,
	# which is a state-machine divergence, not the multiplier this lane is about.
	var spot: Vector2i = _open_stretch(_world())
	if spot.x < 0:
		push_error("DEAD: no fifteen-tile-open stretch to walk")
		return false
	var start: Vector2 = Vector2(float(spot.x) + 0.5, float(spot.y) + 0.5)
	var dist: Dictionary = {}
	for k in ["clear", "cold_snap", "snow"]:
		var w: Variant = _world()
		_force(w, k)
		var z: int = int((w.components.query(["shambler"]) as Array)[0])
		w.components.set_component(z, "position", {"x": start.x, "y": start.y})
		var sd2: Dictionary = w.components.get_component(z, "shambler") as Dictionary
		var speed: float = SimShambler._speed_of(w, z, sd2, "seekSpeed")
		w.components.set_component(z, "velocity", {"dx": speed, "dy": 0.0})
		for _i in 100:
			w.call("_integrate_movement", w)
		var p: Dictionary = w.components.get_component(z, "position") as Dictionary
		dist[k] = absf(float(p["x"]) - start.x)
	if float(dist["clear"]) <= 0.0:
		push_error("DEAD: a shambler sent east covered no ground at all under clear, so there is nothing to compare")
		return false
	if float(dist["cold_snap"]) >= float(dist["clear"]) or float(dist["snow"]) >= float(dist["clear"]) or float(dist["cold_snap"]) >= float(dist["snow"]):
		push_error("DEAD: after a hundred ticks a shambler covered %.4f m clear, %.4f cold, %.4f snow -- wanted cold < snow < clear" % [float(dist["clear"]), float(dist["snow"]), float(dist["cold_snap"])])
		return false
	if absf(float(dist["cold_snap"]) / float(dist["clear"]) - cold_mul) > 0.000001 or absf(float(dist["snow"]) / float(dist["clear"]) - snow_mul) > 0.000001:
		push_error("DEAD: displacement ratios read x%.3f cold / x%.3f snow, wanted x%.2f / x%.2f" % [float(dist["cold_snap"]) / float(dist["clear"]), float(dist["snow"]) / float(dist["clear"]), cold_mul, snow_mul])
		return false
	print("DEAD OK seekSpeed multiplies x1 clear, x%.2f cold, x%.2f snow, and a shambler sent east for a hundred ticks with the resolved speed covers %.3f m clear against %.3f cold / %.3f snow" % [cold_mul, snow_mul, float(dist["clear"]), float(dist["cold_snap"]), float(dist["snow"])])
	return true


# A block of open, non-solid tiles wide enough that a hundred ticks of wandering cannot reach its
# edge, so the movement measured is never a wall's.
func _open_stretch(w: Variant) -> Vector2i:
	if w.tilemap == null:
		return Vector2i(-1, -1)
	for y in range(8, 56):
		for x in range(8, 56):
			var ok: bool = true
			for oy in range(-7, 8):
				for ox in range(-7, 8):
					if SimTileMap.is_solid(w.tilemap, x + ox, y + oy):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# The living: settled snow (cover past its threshold) slows the player and an NPC's walk alike,
# holds nothing below the threshold, holds under a clear sky once the snow has stopped falling,
# and a restore re-applies it a tick later -- the same shape the spine's own save round-trip
# proves for the sky, measured here for the cover specifically.
func _slow_living() -> bool:
	var cover_mul: float = float(SimWeather.CLIMATE_DEFAULTS["snowCoverMoveMul"])
	var threshold: float = float(SimWeather.CLIMATE_DEFAULTS["snowCoverThreshold"])
	var settled: Variant = _world()
	(settled.weather as Dictionary)["snowCover"] = 1.0
	settled.step()
	var npc: int = _npc(settled)
	if npc < 0:
		push_error("LIVING: no NPC")
		return false
	var target: Vector2i = _tile_where(settled, false)
	_place(settled, npc, target)
	var job: Dictionary = {"kind": "Haul", "ticksLeft": 0, "path": [{"x": target.x + 20, "y": target.y}], "pathGen": int(settled.mapGeneration)}
	SimJobs._walk(settled, npc, job, Vector2i(target.x + 20, target.y))
	var v: Dictionary = settled.components.get_component(npc, "velocity") as Dictionary
	var npc_speed: float = sqrt(float(v["dx"]) * float(v["dx"]) + float(v["dy"]) * float(v["dy"]))
	var clear: Variant = _world()
	clear.step()
	var player_clear: float = float(clear.modifiers.resolve("move_speed", int(clear.player)))
	var player_settled: float = float(settled.modifiers.resolve("move_speed", int(settled.player)))
	if absf(player_clear - 1.0) > 0.000001 or absf(player_settled / player_clear - cover_mul) > 0.000001:
		push_error("LIVING: move_speed resolves %.3f clear, %.3f at cover 1.0" % [player_clear, player_settled])
		return false
	var npc_clear: int = _npc(clear)
	if npc_clear < 0:
		push_error("LIVING: no NPC under clear")
		return false
	var target2: Vector2i = _tile_where(clear, false)
	_place(clear, npc_clear, target2)
	var job2: Dictionary = {"kind": "Haul", "ticksLeft": 0, "path": [{"x": target2.x + 20, "y": target2.y}], "pathGen": int(clear.mapGeneration)}
	SimJobs._walk(clear, npc_clear, job2, Vector2i(target2.x + 20, target2.y))
	var v2: Dictionary = clear.components.get_component(npc_clear, "velocity") as Dictionary
	var npc_clear_speed: float = sqrt(float(v2["dx"]) * float(v2["dx"]) + float(v2["dy"]) * float(v2["dy"]))
	if npc_clear_speed <= 0.0 or absf(npc_speed / npc_clear_speed - cover_mul) > 0.000001:
		push_error("LIVING: an NPC walks %.3f a tick clear and %.3f at cover 1.0, wanted x%.2f" % [npc_clear_speed, npc_speed, cover_mul])
		return false

	# Just below the threshold: no slowing at all.
	var below: Variant = _world()
	(below.weather as Dictionary)["snowCover"] = threshold - 0.01
	below.step()
	if absf(float(below.modifiers.resolve("move_speed", int(below.player))) - 1.0) > 0.000001:
		push_error("LIVING: cover %.3f (just below the threshold %.3f) resolves move_speed %.3f, wanted 1.0" % [threshold - 0.01, threshold, float(below.modifiers.resolve("move_speed", int(below.player)))])
		return false

	# The cover at 1.0 under a clear sky (the snow that has stopped) still slows.
	var stopped: Variant = _world()
	_force(stopped, "clear")
	(stopped.weather as Dictionary)["snowCover"] = 1.0
	stopped.step()
	if absf(float(stopped.modifiers.resolve("move_speed", int(stopped.player))) - cover_mul) > 0.000001:
		push_error("LIVING: cover 1.0 under a clear sky resolves move_speed %.3f, wanted x%.2f" % [float(stopped.modifiers.resolve("move_speed", int(stopped.player))), cover_mul])
		return false

	# A restore keeps the cover and re-applies the modifier a tick later -- the round-trip the
	# spine already proves for the sky, pinned here for the cover specifically.
	var before: Variant = _world()
	(before.weather as Dictionary)["snowCover"] = 1.0
	var snap: Dictionary = before.snapshot()
	var after: Variant = _world()
	after.restore(snap)
	if absf(SimWeather.snow_cover(after) - 1.0) > 0.000001:
		push_error("LIVING: a restore lost the snow cover: %.3f" % SimWeather.snow_cover(after))
		return false
	var mid: float = float(after.modifiers.resolve("move_speed", int(after.player)))
	after.step()
	var post: float = float(after.modifiers.resolve("move_speed", int(after.player)))
	if absf(post - cover_mul) > 0.000001:
		push_error("LIVING: a tick after restore move_speed resolves %.3f (was %.3f right after restore), wanted x%.2f" % [post, mid, cover_mul])
		return false
	print("LIVING OK cover 1.0 resolves move_speed x%.3f for the player and x%.3f for an NPC's walk; cover just below %.2f holds nothing; cover 1.0 under a clear sky still slows; a restore keeps the cover and re-applies it a tick later" % [player_settled, npc_speed / npc_clear_speed, threshold])
	return true


# The cover climbs while it snows, stops at 1.0, and melts at meltPerTick under clear and under a
# cold snap alike (the shipped rule: only snow's own coverPerTick lays cover, so any kind without
# one melts it), and never below zero.
func _cover() -> bool:
	var w: Variant = _world()
	_force(w, "snow")
	for _i in 1000:
		w.step()
	var laid: float = SimWeather.snow_cover(w)
	var lay_rate: float = float(SimWeather.spec_of(w, "snow").get("coverPerTick", 0.0))
	if absf(laid - lay_rate * 1000.0) > 0.000001:
		push_error("COVER: after 1000 ticks of snow cover reads %.8f, wanted %.8f (%.10f a tick)" % [laid, lay_rate * 1000.0, lay_rate])
		return false
	(w.weather as Dictionary)["snowCover"] = 1.0
	w.step()
	if SimWeather.snow_cover(w) > 1.0:
		push_error("COVER: cover exceeded 1.0: %.6f" % SimWeather.snow_cover(w))
		return false

	var melt_rate: float = float(SimWeather.climate(w).get("meltPerTick", 0.0))
	var clear_melt: Variant = _world()
	(clear_melt.weather as Dictionary)["snowCover"] = 1.0
	_force(clear_melt, "clear")
	clear_melt.step()
	if absf(SimWeather.snow_cover(clear_melt) - (1.0 - melt_rate)) > 0.000001:
		push_error("COVER: one clear tick from cover 1.0 reads %.8f, wanted %.8f" % [SimWeather.snow_cover(clear_melt), 1.0 - melt_rate])
		return false

	var cold_melt: Variant = _world()
	(cold_melt.weather as Dictionary)["snowCover"] = 1.0
	_force(cold_melt, "cold_snap")
	cold_melt.step()
	if absf(SimWeather.snow_cover(cold_melt) - (1.0 - melt_rate)) > 0.000001:
		push_error("COVER: one cold-snap tick from cover 1.0 reads %.8f, wanted %.8f (the shipped rule: only snow lays cover)" % [SimWeather.snow_cover(cold_melt), 1.0 - melt_rate])
		return false

	var floor_w: Variant = _world()
	(floor_w.weather as Dictionary)["snowCover"] = 0.0000001
	_force(floor_w, "clear")
	for _j in 5:
		floor_w.step()
	if SimWeather.snow_cover(floor_w) < 0.0:
		push_error("COVER: cover fell below zero: %.8f" % SimWeather.snow_cover(floor_w))
		return false
	print("COVER OK 1000 ticks of snow lay %.8f (%.10f a tick), capped at 1.0, one tick melts %.8f under clear and under a cold snap alike, never below zero" % [laid, lay_rate, melt_rate])
	return true


# A perishable ages at half the clear rate under a cold snap and under snow alike; clear is
# exactly the colony's pantry rate.
func _pantry() -> bool:
	var aged: Dictionary = {}
	for k in ["clear", "cold_snap", "snow"]:
		var w: Variant = _world()
		_force(w, k)
		var item: int = SimItems.spawn_item(w, "item.food.cooked", {})
		if not w.components.has_component(item, "spoilage"):
			push_error("PANTRY: item.food.cooked spawned with no spoilage component")
			return false
		for _i in 1000:
			w.step()
		var sp: Dictionary = w.components.get_component(item, "spoilage") as Dictionary
		aged[k] = float(sp["aged"])
	var rate: float = SimNeeds.pantry_rate(_world())
	if absf(float(aged["clear"]) - rate * 1000.0) > 0.001:
		push_error("PANTRY: clear ages %.4f in 1000 ticks, wanted the pantry rate %.4f x 1000" % [float(aged["clear"]), rate])
		return false
	var cold_want: float = rate * 1000.0 * float(SimWeather.DEFAULTS["cold_snap"]["spoilageMul"])
	var snow_want: float = rate * 1000.0 * float(SimWeather.DEFAULTS["snow"]["spoilageMul"])
	if absf(float(aged["cold_snap"]) - cold_want) > 0.001 or absf(float(aged["snow"]) - snow_want) > 0.001:
		push_error("PANTRY: 1000 ticks age %.4f cold / %.4f snow, wanted %.4f / %.4f (half the clear rate %.4f)" % [float(aged["cold_snap"]), float(aged["snow"]), cold_want, snow_want, float(aged["clear"])])
		return false
	print("PANTRY OK 1000 ticks age %.4f clear (the pantry rate), %.4f cold snap and %.4f snow -- half the clear rate for both" % [float(aged["clear"]), float(aged["cold_snap"]), float(aged["snow"])])
	return true


# Scent sits between rain's heavier wash and clear's none, and clear equals no weather at all.
func _scent() -> bool:
	var cold: Variant = _world()
	var rain: Variant = _world()
	var clear: Variant = _world()
	var none: Variant = _world()
	_force(cold, "cold_snap")
	_force(rain, "rain")
	(none.weather as Dictionary).clear()
	var at: Vector2i = _tile_where(cold, false)
	var x: float = float(at.x) + 0.5
	var y: float = float(at.y) + 0.5
	for w in [cold, rain, clear, none]:
		w.tick = Clock.tick_on_day(1, 0.3)
		w.field.add_scent(x, y, 500.0)
	for _i in 20:
		cold.step()
		rain.step()
		clear.step()
		none.step()
	var s_cold: float = float(cold.field.scent_at(x, y))
	var s_rain: float = float(rain.field.scent_at(x, y))
	var s_clear: float = float(clear.field.scent_at(x, y))
	var s_none: float = float(none.field.scent_at(x, y))
	if not (s_cold < s_clear and s_cold > s_rain):
		push_error("SCENT: after twenty diffusions cold snap leaves %.4f, rain %.4f, clear %.4f -- wanted rain < cold < clear" % [s_cold, s_rain, s_clear])
		return false
	if absf(s_clear - s_none) > 0.000001:
		push_error("SCENT: a clear sky costs the field something: %.6f with weather, %.6f with none" % [s_clear, s_none])
		return false
	print("SCENT OK after twenty diffusions a cold snap leaves %.4f, between rain's %.4f and clear's %.4f (a clear sky equals no weather at all)" % [s_cold, s_rain, s_clear])
	return true


func _hud() -> bool:
	var w: Variant = _world()
	w.step()
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, w.player, "")
	var right_clear: Array = (hud.get("_right") as Array).duplicate()
	if right_clear.has("It's bitterly cold.") or right_clear.has("It's snowing."):
		push_error("HUD: a clear sky already carries a cold-weather line: %s" % str(right_clear))
		hud.queue_free()
		return false
	var lines: Dictionary = {}
	for k in ["cold_snap", "snow"]:
		_force(w, k)
		hud.call("refresh", w, w.player, "")
		var right: Array = (hud.get("_right") as Array).duplicate()
		var line: String = SimWeather.hud_clause(w)
		if line.is_empty() or not right.has(line):
			push_error("HUD: the world column does not carry '%s' under %s: %s" % [line, k, str(right)])
			hud.queue_free()
			return false
		for ch in line:
			if String(ch).is_valid_int():
				push_error("HUD: the %s line carries a digit: '%s'" % [k, line])
				hud.queue_free()
				return false
		lines[k] = line
	hud.queue_free()
	if String(lines.get("cold_snap", "")) != "It's bitterly cold." or String(lines.get("snow", "")) != "It's snowing.":
		push_error("HUD: cold snap says '%s', snow says '%s'" % [str(lines.get("cold_snap")), str(lines.get("snow"))])
		return false
	print("HUD OK 'It's bitterly cold.' under a cold snap, 'It's snowing.' under snow, neither under clear, no digits")
	return true
