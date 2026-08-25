extends SceneTree
# The balance harness -- Milestone 2 build order step 7, "Proof: automated distribution runs
# first, then the human ten-day playtest".
#
# docs/19's testing table asks for "thousands of headless runs". That is not reachable here and
# saying so is cheaper than pretending: `Clock.DAY_TICKS` is 4 h x 3600 x 20 Hz = 288,000, so one
# ten-day campaign is 2.88 M ticks and takes tens of minutes of headless GDScript. So there are
# two tiers, and they are honest about being different things.
#
#   FAST (default, inside `godot:m2`) -- FAST_SEEDS x a *compressed* campaign: jump the clock to
#   each day's dusk, which is the director's one decision point, then step a real window so what
#   it placed starts moving. This measures **pacing and placement** and deliberately claims
#   nothing else. What it cannot see, measured rather than assumed: a packet lands on a district
#   edge and DUSK_WINDOW_TICKS is 100 seconds of sim, which is not enough to cross a 256 m
#   district, so most of what it places never reaches anybody. It is no longer true that every
#   combat counter reads zero -- arming the whole colony put the district's own wanderers within
#   reach of somebody who could answer them, and the tier now records a handful of kills on two
#   seeds in four -- but a handful is not a distribution. Survival and the arms still belong to
#   the full tier, and saying so is cheaper than a band nobody trusts.
#
#   FULL (`BALANCE_FULL=1`) -- FULL_SEEDS x the real ten-day step loop, no compression. Where the
#   risk 3 and risk 6 numbers actually come from. Asserts only what must hold at any pacing, and
#   *reports* everything else, which is the discipline check_m2_harness.gd's `_full_ten_day`
#   already had; what is new is having arms to compare.
#
# Every fact here is read off the event bus -- director.packet, fortify.breached, entity.killed,
# run.over -- so the harness adds no simulation state and cannot change what it measures.
#
# check_m2_harness.gd is left alone: it is the soft tuning harness, this is the gate.

const SimBoot = preload("res://sim/boot.gd")
const SimDirector = preload("res://sim/modules/director.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const Clock = preload("res://sim/time/clock.gd")

const DAYS: int = 10
const FAST_SEEDS: Array[int] = [20260805, 404, 31337, 90210]
const FULL_SEEDS: Array[int] = [20260805, 404, 31337, 90210]
const MAP_TILES: int = 64

# Long enough for a packet placed on a district edge to close on the annex and be fought, short
# enough that six seeds stay inside a couple of minutes. 2000 ticks is 100 seconds of sim.
const DUSK_WINDOW_TICKS: int = 2000

# --- bands -------------------------------------------------------------------------------
# Named so re-tuning is a visible edit rather than a moved goalpost, and each carries the figure
# actually measured when it was written. A band, not a value: the point of six seeds is spread.
const SIEGE_NIGHTS_MIN: int = 1          # measured: 3 of 10 on every seed
const SIEGE_NIGHTS_MAX: int = 9          # a campaign that sieges every night has no lulls left
const TOTAL_PACKETS_MIN: int = 6         # measured: 12 across four seeds
const BREACH_SEEDS_MIN: int = 0          # measured: 0 -- see the note in _assert_bands
const ARMS: Array[String] = ["mixed", "melee", "ranged"]
# What the `mixed` arm hands somebody the boot left empty-handed. The humblest thing in the
# content tree on purpose: this is a floor under the harness, not a buff, and if it ever has to
# fire the ARMED assertion has already failed and said so.
const MIXED_FALLBACK_WEAPON: String = "item.knife.kitchen"

# The live count is sampled rather than read every tick: `query` sorts, and a per-tick call to it
# is the difference between a full campaign taking half an hour and taking an hour. LIVE_CAP is
# enforced at spawn time and a breach of it would persist for thousands of ticks, so a one-second
# sample cannot plausibly miss one.
const LIVE_SAMPLE_TICKS: int = 20

var _fast: bool = OS.get_environment("BALANCE_FULL") != "1"

# What the full tier costs, so nobody starts it by accident. A ten-day campaign is 2.88 M ticks
# (`Clock.DAY_TICKS` is 288,000), and the default FULL_SEEDS x ARMS grid is twelve of them.
#
# Measured, not estimated: one real single-day campaign is 180,000 ticks and took **166 s**, so
# headless GDScript runs this district at about **1,085 ticks/second** -- and the compressed tier
# measures ~950, which is close enough to say the day phases are not the expensive part. A ten-day
# campaign is therefore about **forty-five minutes**, and the default grid is twelve of them:
# roughly **nine hours**.
#
# That is why the tier is opt-in and why these two knobs exist: scale it down to exercise the
# code path, scale it back up when you want the numbers. Anything recorded in docs/23's status
# section as a *result* must come from a run at the full DAYS.
var _days: int = int(OS.get_environment("BALANCE_DAYS")) if OS.get_environment("BALANCE_DAYS") != "" else DAYS
var _seeds: int = int(OS.get_environment("BALANCE_SEEDS")) if OS.get_environment("BALANCE_SEEDS") != "" else 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	if _fast:
		ok = _fast_tier() and ok
	else:
		ok = _full_tier() and ok
	if ok:
		if _fast:
			print("M2_BALANCE_OK fast %d seeds, %d days, bands invariants placement" % [FAST_SEEDS.size(), _days])
		else:
			print("M2_BALANCE_OK full %d seeds x %d arms, %d days, invariants runover arms auto" % [_full_seeds().size(), ARMS.size(), _days])
		quit(0)
	else:
		push_error("M2_BALANCE_FAIL")
		quit(1)


func _full_seeds() -> Array[int]:
	return FULL_SEEDS.slice(0, _seeds) if _seeds > 0 else FULL_SEEDS


# --- the two tiers -----------------------------------------------------------------------

func _fast_tier() -> bool:
	var runs: Array[Dictionary] = []
	for seed_value in FAST_SEEDS:
		var run: Dictionary = _compressed_campaign(int(seed_value), "mixed")
		_print_run("FAST", run)
		runs.append(run)
	var ok: bool = _assert_invariants(runs)
	ok = _assert_bands(runs) and ok
	ok = _assert_the_seed_moves_placement(runs) and ok
	ok = _the_armed_count_can_see_an_empty_hand() and ok
	return ok


# Every full-tier campaign belongs to an arm, and `mixed` is one of them -- so the invariant runs
# and the risk-6 comparison are the same 12 campaigns rather than 16. At roughly half an hour a
# campaign that difference is two hours, which is the difference between a thing that gets run
# and a thing that does not.
func _full_tier() -> bool:
	var runs: Array[Dictionary] = []
	var by_arm: Dictionary = {}
	var seeds: Array[int] = _full_seeds()
	for arm in ARMS:
		var total: Dictionary = {"kills": 0, "survivors_end": 0, "survivors_start": 0, "days": 0, "deaths": 0, "packets": 0}
		for seed_value in seeds:
			var run: Dictionary = _real_campaign(int(seed_value), String(arm))
			_print_run("FULL", run)
			runs.append(run)
			for key in total.keys():
				total[key] = int(total[key]) + int(run[key])
		by_arm[arm] = total
		print("ARM %s totals kills=%d deaths=%d survivors=%d/%d days=%d" % [
			arm, int(total["kills"]), int(total["deaths"]), int(total["survivors_end"]),
			int(total["survivors_start"]), int(total["days"]),
		])
		by_arm[arm]["seeds"] = seeds.size()
	var ok: bool = _assert_invariants(runs)
	ok = _the_armed_count_can_see_an_empty_hand() and ok
	ok = _assert_run_over_iff_wiped(runs) and ok
	ok = _assert_arms_are_comparable(by_arm) and ok
	# Risk 1: a seeded six-survivor colony, everyone on Auto, must not stall.
	ok = _six_survivors_on_auto() and ok
	return ok


# --- campaigns ---------------------------------------------------------------------------

# Jump to each day's dusk -- the director's single decision point -- then step a real window so
# what it placed has time to matter. The technique is check_m2_harness.gd's `_jump_dusk`.
#
# What compression costs, stated rather than hidden: the ticks between windows never run, so
# needs do not drain, `_tick_peak`'s weekly noise peak sees only the windows, and nobody
# starves. That is exactly why the colony-survival check below is a floor and not a distribution.
func _compressed_campaign(seed_value: int, arm: String) -> Dictionary:
	var w: Variant = _boot(seed_value, arm)
	var run: Dictionary = _blank_run(seed_value, arm, w)
	for day in range(1, _days + 1):
		var packets_before_dusk: int = int(run["packets"])
		w.tick = Clock.tick_on_day(day, Clock.DAY_ENDS) - 1
		var before: Array[int] = _shambler_ids(w)
		w.step()
		_observe(w, run, before)
		for _t in DUSK_WINDOW_TICKS:
			w.step()
			_observe(w, run, null)
		if int(run["packets"]) > packets_before_dusk:
			run["siege_nights"] = int(run["siege_nights"]) + 1
		else:
			run["quiet_nights"] = int(run["quiet_nights"]) + 1
		run["days"] = day
	_close_run(w, run)
	return run


func _real_campaign(seed_value: int, arm: String) -> Dictionary:
	var w: Variant = _boot(seed_value, arm)
	var run: Dictionary = _blank_run(seed_value, arm, w)
	var end_tick: int = Clock.tick_on_day(_days, Clock.DUSK_ENDS)
	var last_day: int = Clock.day_number(int(w.tick))
	var packets_at_day_start: int = 0
	while int(w.tick) < end_tick:
		# Packets only ever arrive on the tick the district enters Dusk -- `director.dusk`'s own
		# condition -- so that is the only tick worth paying a component query for.
		var before: Variant = null
		if Clock.phase_of(int(w.tick) + 1) == Clock.Phase.Dusk and Clock.phase_of(int(w.tick)) != Clock.Phase.Dusk:
			before = _shambler_ids(w)
		w.step()
		_observe(w, run, before)
		var day: int = Clock.day_number(int(w.tick))
		if day != last_day:
			if int(run["packets"]) > packets_at_day_start:
				run["siege_nights"] = int(run["siege_nights"]) + 1
			else:
				run["quiet_nights"] = int(run["quiet_nights"]) + 1
			packets_at_day_start = int(run["packets"])
			last_day = day
		if bool(w.runOver):
			break
	# Run length is the day the campaign reached -- the number the risk register actually wants,
	# and the one that shortens when a colony is wiped out on day four.
	run["days"] = Clock.day_number(int(w.tick))
	_close_run(w, run)
	return run


# --- observation -------------------------------------------------------------------------

func _blank_run(seed_value: int, arm: String, w: Variant) -> Dictionary:
	return {
		"seed": seed_value,
		"arm": arm,
		"days": 0,
		"packets": 0,
		"siege_nights": 0,
		"quiet_nights": 0,
		"breaches": 0,
		"kills": 0,
		"melee_kills": 0,
		"ranged_kills": 0,
		"deaths": 0,
		# The hold loop, counted off the bus like everything else here. `grab.started` is one per
		# hand that closes; `grab.broken` is one per victim who becomes fully free, tagged with why,
		# which is the only way a harness that reads nothing but events can tell an escape from a
		# rescue from a corpse. Reported, not asserted -- see the note above `_assert_bands`.
		"grabs": 0,
		"broken": {},
		"seen_dead": {},
		"turned": 0,
		"recruits": 0,
		"max_live": _live(w),
		"over_cap": 0,
		"illegal_placements": 0,
		# A plain Array, deliberately: a PackedStringArray is a *value* in GDScript, so appending
		# through the dictionary would append to a copy and every seed would look identical.
		"placements": [],
		"survivors_start": _survivors_alive(w),
		"survivors_end": 0,
		# Sampled at boot, once, because that is the moment the claim is about: a colony that
		# starts a ten-day campaign with somebody's hands empty is not measuring the game. Losing
		# a weapon later is play; starting without one is a setup bug, and this one hid for a
		# whole slice behind an arm that equipped people only when it was not `mixed`.
		"unarmed_at_boot": _unarmed_colonists(w).size(),
		"run_over": false,
	}


# One drain, read once. Everything below is a count of something the simulation already said.
# `before` is the shambler roster from before this step, or null on the ticks where no packet
# could have arrived -- see the note at the call site.
func _observe(w: Variant, run: Dictionary, before: Variant) -> void:
	for e in w.events.drained:
		var ev: Dictionary = e as Dictionary
		match String(ev.get("type", "")):
			"director.packet":
				run["packets"] = int(run["packets"]) + 1
			"fortify.breached":
				run["breaches"] = int(run["breaches"]) + 1
			"recruit.arrived":
				run["recruits"] = int(run["recruits"]) + 1
			"survivor.turned":
				run["turned"] = int(run["turned"]) + 1
			"run.over":
				run["run_over"] = true
			"grab.started":
				run["grabs"] = int(run["grabs"]) + 1
			"grab.broken":
				var why: String = String(ev.get("cause", "unknown"))
				(run["broken"] as Dictionary)[why] = int((run["broken"] as Dictionary).get(why, 0)) + 1
			"entity.killed":
				var victim: int = int(ev.get("entity", -1))
				var killer: int = int(ev.get("killer", -1))
				# `entity.killed` is published from more than one place for the same individual --
				# `health.gd` when a head is destroyed, `infection.gd` on a put-down and again on
				# turning -- so counting events would report three deaths for one person. Count
				# distinct victims, which is what the word means.
				if (run["seen_dead"] as Dictionary).has(victim):
					continue
				(run["seen_dead"] as Dictionary)[victim] = true
				if not w.components.has_component(victim, "shambler"):
					# A survivor is a death however they died. Starving carries no killer, and
					# requiring one here would quietly drop the deaths the needs system causes --
					# which are exactly the ones a ten-day run is supposed to surface.
					run["deaths"] = int(run["deaths"]) + 1
					continue
				if killer >= 0:
					run["kills"] = int(run["kills"]) + 1
					# The arms carry exactly one class of weapon, so this is unambiguous.
					if w.components.has_component(killer, "rangedWeapon"):
						run["ranged_kills"] = int(run["ranged_kills"]) + 1
					elif w.components.has_component(killer, "meleeWeapon"):
						run["melee_kills"] = int(run["melee_kills"]) + 1
	if before is Array or int(w.tick) % LIVE_SAMPLE_TICKS == 0:
		var live: int = _live(w)
		if live > int(run["max_live"]):
			run["max_live"] = live
		if live > SimDirector.LIVE_CAP:
			run["over_cap"] = int(run["over_cap"]) + 1
	if not before is Array:
		return
	for tile in _placed_since(w, before as Array[int]):
		(run["placements"] as Array).append("%d,%d" % [tile.x, tile.y])
		if not _legal_placement(w, tile):
			run["illegal_placements"] = int(run["illegal_placements"]) + 1


func _close_run(w: Variant, run: Dictionary) -> void:
	run["survivors_end"] = _survivors_alive(w)
	run["run_over"] = bool(run["run_over"]) or bool(w.runOver)


func _print_run(label: String, run: Dictionary) -> void:
	print("%s seed=%d arm=%s days=%d siege=%d quiet=%d packets=%d breaches=%d kills=%d(m%d/r%d) deaths=%d turned=%d recruits=%d max_live=%d survivors=%d/%d over=%s grabs=%d broken=%s" % [
		label, int(run["seed"]), String(run["arm"]), int(run["days"]),
		int(run["siege_nights"]), int(run["quiet_nights"]), int(run["packets"]),
		int(run["breaches"]), int(run["kills"]), int(run["melee_kills"]), int(run["ranged_kills"]),
		int(run["deaths"]), int(run["turned"]), int(run["recruits"]), int(run["max_live"]),
		int(run["survivors_end"]), int(run["survivors_start"]), str(run["run_over"]),
		int(run["grabs"]), str(run["broken"]),
	])


# --- assertions --------------------------------------------------------------------------

# The things that must hold whatever the pacing turns out to be. These are the assertions the
# compressed tier is entitled to make, because none of them depends on how much time passed.
func _assert_invariants(runs: Array[Dictionary]) -> bool:
	var ok: bool = true
	for run in runs:
		if int(run["illegal_placements"]) > 0:
			push_error("seed %d placed %d packets on a gate, in the annex, or inside GATE_EXCLUSION" % [int(run["seed"]), int(run["illegal_placements"])])
			ok = false
		if int(run["over_cap"]) > 0:
			push_error("seed %d exceeded LIVE_CAP %d on %d ticks (max %d)" % [int(run["seed"]), SimDirector.LIVE_CAP, int(run["over_cap"]), int(run["max_live"])])
			ok = false
		if int(run["survivors_start"]) < 1:
			push_error("seed %d booted with no survivors, so it measures nothing" % int(run["seed"]))
			ok = false
		if int(run["unarmed_at_boot"]) > 0:
			push_error("seed %d arm %s: %d colonist(s) started the campaign with nothing to fight with" % [int(run["seed"]), String(run["arm"]), int(run["unarmed_at_boot"])])
			ok = false
	if ok:
		print("INVARIANTS OK placement, cap %d, %d runs" % [SimDirector.LIVE_CAP, runs.size()])
	return ok


# The true negative for the counter the invariant above reads. An assertion that every colonist
# boots armed is worth exactly as much as the counter's ability to say otherwise, and "0 unarmed"
# is also what a counter that cannot see anybody returns -- so take a real boot, take the weapon
# out of one person's hands, and require the count to move by exactly one.
func _the_armed_count_can_see_an_empty_hand() -> bool:
	var w: Variant = _boot(int(FAST_SEEDS[0]), "mixed")
	var armed: int = _unarmed_colonists(w).size()
	var colonists: Array[int] = _colonists(w)
	if colonists.size() < 2:
		push_error("the playable boot has %d colonists -- this assertion needs a colony, not a person" % colonists.size())
		return false
	SimInventory.unequip(w, int(colonists[colonists.size() - 1]), "primary")
	w.events.drain()
	var stripped: int = _unarmed_colonists(w).size()
	if armed != 0:
		push_error("a fresh %s boot already had %d unarmed colonists" % ["mixed", armed])
		return false
	if stripped != 1:
		push_error("disarming one colonist moved the unarmed count to %d, expected 1 -- the counter is not measuring hands" % stripped)
		return false
	print("ARMED OK %d colonists all armed at boot; disarming one is seen (0 -> %d)" % [colonists.size(), stripped])
	return true


func _assert_bands(runs: Array[Dictionary]) -> bool:
	var packets: int = 0
	var breach_seeds: int = 0
	var ok: bool = true
	for run in runs:
		var siege: int = int(run["siege_nights"])
		if siege < SIEGE_NIGHTS_MIN or siege > SIEGE_NIGHTS_MAX:
			push_error("seed %d had %d siege nights, band is %d..%d" % [int(run["seed"]), siege, SIEGE_NIGHTS_MIN, SIEGE_NIGHTS_MAX])
			ok = false
		if siege + int(run["quiet_nights"]) != int(run["days"]):
			push_error("seed %d: %d siege + %d quiet != %d days" % [int(run["seed"]), siege, int(run["quiet_nights"]), int(run["days"])])
			ok = false
		if int(run["survivors_end"]) < 1:
			push_error("seed %d lost the whole colony inside the compressed campaign" % int(run["seed"]))
			ok = false
		packets += int(run["packets"])
		if int(run["breaches"]) > 0:
			breach_seeds += 1
	if packets < TOTAL_PACKETS_MIN:
		push_error("%d packets across %d seeds, floor is %d -- the director has gone quiet" % [packets, runs.size(), TOTAL_PACKETS_MIN])
		ok = false
	# Breaches are a *report*, not yet a floor. Nothing in the compressed model boards a window
	# or drives a horde into one for long enough, so a zero here is the model's limit rather than
	# the director's -- the honest place for that assertion is the full tier once it has a number.
	if breach_seeds < BREACH_SEEDS_MIN:
		push_error("%d seeds breached, floor is %d" % [breach_seeds, BREACH_SEEDS_MIN])
		ok = false
	if ok:
		print("BANDS OK packets=%d siege in %d..%d breach_seeds=%d" % [packets, SIEGE_NIGHTS_MIN, SIEGE_NIGHTS_MAX, breach_seeds])
	return ok


# The one thing a seed genuinely buys at this compression, and the reason the seed loop is not
# vacuous. The director's *size* decisions read the day, the live count, colony power and the
# week's noise peak -- none of which the seed moves, because `apply_patch` blits the same
# authored annex over every generated district. What the seed does move is `_emit_packet`'s
# edge pick. Assert that, or six identical campaigns would pass six times and prove once.
func _assert_the_seed_moves_placement(runs: Array[Dictionary]) -> bool:
	var seen: Dictionary = {}
	for run in runs:
		seen[String("|").join(PackedStringArray(run["placements"] as Array))] = true
	if seen.size() < 2:
		push_error("%d seeds placed every packet on the same tiles -- the seed is not reaching the director" % runs.size())
		return false
	print("SEEDS OK %d distinct placement sets across %d seeds" % [seen.size(), runs.size()])
	return true


# Closes the backlog's "run ends only when the last survivor dies". Both directions: a run that
# ended must have been wiped out, and a colony that was wiped out must have ended.
func _assert_run_over_iff_wiped(runs: Array[Dictionary]) -> bool:
	var ok: bool = true
	for run in runs:
		var wiped: bool = int(run["survivors_end"]) < 1
		if bool(run["run_over"]) != wiped:
			push_error("seed %d: run_over=%s with %d survivors left" % [int(run["seed"]), str(run["run_over"]), int(run["survivors_end"])])
			ok = false
	if ok:
		print("RUN-OVER OK ends exactly when the last survivor dies")
	return ok


# Risk 6. Not "the same numbers" -- non-convertible currencies are the point, per the settled
# decision that melee and ranged spend body/bite-risk against ammo/attention. What would fail
# the checkpoint is one arm being unable to fight at all, or one arm's colony surviving while
# the other's does not.
func _assert_arms_are_comparable(by_arm: Dictionary) -> bool:
	var ok: bool = true
	var melee: Dictionary = by_arm["melee"] as Dictionary
	var ranged: Dictionary = by_arm["ranged"] as Dictionary
	# The director spends its first week on grace and trickle -- `GRACE_PRESSURE_UNTIL_DAY` is 8 --
	# so a shortened grid is a grid nothing attacked, and an arm cannot be judged on a campaign it
	# was never pressured in. Refuse to assert rather than assert on no data, and say so loudly.
	if int(melee["packets"]) + int(ranged["packets"]) < 1:
		print("ARMS SKIPPED no packets across the grid at %d days -- risk 6 needs a full %d-day run" % [_days, DAYS])
		return true
	for name in ["melee", "ranged"]:
		if int((by_arm[name] as Dictionary)["kills"]) < 1:
			push_error("the %s-only arm killed nothing across %d campaigns" % [name, int((by_arm[name] as Dictionary)["seeds"])])
			ok = false
	var m_alive: int = int(melee["survivors_end"])
	var r_alive: int = int(ranged["survivors_end"])
	if (m_alive < 1) != (r_alive < 1):
		push_error("one arm was wiped out and the other was not: melee=%d ranged=%d survivors" % [m_alive, r_alive])
		ok = false
	if ok:
		print("ARMS OK melee kills=%d alive=%d | ranged kills=%d alive=%d" % [int(melee["kills"]), m_alive, int(ranged["kills"]), r_alive])
	return ok


# Risk 1, the micromanagement cliff: six survivors, every one of them on Auto, must not stall.
# A stall is a survivor who never picks up a job at all -- that is the shape the checkpoint asks
# about, because it is what would say the item and web systems need shrinking rather than the UI
# improving.
func _six_survivors_on_auto() -> bool:
	var w: Variant = SimBoot.playable(int(FULL_SEEDS[0]), MAP_TILES)["world"]
	var rng: Variant = w.rng.stream("recruit")
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	var roster: Array[int] = []
	for ent in w.components.query(["needs", "jobPriorities"]):
		roster.append(int(ent))
	var ring: int = 0
	while roster.size() < 6:
		ring += 1
		# `spawn_generated` already produces a colonist -- name, traits, aptitudes, kit and an
		# "Auto" job row. `accept` is for the recruit beat's waiting strangers, and these are not
		# strangers; calling it here would read as if it mattered and return false.
		var ent: int = SimRecruits.spawn_generated(w, SimRecruits.roll(w, rng), float(pos["x"]) + float(ring), float(pos["y"]))
		if ent < 0:
			push_error("could not generate survivor %d" % roster.size())
			return false
		roster.append(ent)
	var worked: Dictionary = {}
	for ent in roster:
		SimJobs.set_focus(w, int(ent), "Auto")
		worked[ent] = false
	for _t in Clock.DAY_TICKS:
		w.step()
		for ent in roster:
			if w.components.get_component(int(ent), "job") is Dictionary:
				worked[ent] = true
	var idle: Array[int] = []
	for ent in roster:
		if not bool(worked[ent]):
			idle.append(int(ent))
	if not idle.is_empty():
		push_error("%d of %d survivors on Auto never took a job in a day: %s" % [idle.size(), roster.size(), str(idle)])
		return false
	print("AUTO OK %d survivors, all took work inside one day" % roster.size())
	return true


# --- world helpers -----------------------------------------------------------------------

func _boot(seed_value: int, arm: String) -> Variant:
	var w: Variant = SimBoot.playable(seed_value, MAP_TILES)["world"]
	_configure_arm(w, arm)
	w.events.drain()
	return w


# The arms differ only in what people carry. Loose loot of the wrong class is removed from the
# ground too, or an arm would drift back to mixed the first time somebody hauled.
#
# `mixed` is an arm like the other two rather than "whatever the boot happened to leave", which
# is the shape it used to have and the reason a whole colonist could be measured for ten days
# with empty hands. It re-equips nobody -- the point of the arm is the game's own loadout -- it
# only refuses to start a campaign with an unarmed colonist in it. With the boot itself fixed
# (`SimSurvivors._hold_it` puts a kit weapon in the hand it belongs to) this is a floor that
# should now never have to fire; `_unarmed_colonists` below is what asserts that it does not.
func _configure_arm(w: Variant, arm: String) -> void:
	if arm == "mixed":
		for ent in _unarmed_colonists(w):
			SimInventory.equip(w, int(ent), SimItems.spawn_item(w, MIXED_FALLBACK_WEAPON, {"tier": "scavenged"}))
		w.events.drain()
		return
	var weapon_id: String = "item.bat.aluminium" if arm == "melee" else "item.bow.hunting"
	for ent in w.components.query(["needs", "position"]):
		SimInventory.unequip(w, int(ent), "primary")
		SimInventory.unequip(w, int(ent), "secondary")
		SimInventory.equip(w, int(ent), SimItems.spawn_item(w, weapon_id, {"tier": "scavenged"}))
		if arm == "ranged":
			var arrows: int = SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 20})
			if not SimInventory.stow(w, int(ent), arrows):
				# A full grid must not silently swallow the quiver -- drop it where they stand,
				# the way `spawn_generated` handles a kit that will not fit.
				var at: Variant = w.components.get_component(int(ent), "position")
				if at is Dictionary:
					w.components.set_component(arrows, "position", (at as Dictionary).duplicate())
	var wrong: Array[int] = []
	for item in w.components.query(["itemBase", "position"]):
		var melee: bool = SimItems.melee_profile_of(w, int(item)) != null
		var ranged: bool = SimItems.ranged_profile_of(w, int(item)) != null
		if not melee and not ranged:
			continue
		if (arm == "melee" and ranged) or (arm == "ranged" and melee):
			wrong.append(int(item))
	for item in wrong:
		w.entities.despawn(item)


func _live(w: Variant) -> int:
	return w.components.query(["shambler"]).size()


# The people the campaign is about: alive, not a corpse, not a stranger who has not joined yet.
# Same exclusions as `_survivors_alive`, which counts them rather than listing them.
func _colonists(w: Variant) -> Array[int]:
	var out: Array[int] = []
	for ent in w.components.query(["needs", "body"]):
		if w.components.has_component(int(ent), "corpse") or w.components.has_component(int(ent), "recruit"):
			continue
		var body: Variant = w.components.get_component(int(ent), "body")
		if body is Dictionary and SimHealth.is_alive(body as Dictionary):
			out.append(int(ent))
	return out


# "Armed" asked of the components combat actually reads, not of what is in somebody's pack: a
# knife in a satchel raises no `meleeWeapon`, and `melee.gd` and `npc_combat.gd` both look here.
func _unarmed_colonists(w: Variant) -> Array[int]:
	var out: Array[int] = []
	for ent in _colonists(w):
		if w.components.has_component(int(ent), "meleeWeapon") or w.components.has_component(int(ent), "rangedWeapon"):
			continue
		out.append(int(ent))
	return out


func _shambler_ids(w: Variant) -> Array[int]:
	return w.components.query(["shambler"])


func _survivors_alive(w: Variant) -> int:
	var n: int = 0
	for ent in w.components.query(["needs", "body"]):
		if w.components.has_component(int(ent), "corpse"):
			continue
		if w.components.has_component(int(ent), "recruit"):
			continue
		var body: Variant = w.components.get_component(int(ent), "body")
		if body is Dictionary and SimHealth.is_alive(body as Dictionary):
			n += 1
	return n


func _placed_since(w: Variant, before: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ent in w.components.query(["shambler", "position"]):
		if before.has(int(ent)):
			continue
		var pos: Variant = w.components.get_component(int(ent), "position")
		if pos is Dictionary:
			out.append(Vector2i(floori(float((pos as Dictionary)["x"])), floori(float((pos as Dictionary)["y"]))))
	return out


# The director never spawns at your gate and never inside the annex -- `_legal_tile`'s promise,
# checked from the outside against what actually landed rather than against the same code.
#
# Where the gate and the annex are comes off the campaign's own map: they are anchors the district
# carries now, not constants, so this keeps checking the real colony rather than a remembered one.
# Only reached for tiles a night actually placed, so there is no per-tick lookup here.
func _legal_placement(w: Variant, tile: Vector2i) -> bool:
	var gate_a: Vector2i = SimTileMap.gate_a(w.tilemap)
	var gate_b: Vector2i = SimTileMap.gate_b(w.tilemap)
	if tile == gate_a or tile == gate_b:
		return false
	var annex: Rect2i = SimTileMap.annex_rect(w.tilemap)
	if annex.size.x > 0 and annex.size.y > 0 and annex.has_point(tile):
		return false
	for gate in [gate_a, gate_b]:
		if (gate as Vector2i).x < 0:
			continue
		var dx: float = (float(tile.x) + 0.5) - (float((gate as Vector2i).x) + 0.5)
		var dy: float = (float(tile.y) + 0.5) - (float((gate as Vector2i).y) + 0.5)
		if dx * dx + dy * dy < SimDirector.GATE_EXCLUSION * SimDirector.GATE_EXCLUSION:
			return false
	return true
