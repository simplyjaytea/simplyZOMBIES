extends SceneTree
# Aiming sway: cone half-angle tightens on Steady, widens when moving (ADR 0012) -- and, since
# 2026-09-10, the three rungs of that ladder are the weapon's own rather than three constants every
# firearm shared.
#
# docs/09-combat.md:76 states the ladder as "raise -> steady -> fire -> recover -> (reload)" and
# :153 says a crossbow's rate of fire is "much slower". Only `reloadTicks` was ever per-weapon, so
# the second claim was true of the reload and of nothing else: a submachine gun and a bolt rifle
# came up, settled and recovered in exactly the same number of ticks. `ranged.weight` is the
# content field that fixes it, mirroring `melee.weight`, and `handling` is the multiplier
# attachments fold in against it.
#
# The lanes below are arranged so that reverting any part of that turns one of them red. HEFT reads
# the number the ladder actually set; CONE catches the subtler half -- `_refresh_cone` used the
# shared constants as its lerp *denominators*, and `lerpf` does not clamp, so a heavy weapon
# extrapolated past WIDE_HALF and was saved only by the clampf at the bottom while a light one
# started already half-tightened. Bounded, silent, wrong, and invisible to any assertion that only
# looks at tick counts.

const SimBoot = preload("res://sim/boot.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")

# Weapon, its ammunition, and the `ranged.weight` its base declares. The weight is written out
# here rather than read off the content on purpose: a gate that reads the value under test and
# compares it to itself is a gate that cannot fail. check_worn.gd's EXPECT_ORDER is the precedent.
const HEFT: Dictionary = {
	"item.pistol.service": {"ammo": "item.ammo.9mm", "weight": 1.0},
	"item.revolver.snub": {"ammo": "item.ammo.38", "weight": 1.0},
	"item.crossbow.hunting": {"ammo": "item.ammo.bolt", "weight": 1.6},
	"item.shotgun.pump": {"ammo": "item.ammo.12g", "weight": 1.4},
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _sway_tightens_and_widens() and ok
	ok = _the_ladder_runs_on_the_weapons_own_clock() and ok
	ok = _the_cone_is_normalised_to_each_weapons_rung() and ok
	ok = _a_ruined_arm_widens_the_cone_and_an_intact_one_does_not() and ok
	ok = _recovery_after_a_shot_is_per_weapon() and ok
	if not ok:
		push_error("M2_AIM_FAIL")
		quit(1)
		return
	print("M2_AIM_OK sway heft cone arm recover")
	quit(0)


func _world() -> Variant:
	var boot: Dictionary = SimBoot.playable(20260805, 64)
	return boot["world"]


## Equips `id` with ammunition and returns the live `rangedWeapon` dictionary, or null.
func _armed(w: Variant, id: String) -> Variant:
	var weapon: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, weapon):
		push_error("%s: equip refused" % id)
		return null
	var ammo_id: String = String((HEFT[id] as Dictionary).get("ammo", ""))
	var ammo: int = SimItems.spawn_item(w, ammo_id, {"tier": "scavenged", "count": 20})
	if not SimInventory.stow(w, w.player, ammo):
		w.components.set_component(ammo, "stored", {"container": w.player})
	# The equip event is what builds the profile, and publish() only queues -- without this the
	# component is not there yet and every assertion below would judge an unarmed survivor.
	w.events.drain()
	var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
	if not rw is Dictionary:
		push_error("%s: no rangedWeapon after equip" % id)
		return null
	var vel: Variant = w.components.get_component(w.player, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0
	return rw


## Puts the *person* out of the way so a lane can measure the *weapon*. `_refresh_cone` adds a
## penalty for low stamina and one for a ruined arm, and both saturate at WIDE_HALF, which is
## enough to swamp anything a rung is doing.
##
## The arm line keeps the arm penalty off the cone lanes: arms at 40 read Unhurt, so neither lane
## is charged for a limb. ARM (below) is the lane that charges a ruined arm and an intact one apart.
func _steady_hands(w: Variant) -> void:
	var body: Variant = w.components.get_component(w.player, "body")
	if body is Dictionary:
		(body as Dictionary)["arm_left"] = 40.0
		(body as Dictionary)["arm_right"] = 40.0
	var stam: Variant = w.components.get_component(w.player, "stamina")
	if stam is Dictionary:
		(stam as Dictionary)["current"] = float((stam as Dictionary).get("max", 100))


# --- sway (the original lane, unchanged in intent) ----------------------------------------------

func _sway_tightens_and_widens() -> bool:
	var w: Variant = _world()
	var rw: Variant = _armed(w, "item.pistol.service")
	if not rw is Dictionary:
		return false
	var r: Dictionary = rw as Dictionary
	r["state"] = SimRanged.FireState.Raise
	r["ticksLeft"] = SimCombat.raise_ticks(1.0, 1.0)
	SimRanged._refresh_cone(w, w.player, r)
	var raise_half: float = float(r["coneHalf"])
	r["state"] = SimRanged.FireState.Steady
	r["ticksLeft"] = 1
	SimRanged._refresh_cone(w, w.player, r)
	var steady_half: float = float(r["coneHalf"])
	if steady_half >= raise_half:
		push_error("SWAY: steady should tighten: raise=%s steady=%s" % [raise_half, steady_half])
		return false
	var vel: Variant = w.components.get_component(w.player, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 2.0
	SimRanged._refresh_cone(w, w.player, r)
	var move_half: float = float(r["coneHalf"])
	if move_half < SimRanged.WIDE_HALF - 0.001:
		push_error("SWAY: moving should widen to WIDE: %s" % move_half)
		return false
	print("SWAY OK raise %.3f steady %.3f move %.3f" % [raise_half, steady_half, move_half])
	return true


# --- heft ---------------------------------------------------------------------------------------
#
# The positive: the raise the ladder sets is the one `SimCombat.raise_ticks` derives from the
# weapon's declared heft, per weapon. The negatives are both here rather than in a comment: two
# weapons of *equal* weight must agree (so the lane cannot pass on any arrangement that merely
# returns different numbers), and a heavy weapon must be strictly slower than a light one (so
# reverting `_raise_of` to the old shared constant makes every weapon 8 and fails the comparison).

func _the_ladder_runs_on_the_weapons_own_clock() -> bool:
	var seen: Dictionary = {}
	for id_v in HEFT.keys():
		var id: String = String(id_v)
		var w: Variant = _world()
		var rw: Variant = _armed(w, id)
		if not rw is Dictionary:
			return false
		if not SimRanged.try_begin_fire(w, w.player):
			push_error("HEFT: %s refused to begin firing" % id)
			return false
		var r: Dictionary = w.components.get_component(w.player, "rangedWeapon") as Dictionary
		if int(r["state"]) != SimRanged.FireState.Raise:
			push_error("HEFT: %s is not raising after try_begin_fire" % id)
			return false
		var weight: float = float((HEFT[id] as Dictionary)["weight"])
		var want: int = SimCombat.raise_ticks(weight, 1.0)
		var got: int = int(r["ticksLeft"])
		if got != want:
			push_error("HEFT: %s raises in %d ticks, want %d for weight %s" % [id, got, want, weight])
			return false
		if absf(float(r.get("weight", -1.0)) - weight) > 0.001:
			push_error("HEFT: %s profile carries weight %s, content declares %s" % [id, r.get("weight", -1.0), weight])
			return false
		seen[id] = got
	# A heavy weapon is strictly slower to the shoulder than a light one. This is the assertion the
	# old shared constant fails: it made every entry here 8.
	if int(seen["item.crossbow.hunting"]) <= int(seen["item.pistol.service"]):
		push_error("HEFT: a crossbow comes up in %d ticks and a pistol in %d -- the ladder is not reading the weapon" % [int(seen["item.crossbow.hunting"]), int(seen["item.pistol.service"])])
		return false
	# ... and two weapons of the same declared heft agree, so the lane is judging weight rather
	# than merely noticing that two weapons are different objects.
	if int(seen["item.pistol.service"]) != int(seen["item.revolver.snub"]):
		push_error("HEFT: a pistol and a revolver both declare weight 1.0 and raise in %d and %d" % [int(seen["item.pistol.service"]), int(seen["item.revolver.snub"])])
		return false
	print("HEFT OK pistol %d, revolver %d, shotgun %d, crossbow %d ticks to the shoulder" % [int(seen["item.pistol.service"]), int(seen["item.revolver.snub"]), int(seen["item.shotgun.pump"]), int(seen["item.crossbow.hunting"])])
	return true


# --- the cone -----------------------------------------------------------------------------------
#
# Halfway up is halfway tightened, whatever the weapon weighs. `_refresh_cone` lerps across the
# rung, so the *fraction* of the rung is what decides the cone; if the denominator is a shared
# constant instead of this weapon's own raise, a crossbow at half its raise reads as a quarter of
# the way up and this lane goes red. That is the whole point of it -- a tick-count assertion cannot
# see this, because the tick counts are right either way.

func _the_cone_is_normalised_to_each_weapons_rung() -> bool:
	var cones: Dictionary = {}
	for id_v in ["item.pistol.service", "item.crossbow.hunting"]:
		var id: String = String(id_v)
		var w: Variant = _world()
		var rw: Variant = _armed(w, id)
		if not rw is Dictionary:
			return false
		_steady_hands(w)
		var r: Dictionary = rw as Dictionary
		var weight: float = float((HEFT[id] as Dictionary)["weight"])
		var full: int = SimCombat.raise_ticks(weight, 1.0)
		if full < 4:
			push_error("CONE: %s raises in %d ticks, too few for a halfway point to mean anything" % [id, full])
			return false
		r["state"] = SimRanged.FireState.Raise
		r["ticksLeft"] = full / 2
		SimRanged._refresh_cone(w, w.player, r)
		cones[id] = float(r["coneHalf"])
	var light: float = float(cones["item.pistol.service"])
	var heavy: float = float(cones["item.crossbow.hunting"])
	# Integer halves differ by at most one tick out of the rung, so the tolerance is a tick's worth
	# of the lerp rather than an arbitrary epsilon.
	var slack: float = (SimRanged.WIDE_HALF - SimRanged.TIGHT_HALF) * 0.5 / float(SimCombat.raise_ticks(1.0, 1.0))
	if absf(light - heavy) > slack:
		push_error("CONE: halfway up, a pistol sits at %.4f and a crossbow at %.4f -- the lerp is not normalised to each weapon's own rung" % [light, heavy])
		return false
	if light >= SimRanged.WIDE_HALF - 0.0001:
		push_error("CONE: halfway up is still fully wide (%.4f), so this lane is comparing two saturated values and proves nothing" % light)
		return false
	print("CONE OK halfway up reads %.4f for a pistol and %.4f for a crossbow" % [light, heavy])
	return true


# --- a ruined arm, and only a ruined arm --------------------------------------------------------
#
# The arm penalty is for an arm the normaliser calls BadlyHurt or worse. Before the fix it read raw
# integrity against 25, so an intact arm (20 of its own 20) was penalised for every survivor, and a
# ruined arm (4 of 20) cost exactly what an intact one did. Judged at Steady, where the cone sits
# well off saturation: at Idle the penalty clamps back to WIDE_HALF and cannot show.

func _a_ruined_arm_widens_the_cone_and_an_intact_one_does_not() -> bool:
	var cones: Dictionary = {}
	for label in ["neutral", "intact", "ruined"]:
		var w: Variant = _world()
		var rw: Variant = _armed(w, "item.pistol.service")
		if not rw is Dictionary:
			return false
		_steady_hands(w)
		var body: Variant = w.components.get_component(w.player, "body")
		if not body is Dictionary:
			push_error("ARM: no body on the player")
			return false
		var b: Dictionary = body as Dictionary
		match label:
			"neutral":
				b["arm_left"] = 40.0
				b["arm_right"] = 40.0
			"intact":
				b["arm_left"] = 20.0
				b["arm_right"] = 20.0
			"ruined":
				b["arm_left"] = 4.0
				b["arm_right"] = 20.0
		var r: Dictionary = rw as Dictionary
		r["state"] = SimRanged.FireState.Steady
		r["ticksLeft"] = SimRanged._steady_of(r)
		SimRanged._refresh_cone(w, w.player, r)
		cones[label] = float(r["coneHalf"])
	var neutral: float = float(cones["neutral"])
	var intact: float = float(cones["intact"])
	var ruined: float = float(cones["ruined"])
	if absf(intact - neutral) > 0.0001:
		push_error("ARM: an intact survivor's cone is %.4f against %.4f with no arm penalty -- a healthy arm is being charged" % [intact, neutral])
		return false
	if ruined <= intact + 0.05:
		push_error("ARM: a ruined arm's cone is %.4f against an intact one's %.4f -- a ruined arm costs nothing" % [ruined, intact])
		return false
	print("ARM OK intact %.4f matches neutral, ruined widens to %.4f" % [intact, ruined])
	return true


# --- recovery -----------------------------------------------------------------------------------
#
# The third rung, and the one that is rate of fire. Asserted by firing rather than by asking the
# helper, because a helper returning the right number is not evidence that anything reads it.

func _recovery_after_a_shot_is_per_weapon() -> bool:
	var got: Dictionary = {}
	for id_v in ["item.pistol.service", "item.shotgun.pump"]:
		var id: String = String(id_v)
		var w: Variant = _world()
		var rw: Variant = _armed(w, id)
		if not rw is Dictionary:
			return false
		if not SimRanged.try_begin_fire(w, w.player):
			push_error("RECOVER: %s refused to begin firing" % id)
			return false
		var observed: int = -1
		for _i in range(200):
			w.step()
			var r: Variant = w.components.get_component(w.player, "rangedWeapon")
			if not r is Dictionary:
				break
			var st: int = int((r as Dictionary)["state"])
			if st == SimRanged.FireState.Clearing:
				# A jam is legal and is not what this lane measures. Say so and skip rather than
				# passing quietly on a run that never reached the rung.
				print("RECOVER SKIP %s jammed before it recovered" % id)
				observed = -2
				break
			if st == SimRanged.FireState.Recover:
				observed = int((r as Dictionary)["ticksLeft"])
				break
		if observed == -2:
			continue
		if observed < 0:
			push_error("RECOVER: %s never reached Recover in 200 ticks" % id)
			return false
		var weight: float = float((HEFT[id] as Dictionary)["weight"])
		var want: int = SimCombat.shot_recover_ticks(weight, 1.0)
		# The rung is read on the tick it is entered, so the count is the full rung less the tick
		# already spent getting here.
		if observed != want and observed != want - 1:
			push_error("RECOVER: %s recovers in %d ticks, want %d for weight %s" % [id, observed, want, weight])
			return false
		got[id] = observed
	if got.size() < 2:
		print("RECOVER SKIP fewer than two weapons reached the rung")
		return true
	if int(got["item.shotgun.pump"]) <= int(got["item.pistol.service"]):
		push_error("RECOVER: a shotgun recovers in %d ticks and a pistol in %d -- recovery is not reading the weapon" % [int(got["item.shotgun.pump"]), int(got["item.pistol.service"])])
		return false
	print("RECOVER OK pistol %d, shotgun %d ticks between shots" % [int(got["item.pistol.service"]), int(got["item.shotgun.pump"])])
	return true
