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
# picked within each range. Recorded now, used in no code -- Slice 3's recovery pass reads
# this. Do not delete it for being unreferenced; it is deliberately dead in Part A.
const RECOVERY_DAYS: Dictionary = {
	Severity.Scratch: 2,
	Severity.Laceration: 6,
	Severity.DeepWound: 16,
}

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

	world.systems.register("wounds.reap-bled-out", "cleanup", 2, func(w: Variant) -> void:
		if killed.is_empty():
			return
		var to_process: Array[int] = killed.duplicate()
		killed.clear()
		for entity in to_process:
			SimHealth.finish_death(w, int(entity))
	)
