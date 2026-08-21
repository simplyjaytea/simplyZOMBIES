extends SceneTree
# Bow/pistol loop: quiet 4 vs loud 180, ammo consume, mag reload.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimStances = preload("res://sim/stances.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _bow_quiet() and ok
	ok = _pistol_loud() and ok
	ok = _a_degraded_firearm_jams_and_a_bow_never_does() and ok
	ok = _clearing_a_jam_takes_longer_than_a_reload() and ok
	ok = _a_sprint_cannot_aim_and_every_other_rung_can() and ok
	if ok:
		print("M2_RANGED_OK bow pistol jam sprint")
		quit(0)
	else:
		push_error("M2_RANGED_FAIL")
		quit(1)

func _world() -> Variant:
	var f: Dictionary = {"seed": 21, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 12.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	return w

func _fire_through(w: Variant, shots: int = 1) -> Array:
	var noises: Array = []
	for s in shots:
		w.commands.push({"type": "fire"})
		for i in 40:
			w.step()
			for e in w.events.drained:
				if String((e as Dictionary).get("type", "")) == "noise.emitted" and int((e as Dictionary).get("source", -1)) == w.player:
					noises.append(float((e as Dictionary).get("magnitude", 0)))
			var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary)["state"]) == SimRanged.FireState.Idle:
				break
	return noises

func _bow_quiet() -> bool:
	var w: Variant = _world()
	var bow: int = SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"})
	SimInventory.equip(w, w.player, bow)
	var arrows: int = SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 6})
	if not SimInventory.stow(w, w.player, arrows):
		w.components.set_component(arrows, "stored", {"container": w.player})
	var rng: Variant = w.rng.stream("shambler")
	SimRoster.spawn_zombie(w, 14.0, 12.0, SimRoster.TYPE_SHAMBLER, rng)
	w.events.drain()
	var noises: Array = _fire_through(w, 1)
	if noises.is_empty() or absf(float(noises[0]) - 4.0) > 0.01:
		push_error("bow noise %s" % str(noises))
		return false
	print("BOW OK noise=%s" % str(noises[0]))
	return true

func _pistol_loud() -> bool:
	var w: Variant = _world()
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	SimInventory.equip(w, w.player, pistol)
	var ammo: int = SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 20})
	SimInventory.stow(w, w.player, ammo)
	var rng: Variant = w.rng.stream("shambler")
	SimRoster.spawn_zombie(w, 14.0, 12.0, SimRoster.TYPE_SHAMBLER, rng)
	w.events.drain()
	var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
	if rw == null or int((rw as Dictionary).get("mag", 0)) != 8:
		push_error("pistol mag %s" % str(rw))
		return false
	var noises: Array = _fire_through(w, 1)
	if noises.is_empty() or absf(float(noises[0]) - 180.0) > 0.01:
		push_error("pistol noise %s" % str(noises))
		return false
	rw = w.components.get_component(w.player, "rangedWeapon")
	if int((rw as Dictionary).get("mag", 0)) != 7:
		push_error("pistol mag after shot %s" % (rw as Dictionary).get("mag", -1))
		return false
	print("PISTOL OK noise=180 mag=%s" % (rw as Dictionary)["mag"])
	return true


# --- jamming (docs/09) -----------------------------------------------------------------------
#
# "Degraded firearms jam, and clearing a jam takes longer than a reload. ... Stagger is the actual
# survival mechanic in a crowd" -- and a jam is the thing that takes it away from you. Condition
# affected damage already; it did not affect whether the weapon worked at all, so a pistol at 10%
# was a slightly weaker pistol rather than one you could not trust.
#
# The chance is not authored. docs/10's condition table has the bands ("49-20%: serious; firearms
# jam regularly"), so SimItems.JAM_CHANCE_BY_BAND is keyed off condition_band -- the same function
# that produces the word the inventory screen shows, which is what stops a weapon the player is
# told is "failing" from being one that never jams.

# Enough trigger pulls that a rate is a rate rather than a coin toss.
const JAM_SHOTS: int = 400


# Equips a pistol at a chosen condition and returns it, with ammo enough that the magazine is
# never the thing that stops the run.
func _worn_pistol(w: Variant, condition: float) -> int:
	var pistol: int = SimItems.spawn_item(w, "item.pistol.service", {"tier": "scavenged"})
	var c: Dictionary = w.components.get_component(pistol, "condition") as Dictionary
	c["current"] = condition
	SimInventory.equip(w, w.player, pistol)
	var ammo: int = SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 20})
	SimInventory.stow(w, w.player, ammo)
	w.events.drain()
	return pistol


# Refills every ammo stack the actor carries, so a long measurement is not silently cut short.
func _top_up_ammo(w: Variant) -> void:
	for item in w.components.query(["stack", "itemBase"]):
		var base: Dictionary = w.components.get_component(int(item), "itemBase") as Dictionary
		if String(base.get("baseId", "")).begins_with("item.ammo."):
			var st: Dictionary = w.components.get_component(int(item), "stack") as Dictionary
			st["count"] = 20


# The jam rate over many trigger pulls, driven through the real state machine rather than by
# calling the roll: this has to be what a player experiences, not what the helper returns.
func _jam_rate(w: Variant, shots: int) -> float:
	var jams: Array = []
	w.events.subscribe({"type": "weapon.jammed", "id": "gate.jam", "handler": func(_e: Dictionary) -> void:
		jams.append(1)
	})
	var pulls: int = 0
	for _s in shots:
		var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
		if not (rw is Dictionary):
			break
		# Top the magazine AND the pouch up by hand so neither is ever the reason a pull does not
		# happen -- this measures jamming, not logistics. Without the pouch half the denominator
		# is a lie: try_begin_fire refuses outright with no ammo, so 400 pushes became 20 real
		# trigger pulls and the measured rate read a fifth of the truth.
		(rw as Dictionary)["mag"] = int((rw as Dictionary).get("magSize", 8))
		_top_up_ammo(w)
		w.commands.push({"type": "fire"})
		pulls += 1
		for _i in 200:
			w.step()
			var live: Variant = w.components.get_component(w.player, "rangedWeapon")
			if live is Dictionary and int((live as Dictionary)["state"]) == SimRanged.FireState.Idle:
				break
	return float(jams.size()) / float(maxi(1, pulls))


func _a_degraded_firearm_jams_and_a_bow_never_does() -> bool:
	# A sound pistol, a failing one, and a bow in the same state a failing pistol is in.
	var sound: Variant = _world()
	_worn_pistol(sound, 1.0)
	var sound_rate: float = _jam_rate(sound, JAM_SHOTS)

	var failing: Variant = _world()
	_worn_pistol(failing, 0.3)
	var failing_rate: float = _jam_rate(failing, JAM_SHOTS)

	if sound_rate != 0.0:
		push_error("a sound pistol jammed at %.3f -- nominal condition must not jam at all" % sound_rate)
		return false
	if failing_rate <= 0.0:
		push_error("a failing pistol never jammed over %d pulls" % JAM_SHOTS)
		return false
	var want: float = float(SimItems.JAM_CHANCE_BY_BAND["failing"])
	if absf(failing_rate - want) > 0.06:
		push_error("a failing pistol jammed at %.3f, expected about %.3f from the band table" % [failing_rate, want])
		return false

	# The true negative that makes `jams` a content flag rather than decoration: a bow at the same
	# ruinous condition never jams, because it has nothing to stovepipe and declares no `jams`.
	var bow_world: Variant = _world()
	var bow: int = SimItems.spawn_item(bow_world, "item.bow.hunting", {"tier": "scavenged"})
	var bc: Dictionary = bow_world.components.get_component(bow, "condition") as Dictionary
	bc["current"] = 0.05
	SimInventory.equip(bow_world, bow_world.player, bow)
	var arrows: int = SimItems.spawn_item(bow_world, "item.ammo.arrow", {"tier": "scavenged", "count": 20})
	SimInventory.stow(bow_world, bow_world.player, arrows)
	bow_world.events.drain()
	var bow_rate: float = _jam_rate(bow_world, 100)
	if bow_rate != 0.0:
		push_error("a bow at 5%% condition jammed at %.3f -- only firearms jam" % bow_rate)
		return false

	# And the band table itself must be monotonic, or "degraded firearms jam" is not what it says.
	var order: Array[String] = ["sound", "worn", "failing", "barely holding"]
	for i in range(1, order.size()):
		if float(SimItems.JAM_CHANCE_BY_BAND[order[i]]) <= float(SimItems.JAM_CHANCE_BY_BAND[order[i - 1]]):
			push_error("the jam table is not monotonic: %s %.3f against %s %.3f" % [
				order[i], float(SimItems.JAM_CHANCE_BY_BAND[order[i]]),
				order[i - 1], float(SimItems.JAM_CHANCE_BY_BAND[order[i - 1]]),
			])
			return false

	print("JAM OK sound %.3f, failing %.3f against a table value of %.3f over %d pulls each; a bow at 5%% condition %.3f" % [
		sound_rate, failing_rate, want, JAM_SHOTS, bow_rate,
	])
	return true


# "Clearing a jam takes longer than a reload." Measured in ticks actually spent, and against the
# same weapon's own reload rather than against a number -- the relationship is the claim.
func _clearing_a_jam_takes_longer_than_a_reload() -> bool:
	var w: Variant = _world()
	# Ruined, so the very first pull jams and the measurement does not depend on a rate.
	_worn_pistol(w, 0.05)
	var rw: Dictionary = w.components.get_component(w.player, "rangedWeapon") as Dictionary
	var reload_ticks: int = int(rw.get("reloadTicks", 0))
	if reload_ticks <= 0:
		push_error("the pistol declares no reloadTicks, so there is nothing to be longer than")
		return false

	var mag_before: int = int(rw.get("mag", 0))
	# Arrays, not ints. GDScript lambdas capture primitives BY VALUE, so a handler assigning to an
	# outer `int` mutates its own copy and the accumulator reads back unchanged -- CLAUDE.md lists
	# this trap and it caught this assertion on its first run, reporting "never cleared" for a jam
	# that had cleared exactly on schedule.
	var announced: Array = []
	w.events.subscribe({"type": "weapon.jammed", "id": "gate.jamticks", "handler": func(e: Dictionary) -> void:
		announced.append(int(e.get("ticks", -1)))
	})
	var cleared: Array = []
	w.events.subscribe({"type": "weapon.cleared", "id": "gate.cleared", "handler": func(_e: Dictionary) -> void:
		cleared.append(int(w.tick))
	})

	# "barely holding" is a 0.30 chance, not a certainty, so pull the trigger until one jams
	# rather than asserting the first one does -- an assertion that depended on a 30% roll landing
	# would be a flake wearing a gate's clothes.
	var jammed_at: int = -1
	for _pull in 60:
		if jammed_at >= 0:
			break
		var live0: Dictionary = w.components.get_component(w.player, "rangedWeapon") as Dictionary
		live0["mag"] = int(live0.get("magSize", 8))
		_top_up_ammo(w)
		w.commands.push({"type": "fire"})
		for _i in 400:
			w.step()
			var live: Dictionary = w.components.get_component(w.player, "rangedWeapon") as Dictionary
			if jammed_at < 0 and int(live["state"]) == SimRanged.FireState.Clearing:
				jammed_at = int(w.tick)
			if not cleared.is_empty():
				break
			if jammed_at < 0 and int(live["state"]) == SimRanged.FireState.Idle:
				break
	if jammed_at < 0:
		push_error("a pistol at 5%% condition did not jam over 60 pulls")
		return false
	if cleared.is_empty():
		push_error("a jammed pistol never cleared over 400 ticks")
		return false

	var spent: int = int(cleared[0]) - jammed_at
	if spent <= reload_ticks:
		push_error("clearing took %d ticks against a reload of %d -- docs/09 says it must be longer" % [spent, reload_ticks])
		return false
	if announced.is_empty() or int(announced[0]) != spent:
		push_error("the jam announced %s ticks and took %d" % [str(announced), spent])
		return false

	# The round was stuck, not fired: the magazine is what it was, and the weapon is back to Idle
	# rather than resuming the shot on its own.
	var after: Dictionary = w.components.get_component(w.player, "rangedWeapon") as Dictionary
	if int(after.get("mag", -1)) != mag_before:
		push_error("a jam spent a round: magazine %d -> %d" % [mag_before, int(after.get("mag", -1))])
		return false
	if int(after["state"]) != SimRanged.FireState.Idle:
		push_error("a cleared weapon resumed by itself instead of returning to Idle")
		return false

	print("CLEAR OK jammed at %d, cleared %d ticks later against a reload of %d, magazine still %d, back to Idle" % [
		jammed_at, spent, reload_ticks, mag_before,
	])
	return true


# docs/29's stance table, walked rung by rung: "Sprint: cannot aim", and Crawl cannot either.
#
# `SimStances.CAN_AIM` has encoded exactly this since the ladder landed and was **read by nothing
# anywhere in the repo** -- `SimRanged._capable_of` refused stance 0 with a hand-written `!= 0`
# and let a sprinting survivor raise, steady and fire. A ninth entry for CLAUDE.md's dead-socket
# list, and the reason this assertion walks all five rungs rather than checking the one that was
# wrong: three of them must still fire, or "nobody can shoot" would pass just as well.
func _a_sprint_cannot_aim_and_every_other_rung_can() -> bool:
	var fired: Array[int] = []
	var refused: Array[int] = []
	for rung in [SimStances.Stance.Crawl, SimStances.Stance.Crouch, SimStances.Stance.Walk, SimStances.Stance.Jog, SimStances.Stance.Sprint]:
		var w: Variant = _world()
		var bow: int = SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"})
		SimInventory.equip(w, w.player, bow)
		var arrows: int = SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 6})
		if not SimInventory.stow(w, w.player, arrows):
			w.components.set_component(arrows, "stored", {"container": w.player})
		var rng: Variant = w.rng.stream("shambler")
		SimRoster.spawn_zombie(w, 14.0, 12.0, SimRoster.TYPE_SHAMBLER, rng)
		w.events.drain()
		# Set the rung outright rather than through a stance command: request_stance takes
		# STANCE_CHANGE_TICKS to arrive and this assertion is about the rung, not the ladder.
		var posture: Dictionary = w.components.get_component(w.player, "posture") as Dictionary
		posture["current"] = int(rung)
		posture["target"] = int(rung)
		posture["ticks_left"] = 0
		if not _fire_through(w, 1).is_empty():
			fired.append(int(rung))
		else:
			refused.append(int(rung))
	var want_refused: Array[int] = [int(SimStances.Stance.Crawl), int(SimStances.Stance.Sprint)]
	for rung in want_refused:
		if not refused.has(rung):
			push_error("%s fired, and SimStances.CAN_AIM says it cannot aim" % SimStances.NAMES[rung])
			return false
	for rung in [int(SimStances.Stance.Crouch), int(SimStances.Stance.Walk), int(SimStances.Stance.Jog)]:
		if not fired.has(rung):
			push_error("%s did not fire, so the two refusals above prove nothing" % SimStances.NAMES[rung])
			return false
	print("SPRINT OK fired from %d rungs, refused from crawling and sprinting" % fired.size())
	return true
