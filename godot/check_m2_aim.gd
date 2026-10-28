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
#
# HEADING is aim as a second heading, priced at a walk (sim/aim.gd; docs/30's decoupled paperdoll,
# decision 7; alpha plan A9 with the owner's 2026-10-19 answer to Q3, the cursor is the aimer). A
# stationary body turns feet and aim to a proposal; a walking one keeps its heading and turns only
# its aim; a jogging one refuses the proposal and has a held aim snapped back to the heading; the
# shot, the swing and the eyes read the aim; a moving shooter aiming away from where it walks has
# its cone widened *past* WIDE_HALF, in proportion to the turn; anything else that turns a body
# turns its aim. True negatives throughout: a body never aimed has no `aim` and reads its facing, a
# walking shooter aiming where it walks pays nothing extra, and a standing one pays nothing at all.

const SimBoot = preload("res://sim/boot.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimAim = preload("res://sim/aim.gd")
const SimStances = preload("res://sim/stances.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")

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
	ok = _aim_is_a_second_heading_priced_at_a_walk() and ok
	ok = _furniture_moves_the_aim_and_the_recovery() and ok
	ok = _item_scoped_clocks_move_the_ladder_and_nothing_else() and ok
	if not ok:
		push_error("M2_AIM_FAIL")
		quit(1)
		return
	print("M2_AIM_OK sway heft cone arm recover heading furniture readers")
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
	SimRanged.load_held(w, w.player)
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
		r["ticksLeft"] = SimRanged._steady_of(w, r)
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


# --- heading ------------------------------------------------------------------------------------

func _stand(w: Variant) -> void:
	w.commands.push({"type": "move", "dx": 0.0, "dy": 0.0})
	w.step()


func _walk_east(w: Variant, stance: int) -> void:
	var posture: Dictionary = w.components.get_component(w.player, "posture") as Dictionary
	posture["current"] = stance
	posture["target"] = stance
	posture["ticks_left"] = 0
	w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
	w.step()


func _facing_of(w: Variant) -> float:
	return float((w.components.get_component(w.player, "facing") as Dictionary)["radians"])


func _aim_is_a_second_heading_priced_at_a_walk() -> bool:
	var lane: String = "HEADING"
	var w: Variant = _world()
	# A body never aimed has no `aim`, and reads its facing.
	if w.components.has_component(w.player, "aim"):
		push_error("%s: the player carries an aim nobody proposed" % lane)
		return false
	_stand(w)
	if SimAim.radians_of(w.components, w.player) != _facing_of(w):
		push_error("%s: a body with no aim does not read its facing" % lane)
		return false
	SimAim.follow_facing(w.components, w.player)
	if w.components.has_component(w.player, "aim"):
		push_error("%s: follow_facing grew an aim on a body that had none" % lane)
		return false

	# Standing still: feet and aim both turn to the proposal.
	w.commands.push({"type": "aim", "radians": 1.0})
	w.step()
	if absf(_facing_of(w) - 1.0) > 1e-6 or absf(SimAim.radians_of(w.components, w.player) - 1.0) > 1e-6:
		push_error("%s: a standing body aimed at 1.0 faces %.3f and aims %.3f" % [lane, _facing_of(w), SimAim.radians_of(w.components, w.player)])
		return false

	# Walking east and aiming north: the feet keep east, the aim holds north, the cone is priced.
	var rw: Variant = _armed(w, "item.pistol.service")
	if not rw is Dictionary:
		return false
	_steady_hands(w)
	_walk_east(w, SimStances.Stance.Walk)
	# Aimed where it walks first: the standing aim of 1.0 is still held, and walking east under it
	# is already a twist.
	w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
	w.commands.push({"type": "aim", "radians": 0.0})
	w.step()
	var straight_half: float = 0.0
	SimRanged._refresh_cone(w, w.player, rw as Dictionary)
	straight_half = float((rw as Dictionary)["coneHalf"])
	w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
	w.commands.push({"type": "aim", "radians": -PI / 2.0})
	w.step()
	if absf(_facing_of(w)) > 1e-6 or absf(SimAim.radians_of(w.components, w.player) + PI / 2.0) > 1e-6:
		push_error("%s: walking east aimed north faces %.3f and aims %.3f; want 0 and -PI/2" % [lane, _facing_of(w), SimAim.radians_of(w.components, w.player)])
		return false
	SimRanged._refresh_cone(w, w.player, rw as Dictionary)
	var twisted_half: float = float((rw as Dictionary)["coneHalf"])
	var want_twisted: float = SimRanged.WIDE_HALF + SimRanged.TWIST_WIDEN * 0.5
	if absf(straight_half - SimRanged.WIDE_HALF) > 1e-6 or absf(twisted_half - want_twisted) > 1e-4:
		push_error("%s: walking straight the cone is %.4f (want WIDE_HALF %.4f) and aimed a quarter turn away %.4f (want %.4f, past WIDE_HALF)" % [lane, straight_half, SimRanged.WIDE_HALF, twisted_half, want_twisted])
		return false
	# The eyes follow the aim: a point four metres north is seen better than one four metres south.
	var p: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	var north: int = int(w.vision.detail(int(w.player), float(p["x"]), float(p["y"]) - 4.0))
	var south: int = int(w.vision.detail(int(w.player), float(p["x"]), float(p["y"]) + 4.0))
	if north <= south:
		push_error("%s: walking east aimed north, the eyes see north at detail %d and south at %d" % [lane, north, south])
		return false

	# Standing still twisted is free: the feet turn with the aim, so there is no twist to price.
	_stand(w)
	w.commands.push({"type": "aim", "radians": PI / 2.0})
	w.step()
	SimRanged._refresh_cone(w, w.player, rw as Dictionary)
	if SimAim.twist(w.components, w.player) > 1e-6 or float((rw as Dictionary)["coneHalf"]) > SimRanged.WIDE_HALF + 1e-6:
		push_error("%s: a standing body that turned to its aim still pays %.4f (twist %.3f)" % [lane, float((rw as Dictionary)["coneHalf"]), SimAim.twist(w.components, w.player)])
		return false

	# Jogging: a proposal is refused, and a held aim snaps back to the heading.
	_walk_east(w, SimStances.Stance.Walk)
	w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
	w.commands.push({"type": "aim", "radians": -PI / 2.0})
	w.step()
	_walk_east(w, SimStances.Stance.Jog)
	if absf(SimAim.radians_of(w.components, w.player) - _facing_of(w)) > 1e-6:
		push_error("%s: jogging east the aim stayed at %.3f; it should snap to the heading %.3f" % [lane, SimAim.radians_of(w.components, w.player), _facing_of(w)])
		return false
	w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
	w.commands.push({"type": "aim", "radians": PI / 2.0})
	w.step()
	if absf(SimAim.radians_of(w.components, w.player) - _facing_of(w)) > 1e-6:
		push_error("%s: a jogging body took an aim proposal of PI/2 (aims %.3f)" % [lane, SimAim.radians_of(w.components, w.player)])
		return false

	# An NPC turn turns the aim: a stale proposal never points the swing a turn is for.
	_stand(w)
	(w.components.get_component(w.player, "posture") as Dictionary)["current"] = SimStances.Stance.Walk
	w.commands.push({"type": "aim", "radians": PI})
	w.step()
	SimNpcCombat._face_at(w, w.player, float(p["x"]), float(p["y"]) - 3.0)
	if absf(SimAim.radians_of(w.components, w.player) - _facing_of(w)) > 1e-6:
		push_error("%s: an NPC turn left the aim at %.3f behind a body facing %.3f" % [lane, SimAim.radians_of(w.components, w.player), _facing_of(w)])
		return false

	# The shot, the swing and the eyes read the aim, not the facing -- and the needle can fail.
	for path in ["res://sim/modules/ranged.gd", "res://sim/modules/melee.gd", "res://sim/vision/visibility.gd"]:
		if not _reads_aim(FileAccess.get_file_as_string(path)):
			push_error("%s: %s does not read the aim" % [lane, path])
			return false
	if _reads_aim("\t# SimAimRes.radians_of(world.components, x)\n") or not _reads_aim("\tvar a: float = SimAimRes.radians_of(world.components, x)\n"):
		push_error("%s: the aim-reader scan passed a commented read or refused a real one" % lane)
		return false
	print("HEADING OK a body never aimed reads its facing and grows no aim; standing still turns feet and aim; walking east aimed north keeps the feet east, sees north better than south, and widens the cone from %.3f to %.3f (past WIDE_HALF); standing twisted is free; jogging refuses a proposal and snaps a held aim back; an NPC turn turns the aim; the shot, the swing and the eyes read it" % [straight_half, twisted_half])
	return true


# Whether a source reads the aim in code, not in a comment.
func _reads_aim(src: String) -> bool:
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("#") and line.contains("SimAimRes.radians_of(world.components, "):
			return true
	return false


# --- furniture (F4) -----------------------------------------------------------------------------

# The handling each piece of furniture declares, written out here on purpose: a gate that reads the
# multiplier under test and compares it to itself cannot fail (HEFT's rule). The expected value still
# goes through the part's condition, the way the fold does, so a worn stock is judged as worn.
const FURNITURE_HANDLING: Dictionary = {
	"item.attach.furniture.folding": 1.35,
	"item.attach.underbarrel.grip": 1.15,
}

# Which slot each variant fits, for the variants that add a part rather than take the stock off.
const FITS: Dictionary = {
	"folding": ["item.attach.furniture.folding", "furniture"],
	"grip": ["item.attach.underbarrel.grip", "underbarrel"],
}


# Furniture is the ergonomics the ladder reads: a folding stock and a vertical foregrip bring the
# weapon up quicker, and a quicker weapon also comes back down sooner after a shot. The true negative
# is a receiver with no stock, and the standard stock declares no ergonomics of its own: both must sit
# at the numbers the ladder had before furniture was read at all. Each variant is refit on a fresh
# world and read the way the trigger reads it, so a lane that passes is the ladder's own clock.
func _furniture_moves_the_aim_and_the_recovery() -> bool:
	var id: String = "item.shotgun.pump"
	var weight: float = float((HEFT[id] as Dictionary)["weight"])
	var got: Dictionary = {}
	for variant in ["bare", "standard", "folding", "grip"]:
		got[variant] = _refit(id, variant)
		if (got[variant] as Dictionary).is_empty():
			return false
	var old_raise: int = SimCombat.raise_ticks(weight, 1.0)
	var old_recover: int = SimCombat.shot_recover_ticks(weight, 1.0)
	for variant in ["bare", "standard"]:
		var g: Dictionary = got[variant]
		if int(g["raise"]) != old_raise or int(g["recover"]) != old_recover:
			push_error("FURNITURE: the %s receiver comes up in %d ticks and recovers in %d, want the old %d and %d" % [variant, int(g["raise"]), int(g["recover"]), old_raise, old_recover])
			return false
	for variant in ["folding", "grip"]:
		var g: Dictionary = got[variant]
		if int(g["raise"]) >= old_raise or int(g["recover"]) >= old_recover:
			push_error("FURNITURE: the %s does not come up or recover faster than a bare receiver (%d/%d against %d/%d)" % [variant, int(g["raise"]), int(g["recover"]), old_raise, old_recover])
			return false
	print("FURNITURE OK bare and standard stock sit at the old %d up and %d back; folding %d and %d; foregrip %d and %d" % [old_raise, old_recover, int(got["folding"]["raise"]), int(got["folding"]["recover"]), int(got["grip"]["raise"]), int(got["grip"]["recover"])])
	return true


## One pump shotgun refit as `variant` says, on a fresh world, read back the way the ladder reads it.
## Returns {raise, recover, handling}, or {} and an error when the refit or the read could not be made.
func _refit(id: String, variant: String) -> Dictionary:
	var w: Variant = _world()
	var rw: Variant = _armed(w, id)
	if not rw is Dictionary:
		return {}
	var weapon: int = int((rw as Dictionary)["source"])
	if variant == "bare" or variant == "folding":
		if not SimAttachments.detach(w, SimAttachments.in_slot(w, weapon, "furniture")):
			push_error("FURNITURE: %s could not take the standard stock off" % variant)
			return {}
	var want: float = 1.0
	if FITS.has(variant):
		var fit: Array = FITS[variant]
		var part: int = SimItems.spawn_item(w, String(fit[0]), {"tier": "scavenged"})
		if not SimAttachments.attach(w, weapon, part, String(fit[1])):
			push_error("FURNITURE: %s would not fit the %s" % [variant, id])
			return {}
		want = SimAttachments.effect_scale(w, part, float(FURNITURE_HANDLING[String(fit[0])]))
	w.events.drain()
	rw = w.components.get_component(w.player, "rangedWeapon")
	if not rw is Dictionary:
		push_error("FURNITURE: %s lost its rangedWeapon in the refit" % variant)
		return {}
	var handling: float = float((rw as Dictionary)["handling"])
	if absf(handling - want) > 0.0001:
		push_error("FURNITURE: %s reads handling %.4f, want %.4f" % [variant, handling, want])
		return {}
	if not SimRanged.try_begin_fire(w, w.player):
		push_error("FURNITURE: %s refused to begin firing" % variant)
		return {}
	rw = w.components.get_component(w.player, "rangedWeapon")
	return {"raise": int((rw as Dictionary)["ticksLeft"]), "recover": SimRanged._recover_of(w, rw as Dictionary), "handling": handling}


# --- item-scoped clocks (F4, for the affixes follow-up) ------------------------------------------

const CLOCK_ID: String = "item.shotgun.pump"

# A modifier on one item's `steady_ticks`, `recover_ticks` or `reload_ticks` is an affix's move. The
# lane puts a x2 on each clock in turn and reads the number the ladder actually runs: the moved clock
# doubles, the other two stay put, the share the reader reports is 2.0, and a sibling gun with no
# affix reads 1.0. The bare gun is the true negative: all three shares 1.0 and the old clocks.
func _item_scoped_clocks_move_the_ladder_and_nothing_else() -> bool:
	var weight: float = float((HEFT[CLOCK_ID] as Dictionary)["weight"])
	var bare: Dictionary = _fire_clocks("", 1.0)
	var bare_reload: int = _reload_clock("", 1.0)
	if bare.is_empty() or bare_reload < 0:
		return false
	if int(bare["steady"]) != SimCombat.steady_ticks(weight, 1.0) or int(bare["recover"]) != SimCombat.shot_recover_ticks(weight, 1.0):
		push_error("READERS: a bare pump runs steady %d and recover %d, want the old %d and %d" % [int(bare["steady"]), int(bare["recover"]), SimCombat.steady_ticks(weight, 1.0), SimCombat.shot_recover_ticks(weight, 1.0)])
		return false
	var cases: Dictionary = {"steady_ticks": "steady", "recover_ticks": "recover", "reload_ticks": "reload"}
	for stat in cases.keys():
		var key: String = String(cases[stat])
		var moved: Dictionary = _fire_clocks(String(stat), 2.0)
		var moved_reload: int = _reload_clock(String(stat), 2.0)
		if moved.is_empty() or moved_reload < 0:
			return false
		var want_moved: int = int(round(float(int(bare[key] if key != "reload" else bare_reload)) * 2.0))
		var got: int = int(moved[key]) if key != "reload" else moved_reload
		if got != want_moved:
			push_error("READERS: a x2 %s on the pump runs %s %d, want %d" % [stat, key, got, want_moved])
			return false
		for other in ["steady", "recover"]:
			if other != key and int(moved[other]) != int(bare[other]):
				push_error("READERS: a x2 %s moved the %s clock to %d, not %d" % [stat, other, int(moved[other]), int(bare[other])])
				return false
		if key != "reload" and moved_reload != bare_reload:
			push_error("READERS: a x2 %s moved the reload to %d, not %d" % [stat, moved_reload, bare_reload])
			return false
	print("READERS OK a bare pump runs steady %d, recover %d, reload %d; a x2 on each clock moves that clock alone on that gun; a sibling with no affix reads 1.0" % [int(bare["steady"]), int(bare["recover"]), bare_reload])
	return true


## Fires one armed pump with a jam-free trigger and reads the steady and recover clocks off the ladder.
## `stat` is an optional x`value` modifier scoped to the pump. Returns {steady, recover}, or {} on error.
func _fire_clocks(stat: String, value: float) -> Dictionary:
	var w: Variant = _world()
	var rw: Variant = _armed(w, CLOCK_ID)
	if not rw is Dictionary:
		return {}
	var weapon: int = int((rw as Dictionary)["source"])
	if stat != "":
		w.modifiers.add({"stat": stat, "op": "mul", "value": value, "source": "gate.fixture"}, weapon)
	# A sibling gun with no affix reads the plain share: the modifier is scoped to one item.
	var sibling: int = SimItems.spawn_item(w, CLOCK_ID, {"tier": "scavenged"})
	if stat != "" and SimItems.steady_share_of(w, sibling) != 1.0:
		push_error("READERS: a modifier scoped to one pump moved a sibling pump's share")
		return {}
	w.events.drain()
	rw = w.components.get_component(w.player, "rangedWeapon")
	# A jam is a draw, not a clock, and this lane measures clocks.
	(rw as Dictionary)["jams"] = false
	if not SimRanged.try_begin_fire(w, w.player):
		push_error("READERS: the pump refused to begin firing")
		return {}
	var steady: int = -1
	var recover: int = -1
	for _i in range(120):
		w.step()
		var r: Dictionary = w.components.get_component(w.player, "rangedWeapon") as Dictionary
		var st: int = int(r["state"])
		if st == SimRanged.FireState.Steady and steady < 0:
			steady = int(r["ticksLeft"])
		if st == SimRanged.FireState.Recover:
			recover = int(r["ticksLeft"])
			break
	if steady < 0 or recover < 0:
		push_error("READERS: the pump never reached Steady and Recover in 120 ticks")
		return {}
	return {"steady": steady, "recover": recover}


## The reload clock the ladder runs for a pump with `stat` x`value` on it, or -1 on error.
func _reload_clock(stat: String, value: float) -> int:
	var w: Variant = _world()
	var rw: Variant = _armed(w, CLOCK_ID)
	if not rw is Dictionary:
		return -1
	var weapon: int = int((rw as Dictionary)["source"])
	if stat != "":
		w.modifiers.add({"stat": stat, "op": "mul", "value": value, "source": "gate.fixture"}, weapon)
	w.events.drain()
	# `_armed` loads the pump full, and a reload that would change nothing is refused (docs/30, "The
	# round you load"), so the magazine is emptied first; the pack still holds the rest of the box.
	w.components.remove_component(weapon, SimRanged.LOAD)
	if not SimRanged.try_begin_reload(w, w.player):
		push_error("READERS: the pump refused to begin a reload")
		return -1
	return int((w.components.get_component(w.player, "rangedWeapon") as Dictionary)["ticksLeft"])
