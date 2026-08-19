class_name SimWounds
extends RefCounted

# Slice 2 Part A -- wounds that bleed. docs/05-health-injury.md's severity table made
# mechanical: a wound is no longer an inert append-only record, it carries a severity, it
# can bleed, and untreated bleeding can kill. The answer to it -- pressure and bandaging --
# lives in treatment.gd (Part B), which reads PRESSURE_TICKS/BANDAGE_TICKS below for its
# channel lengths and writes `bleeding`/`bandage` back onto the wound records built here.
#
# This taxonomy is code, not content JSON -- an explicit decision (see the Slice 2 Part A
# brief and docs/30). It never varies per zombie/item content entry the way appearance or
# armor do, so it does not belong under godot/content/.

const SimHealth = preload("res://sim/modules/health.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimClock = preload("res://sim/time/clock.gd")
const SimStances = preload("res://sim/stances.gd")

# "Bite" is a *kind* (docs/05: "as laceration, plus infection"), not a severity. Keeping it
# out of this enum is deliberate -- a bite's severity is computed by severity_for exactly
# like any other wound; only its kind and its presentation lie are bite-specific.
enum Severity { Scratch = 0, Laceration = 1, DeepWound = 2 }

const SEVERITY_WORD: Dictionary = {
	Severity.Scratch: "scratch",
	Severity.Laceration: "laceration",
	Severity.DeepWound: "deep wound",
}

# Blood lost per tick while a wound is open (bleeding == true and bandage == "none").
# Tuned so a DeepWound alone reaches BLOOD_LOSS_FATAL in 5,000 ticks (~4.2 game minutes at
# 20 Hz) if left completely untreated -- fast enough that ignoring a deep wound is lethal,
# slow enough a player has time to notice and react.
const BLEED_PER_TICK: Dictionary = {
	Severity.Scratch: 0.0006,
	Severity.Laceration: 0.004,
	Severity.DeepWound: 0.02,
}

# Ticks until a wound clots on its own, or 0 if it never does untreated. Only a Scratch
# self-resolves (~10 game minutes); Laceration and DeepWound need Part B's pressure/bandage
# to ever stop.
const CLOT_TICKS: Dictionary = {
	Severity.Scratch: 2000,
	Severity.Laceration: 0,
	Severity.DeepWound: 0,
}

# docs/05's healing table: 2-3 days / 5-8 days / 2-3 weeks, recorded here as whole game-days
# picked within each range. Slice 3 reads it twice: it is how long a wound takes to close,
# and it is the denominator for how fast the struck part gets its integrity back, so a deep
# wound is slow in both senses rather than slow in one and instant in the other.
# --- bacterial infection (docs/05) --------------------------------------------------------
#
# "Any open wound can go septic, with probability driven by wound severity, hygiene, whether it was
# cleaned, bandage cleanliness, and treatment skill. It presents as fever, pain, and worsening --
# *which is also how zombie infection presents in its early stages*." docs/05 calls the separation
# from zombie infection "one of the design's better ideas", and the two consequences it names are
# the point of the whole thing:
#
#   - Antibiotics are pulled in two directions. The finite, uncraftable supply that saves somebody
#     from a bite is the same supply that saves somebody from a dirty laceration, so every ordinary
#     wound spends the infection budget.
#   - Diagnostic ambiguity gets worse. A feverish survivor with a scratch might have sepsis, or
#     might be turning.
#
# What shipped before this was a socket: needs.gd's `_daily_sepsis` published `sepsis.checked`
# with a hygiene multiplier every dusk and **nothing subscribed to it**. `sepsis_mul` was gated and
# correct and reached no wound.
#
# **What Milestone 2 scopes in, and what it does not.** Sepsis here is debilitating and permanent
# until treated; it is deliberately **not directly lethal**. A septic wound stops healing entirely,
# costs mood and work while it runs, and clears only to antibiotics -- so it spends the budget and
# creates the pull docs/05 asks for, without adding a death path to a lethality model whose
# balance is currently the thing standing between GRABS_ENABLED and its flip. Making sepsis kill is
# a balance decision with a measurement attached, not a detail to slip in beside the mechanic.
const SEPSIS_SOURCE: String = "wound.sepsis"
const SEPSIS_STREAM: String = "sepsis"
# Per-day chance before any multiplier, by severity. A scratch going septic is meant to be an
# unlucky annoyance; a deep wound left dirty is meant to be most of the reason antibiotics are
# scarce.
const SEPSIS_BASE_BY_SEVERITY: Dictionary = {
	Severity.Scratch: 0.02,
	Severity.Laceration: 0.06,
	Severity.DeepWound: 0.12,
}
# "Supplies degrade in quality: sterile medical bandages > cloth bandages > dirty rags, with rising
# infection risk down the chain" (docs/05). An unbandaged wound is worse than a dirty rag, which is
# what makes a bad dressing better than none.
const SEPSIS_BANDAGE_MUL: Dictionary = {
	"sterile": 0.4,
	"cloth": 1.0,
	"dirty": 1.5,
	"none": 1.8,
}
# "...and treatment skill." Each Medicine point buys this much off the chance, floored so a good
# medic never makes a dirty wound safe.
const SEPSIS_SKILL_RELIEF: float = 0.08
const SEPSIS_MIN_MUL: float = 0.35
# Fever and pain, while it runs.
const SEPSIS_MOOD: float = -12.0
const SEPSIS_WORK_MUL: float = 0.7

const RECOVERY_DAYS: Dictionary = {
	Severity.Scratch: 2,
	Severity.Laceration: 6,
	Severity.DeepWound: 16,
}

# Recovery is *earned time*, not elapsed time. A wound's healedTicks only advances on ticks
# where the survivor is fed and is not exerting, so a run spent starving and sprinting heals
# nothing at all no matter how many days pass. docs/05 and the design record both ask for
# this; the alternative -- a wall-clock timer -- would make being wounded a waiting game
# rather than a constraint on what you can do next.
#
# "Not exerting" reuses the signal stamina recovery already uses: stamina.ticksUntilRecovery
# is set to STAMINA_RECOVERY_DELAY_TICKS by every stamina.spent, so it is non-zero for a
# while after any sprint, jog, swing or struggle. Reusing it means exertion has one
# definition in this simulation rather than two that can drift apart.
const RECOVERY_HUNGER_FLOOR: float = 30.0

# A part climbs back over its own wound's recovery window: an arm ruined to 1 of 20 by a deep
# wound is whole again after the same sixteen fed, idle days the wound itself takes to close.
# Rate is derived, never a second table -- the two cannot disagree.
static func regen_per_tick(max_integrity: int, severity: int) -> float:
	var days: int = int(RECOVERY_DAYS.get(severity, RECOVERY_DAYS[Severity.Scratch]))
	return float(max_integrity) / float(days * SimClock.DAY_TICKS)


# A part at exactly zero does not come back. This is the permanent-loss half of docs/05 --
# "a one-armed survivor" is a real outcome, and it stops being real the moment a ruined arm
# regrows overnight. It also means amputation needs no special case here: infection.gd's
# amputate sets the part to 0, and 0 is the floor recovery will not lift.
const DESTROYED: float = 0.0

# Overwork reopens a fresh deep wound. Sprinting on a deep wound that is less than a quarter
# healed tears it open again: it bleeds, its dressing is gone, and its earned time resets to
# nothing. Deliberately narrow -- only DeepWound, only sprinting, only while fresh -- because
# the point is to make one specific decision expensive ("do I run on this leg?") rather than
# to tax every wounded survivor for moving at all. No RNG: the player can learn this rule.
const REOPEN_BELOW_FRACTION: float = 0.25

# Ticks of applied pressure / a bandage needed to stop a wound of this severity. treatment.gd
# is the only consumer: these are the channel lengths, and the reason a deep wound is a
# commitment rather than a keystroke. Bandaging is always the slower of the two -- it is also
# the one that survives an interruption.
const PRESSURE_TICKS: Dictionary = {
	Severity.Scratch: 100,
	Severity.Laceration: 200,
	Severity.DeepWound: 400,
}
const BANDAGE_TICKS: Dictionary = {
	Severity.Scratch: 200,
	Severity.Laceration: 400,
	Severity.DeepWound: 800,
}

# The accumulator's ceiling. bloodLoss >= BLOOD_LOSS_FATAL is death.
const BLOOD_LOSS_FATAL: float = 100.0

const BLOODLOSS_SOURCE: String = "wound.bloodloss"

# Per-severity-step penalty magnitudes for family (b), per-part impairment. Indexed by
# Severity (0/1/2), i.e. index == the worst wound's severity on that part.
const LEG_MOVE_PENALTY: Array[float] = [0.04, 0.08, 0.12]
const ARM_SWING_PENALTY: Array[float] = [0.05, 0.10, 0.15]
const ARM_RANGED_PENALTY: Array[float] = [0.08, 0.16, 0.24]

# SimHealth.CRIPPLED_SOURCE ("injury.crippled") is declared in health.gd and referenced
# nowhere -- a socket already cut for a modifier keyed off the "crippled" (both-legs-gone)
# state. Read it; did not use it here. Family (b) below keys its per-part sources off the
# wound itself ("wound." + part), which already covers a crippled leg as a maximally severe
# leg wound, and CRIPPLED_SOURCE's *event* (injury.sustained/crippled) fires once at the
# moment a survivor starts crawling rather than describing an ongoing wound state, so it is
# the wrong shape for a per-tick modifier source. Leaving the socket for whoever wires up a
# crawl-specific modifier distinct from "worst leg wound is a DeepWound".
const _CRIPPLED_SOURCE_NOTE: bool = true


# Severity is a fraction of the struck part's *maximum*, never raw damage -- the same trap
# CLAUDE.md records for part_state: 10 damage is a scratch on a 40-torso and destroys a
# 10-hand. Armor reduces how far a hit escalates rather than blocking damage outright here
# (damage_taken already happened in health.gd's damage_part before this runs).
static func severity_for(world: Variant, target: int, part: String, damage: float) -> int:
	var body: Variant = world.components.get_component(target, "body")
	if not (body is Dictionary):
		return Severity.Scratch
	var maxv: Variant = SimHealth.max_of(body as Dictionary, part)
	if maxv == null or int(maxv) <= 0:
		return Severity.Scratch
	var fraction: float = float(damage) / float(int(maxv))
	var armor: float = clampf(SimInfection.armor_coverage_of(world, target, part), 0.0, 1.0)
	fraction *= 1.0 - 0.5 * armor
	if fraction < 0.15:
		return Severity.Scratch
	if fraction < 0.40:
		return Severity.Laceration
	return Severity.DeepWound


# The one place a wound is appended to injuries.wounds, creating the component (and the
# bloodLoss field alongside it) if absent. health.gd's take-damage and take-bite handlers
# both call this rather than each building the dict inline -- melee.gd:133-136 already
# names the class of bug two independently-written intakes produce.
#
# presentation_override lets the bite path keep its own lie (docs/06: "a bite can present as
# a scratch") independent of severity; an ordinary cut has no override and gets the
# severity's plain word instead.
static func append_wound(world: Variant, entity: int, kind: String, part: String, source: int, damage: float, presentation_override: String = "") -> Dictionary:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if inj == null:
		inj = {"wounds": [], "bloodLoss": 0.0, "bledOut": false}
		world.components.set_component(entity, "injuries", inj)
	var d: Dictionary = inj as Dictionary
	if not d.has("wounds"):
		d["wounds"] = []
	if not d.has("bloodLoss"):
		d["bloodLoss"] = 0.0
	if not d.has("bledOut"):
		d["bledOut"] = false
	var wounds: Array = d["wounds"] as Array

	var severity: int = severity_for(world, entity, part, damage)
	var bleed_rate: float = float(BLEED_PER_TICK.get(severity, 0.0))
	var clot_ticks: int = int(CLOT_TICKS.get(severity, 0))
	var clots_at: int = int(world.tick) + clot_ticks if clot_ticks > 0 else -1
	var presentation: String = presentation_override if presentation_override != "" else String(SEVERITY_WORD.get(severity, "scratch"))

	var wound: Dictionary = {
		"kind": kind,
		"presentation": presentation,
		"bodyPart": part,
		"source": source,
		"sustainedAtTick": int(world.tick),
		"severity": severity,
		"bleeding": bleed_rate > 0.0,
		"bandage": "none",
		"clotsAtTick": clots_at,
		# Earned recovery time, not elapsed -- see RECOVERY_DAYS. Starts at zero and only
		# ever advances on a tick the survivor was fed and idle.
		"healedTicks": 0,
	}
	wounds.append(wound)
	return wound


# Family (a): blood loss impairs everything, entity-scoped, one band's worth (not
# cumulative). Copies melee.gd:166 _apply_exhaustion's structure exactly -- strip the source
# unconditionally first, THEN early-return on the neutral case, THEN recompute magnitude
# from scratch and add. Reversing the strip and the early return is the bug that makes
# recovery never clear the penalty.
static func _apply_bloodloss_impairment(world: Variant, entity: int, blood_loss: float) -> void:
	world.modifiers.call("remove_by_source", BLOODLOSS_SOURCE, entity)
	var frac: float = blood_loss / BLOOD_LOSS_FATAL
	if frac < 0.25:
		return
	var move_mul: float = 0.90
	var swing_mul: float = 0.90
	var ranged_mul: float = -1.0 # sentinel: below 0.50 there is no ranged_accuracy penalty at all
	if frac >= 0.75:
		move_mul = 0.50
		swing_mul = 0.60
		ranged_mul = 0.40
	elif frac >= 0.50:
		move_mul = 0.75
		swing_mul = 0.80
		ranged_mul = 0.70
	world.modifiers.call("add", {"stat": "move_speed", "op": "mul", "value": move_mul, "source": BLOODLOSS_SOURCE}, entity)
	world.modifiers.call("add", {"stat": "swing_speed", "op": "mul", "value": swing_mul, "source": BLOODLOSS_SOURCE}, entity)
	if ranged_mul >= 0.0:
		world.modifiers.call("add", {"stat": "ranged_accuracy", "op": "mul", "value": ranged_mul, "source": BLOODLOSS_SOURCE}, entity)


# Family (b): per-part wounds, one source string PER PART ("wound." + part) so
# explain("move_speed", entity) names the limb, not a shared bucket -- the whole point of a
# diegetic read model. Same strip-first-then-recompute structure as family (a). Picks the
# worst wound on each part, not cumulative across wounds on that part.
static func _apply_part_impairment(world: Variant, entity: int, wounds: Array) -> void:
	var worst_by_part: Dictionary = {}
	for w in wounds:
		var wd: Dictionary = w as Dictionary
		var part: String = String(wd.get("bodyPart", ""))
		var sev: int = int(wd.get("severity", Severity.Scratch))
		if not worst_by_part.has(part) or sev > int(worst_by_part[part]):
			worst_by_part[part] = sev

	for part in SimCombat.SURVIVOR_BODY_PARTS:
		var source: String = "wound." + String(part)
		world.modifiers.call("remove_by_source", source, entity)
		if not worst_by_part.has(part):
			continue
		var sev: int = int(worst_by_part[part])
		if String(part).begins_with("leg_") or String(part).begins_with("foot_"):
			var mv: float = 1.0 - float(LEG_MOVE_PENALTY[sev])
			world.modifiers.call("add", {"stat": "move_speed", "op": "mul", "value": mv, "source": source}, entity)
		elif String(part).begins_with("arm_") or String(part).begins_with("hand_"):
			var sw: float = 1.0 - float(ARM_SWING_PENALTY[sev])
			var racc: float = 1.0 - float(ARM_RANGED_PENALTY[sev])
			world.modifiers.call("add", {"stat": "swing_speed", "op": "mul", "value": sw, "source": source}, entity)
			world.modifiers.call("add", {"stat": "melee_damage", "op": "mul", "value": sw, "source": source}, entity)
			world.modifiers.call("add", {"stat": "ranged_accuracy", "op": "mul", "value": racc, "source": source}, entity)
		# head/torso: no per-part modifier -- torso's contribution is blood loss (family a).
		# The remove_by_source above still runs so a healed/removed head or torso wound
		# clears correctly; there is simply nothing to add back.


# The one effect a completed act of first aid has, shared by the NPC Doctor job
# (jobs.gd:_treat) and the player's treatment channel. Before this existed the two were
# separately written and had already drifted: the Doctor's version added 8 to the torso and
# nothing else, capped at a hardcoded 40, ignoring `injuries.wounds` and every other part.
#
# It stops the worst open wound the way a competent dressing would, and it does *not* raise
# integrity -- that is wounds.recover's job, and it is earned over days rather than granted by
# an act. Treatment is what starts the recovery clock (an open wound does not knit); it is not
# the recovery itself.
#
# `tier` of "none" is a real answer, not a missing one: it is a treater who had no dressing and
# closed the wound with their hands, which is exactly what pressure does.
static func dress_worst(world: Variant, treater: int, patient: int, tier: String = "cloth") -> Dictionary:
	var inj: Variant = world.components.get_component(patient, "injuries")
	if not (inj is Dictionary):
		return {"ok": false, "reason": "no-wounds"}
	var worst: Variant = null
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		var wd: Dictionary = wound as Dictionary
		if not bool(wd.get("bleeding", false)):
			continue
		if worst == null or int(wd.get("severity", 0)) > int((worst as Dictionary).get("severity", 0)):
			worst = wd
	if worst == null:
		return {"ok": false, "reason": "not-bleeding"}
	var w: Dictionary = worst as Dictionary
	w["bleeding"] = false
	w["bandage"] = tier
	world.events.publish({
		"type": "wound.treated",
		"entity": patient,
		"treater": treater,
		"bodyPart": String(w.get("bodyPart", "")),
		"verb": "bandage",
		"tier": tier,
		"wounds": 1,
	})
	return {"ok": true, "bodyPart": String(w.get("bodyPart", ""))}


# Is this body currently earning recovery time? Fed, and not exerting. Both halves are read
# from state something else already owns -- SimNeeds' hunger pool and health.gd's stamina
# recovery delay -- rather than from a flag this module sets, so there is no third definition
# of "resting" to keep in sync with the other two.
static func _is_recovering(world: Variant, entity: int) -> bool:
	var stamina: Variant = world.components.get_component(entity, "stamina")
	if stamina is Dictionary and int((stamina as Dictionary).get("ticksUntilRecovery", 0)) > 0:
		return false
	var needs: Variant = world.components.get_component(entity, "needs")
	if needs is Dictionary:
		if float((needs as Dictionary).get("hunger", 100.0)) < RECOVERY_HUNGER_FLOOR:
			return false
	# A survivor with no needs component (a bare fixture, a test body) is treated as fed. The
	# stamina half above still gates them, which is the half every survivor has.
	return true


# Sprinting on a wound that is still fresh and still deep. Returns the wounds it tore open.
static func _reopen_from_overwork(world: Variant, entity: int, wounds: Array) -> Array:
	var posture: Variant = world.components.get_component(entity, "posture")
	if not (posture is Dictionary):
		return []
	if int((posture as Dictionary).get("current", SimStances.Stance.Walk)) != SimStances.Stance.Sprint:
		return []
	var torn: Array = []
	for wound in wounds:
		var wd: Dictionary = wound as Dictionary
		if int(wd.get("severity", Severity.Scratch)) != Severity.DeepWound:
			continue
		if bool(wd.get("bleeding", false)):
			continue
		var budget: int = int(RECOVERY_DAYS[Severity.DeepWound]) * SimClock.DAY_TICKS
		if float(wd.get("healedTicks", 0)) >= float(budget) * REOPEN_BELOW_FRACTION:
			continue
		wd["bleeding"] = true
		wd["bandage"] = "none"
		wd["healedTicks"] = 0
		# A reopened wound has no clot to fall back on: whatever stopped it the first time
		# (pressure, a dressing) is undone, and clotsAtTick was already spent. Treatment's R8
		# bank goes with it for the same reason -- the pressure that closed this once has been
		# torn out, so the next press starts from cold. The key is erased by name rather than
		# through treatment.gd to keep this module's dependency direction intact: treatment reads
		# wounds, not the other way round.
		wd["clotsAtTick"] = -1
		wd.erase("pressedTicks")
		torn.append(wd)
	return torn


# What a bleeding survivor says about themselves, in the shape needs.gd:801 hud_clause set:
# a rank spine, a third-person rewrite for anyone who is not the player, and "" when there is
# nothing worth saying. Words only -- check_hud.gd allows no digits on the HUD but the day
# counter, and this is the read model that keeps the blood-loss clock visible without a bar.
#
# "You're bleeding" is deliberately the *first* thing said, at any loss at all: the player
# needs to know to act while acting is still cheap, and by the time light-headedness arrives
# a deep wound has already spent a quarter of its lethal budget.
static func hud_clause(world: Variant, entity: int) -> String:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return ""
	var d: Dictionary = inj as Dictionary
	var open: bool = false
	for wound in d.get("wounds", []) as Array:
		if bool((wound as Dictionary).get("bleeding", false)):
			open = true
			break
	var frac: float = float(d.get("bloodLoss", 0.0)) / BLOOD_LOSS_FATAL

	var line: String = ""
	if frac >= 0.75:
		line = "You're going grey."
	elif frac >= 0.50:
		line = "You're light-headed."
	elif frac >= 0.25:
		line = "You've lost a lot of blood."
	elif open:
		line = "You're bleeding."
	if line == "":
		return ""

	if world.components.has_component(entity, "controlled"):
		return line
	var name: String = "They"
	var ident: Variant = world.components.get_component(entity, "identity")
	if ident is Dictionary:
		name = String((ident as Dictionary).get("name", "They"))
	if line.begins_with("You're "):
		return name + " looks " + line.substr(7)
	return name + " has lost a lot of blood."


# --- sepsis: the roll, the effects, and the cure -------------------------------------------

# One dusk's worth of rolls for one survivor. `hygiene_mul` comes from needs.gd, which owns
# hygiene and already computed it -- this does not reach across and re-derive it.
#
# Returns how many wounds went septic, so a caller can say something happened without counting
# again. Wounds that are already septic are skipped rather than re-rolled: sepsis is a state, not
# a stacking counter, and rolling an infected wound nightly would make severity meaningless.
static func roll_sepsis(world: Variant, entity: int, hygiene_mul: float, medicine_skill: int = 0) -> int:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return 0
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	if wounds.is_empty():
		return 0
	var rng: Variant = world.rng.stream(SEPSIS_STREAM)
	var caught: int = 0
	for wound in wounds:
		var wd: Dictionary = wound as Dictionary
		if bool(wd.get("septic", false)):
			continue
		var chance: float = sepsis_chance(wd, hygiene_mul, medicine_skill)
		if chance <= 0.0:
			continue
		if float(rng.call("float_range", 0.0, 1.0)) >= chance:
			continue
		wd["septic"] = true
		caught += 1
		world.events.publish({
			"type": "sepsis.contracted", "entity": entity,
			"bodyPart": String(wd.get("bodyPart", "")), "severity": int(wd.get("severity", Severity.Scratch)),
		})
	if caught > 0:
		_apply_sepsis_burden(world, entity)
	return caught


# The four factors docs/05 names, in one expression so no caller can apply three of them.
# Severity is the base; hygiene, bandage cleanliness and treatment skill are multipliers on it.
static func sepsis_chance(wound: Dictionary, hygiene_mul: float, medicine_skill: int) -> float:
	var base: float = float(SEPSIS_BASE_BY_SEVERITY.get(int(wound.get("severity", Severity.Scratch)), 0.0))
	if base <= 0.0:
		return 0.0
	var dressing: String = String(wound.get("bandage", "none"))
	var bandage_mul: float = float(SEPSIS_BANDAGE_MUL.get(dressing, float(SEPSIS_BANDAGE_MUL["none"])))
	var skill_mul: float = maxf(SEPSIS_MIN_MUL, 1.0 - float(maxi(0, medicine_skill)) * SEPSIS_SKILL_RELIEF)
	return clampf(base * maxf(0.0, hygiene_mul) * bandage_mul * skill_mul, 0.0, 1.0)


static func is_septic(world: Variant, entity: int) -> bool:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return false
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		if bool((wound as Dictionary).get("septic", false)):
			return true
	return false


# Fever and pain, as one modifier from one source rather than one per infected wound: two septic
# wounds are a worse situation but not twice the fever, and stacking sources here would make a
# survivor with four scratches unplayable for reasons nothing in docs/05 asks for.
static func _apply_sepsis_burden(world: Variant, entity: int) -> void:
	if world.modifiers == null:
		return
	world.modifiers.call("remove_by_source", SEPSIS_SOURCE, entity)
	if not is_septic(world, entity):
		return
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": SEPSIS_MOOD, "source": SEPSIS_SOURCE}, entity)


# Antibiotics. Clears every septic wound at once -- a course treats the patient, not one cut --
# and returns how many it cleared so the caller can refuse to spend a course on somebody who has
# none. This is the one cure: sepsis does not resolve on its own, which is what makes the finite
# stock docs/05 describes actually get spent on ordinary wounds.
static func clear_sepsis(world: Variant, entity: int) -> int:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return 0
	var cleared: int = 0
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		if bool((wound as Dictionary).get("septic", false)):
			(wound as Dictionary)["septic"] = false
			cleared += 1
	if cleared > 0:
		if world.modifiers != null:
			world.modifiers.call("remove_by_source", SEPSIS_SOURCE, entity)
		world.events.publish({"type": "sepsis.cleared", "entity": entity, "wounds": cleared})
	return cleared


# What a septic survivor says about themselves. Prose, no digits, and deliberately the same word
# zombie infection's early stages use: docs/05 says sepsis "presents as fever, pain, and worsening
# -- which is also how zombie infection presents in its early stages", and that ambiguity is the
# feature. Nothing here says which one it is.
static func sepsis_clause(world: Variant, entity: int) -> String:
	if not is_septic(world, entity):
		return ""
	return "You're feverish, and it isn't getting better."


static func register_module(world: Variant) -> void:
	var killed: Array[int] = []

	# Impairment is recomputed every tick in "input" (order -1), the same phase and order as
	# melee.gd's "melee.exhaustion" -- and for the same reason: PHASES runs "movement" before
	# "health", so a system that both updates bloodLoss *and* writes the modifier from inside
	# "health" is one tick late for *this* tick's movement. Concretely: clearing bloodLoss
	# back to 0 would still leave the previous tick's modifier in effect for the very next
	# movement pass, so a "recovered" walk would not match a "never hurt" walk exactly.
	# Recomputing fresh from the live component before movement runs removes the lag
	# entirely, the same way melee.exhaustion recomputes from the live stamina pool rather
	# than caching a multiplier at the moment stamina changes.
	world.systems.register("wounds.impair", "input", -1, func(w: Variant) -> void:
		if w.modifiers == null or not (w.modifiers as Object).has_method("add"):
			return
		for entity in w.components.query(["injuries"]):
			var inj: Variant = w.components.get_component(int(entity), "injuries")
			if inj == null:
				continue
			# Same corpse guard wounds.bleed carries. recruits._make_corpse leaves `injuries`
			# on the body, so without this every corpse in the world re-strips and re-adds ten
			# per-part modifier sources on every tick, forever, to slow down something that is
			# not going anywhere. Correctness and cost, not just tidiness.
			if w.components.has_component(int(entity), "corpse"):
				continue
			var d: Dictionary = inj as Dictionary
			_apply_bloodloss_impairment(w, int(entity), float(d.get("bloodLoss", 0.0)))
			_apply_part_impairment(w, int(entity), d.get("wounds", []) as Array)
	)

	world.systems.register("wounds.bleed", "health", 1, func(w: Variant) -> void:
		for entity in w.components.query(["injuries"]):
			var inj: Variant = w.components.get_component(int(entity), "injuries")
			if inj == null:
				continue
			var d: Dictionary = inj as Dictionary
			# The dead do not bleed. recruits._make_corpse leaves `injuries` on the body it
			# turns into a corpse (it removes needs/job/velocity and nothing else), so without
			# this a bled-out corpse stays in this query forever -- still at BLOOD_LOSS_FATAL,
			# re-publishing entity.killed on every single tick, because `killed` below is
			# cleared each tick by the reaper. CLAUDE.md already records entity.killed firing
			# three times for one individual; this would make it hundreds per second.
			if w.components.has_component(int(entity), "corpse"):
				continue
			if bool(d.get("bledOut", false)):
				continue
			var wounds: Array = d.get("wounds", []) as Array

			# Which part, if any, currently has a hand pressed to it. Read as a *component*
			# rather than by calling into treatment.gd, deliberately: treatment.gd preloads
			# this file for its severity tables, so a call back the other way would be a
			# cyclic preload. A component is the seam that costs nothing either way.
			var under_pressure: String = ""
			var treated: Variant = w.components.get_component(int(entity), "treated")
			if treated is Dictionary and String((treated as Dictionary).get("verb", "")) == "pressure":
				under_pressure = String((treated as Dictionary).get("part", ""))

			var bleed_sum: float = 0.0
			for wound in wounds:
				var wd: Dictionary = wound as Dictionary
				var clots_at: int = int(wd.get("clotsAtTick", -1))
				if bool(wd.get("bleeding", false)) and clots_at >= 0 and int(w.tick) >= clots_at:
					wd["bleeding"] = false
				if not bool(wd.get("bleeding", false)):
					continue
				if String(wd.get("bandage", "none")) != "none":
					continue
				# Suppressed, not stopped: the wound is still bleeding: true and resumes on
				# the very next tick if the hold breaks. Only a completed hold clots it.
				if under_pressure != "" and String(wd.get("bodyPart", "")) == under_pressure:
					continue
				bleed_sum += float(BLEED_PER_TICK.get(int(wd.get("severity", Severity.Scratch)), 0.0))

			var blood_loss: float = clampf(float(d.get("bloodLoss", 0.0)) + bleed_sum, 0.0, BLOOD_LOSS_FATAL)
			d["bloodLoss"] = blood_loss

			if blood_loss >= BLOOD_LOSS_FATAL and not killed.has(int(entity)):
				# bledOut is the *durable* half of this de-duplication. `killed` only guards
				# within a tick -- the reaper clears it -- so it cannot stop a second kill on
				# a later tick for a body that survived its own death (a corpse, a succession
				# handoff). This flag lives on the component and is therefore serialised too.
				d["bledOut"] = true
				killed.append(int(entity))
				var pos: Variant = w.components.get_component(int(entity), "position")
				# Same payload shape health.gd publishes -- bloater.bloom reads x/y off this
				# event (with a 0.0 default that would silently bloom at the origin).
				w.events.publish({
					"type": "entity.killed",
					"entity": int(entity),
					"cause": "bloodloss",
					"x": float((pos as Dictionary).get("x", 0.0)) if pos is Dictionary else 0.0,
					"y": float((pos as Dictionary).get("y", 0.0)) if pos is Dictionary else 0.0,
				})
	)

	# Recovery runs in "health" at order 2, behind wounds.bleed (1): a wound that bleeds and
	# heals on the same tick should bleed first, so a survivor who is losing blood faster than
	# they are mending is not quietly credited with the difference.
	world.systems.register("wounds.recover", "health", 2, func(w: Variant) -> void:
		for entity in w.components.query(["injuries", "body"]):
			if w.components.has_component(int(entity), "corpse"):
				continue
			var inj: Variant = w.components.get_component(int(entity), "injuries")
			if not (inj is Dictionary):
				continue
			var d: Dictionary = inj as Dictionary
			if bool(d.get("bledOut", false)):
				continue
			var wounds: Array = d.get("wounds", []) as Array

			# Overwork is checked whether or not the survivor is resting -- sprinting *is*
			# the thing that tears a wound open, so it can hardly be gated on resting.
			for torn in _reopen_from_overwork(w, int(entity), wounds):
				w.events.publish({
					"type": "wound.reopened",
					"entity": int(entity),
					"bodyPart": String((torn as Dictionary).get("bodyPart", "")),
				})

			if not _is_recovering(w, int(entity)):
				continue

			var body: Dictionary = w.components.get_component(int(entity), "body") as Dictionary
			# The worst open wound on each part sets that part's healing rate, so a limb
			# carrying both a scratch and a deep wound mends at the deep wound's pace.
			var worst_by_part: Dictionary = {}
			var closed: Array = []
			for wound in wounds:
				var wd: Dictionary = wound as Dictionary
				if bool(wd.get("bleeding", false)):
					# An open wound does not knit. Stopping the bleeding is what starts the
					# clock, which is the whole reason Part B's two verbs matter beyond the
					# blood-loss arithmetic.
					continue
				if bool(wd.get("septic", false)):
					# A septic wound does not knit, for the same reason an open one does not: the
					# thing that has to stop before healing starts has not stopped. This is the
					# whole cost of sepsis in Milestone 2 and the reason antibiotics get spent on
					# ordinary wounds -- an infected deep wound never closes on its own, however
					# well fed and rested the survivor is.
					continue
				var part: String = String(wd.get("bodyPart", ""))
				var sev: int = int(wd.get("severity", Severity.Scratch))
				if not worst_by_part.has(part) or sev > int(worst_by_part[part]):
					worst_by_part[part] = sev
				wd["healedTicks"] = int(wd.get("healedTicks", 0)) + 1
				if int(wd["healedTicks"]) >= int(RECOVERY_DAYS.get(sev, 2)) * SimClock.DAY_TICKS:
					closed.append(wd)

			for part in worst_by_part.keys():
				var current: float = float(body.get(String(part), 0.0))
				# DESTROYED is a floor, not a stage: a part at zero is gone for good, which
				# is what makes "a one-armed survivor" a real outcome and what keeps an
				# amputation from growing back.
				if current <= DESTROYED:
					continue
				var maxv: Variant = SimHealth.max_of(body, String(part))
				if maxv == null or current >= float(int(maxv)):
					continue
				body[String(part)] = minf(float(int(maxv)), current + regen_per_tick(int(maxv), int(worst_by_part[part])))

			for done in closed:
				wounds.erase(done)
				w.events.publish({
					"type": "wound.closed",
					"entity": int(entity),
					"bodyPart": String((done as Dictionary).get("bodyPart", "")),
					"severity": int((done as Dictionary).get("severity", 0)),
				})
	)

	world.systems.register("wounds.reap-bled-out", "cleanup", 2, func(w: Variant) -> void:
		if killed.is_empty():
			return
		var to_process: Array[int] = killed.duplicate()
		killed.clear()
		for entity in to_process:
			SimHealth.finish_death(w, int(entity))
	)
