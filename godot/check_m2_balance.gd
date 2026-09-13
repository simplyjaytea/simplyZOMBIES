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
# 64 unless `BALANCE_TILES` names another size (the `BALANCE_DISTRICT` precedent): the chain's
# FAST tier stays at 64 so its lines stay comparable, and the FULL tier can be run at the shipped
# 256 by hand -- `BALANCE_FULL=1 BALANCE_TILES=256`.
var _tiles: int = int(OS.get_environment("BALANCE_TILES")) if OS.get_environment("BALANCE_TILES") != "" else 64

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

# --- the armour arms -----------------------------------------------------------------------
# The second half of "armour that reaches a campaign", and the reason the first half is worth
# anything. Coverage has stopped blows since the armour slice, and this harness measured it as
# **byte-identical on all four seeds** -- not because the mechanic failed but because nothing ever
# put a vest on anybody, so every seed ran a colony in shirtsleeves twice.
#
# Three things had to be measured before this could be written, and each of them killed a simpler
# design:
#
#   1. **The colony never opens a container.** `searches=0` on every seed of the FAST tier, and a
#      throwaway driver that ran a *whole real day* -- 180,000 uncompressed ticks, no jumps --
#      recorded `searches=0` and `worn=0` as well. So an arm that waits for colonists to find
#      armour waits forever, and "colonists wear what they find" is measurable here only if
#      something is lying where the rule's ground branch reaches. That is what `_lay_out_armour`
#      does: a set per colonist, at their feet, exactly as a Haul leaves a load.
#   2. **The dusk window never touches the colony.** Compressed to dusk, seed 20260805 records 117
#      grabs and *not one of them on a colonist*: zero hits, zero bites, zero integrity lost on
#      both arms. Two zeroes are equal, and a gate that reports "dressed is no worse than bare"
#      about two campaigns in which nobody was touched has measured nothing. So the armour arms
#      compress to the **working day** instead, where Haul and Scavenge put people out among the
#      district's own wanderers -- the contact the Guard slice measured when it found Ellis
#      grabbed sixteen times in a day. Widening the dusk window does not fix it, it overshoots:
#      at 12,000 ticks the same seed loses the entire colony.
#   3. **Neither raw integrity lost nor a naive ratio is a statistic here, and the sabotage pass is
#      what proved it.** Every campaign measured loses exactly one colonist on every seed and both
#      arms, and a body that dies contributes its whole 185 points whatever route it took, so the
#      raw figure is one death plus noise: it moves 1.4% between arms across four seeds. The
#      obvious repair -- integrity lost per point of damage *offered* -- was written, measured at
#      0.497 bare against 0.330 dressed, and then **stayed green with `armor_damage_factor` deleted
#      from `damage_part`**, which is the whole of why a lane is not believed until somebody has
#      broken the thing it guards. It was measuring saturation, not armour: `damage_part` clamps at
#      zero, so an arm that takes more contact wastes more of it on parts that have already run out,
#      and the dressed arm takes more contact because dressing means walking.
#
#      So the ratio is taken over **unhurt colonists only**. A colonist is dropped from both
#      accumulators, permanently, the moment any part of them reaches zero, and a tick on which
#      that happens is dropped whole. Nothing left in the sample can be clamped, so what remains is
#      the fraction of each blow that got past what the target was wearing -- which is exactly what
#      armour governs and nothing else. Bare reads essentially 1.0 by construction; with the
#      mitigation deleted the dressed arm reads 1.0 too and the lane goes red, which is the
#      sabotage that the first version survived.

# Two, and the arithmetic is the reason rather than the evidence. The owner priced this pair at
# roughly a doubled fast tier -- 4.5 minutes to 9 -- and an armour campaign costs what a FAST one
# costs, so four seeds measured **15m05s** against the tier's 4m30s and two land a little over
# nine. The four-seed run is the number of record and it is in docs/23; these two are the ones the
# chain carries, and each is in the right direction on its own rather than only in the total. What
# makes that safe is that the statistic below is **structural, not statistical**: with no coverage
# anywhere every point swung at an unhurt colonist lands, so the bare arm reads 1.0000 by
# construction and a third seed reads 1.0000 as well.
const ARMOR_SEEDS: Array[int] = [20260805, 404]
# Mid-afternoon. Any fraction below `Clock.DAY_ENDS` behaves identically -- what this picks is the
# phase, not the hour -- and dawn and 0.35 measured byte-identical, which is how that was checked.
const ARMOR_WINDOW_AT: float = 0.35
# Half the FAST tier's window. Chosen because contact, not because of the clock: at the tier's own
# 2,000 the colony is swarmed hard enough that the sample below empties -- everybody is hurt within
# a day or two and there is nothing left that a blow can land on cleanly -- and at 300 two seeds in
# four record no contact at all. A thousand is where every seed is fought and somebody is still
# whole to measure it on.
const ARMOR_WINDOW_TICKS: int = 1000
# What the dressed arm has to find. Whole-body armour so the difference is not one sleeve: a vest,
# a helmet, gloves, jeans and boots, in the tiers a district actually drops.
const ARMOR_KIT: Array[String] = [
	"item.vest.riot", "item.helmet.bike", "item.gloves.leather",
	"item.jeans.denim", "item.boots.steel",
]

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
			print("M2_BALANCE_OK fast %d seeds, %d days, bands invariants placement, armour bare vs dressed on %d seeds, flag" % [FAST_SEEDS.size(), _days, ARMOR_SEEDS.size()])
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
	# Read before anything pins it, checked after everything has put it back. A static is shared by
	# every world this one process boots, so a lane that pins it and forgets is not a lane that
	# fails -- it is a lane that quietly changes every campaign after it.
	var flag_at_entry: bool = SimJobs.WEAR_FOUND_ARMOR
	var runs: Array[Dictionary] = []
	for seed_value in FAST_SEEDS:
		var run: Dictionary = _compressed_campaign(int(seed_value), "mixed")
		_print_run("FAST", run)
		runs.append(run)
	var ok: bool = _assert_invariants(runs)
	ok = _assert_bands(runs) and ok
	ok = _assert_the_seed_moves_placement(runs) and ok
	ok = _the_armed_count_can_see_an_empty_hand() and ok
	ok = _assert_grabs_reach_the_campaign(runs) and ok
	ok = _the_grab_counters_can_see_a_grab() and ok
	ok = _assert_armour_reaches_a_campaign() and ok
	ok = _the_dress_flag_went_back(flag_at_entry) and ok
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
		"withdrew": 0,
		# The raid, reported rather than banded. A band is a 20% roll on a post-grace night and a
		# ten-day campaign has three of those, so a floor here would be a coin toss; what the
		# harness owes is the number, plus the assertion that already covers it -- a colony wiped
		# out by raiders fails `survivors_end >= 1` like a colony wiped out by anything else.
		"raids": 0,
		"raiders_in": 0,
		"raiders_killed": 0,
		# Two id sets rather than two counters, resolved against each other in `_close_run`. See
		# the note in `_observe`'s `entity.killed` branch for why a count taken at event time
		# cannot tell a dead raider from a dead colonist.
		"dead_raiders": {},
		"dead_people": {},
		"kills": 0,
		"melee_kills": 0,
		"ranged_kills": 0,
		"deaths": 0,
		# The hold loop, counted off the bus like everything else here. `grab.started` is one per
		# hand that closes; `grab.broken` is one per victim who becomes fully free, tagged with why,
		# which is the only way a harness that reads nothing but events can tell an escape from a
		# rescue from a corpse. Asserted since the GRABS_ENABLED flip: `_assert_grabs_reach_the_campaign`
		# is the floor, `_the_grab_counters_can_see_a_grab` is the counters' own true negative.
		"grabs": 0,
		"broken": {},
		# Container searches by anybody but the player: the Scavenge job's reach into the district
		# (2026-09-06, the playable state). Reported, not banded.
		"npc_searches": 0,
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
			"container.searched":
				if int(ev.get("actor", -1)) != int(w.player):
					run["npc_searches"] = int(run["npc_searches"]) + 1
			"director.packet":
				run["packets"] = int(run["packets"]) + 1
			"director.raid":
				if int(ev.get("size", 0)) > 0:
					run["raids"] = int(run["raids"]) + 1
					run["raiders_in"] = int(run["raiders_in"]) + int(ev.get("size", 0))
			"raider.killed":
				(run["dead_raiders"] as Dictionary)[int(ev.get("entity", -1))] = true
			"raid.withdrew":
				run["withdrew"] = int(run.get("withdrew", 0)) + 1
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
					#
					# Set aside rather than counted, because at this instant a raider and a
					# colonist are indistinguishable and stay that way until `_close_run`. The
					# reason is a tick, and it is worth writing down: `entity.killed` is published
					# from a drain-time handler on tick N, while `raider.killed` comes from
					# `health.reap` -> `handle_death` in tick N+1's *cleanup* phase -- so a
					# per-tick pairing of the two never matches, and a first attempt at this
					# booked every dead raider as a colonist death anyway. By N+1 the body has
					# been despawned and carries no component that says what it was, which is why
					# the answer has to come off the bus rather than out of the store.
					(run["dead_people"] as Dictionary)[victim] = true
					continue
				if killer >= 0:
					# A raider thinning the horde on its way in is not the colony's kill, and
					# counting it would let an arm pass the risk-6 comparison on somebody else's
					# work. The killer is still queryable here: only the *victim* was despawned.
					if w.components.has_component(killer, "raider"):
						continue
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
		if live > SimDirector.live_cap_for(w):
			run["over_cap"] = int(run["over_cap"]) + 1
	if not before is Array:
		return
	for tile in _placed_since(w, before as Array[int]):
		(run["placements"] as Array).append("%d,%d" % [tile.x, tile.y])
		if not _legal_placement(w, tile):
			run["illegal_placements"] = int(run["illegal_placements"]) + 1


func _close_run(w: Variant, run: Dictionary) -> void:
	# The two id sets, settled. Everything that died and was not a zombie is in `dead_people`;
	# whichever of those the bus later named a raider comes back out. A colony death and a raider
	# death are the same event on the same tick, and only this difference tells them apart.
	var raiders: Dictionary = run["dead_raiders"] as Dictionary
	var people: Dictionary = run["dead_people"] as Dictionary
	run["raiders_killed"] = raiders.size()
	var colony: int = 0
	for id in people.keys():
		if not raiders.has(id):
			colony += 1
	run["deaths"] = colony
	run["survivors_end"] = _survivors_alive(w)
	run["run_over"] = bool(run["run_over"]) or bool(w.runOver)


func _print_run(label: String, run: Dictionary) -> void:
	print("%s seed=%d arm=%s days=%d siege=%d quiet=%d packets=%d raids=%d(%din/%ddown/%dleft) breaches=%d kills=%d(m%d/r%d) deaths=%d turned=%d recruits=%d max_live=%d survivors=%d/%d over=%s grabs=%d searches=%d broken=%s" % [
		label, int(run["seed"]), String(run["arm"]), int(run["days"]),
		int(run["siege_nights"]), int(run["quiet_nights"]), int(run["packets"]),
		int(run["raids"]), int(run["raiders_in"]), int(run["raiders_killed"]), int(run.get("withdrew", 0)),
		int(run["breaches"]), int(run["kills"]), int(run["melee_kills"]), int(run["ranged_kills"]),
		int(run["deaths"]), int(run["turned"]), int(run["recruits"]), int(run["max_live"]),
		int(run["survivors_end"]), int(run["survivors_start"]), str(run["run_over"]),
		int(run["grabs"]), int(run["npc_searches"]), str(run["broken"]),
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
			push_error("seed %d exceeded the live cap on %d ticks (max %d)" % [int(run["seed"]), int(run["over_cap"]), int(run["max_live"])])
			ok = false
		if int(run["survivors_start"]) < 1:
			push_error("seed %d booted with no survivors, so it measures nothing" % int(run["seed"]))
			ok = false
		if int(run["unarmed_at_boot"]) > 0:
			push_error("seed %d arm %s: %d colonist(s) started the campaign with nothing to fight with" % [int(run["seed"]), String(run["arm"]), int(run["unarmed_at_boot"])])
			ok = false
	if ok:
		print("INVARIANTS OK placement, cap %d at %d tiles, %d runs" % [SimDirector.live_cap_for(SimBoot.bare(int(FULL_SEEDS[0]), _tiles)["world"]), _tiles, runs.size()])
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


# The flip's dead-socket proof, and the promotion of two counters that spent the whole milestone
# bus-only. With GRABS_ENABLED shipping true, a compressed campaign must actually reach the hold
# loop: at least one seed records a grab, and at least one hold ends with a named cause. A zero
# here would mean the flag flipped and connected to nothing -- exactly the mechanism-nobody-reads
# shape CLAUDE.md's dead-socket list exists to catch. A floor, not a band: how *many* grabs a
# seed sees is pacing, and pacing belongs to the full tier.
func _assert_grabs_reach_the_campaign(runs: Array[Dictionary]) -> bool:
	var grabs: int = 0
	var causes: Dictionary = {}
	for run in runs:
		grabs += int(run["grabs"])
		for why in (run["broken"] as Dictionary).keys():
			causes[String(why)] = true
	if grabs < 1:
		push_error("no seed recorded a single grab with GRABS_ENABLED shipping true -- the flip reaches no campaign")
		return false
	if causes.is_empty():
		push_error("%d grabs and not one grab.broken cause -- holds start and never resolve, or the counter is dead" % grabs)
		return false
	print("GRABS OK %d grabs across %d seeds, broken causes %s" % [grabs, runs.size(), str(causes.keys())])
	return true


# The true negative for the counters the floor above reads: feed `_observe` one fabricated
# grab.started / grab.broken pair through a real drain and require each counter to move by
# exactly one. Without this, "grabs > 0" is worth exactly as much as the counter's ability to
# see a grab -- the `_the_armed_count_can_see_an_empty_hand` discipline, applied to the bus.
# Publish queues and handlers run at drain, at the end of world.step(), so the step sits
# between the publish and the read.
func _the_grab_counters_can_see_a_grab() -> bool:
	var w: Variant = _boot(int(FAST_SEEDS[0]), "mixed")
	var run: Dictionary = _blank_run(int(FAST_SEEDS[0]), "mixed", w)
	var grabs_before: int = int(run["grabs"])
	w.events.publish({"type": "grab.started", "victim": 999902, "source": 999901})
	w.events.publish({"type": "grab.broken", "victim": 999902, "by": 999901, "cause": "synthetic"})
	w.step()
	_observe(w, run, null)
	var moved: int = int(run["grabs"]) - grabs_before
	if moved != 1:
		push_error("one fabricated grab.started moved the grab counter by %d, expected exactly 1" % moved)
		return false
	if int((run["broken"] as Dictionary).get("synthetic", 0)) != 1:
		push_error("one fabricated grab.broken left the cause tally at %s, expected synthetic=1" % str(run["broken"]))
		return false
	print("GRAB-COUNTERS OK a fabricated started/broken pair moves each counter by exactly one")
	return true


# --- armour, the two arms ------------------------------------------------------------------

# One seed, two campaigns, one difference. Both arms boot the same world and both have the same
# armour laid at the colonists' feet; **BARE pins `SimJobs.WEAR_FOUND_ARMOR` off and DRESSED leaves
# it at the shipped default**, so the only thing that separates them is whether the acquisition
# rule is allowed to run. Nothing here equips anybody -- if the rule stops working the dressed arm
# goes bare and the first assertion below says so, which is the whole point of dressing the colony
# through the game's own rule instead of through the harness.
#
# Since colonists wear what they find, "the bare arm" can no longer mean "the tier as it is": the
# shipped rule dresses the colony, so the control has to be a colony that genuinely ends up wearing
# nothing, and pinning the flag is what makes it one.
func _assert_armour_reaches_a_campaign() -> bool:
	var was: bool = SimJobs.WEAR_FOUND_ARMOR
	var arms: Dictionary = {}
	for arm in ["bare", "dressed"]:
		var total: Dictionary = {"lost": 0.0, "offered": 0.0, "clean_lost": 0.0, "clean_offered": 0.0, "worn": 0, "dressed_by": 0, "bites": 0, "grabs": 0, "deaths": 0}
		for seed_value in ARMOR_SEEDS:
			var run: Dictionary = _armour_campaign(int(seed_value), String(arm))
			print("ARMOUR %-7s seed=%d dressed_by_day_one=%d worn_at_end=%d grabs=%d bites=%d offered=%.2f lost=%.2f unhurt=%.2f/%.2f through=%.4f deaths=%d survivors=%d" % [
				String(arm), int(run["seed"]), int(run["dressed_by"]), int(run["worn"]),
				int(run["grabs"]), int(run["bites"]), float(run["offered"]), float(run["lost"]),
				float(run["clean_lost"]), float(run["clean_offered"]),
				(float(run["clean_lost"]) / float(run["clean_offered"])) if float(run["clean_offered"]) > 0.0 else 0.0,
				int(run["deaths"]), int(run["alive"]),
			])
			for key in total.keys():
				if total[key] is float:
					total[key] = float(total[key]) + float(run[key])
				else:
					total[key] = int(total[key]) + int(run[key])
		arms[arm] = total
	# Put back before the assertions rather than after them: an early return below would otherwise
	# leave every campaign in the rest of this process running a rule the gate turned off.
	SimJobs.WEAR_FOUND_ARMOR = was
	var bare: Dictionary = arms["bare"] as Dictionary
	var dressed: Dictionary = arms["dressed"] as Dictionary
	# 1. The control is a control. If the bare arm ends up wearing anything the two arms are not
	#    the comparison this prints.
	if int(bare["dressed_by"]) != 0 or int(bare["worn"]) != 0:
		push_error("ARMOUR: the bare arm wore %d points of armour by the end of day one and %d at the end -- with WEAR_FOUND_ARMOR pinned off nobody may dress, so the control is not one" % [int(bare["dressed_by"]), int(bare["worn"])])
		return false
	# 2. And the treatment is a treatment. Zero here is the dead socket this slice exists to end:
	#    armour lying at somebody's feet for ten days that nobody ever picks up. Asked of the end of
	#    **day one**, not of the end of the campaign, and measured rather than assumed: on seed
	#    31337 the dressed colony wears 56 points through the run and finishes on zero, because the
	#    two who were wearing them died and a body that turns takes its equipment with it. The end
	#    of the campaign answers "who is still standing"; the question here is whether the rule
	#    fired at all.
	if int(dressed["dressed_by"]) <= 0:
		push_error("ARMOUR: the dressed arm had put on nothing by the end of day one, so both arms ran the same campaign and the acquisition rule reaches no colony")
		return false
	# 3. Both arms are decided. This is the assertion the dusk window fails -- it is not enough for
	#    the dressed arm to be no worse, the colony has to have been fought.
	if float(bare["offered"]) <= 0.0 or float(dressed["offered"]) <= 0.0:
		push_error("ARMOUR: no colonist was attacked in the %s arm (bare %.2f, dressed %.2f damage offered) -- this window measures no contact, so it decides nothing" % [
			("bare" if float(bare["offered"]) <= 0.0 else "dressed"), float(bare["offered"]), float(dressed["offered"]),
		])
		return false
	if float(bare["lost"]) <= 0.0 or float(dressed["lost"]) <= 0.0:
		push_error("ARMOUR: no integrity moved in the %s arm (bare %.2f, dressed %.2f) -- a campaign nobody was hurt in compares nothing" % [
			("bare" if float(bare["lost"]) <= 0.0 else "dressed"), float(bare["lost"]), float(dressed["lost"]),
		])
		return false
	# 4. And the direction, over unhurt colonists only, for the reason written out at ARMOR_SEEDS:
	#    anything clamped is saturation rather than armour, and a lane that cannot tell the two
	#    apart passes with the mitigation deleted. Measured on these two seeds at **1.0000 bare
	#    against 0.7213 dressed**, a 27.9% cut, and across all four of FAST_SEEDS by hand at 0.9802
	#    against 0.7076, a 27.8% cut -- the same answer, which is what a structural figure should do
	#    when seeds are added to it. There is nothing approximate about the bare number: with no
	#    coverage anywhere, every point swung at an unhurt colonist lands, exactly.
	if float(bare["clean_offered"]) <= 0.0 or float(dressed["clean_offered"]) <= 0.0:
		push_error("ARMOUR: no blow landed on an unhurt colonist in the %s arm -- the sample the direction is taken over is empty, so it decides nothing" % [
			"bare" if float(bare["clean_offered"]) <= 0.0 else "dressed",
		])
		return false
	var bare_through: float = float(bare["clean_lost"]) / float(bare["clean_offered"])
	var dressed_through: float = float(dressed["clean_lost"]) / float(dressed["clean_offered"])
	if dressed_through >= bare_through:
		push_error("ARMOUR: %.4f of the damage swung at an unhurt dressed colonist got through, against %.4f at a bare one (%.2f of %.2f, against %.2f of %.2f) -- armour is not reaching the campaign" % [
			dressed_through, bare_through, float(dressed["clean_lost"]), float(dressed["clean_offered"]),
			float(bare["clean_lost"]), float(bare["clean_offered"]),
		])
		return false
	print("ARMOUR OK %d seeds: bare wears 0 and takes %.4f of every blow it is unhurt for (%.2f of %.2f); dressed wears %d by day one and takes %.4f (%.2f of %.2f), a %.1f%% cut. Raw integrity lost over the whole colony, deaths and all, %.2f against %.2f" % [
		ARMOR_SEEDS.size(), bare_through, float(bare["clean_lost"]), float(bare["clean_offered"]),
		int(dressed["dressed_by"]), dressed_through, float(dressed["clean_lost"]), float(dressed["clean_offered"]),
		100.0 * (1.0 - dressed_through / bare_through), float(bare["lost"]), float(dressed["lost"]),
	])
	return true


# The lane that catches the static being left where a campaign put it. Not the same claim as "the
# rule works": this one is about the harness, and it is what would say so if the arm above pinned
# the flag off and returned early on a failed assertion -- every campaign after it would then have
# run a colony that cannot dress, and nothing else here would say a word.
func _the_dress_flag_went_back(at_entry: bool) -> bool:
	if not at_entry:
		push_error("FLAG: SimJobs.WEAR_FOUND_ARMOR was already off when this gate started -- the shipped default is on, so every run above measured a game nobody plays")
		return false
	if SimJobs.WEAR_FOUND_ARMOR != at_entry:
		push_error("FLAG: SimJobs.WEAR_FOUND_ARMOR entered as %s and left as %s -- a lane pinned the static and did not put it back" % [str(at_entry), str(SimJobs.WEAR_FOUND_ARMOR)])
		return false
	print("FLAG OK WEAR_FOUND_ARMOR shipped on, pinned off by the bare arm, and back on at the end")
	return true


# The campaign the two arms share: the FAST tier's compression technique with the jump moved into
# the working day, for the reason written out at ARMOR_WINDOW_AT. Everything counted is read off
# the world or off the bus, so this adds no simulation state and cannot change what it measures.
#
# **Integrity lost is sampled, because nothing publishes it.** The one closure that moves a body
# (`SimHealth.damage_part`) computes what it took and keeps it, so the roster is fixed at boot and
# every colonist's body totalled each tick, with only *drops* added: healing between two samples
# resets the baseline instead of subtracting, so this counts damage done rather than net condition.
# A colonist whose `body` component is gone stops contributing from that moment -- without that,
# a death books the whole 185 points of a body as damage and one death then swamps every blow in
# the campaign. The roster is fixed at boot on purpose too: a recruit who walks in on day six joins
# one arm's campaign and not necessarily the other's.
#
# **Damage offered is the same events' own `damage` field**, read before `damage_part` touches it.
#
# The `clean_` pair is the one the direction is decided on, and it is the whole of what the sabotage
# pass forced: a colonist counts only while **every part of them is still above zero**, and a tick
# on which one of them stops being is thrown away whole rather than half-counted. `damage_part`
# clamps at zero, so a blow at a part that has already run out is recorded as offered and lands as
# less than it offered -- through no armour at all. Filtering that out is what leaves a figure that
# only coverage can move: every point swung at an unhurt bare colonist lands, exactly, and the bare
# arm reading anything but 1.0000 would itself be news.
func _armour_campaign(seed_value: int, arm: String) -> Dictionary:
	SimJobs.WEAR_FOUND_ARMOR = arm != "bare"
	var w: Variant = SimBoot.playable(seed_value, _tiles, _district())["world"]
	var roster: Array[int] = _colonists(w)
	_lay_out_armour(w, roster)
	w.events.drain()
	var last: Dictionary = {}
	var unhurt: Dictionary = {}
	for ent in roster:
		var read: Array = _body_read(w, int(ent))
		last[int(ent)] = float(read[0]) if not read.is_empty() else null
		unhurt[int(ent)] = (not read.is_empty()) and bool(read[1])
	var run: Dictionary = {
		"seed": seed_value, "arm": arm, "lost": 0.0, "offered": 0.0,
		"clean_lost": 0.0, "clean_offered": 0.0,
		"bites": 0, "grabs": 0, "deaths": 0, "worn": 0, "dressed_by": 0, "alive": 0,
	}
	var dead: Dictionary = {}
	# Reused rather than rebuilt each tick: a Dictionary is a reference type, and one allocation per
	# tick across eight campaigns is not free.
	var swung: Dictionary = {}
	for day in range(1, _days + 1):
		w.tick = Clock.tick_on_day(day, ARMOR_WINDOW_AT) - 1
		for _t in ARMOR_WINDOW_TICKS + 1:
			swung.clear()
			w.step()
			for e in w.events.drained:
				var ev: Dictionary = e as Dictionary
				match String(ev.get("type", "")):
					"bite.landed":
						var bitten: int = int(ev.get("victim", -1))
						if roster.has(bitten):
							run["bites"] = int(run["bites"]) + 1
							run["offered"] = float(run["offered"]) + float(ev.get("damage", 0.0))
							swung[bitten] = float(swung.get(bitten, 0.0)) + float(ev.get("damage", 0.0))
					"attack.connected":
						var hit: int = int(ev.get("target", -1))
						if roster.has(hit):
							run["offered"] = float(run["offered"]) + float(ev.get("damage", 0.0))
							swung[hit] = float(swung.get(hit, 0.0)) + float(ev.get("damage", 0.0))
					"grab.started":
						if roster.has(int(ev.get("victim", -1))):
							run["grabs"] = int(run["grabs"]) + 1
					"entity.killed":
						# De-duplicated by id: one individual is announced up to three times.
						if roster.has(int(ev.get("entity", -1))):
							dead[int(ev.get("entity", -1))] = true
			for ent in roster:
				var before: Variant = last[int(ent)]
				if before == null:
					continue
				# One walk of the body, not two: this runs on every colonist on every tick of eight
				# campaigns, and asking the same dictionary the same question twice cost minutes.
				var read: Array = _body_read(w, int(ent))
				if read.is_empty():
					last[int(ent)] = null
					unhurt[int(ent)] = false
					continue
				var now: float = float(read[0])
				var still: bool = bool(read[1])
				var drop: float = float(before) - now
				if drop > 0.0:
					run["lost"] = float(run["lost"]) + drop
				# Whole and whole again: only then is `drop` the blow and nothing else.
				if bool(unhurt[int(ent)]) and still:
					run["clean_lost"] = float(run["clean_lost"]) + maxf(0.0, drop)
					run["clean_offered"] = float(run["clean_offered"]) + float(swung.get(int(ent), 0.0))
				unhurt[int(ent)] = still
				last[int(ent)] = now
		if day == 1:
			run["dressed_by"] = _armour_points_worn(w, roster)
	run["deaths"] = dead.size()
	run["alive"] = _survivors_alive(w)
	run["worn"] = _armour_points_worn(w, roster)
	return run


# Parts do not share a scale (a head is 15, a torso 40) and the total below deliberately does not
# care: it is the same sum on both arms of the same seed, and what is compared is two campaigns
# rather than any one body's condition. Nothing here is published, stored or shown -- the
# health-bar ban is about what the *screen* can compute, and this is a harness reading the sim from
# outside it.
#
# One pass over a body answering both questions the sampler asks of it: `[total, every part above
# zero]`, or an empty array when there is no body left. Intactness is asked of the *parts* rather
# than of the total, because a total says nothing about whether the next blow to a hand will be
# clamped, and clamping is the one thing the clean sample must not contain.
func _body_read(w: Variant, ent: int) -> Array:
	var body: Variant = w.components.get_component(ent, "body")
	if not body is Dictionary:
		return []
	var total: float = 0.0
	var whole: bool = true
	for part in (body as Dictionary).keys():
		var v: float = float((body as Dictionary)[part])
		total += v
		if v <= 0.0:
			whole = false
	return [total, whole]


# A set of armour per colonist, on the tile they are standing on. Not a kit and not an equip: it is
# a pile on the floor, which is the one state the acquisition rule can reach in a harness whose
# colony never opens a cupboard, and the state a Haul leaves every load in. The bare arm gets the
# identical pile and walks past it for ten days.
func _lay_out_armour(w: Variant, roster: Array[int]) -> void:
	for ent in roster:
		var at: Variant = w.components.get_component(int(ent), "position")
		if not at is Dictionary:
			continue
		for id in ARMOR_KIT:
			var item: int = SimItems.spawn_item(w, String(id), {"tier": "scavenged"})
			w.components.set_component(item, "position", (at as Dictionary).duplicate())


# How much armour the colony finished wearing, in `armor_points_of_base`'s whole-body points -- the
# same scalar the dress rule itself decides with, so "the bare arm wears nothing" is asked in the
# units the rule under test answers in.
func _armour_points_worn(w: Variant, roster: Array[int]) -> int:
	var total: int = 0
	for ent in roster:
		for item in SimInventory.equipped_items(w, int(ent)):
			var base: Variant = SimItems.item_base_of(w, int(item))
			if base is Dictionary:
				total += SimNeeds.armor_points_of_base(base as Dictionary)
	return total


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
	# The director's first `GRACE_NIGHTS` nights are grace, so a grid shortened to fewer days is
	# a grid nothing attacked, and an arm cannot be judged on a campaign it was never pressured
	# in. Refuse to assert rather than assert on no data, and say so loudly.
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
	var w: Variant = SimBoot.playable(int(FULL_SEEDS[0]), _tiles)["world"]
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

# Which district the harness boots. The suburb unless `BALANCE_DISTRICT` names another, because
# the FAST tier's bands are suburb-measured and belong to the suburb: a second district's column
# is run BY HAND and recorded beside them, never folded into the 85-second chain, where it would
# quietly re-baseline numbers the owner arbitrated. With the variable unset this is the constant
# it always was, so the chain's four FAST lines cannot move.
func _district() -> String:
	var named: String = OS.get_environment("BALANCE_DISTRICT")
	return named if not named.is_empty() else SimBoot.DEFAULT_DISTRICT


func _boot(seed_value: int, arm: String) -> Variant:
	var w: Variant = SimBoot.playable(seed_value, _tiles, _district())["world"]
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
