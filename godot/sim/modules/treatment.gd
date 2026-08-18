class_name SimTreatment
extends RefCounted

# Slice 2 Part B -- hands that stop the bleeding, and the command path to the five
# infection responses that already existed and could not be reached.
#
# Part A gave a wound a severity and a bleed clock. It gave the player no answer to either:
# a deep wound bled until it killed you and nothing in the sim could stop it. This module is
# the answer, and it is deliberately two verbs rather than a heal button --
# docs/05-health-injury.md's distinction between holding a wound closed and dressing it.
#
#   pressure  no supply, and worth nothing until it is finished. While held it suppresses
#             the bleed (wounds.bleed reads the `treated` component directly); held all the
#             way to PRESSURE_TICKS it clots the wound for good. Interrupted at 99%, the
#             wound is bleeding again on the next tick and the time is simply gone.
#   bandage   costs a bandage, takes longer, and is durable: it survives the stagger that
#             would have cost you a pressure hold, and it records which tier was used.
#
# The infection verbs are **routed, not reimplemented**. SimInfection.cauterize/amputate/
# use_antibiotics/quarantine/put_down already validate their own windows and already return
# {ok, reason}; this module calls them and surfaces the reason. Duplicating a window check
# here would give the sim two answers to one question. Cauterisation and amputation run as
# channels first (docs/06: surgery "needs a skilled medic, supplies, and time") and the
# window is judged by SimInfection at *completion* -- so it is possible to spend the whole
# channel and be told you were too late, which is the honest outcome and costs no duplicated
# logic to produce.
#
# The channel machinery is fortify.gd's, copied deliberately rather than invented: _start
# guarded by _can_channel, a component holding {verb, ticksLeft, ...} ticked down by one
# system, _cancel driven by subscriptions to entity.staggered and grab.started. The swing
# and fire state machines are the wrong template -- a channel is one committed span with a
# cancel, not a multi-phase cycle.
#
# --- one hand on your own wound, while somebody has hold of you ------------------------
#
# `_can_channel` used to refuse everything to a `grabbed` body, and that reading of "you cannot
# work on a wound with a zombie on your arm" cost a colony. The balance harness measured it: a
# held survivor spent two thirds of their life bleeding and forbidden from answering it, and both
# seeds that wiped wiped by blood loss. The fiction was also only half right. You cannot kneel and
# dress somebody's leg inside a grapple. You can clamp your own free hand over your own arm and
# hold it there, badly, while the rest of you fights -- and that is what first aid is at its most
# basic, which is exactly the verb pressure already models.
#
# So one channel is legal while held, and the arbitration is written out here rather than left to
# be inferred, because seven separate rules meet at it and each is gate-asserted (AID-HELD and
# HELD-CONTEXT in check_m2_treatment.gd, the four ARBITRATION assertions in check_m2_contact.gd):
#
#   R1  While `grabbed`, exactly one channel is legal: `pressure` with patient == actor. Bandage,
#       surgery, and anything aimed at another body still refuse -- at begin *and* on the per-tick
#       re-check, because a channel begun free must also end when a hold makes it illegal.
#   R2  `grab.started` cancels every channel touching the victim *except* the victim's own
#       self-pressure. A second holder does not peel your palm off your own wound; a free treater
#       whose patient has just been grabbed does lose the dressing.
#   R3  `entity.staggered` still cancels everything, held self-pressure included. Being knocked
#       off your feet is the one thing that takes your own hand off your own arm.
#   R4  Struggle and self-pressure coexist -- `_arm_struggle` is not consulted here and does not
#       consult this. Pressing is not "your action" for the hold; a survivor who had to choose
#       between the two would either bleed out or never get free.
#   R5  On a mid-channel escape `treatment.pin` outranks `breakAway` (same phase and order,
#       alphabetical tie-break, and treatment.pin's zero lands last). Tear free mid-press and you
#       stay on the wound; flight happens between channels, not during one.
#   R6  `treatment.self-aid` will not *start* a channel while `breakAway` is running: get clear
#       first, then kneel. R5 and R6 are not in tension -- one is about a press already paid for,
#       the other about opening a new one.
#   R7  `context()` picks `pressure` while the actor is grabbed even when they are carrying a
#       dressing, or a held bandage-carrier would be refused every tick and never treat anything.
#
# Why coexistence rather than "pressing costs you the hold": every new hold resets the bite clock
# (`_start_grab` writes a fresh ticksUntilBite), and a struggle cycle resolves at ~17-33 ticks with
# p 0.667, so a press that suppressed struggling would take roughly five bites across a 400-tick
# deep-wound hold and never end. Coexisting, the press runs across grab and escape cycles, the
# bleed is suppressed the whole time it is held (wounds.bleed reads `treated` directly), and it
# clots at completion.

const SimWounds = preload("res://sim/modules/wounds.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimCombat = preload("res://sim/combat.gd")

const REACH: float = 1.5

# Bandage tiers, best first. The rank doubles as the pick order when an actor is carrying
# more than one kind: reach for the sterile dressing before the dirty rag.
const TIER_ORDER: Array[String] = ["sterile", "cloth", "dirty"]

# The flat top-level content key a bandage-capable item carries. Flat, not a nested block,
# because CLAUDE.md's validator is shallow: a nested object gets an "is it an object" check
# and nothing more, which is exactly how a wrong key inside an `armor` block sat for weeks
# giving zero arm protection. A scalar under an enum in item.schema.json is actually checked.
const TIER_KEY: String = "bandageTier"

# Surgery is a channel, not an instant. These are the spans; the window that decides whether
# the surgery still helps belongs to SimInfection and is judged when the channel completes.
const SURGERY_TICKS: Dictionary = {
	"cauterize": 300,
	"amputate": 900,
}

const CHANNEL_VERBS: Array[String] = ["pressure", "bandage"]
const SURGERY_VERBS: Array[String] = ["cauterize", "amputate"]
const INSTANT_VERBS: Array[String] = ["antibiotics", "quarantine", "put_down"]


static func register_module(world: Variant) -> void:
	world.systems.register("treatment.intake", "input", 13, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			match String(c.get("type", "")):
				"treat.begin":
					for actor in w.components.query(["controlled", "position"]):
						var res: Dictionary = begin(w, int(actor), int(c.get("patient", w.player)), String(c.get("part", "")), String(c.get("verb", "")))
						if not bool(res.get("ok", false)):
							w.events.publish({"type": "treatment.refused", "entity": int(actor), "verb": String(c.get("verb", "")), "reason": String(res.get("reason", "unknown"))})
				"treat.context":
					for actor4 in w.components.query(["controlled", "position"]):
						var res3: Dictionary = context(w, int(actor4))
						if not bool(res3.get("ok", false)) and String(res3.get("reason", "")) != "cancelled":
							w.events.publish({"type": "treatment.refused", "entity": int(actor4), "verb": "context", "reason": String(res3.get("reason", "unknown"))})
				"treat.cancel":
					for actor2 in w.components.query(["controlled", "position"]):
						cancel(w, int(actor2))
				"infection.respond":
					for actor3 in w.components.query(["controlled", "position"]):
						var res2: Dictionary = respond(w, int(actor3), int(c.get("patient", w.player)), String(c.get("part", "")), String(c.get("verb", "")))
						if not bool(res2.get("ok", false)):
							w.events.publish({"type": "treatment.refused", "entity": int(actor3), "verb": String(c.get("verb", "")), "reason": String(res2.get("reason", "unknown"))})
	)

	# Survivors who are not the player stop their own bleeding. Registered at the same order
	# as the intake and after it by id, so a command issued this tick always wins over the
	# autonomous choice.
	#
	# This is not a convenience -- it is the difference between a wound being a problem and a
	# wound being a death sentence for anyone the player is not personally standing next to.
	# The NPC Doctor job exists, but it has to notice, path across the district and arrive,
	# and a deep wound bleeds out in five thousand ticks. A person with a hand and an open
	# artery does not wait for a doctor; they press on it. It routes through the same
	# `context` the T key uses, so there is one first-aid decision procedure in this
	# simulation rather than a player one and an NPC one that drift.
	world.systems.register("treatment.self-aid", "input", 13, func(w: Variant) -> void:
		for entity in w.components.query(["injuries", "body", "position"]):
			var e: int = int(entity)
			if w.components.has_component(e, "controlled"):
				continue
			if w.components.has_component(e, "corpse") or w.components.has_component(e, "treatment") or w.components.has_component(e, "treated"):
				continue
			# R6: somebody who has just torn free of a hold is running, not kneeling. Without this
			# the press would open on the tick of the escape and treatment.pin would immediately
			# outrank breakAway (R5) -- the survivor would stand exactly where they escaped from
			# and press, which is the treadmill the break-away exists to end. A press already paid
			# for survives an escape; a new one waits the 26 ticks out.
			if w.components.has_component(e, "breakAway"):
				continue
			if _worst_bleeding_part(w, e) == "":
				continue
			context(w, e)
	)

	# Before movement.integrate (order 0), the same slot shambler.pin uses and for the same
	# reason: a body that is being worked on should not take a step first and be pinned
	# afterwards. Both parties -- the design record's "treating another occupies both".
	world.systems.register("treatment.pin", "movement", -1, func(w: Variant) -> void:
		for entity in w.components.query(["treatment"]):
			_still(w, int(entity))
		for patient in w.components.query(["treated"]):
			_still(w, int(patient))
	)

	# Order 0 in "health", ahead of wounds.bleed at order 1, so a pressure hold that finishes
	# on this tick stops this tick's blood loss rather than the next one's.
	world.systems.register("treatment.channel", "health", 0, func(w: Variant) -> void:
		for entity in w.components.query(["treatment"]):
			_tick_channel(w, int(entity))
	)

	world.events.subscribe({"id": "treatment.stagger-interrupts", "type": "entity.staggered", "handler": func(event: Dictionary) -> void:
		_interrupt(world, int(event.get("entity", -1)))
	})
	world.events.subscribe({"id": "treatment.grab-interrupts", "type": "grab.started", "handler": func(event: Dictionary) -> void:
		_interrupt_grab(world, int(event.get("victim", -1)))
	})


# --- public verbs -------------------------------------------------------------------

# Returns {ok, reason} rather than a bare bool so the screen can show why a verb is
# unavailable using the sim's own words -- the same contract SimInfection's five responses
# already use, so the panel never has to invent a second vocabulary for the same refusal.
static func begin(world: Variant, actor: int, patient: int, part: String, verb: String) -> Dictionary:
	if not CHANNEL_VERBS.has(verb):
		return {"ok": false, "reason": "unknown-verb"}
	var pre: Dictionary = _can_begin(world, actor, patient, verb)
	if not bool(pre.get("ok", false)):
		return pre

	var wound: Variant = _worst_open_wound(world, patient, part)
	if wound == null:
		return {"ok": false, "reason": "not-bleeding"}
	var severity: int = int((wound as Dictionary).get("severity", SimWounds.Severity.Scratch))

	var ticks: int = 0
	if verb == "pressure":
		ticks = int(SimWounds.PRESSURE_TICKS.get(severity, 0))
	else:
		if String(_best_bandage(world, actor).get("tier", "")) == "":
			return {"ok": false, "reason": "no-bandage"}
		ticks = int(SimWounds.BANDAGE_TICKS.get(severity, 0))
	if ticks <= 0:
		return {"ok": false, "reason": "nothing-to-do"}

	_engage(world, actor, patient, part, verb, ticks)
	return {"ok": true, "ticks": ticks}


# The router. Every one of these five already exists, already validates its own window and
# already returns {ok, reason}; this adds a command path and nothing else. The two surgical
# verbs go through the channel first and are answered by SimInfection at completion.
static func respond(world: Variant, actor: int, patient: int, part: String, verb: String) -> Dictionary:
	if SURGERY_VERBS.has(verb):
		# Passed for symmetry and for the next reader: surgery is never self-pressure, so this
		# still refuses a held actor, which is R1 and is the point.
		var pre: Dictionary = _can_begin(world, actor, patient, verb)
		if not bool(pre.get("ok", false)):
			return pre
		_engage(world, actor, patient, part, verb, int(SURGERY_TICKS.get(verb, 0)))
		return {"ok": true, "ticks": int(SURGERY_TICKS.get(verb, 0))}
	if not INSTANT_VERBS.has(verb):
		return {"ok": false, "reason": "unknown-verb"}
	if actor != patient and not _in_reach(world, actor, patient):
		return {"ok": false, "reason": "out-of-reach"}
	return _invoke_infection(world, patient, part, verb)


# One key, decided in the sim. `use.context` already picks a bed, a fire, a recruit or a
# window with no selection state in presentation at all, and first aid is the same kind of
# choice: there is one wound that matters, and the answer to it is a bandage if you have one
# and your hands otherwise. Building a survivor-selection UI for it would be inventing a
# decision the player does not actually have while a zombie is walking towards them.
#
# It also toggles: pressing it again while a channel is running cancels, the same way F means
# both "swing" and "struggle" depending on what is true. The refusal reason "cancelled" is
# how the intake knows not to complain about it.
static func context(world: Variant, actor: int) -> Dictionary:
	if world.components.has_component(actor, "treatment"):
		cancel(world, actor)
		return {"ok": false, "reason": "cancelled"}

	var target: int = _nearest_bleeding(world, actor)
	if target < 0:
		return {"ok": false, "reason": "nothing-to-treat"}
	var part: String = _worst_bleeding_part(world, target)
	if part == "":
		return {"ok": false, "reason": "nothing-to-treat"}
	# Reach for a dressing when there is one: it costs supply and time, and it is the only
	# one of the two that survives being interrupted.
	#
	# R7: not while somebody has hold of you. A held survivor carrying a sterile dressing would
	# otherwise pick `bandage` every tick, be refused `cannot-channel` every tick by R1, and bleed
	# to death with the answer in their pack -- the pick has to know what is actually legal, and
	# the one thing that is legal held is a hand on your own wound.
	var verb: String = "pressure"
	if not world.components.has_component(actor, "grabbed") and String(_best_bandage(world, actor).get("tier", "")) != "":
		verb = "bandage"
	return begin(world, actor, target, part, verb)


# Self first, then the nearest bleeding body in reach. Self first because a survivor who is
# losing blood and reaches for someone else's arm is not a decision anyone meant to make.
static func _nearest_bleeding(world: Variant, actor: int) -> int:
	if _worst_bleeding_part(world, actor) != "":
		return actor
	var best: int = -1
	var best_d: float = INF
	var a: Variant = world.components.get_component(actor, "position")
	if not (a is Dictionary):
		return -1
	for entity in world.components.query(["injuries", "position", "body"]):
		if int(entity) == actor or world.components.has_component(int(entity), "corpse"):
			continue
		if _worst_bleeding_part(world, int(entity)) == "":
			continue
		if not _in_reach(world, actor, int(entity)):
			continue
		var b: Dictionary = world.components.get_component(int(entity), "position") as Dictionary
		var dx: float = float(b["x"]) - float((a as Dictionary)["x"])
		var dy: float = float(b["y"]) - float((a as Dictionary)["y"])
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(entity)
	return best


# The part carrying the worst open wound, or "" if nothing on this body is bleeding. Ties go
# to SURVIVOR_BODY_PARTS order, which is head-down -- the same order the condition view reads
# in, so the sim's pick and the screen's list agree about which wound is "the" wound.
static func _worst_bleeding_part(world: Variant, entity: int) -> String:
	var inj: Variant = world.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return ""
	var best_part: String = ""
	var best_sev: int = -1
	for part in SimCombat.SURVIVOR_BODY_PARTS:
		for wound in _open_wounds(world, entity, String(part)):
			var sev: int = int((wound as Dictionary).get("severity", 0))
			if sev > best_sev:
				best_sev = sev
				best_part = String(part)
	return best_part


static func cancel(world: Variant, entity: int) -> void:
	var t: Variant = world.components.get_component(entity, "treatment")
	if t is Dictionary:
		world.components.remove(int((t as Dictionary).get("patient", -1)), "treated")
	world.components.remove(entity, "treatment")


# --- channel ------------------------------------------------------------------------

static func _engage(world: Variant, actor: int, patient: int, part: String, verb: String, ticks: int) -> void:
	world.components.set_component(actor, "treatment", {"verb": verb, "patient": patient, "part": part, "ticksLeft": ticks})
	world.components.set_component(patient, "treated", {"treater": actor, "verb": verb, "part": part})
	world.events.publish({"type": "treatment.begun", "entity": actor, "patient": patient, "bodyPart": part, "verb": verb, "ticks": ticks})


static func _tick_channel(world: Variant, entity: int) -> void:
	var t: Variant = world.components.get_component(entity, "treatment")
	if not (t is Dictionary):
		return
	var state: Dictionary = t as Dictionary
	var patient: int = int(state.get("patient", -1))

	# Re-checked every tick, not only at _start. fortify.gd checks reach once and lets you
	# walk away from a board that finishes anyway; treatment must not inherit that. The
	# treater is pinned by treatment.pin, so this fires when the *patient* is moved by
	# something else -- dragged by a grab, carried, teleported by a scenario -- which is
	# exactly the case where the dressing should come apart.
	# The R1 exemption is re-derived from the running channel's own state rather than remembered
	# from begin-time, so a channel cannot carry a permission it would no longer be granted: a
	# bandage that was legal when it started is cancelled the moment a hand closes on the treater,
	# while a self-press keeps running.
	var self_press: bool = String(state.get("verb", "")) == "pressure" and patient == entity
	if not _can_channel(world, entity, self_press) or (patient != entity and not _in_reach(world, entity, patient)):
		_refuse(world, entity, String(state.get("verb", "")), "interrupted")
		cancel(world, entity)
		return

	state["ticksLeft"] = int(state.get("ticksLeft", 0)) - 1
	if int(state["ticksLeft"]) > 0:
		return
	_complete(world, entity, patient, String(state.get("part", "")), String(state.get("verb", "")))
	cancel(world, entity)


static func _complete(world: Variant, actor: int, patient: int, part: String, verb: String) -> void:
	if SURGERY_VERBS.has(verb):
		_invoke_infection(world, patient, part, verb)
		return

	# Re-validated at completion, the way fortify._place_scrap re-validates before consuming.
	# An interrupted channel has cost nothing, and a channel that finishes after the wound
	# already clotted (or after the last bandage was used elsewhere) simply fails -- both
	# fall out of the structure rather than needing their own guards.
	var open: Array = _open_wounds(world, patient, part)
	if open.is_empty():
		return

	var tier: String = "none"
	if verb == "bandage":
		var best: Dictionary = _best_bandage(world, actor)
		tier = String(best.get("tier", ""))
		if tier == "":
			_refuse(world, actor, verb, "no-bandage")
			return
		if not SimNeeds.consume_base(world, actor, String(best.get("baseId", ""))):
			_refuse(world, actor, verb, "no-bandage")
			return

	for wound in open:
		var wd: Dictionary = wound as Dictionary
		wd["bleeding"] = false
		if verb == "bandage":
			wd["bandage"] = tier
	world.events.publish({"type": "wound.treated", "entity": patient, "treater": actor, "bodyPart": part, "verb": verb, "tier": tier, "wounds": open.size()})


# A stagger or a grab lands on one entity, and that entity may be either end of a treatment:
# being staggered mid-bandage ruins your own work, and being staggered while someone is
# bandaging *you* ruins theirs. Both directions cancel the one channel.
static func _interrupt(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	if world.components.has_component(entity, "treatment"):
		cancel(world, entity)
	var treated: Variant = world.components.get_component(entity, "treated")
	if treated is Dictionary:
		cancel(world, int((treated as Dictionary).get("treater", -1)))


# R2. A grab is not a stagger, and this is the one place the two part company. Everything a new
# hold touches comes apart -- the victim's own bandage, the dressing somebody else was holding on
# them -- except the victim pressing on their own wound, which is the thing they are allowed to
# keep doing (R1) and which a second set of hands closing on them does not physically undo.
#
# Both branches are needed and neither subsumes the other: the first is the victim as treater, the
# second the victim as patient. `treater != entity` is what separates a self-press (kept) from
# someone else's dressing on a newly grabbed patient (cancelled) in the second branch, and the
# first branch has already removed a self-*bandage*'s `treated` by the time we look.
static func _interrupt_grab(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	var running: Variant = world.components.get_component(entity, "treatment")
	if running is Dictionary and not _is_self_pressure(running as Dictionary, entity):
		cancel(world, entity)
	var treated: Variant = world.components.get_component(entity, "treated")
	if treated is Dictionary:
		var treater: int = int((treated as Dictionary).get("treater", -1))
		if treater != entity:
			cancel(world, treater)


static func _is_self_pressure(state: Dictionary, entity: int) -> bool:
	return String(state.get("verb", "")) == "pressure" and int(state.get("patient", -1)) == entity


# --- infection routing ----------------------------------------------------------------

static func _invoke_infection(world: Variant, patient: int, part: String, verb: String) -> Dictionary:
	var res: Dictionary = {"ok": false, "reason": "unknown-verb"}
	match verb:
		"cauterize":
			res = SimInfection.cauterize(world, patient, part)
		"amputate":
			res = SimInfection.amputate(world, patient, part)
		"antibiotics":
			res = SimInfection.use_antibiotics(world, patient)
		"quarantine":
			res = SimInfection.quarantine(world, patient)
		"put_down":
			res = SimInfection.put_down(world, patient)
	world.events.publish({
		"type": "infection.responded",
		"entity": patient,
		"verb": verb,
		"bodyPart": part,
		"ok": bool(res.get("ok", false)),
		"reason": String(res.get("reason", "")),
	})
	return res


# --- preconditions --------------------------------------------------------------------

# `verb` is optional only so that a caller with nothing to declare cannot accidentally claim the
# R1 exemption: no verb means no exemption, which is the safe direction. The three real callers
# (begin, respond's surgery branch, _dry_run) all pass theirs.
static func _can_begin(world: Variant, actor: int, patient: int, verb: String = "") -> Dictionary:
	if world.components.has_component(actor, "treatment"):
		return {"ok": false, "reason": "busy"}
	if world.components.has_component(patient, "treated"):
		return {"ok": false, "reason": "patient-busy"}
	if not _can_channel(world, actor, verb == "pressure" and actor == patient):
		return {"ok": false, "reason": "cannot-channel"}
	if actor != patient and not _in_reach(world, actor, patient):
		return {"ok": false, "reason": "out-of-reach"}
	return {"ok": true}


# No channelling from a crawl or a sprint, and none at all while held -- with the single R1
# exemption the caller has to ask for by name. `self_pressure` is not a "let me through" flag a
# caller may set to taste: every call site derives it from the verb and the patient, so the only
# thing it can ever unlock is a hand on the actor's own wound.
#
# The posture clause is deliberately skipped rather than also checked on the held path, and that
# is a judgement worth stating: a survivor who was sprinting when a hand closed on them is pinned
# by shambler.pin from that tick on, so the sprint is a stale reading of a body that is no longer
# going anywhere. Refusing on it would make aid-while-held depend on what you were doing a tick
# before you got grabbed. fortify.gd keeps its own copy of this check, unchanged and unexempted --
# boarding a window with a zombie on your arm remains exactly as illegal as it sounds.
static func _can_channel(world: Variant, entity: int, self_pressure: bool = false) -> bool:
	if world.components.has_component(entity, "grabbed"):
		return self_pressure
	var posture: Variant = world.components.get_component(entity, "posture")
	if posture == null:
		return true
	var stance: int = int((posture as Dictionary).get("current", 2))
	return stance != 0 and stance != 4


static func _in_reach(world: Variant, actor: int, other: int) -> bool:
	var a: Variant = world.components.get_component(actor, "position")
	var b: Variant = world.components.get_component(other, "position")
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var dx: float = float((b as Dictionary)["x"]) - float((a as Dictionary)["x"])
	var dy: float = float((b as Dictionary)["y"]) - float((a as Dictionary)["y"])
	return dx * dx + dy * dy <= REACH * REACH


# Velocity's keys are dx/dy, not x/y -- position uses x/y and velocity does not, and writing
# the wrong pair adds a silently-ignored key rather than raising. shambler.pin is the
# in-repo precedent for both the phase slot and the key names.
static func _still(world: Variant, entity: int) -> void:
	var vel: Variant = world.components.get_component(entity, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0


static func _refuse(world: Variant, actor: int, verb: String, reason: String) -> void:
	world.events.publish({"type": "treatment.refused", "entity": actor, "verb": verb, "reason": reason})


# --- reads ------------------------------------------------------------------------------

# Open == still bleeding. A wound that has clotted, or one already under a dressing, is not
# something pressure or a bandage has anything to do with.
static func _open_wounds(world: Variant, entity: int, part: String) -> Array:
	var out: Array = []
	var inj: Variant = world.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return out
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		var wd: Dictionary = wound as Dictionary
		if String(wd.get("bodyPart", "")) != part:
			continue
		if not bool(wd.get("bleeding", false)):
			continue
		out.append(wd)
	return out


# The channel's length comes from the worst wound on the part, and completion then treats
# every open wound on it. Treating a part is one act of first aid, not one per laceration.
static func _worst_open_wound(world: Variant, entity: int, part: String) -> Variant:
	var worst: Variant = null
	for wound in _open_wounds(world, entity, part):
		var wd: Dictionary = wound as Dictionary
		if worst == null or int(wd.get("severity", 0)) > int((worst as Dictionary).get("severity", 0)):
			worst = wd
	return worst


# The best dressing this actor is carrying, as {tier, baseId}, or {} if none. Reads the
# content entry's flat `bandageTier`, so adding a tier is a data edit -- no branch here
# learns a new item id.
static func _best_bandage(world: Variant, actor: int) -> Dictionary:
	var best_rank: int = TIER_ORDER.size()
	var out: Dictionary = {}
	for item in SimInventory.carried_items(world, actor):
		var base: Variant = SimItems.item_base_of(world, int(item))
		if not (base is Dictionary):
			continue
		var tier: String = String((base as Dictionary).get(TIER_KEY, ""))
		if tier == "":
			continue
		var rank: int = TIER_ORDER.find(tier)
		if rank < 0 or rank >= best_rank:
			continue
		best_rank = rank
		out = {"tier": tier, "baseId": String((base as Dictionary).get("id", ""))}
	return out


# The read model the panel uses to decide which verbs to offer. Same {ok, reason} the sim
# returns, computed by the sim, so the screen and the sim cannot disagree about whether a
# verb is available -- and no numbers cross the boundary.
static func options_for(world: Variant, actor: int, patient: int, part: String) -> Array:
	var out: Array = []
	for verb in CHANNEL_VERBS:
		var res: Dictionary = _dry_run(world, actor, patient, part, verb)
		out.append({"verb": verb, "ok": bool(res.get("ok", false)), "reason": String(res.get("reason", ""))})
	return out


static func _dry_run(world: Variant, actor: int, patient: int, part: String, verb: String) -> Dictionary:
	var pre: Dictionary = _can_begin(world, actor, patient, verb)
	if not bool(pre.get("ok", false)):
		return pre
	if _worst_open_wound(world, patient, part) == null:
		return {"ok": false, "reason": "not-bleeding"}
	if verb == "bandage" and String(_best_bandage(world, actor).get("tier", "")) == "":
		return {"ok": false, "reason": "no-bandage"}
	return {"ok": true}
