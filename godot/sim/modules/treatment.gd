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
#   clean     costs a cleaning supply and buys docs/05's sepsis discount. It does not stop a bleed.
#   close     costs a suture kit, refuses a wound that is still bleeding, and needs a medic for a
#             deep one. See the constant block below for what each of the two later rungs reads.
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
# system, _cancel driven by subscriptions to entity.staggered, grab.started and grab.broken.
# The swing and fire state machines are the wrong template -- a channel is one committed span
# with a cancel, not a multi-phase cycle.
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
#   R5  Becoming *fully free* cancels your own self-pressure, and only that. `grab.broken` names
#       one victim; `treatment.escape-releases-press` ends that victim's hand on their own wound so
#       the break-away is a run rather than a pause. This is the inversion of the rule that shipped
#       first ("treatment.pin outranks breakAway; flight happens between channels"), and it was
#       inverted on measurement rather than taste: with the press winning, 94 of 120 escapes on
#       seed 404 were mid-press, 89 of the 91 following re-grab windows were exactly
#       REGRAB_COOLDOWN_TICKS and not one exceeded it, and total grabs *rose* 149 -> 214. The
#       survivors using the aid were exactly the ones the break-away no longer moved.
#       Ordering, by design and gate-asserted (FLIGHT-CANCELS-PRESS): `grab.broken` drains at the
#       END of the escape tick, so on that tick the press still exists and `treatment.pin` still
#       zeroes velocity -- the escapee spends one of breakAway's 26 ticks pinned while the holder
#       keeps closing, and flight begins the tick after. That is a tick of stumble, not a bug to
#       engineer around, and it costs about 0.105 m of the gap.
#   R6  `treatment.self-aid` will not *start* a channel while `breakAway` is running: get clear
#       first, then kneel. R5 and R6 now compose rather than divide the same moment between them --
#       R5 ends the press at the escape, R6 holds the next one off until the running is done, and
#       the press re-opens the tick after `breakAway` goes. It goes at expiry *or* the moment a new
#       hold removes it (`shambler.pin`), so a re-taken survivor is pressing again within a tick or
#       two rather than waiting out the full 26.
#   R7  `context()` picks `pressure` while the actor is grabbed even when they are carrying a
#       dressing, or a held bandage-carrier would be refused every tick and never treat anything.
#   R8  A press banks the time it has already served, on the wound rather than on the presser, and
#       a later press on that part starts from what is left. R5 is what made this necessary: with
#       the escape cancelling the press, a 400-tick deep-wound press has no reachable completion
#       path while holds arrive every ~50 ticks, and the balance harness measured exactly that --
#       126 presses begun and *zero completed* across ten compressed days of seed 404, with all
#       three deaths blood loss. Fragments that bank add up; fragments that do not are wasted
#       motion. The bank lives on the wound, so whoever picks the press up next inherits it: a
#       medic finishing what the patient started with their own hand is the same wound getting the
#       same total pressure, and there is no reason for the sim to care whose palm it was.
#       Two exceptions, and both are the rule saying what it costs. A **stagger** banks nothing --
#       R3 already singles it out as the one thing that takes your hand off your own arm, and being
#       knocked off your feet undoing the work is what makes that rule mean something. And
#       **bandaging never banks**: a dressing is applied, not accumulated, and it spends a supply
#       at completion. The bank does not decay -- deliberately; pressure that has been held is
#       progress toward a clot, and a decay clock would be a second timer nothing else in the
#       module has -- but it is cleared whenever the wound stops being the same wound, which is at
#       completion and at `wounds.reopen`.
#   R9  A landed hit -- `attack.connected` on either participant -- interrupts the channel, and it
#       banks (R8): a claw ripping you away from a press does not un-press what was held, the way a
#       stagger (R3, banks nothing) knocks it all loose. The swipe made this rule necessary and the
#       diagnosis driver dated it: with nothing but grabs and staggers able to interrupt, a swiped
#       colonist on seed 404 spent 378 ticks kneeling mid-fight and died there, head first, having
#       fought back not once. Bites stay R2's business, and a swipe never targets a held body, so
#       this rule only ever fires on the free -- the held arbitration above is untouched.
#   R10 `treatment.self-aid` will not *start* a channel while a live shambler stands in
#       SWIPE_METRES of a free survivor: with a claw in striking range you fight or you run, and
#       kneeling is what the driver measured it to be -- a death. The radius is the swipe's own
#       reach, not CONTACT_METRES, and the first cut of this rule paid for the difference: a
#       break-away ends about 1.4-1.5 m out, inside contact but outside the claw, so at 1.6 the
#       press R5 cancels could never re-open and R6's "deferred" quietly became "closed" -- the
#       contact gate's FLIGHT-CANCELS-PRESS caught it. Reading SWIPE_METRES keeps "too close to
#       kneel" and "close enough to be struck" the same number by construction. A *held* survivor
#       is exempt: R1 grants them the self-press exactly because fighting is no longer among
#       their options.
#
# Why coexistence rather than "pressing costs you the hold": every new hold resets the bite clock
# (`_start_grab` writes a fresh ticksUntilBite), and a struggle cycle resolves at ~17-33 ticks with
# p 0.667, so a press that suppressed struggling would take roughly five bites across a 400-tick
# deep-wound hold and never end. Coexisting, the press runs across grab and escape cycles, the
# bleed is suppressed the whole time it is held (wounds.bleed reads `treated` directly), and it
# clots at completion.

const SimWounds = preload("res://sim/modules/wounds.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
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

# --- the back half of the ladder: clean, then close ------------------------------------------
#
# docs/05's first aid is four steps and only two of them were verbs: you stop the bleeding, you
# clean the wound, you close it, and then it heals while the survivor rests. `pressure` and
# `bandage` were the first rung; `SimWounds._is_recovering` has been the fourth since Slice 3 (fed
# and not exerting is the rest rung, and it was already built and already gated). These are the two
# in the middle, and they are two more entries in the tables above rather than a second state
# machine -- everything about a channel, its interrupts, its pin, its R1..R10 arbitration and its
# per-tick re-check is verb-agnostic, and inheriting all of it is the point.
#
#   clean  spends one cleaning supply and stamps the grade onto every open-or-undressed wound of
#          the part. Its whole effect is `SimWounds.sepsis_chance`'s clean term -- docs/05's third
#          factor, which had been named in that function's own comment and applied by nothing.
#          It does **not** stop a bleed, so cleaning is time spent losing blood.
#   close  spends one suture kit and holds the wound shut. Its two readers already existed:
#          `wounds.recover` gives a closed wound `CLOSED_RECOVERY_MUL` on its earned tick, and
#          `_reopen_from_overwork` will not tear one open. It refuses a wound that is still
#          bleeding -- you close what you have already stopped -- and refuses a deep wound below
#          `CLOSE_MEDICINE_FLOOR` Medicine, which is the one place on this ladder a skill wall sits.
#
# Both flat content keys, for the reason `bandageTier` is one: the validator is shallow, and a
# scalar under an enum is the only part of an item entry it actually checks.
const CLEAN_KEY: String = "cleanTier"
const CLOSE_KEY: String = "closeKind"
# Best first, and the rank doubles as the pick order the way TIER_ORDER does: reach for the
# antiseptic before rinsing it with the drinking water. `alcohol` is declared and unauthored --
# no content entry carries it yet -- and is named as such in docs/23 rather than left to look wired.
const CLEAN_ORDER: Array[String] = ["antiseptic", "alcohol", "water"]
# What `close` will accept out of the pack. `splint` is deferred with the fracture immobilisation
# it belongs to (docs/23); a kit that declares it is refused rather than silently sutured with.
const CLOSE_KINDS: Array[String] = ["suture"]
# R8's bank, a key on the wound record rather than a component: it belongs to the injury, outlives
# every individual press, and is read back by whoever presses next.
const BANK_KEY: String = "pressedTicks"

# Surgery is a channel, not an instant. These are the spans; the window that decides whether
# the surgery still helps belongs to SimInfection and is judged when the channel completes.
const SURGERY_TICKS: Dictionary = {
	"cauterize": 300,
	"amputate": 900,
}

const CHANNEL_VERBS: Array[String] = ["pressure", "bandage", "clean", "close"]
const SURGERY_VERBS: Array[String] = ["cauterize", "amputate"]
# `painkillers` sits with the infection verbs rather than with the channels because it is the same
# shape: instant, its own precondition list, its own {ok, reason}. It is answered by SimWounds
# rather than SimInfection -- pain is a wound property -- which is why _invoke_infection is no
# longer the only destination this router has.
const INSTANT_VERBS: Array[String] = ["antibiotics", "quarantine", "put_down", "painkillers"]


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
			# the press would re-open on the tick after the escape and treatment.pin would zero the
			# break-away's velocity -- the survivor would stand exactly where they escaped from and
			# press, which is the treadmill the break-away exists to end. R5 takes the old press
			# away at the escape; this is what stops a new one being opened in its place before the
			# running is done. The wait is `breakAway`'s life, not a fixed 26: a re-grab removes the
			# component, so a survivor who is caught again is pressing again almost at once.
			if w.components.has_component(e, "breakAway"):
				continue
			# R10: fight or run first, kneel when clear. Held bodies are exempt -- R1 is their
			# whole answer -- and the radius is the shambler's own CONTACT_METRES, not a copy.
			if not w.components.has_component(e, "grabbed") and _claw_in_reach(w, e):
				continue
			# Every rung, not just the bleeding one. `context` is the one first-aid decision
			# procedure in this simulation, and gating entry to it on "is this body bleeding"
			# would have left the two new verbs reachable only by the player's own key.
			if not _needs_care(w, e):
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
	# R9. Distinct from the stagger interrupt in exactly one way: it banks. A zombie target has
	# neither component and the call is a no-op, so a survivor's swing landing on a shambler
	# costs nobody a channel.
	world.events.subscribe({"id": "treatment.hit-interrupts", "type": "attack.connected", "handler": func(event: Dictionary) -> void:
		_interrupt_struck(world, int(event.get("target", -1)))
	})
	world.events.subscribe({"id": "treatment.grab-interrupts", "type": "grab.started", "handler": func(event: Dictionary) -> void:
		_interrupt_grab(world, int(event.get("victim", -1)))
	})
	# R5, and the exact mirror of the one above. `grab.broken` is published once, at the single
	# point a victim goes from held to fully free, so this fires on an escape, a rescue or the
	# holder dying -- everything that means "you can move now".
	world.events.subscribe({"id": "treatment.escape-releases-press", "type": "grab.broken", "handler": func(event: Dictionary) -> void:
		_interrupt_escape(world, int(event.get("victim", -1)))
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

	var plan: Dictionary = _plan(world, actor, patient, part, verb)
	if not bool(plan.get("ok", false)):
		return plan

	_engage(world, actor, patient, part, verb, int(plan.get("ticks", 0)))
	return {"ok": true, "ticks": int(plan.get("ticks", 0))}


# Everything about a verb that is not the actor-and-posture arbitration `_can_begin` owns: is there
# anything on this part for it to do, is the supply in the pack, and how long does it take. One
# function so `begin` and `options_for`'s dry run cannot answer the same question differently --
# they used to be two lists of checks kept in step by hand, and a fourth verb is exactly how that
# ends badly.
static func _plan(world: Variant, actor: int, patient: int, part: String, verb: String) -> Dictionary:
	var wound: Variant = _worst_target(world, patient, part, verb)
	if wound == null:
		return {"ok": false, "reason": _nothing_reason(world, patient, part, verb)}
	var severity: int = int((wound as Dictionary).get("severity", SimWounds.Severity.Scratch))

	var ticks: int = 0
	match verb:
		"pressure":
			# R8: what is left, not what it costs from cold. Floored at one tick rather than zero so
			# a fully-banked wound still runs a channel and clots through the ordinary _complete
			# path -- returning "nothing-to-do" here would strand a wound one tick short of closed.
			ticks = maxi(1, int(SimWounds.PRESSURE_TICKS.get(severity, 0)) - _banked(wound as Dictionary))
		"bandage":
			if String(_best_bandage(world, actor).get("tier", "")) == "":
				return {"ok": false, "reason": "no-bandage"}
			ticks = int(SimWounds.BANDAGE_TICKS.get(severity, 0))
		"clean":
			if String(_best_clean(world, actor).get("tier", "")) == "":
				return {"ok": false, "reason": "no-supply"}
			ticks = int(SimWounds.CLEAN_TICKS.get(severity, 0))
		"close":
			# You close what you have already stopped. Checked before the kit and before the skill
			# so the reason the panel shows is the one the survivor can actually act on.
			if not _open_wounds(world, patient, part).is_empty():
				return {"ok": false, "reason": "still-bleeding"}
			if severity >= SimWounds.Severity.DeepWound and _medicine_of(world, actor) < SimWounds.CLOSE_MEDICINE_FLOOR:
				return {"ok": false, "reason": "unskilled"}
			if String(_best_closer(world, actor).get("kind", "")) == "":
				return {"ok": false, "reason": "no-kit"}
			ticks = int(SimWounds.CLOSE_TICKS.get(severity, 0))
	if ticks <= 0:
		return {"ok": false, "reason": "nothing-to-do"}
	return {"ok": true, "ticks": ticks}


# Why there was nothing to work on. `pressure` and `bandage` keep "not-bleeding" verbatim -- it is
# the vocabulary the panel already speaks and the gate already asserts -- and the two new verbs say
# what is actually true of them: a bleeding wound is not refused "not-bleeding" by `close`, it is
# refused "still-bleeding", which is the opposite problem and a different thing to do about it.
static func _nothing_reason(world: Variant, patient: int, part: String, verb: String) -> String:
	if verb == "pressure" or verb == "bandage":
		return "not-bleeding"
	if verb == "close" and not _open_wounds(world, patient, part).is_empty():
		return "still-bleeding"
	return "nothing-to-do"


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
	if verb == "painkillers":
		# Taken by the patient, from the patient's own supply: a blister goes in a mouth, and
		# routing it through the actor's pack would let a medic dose somebody out of a bag the
		# patient cannot reach.
		return SimWounds.take_painkillers(world, patient)
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

	var target: int = _nearest_needing_care(world, actor)
	if target < 0:
		return {"ok": false, "reason": "nothing-to-treat"}
	var held: bool = world.components.has_component(actor, "grabbed")

	# Rung one, and it outranks everything: blood loss is the only thing on this ladder that kills.
	var bleeding_part: String = _worst_bleeding_part(world, target)
	if bleeding_part != "":
		# Reach for a dressing when there is one: it costs supply and time, and it is the only
		# one of the two that survives being interrupted.
		#
		# R7: not while somebody has hold of you. A held survivor carrying a sterile dressing would
		# otherwise pick `bandage` every tick, be refused `cannot-channel` every tick by R1, and
		# bleed to death with the answer in their pack -- the pick has to know what is actually
		# legal, and the one thing that is legal held is a hand on your own wound.
		var verb: String = "pressure"
		if not held and String(_best_bandage(world, actor).get("tier", "")) != "":
			verb = "bandage"
		return begin(world, actor, target, bleeding_part, verb)

	# R7 again, and the reason this is a guard rather than a fall-through: `clean` and `close`
	# inherit R1's refusal (the exemption `_can_begin` derives is `pressure` and self, by name), so
	# a held survivor with nothing bleeding has no legal rung. Offering one anyway would publish a
	# `cannot-channel` refusal every tick for as long as the hold lasted.
	if held:
		return {"ok": false, "reason": "nothing-to-treat"}

	# Rungs two and three, in order, each skipped rather than refused when its supply is missing:
	# a survivor with no antiseptic and a suture kit should sew, not stall on the rung they cannot
	# pay for. Rung four is `SimWounds._is_recovering` and needs no verb -- resting is what a
	# survivor does when this function has nothing left to offer.
	if String(_best_clean(world, actor).get("tier", "")) != "":
		var dirty: String = _worst_part_for(world, target, "clean")
		if dirty != "":
			return begin(world, actor, target, dirty, "clean")
	if String(_best_closer(world, actor).get("kind", "")) != "":
		var openable: String = _worst_part_for(world, target, "close")
		if openable != "":
			var res: Dictionary = begin(world, actor, target, openable, "close")
			# "unskilled" is a refusal the ladder should absorb rather than repeat: a survivor who
			# cannot suture a deep wound is not going to become able to between ticks, and the one
			# key would otherwise complain forever.
			if bool(res.get("ok", false)) or String(res.get("reason", "")) != "unskilled":
				return res
	return {"ok": false, "reason": "nothing-to-treat"}


# Self first, then the nearest body in reach that wants any rung of the ladder. Self first because
# a survivor who is losing blood and reaches for someone else's arm is not a decision anyone meant
# to make.
#
# This used to ask only about bleeding, which was correct while bleeding was the only thing a verb
# could answer. Left that way, `clean` and `close` would have been reachable exclusively through a
# direct `begin` -- player-only, unreachable by every survivor the player is not personally
# standing beside, and a dead socket the moment the T key had walked its own ladder to the end.
static func _nearest_needing_care(world: Variant, actor: int) -> int:
	if _needs_care(world, actor):
		return actor
	var best: int = -1
	var best_d: float = INF
	var a: Variant = world.components.get_component(actor, "position")
	if not (a is Dictionary):
		return -1
	for entity in world.components.query(["injuries", "position", "body"]):
		if int(entity) == actor or world.components.has_component(int(entity), "corpse"):
			continue
		if not _needs_care(world, int(entity)):
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


# The same pick, for a verb other than the bleeding pair. Same head-down tie-break, so the sim and
# the condition view still agree about which wound is "the" wound whichever rung is being offered.
static func _worst_part_for(world: Variant, entity: int, verb: String) -> String:
	var best_part: String = ""
	var best_sev: int = -1
	for part in SimCombat.SURVIVOR_BODY_PARTS:
		for wound in _targets(world, entity, String(part), verb):
			var sev: int = int((wound as Dictionary).get("severity", 0))
			if sev > best_sev:
				best_sev = sev
				best_part = String(part)
	return best_part


# Is there any rung of the ladder this body wants? Bleeding, dirty, or stopped and unsutured.
# Whether the *actor* can pay for the rung is not asked here -- `context` decides that, and a body
# whose only need is a suture kit nobody is carrying is still a body that needs care.
static func _needs_care(world: Variant, entity: int) -> bool:
	if _worst_bleeding_part(world, entity) != "":
		return true
	return _worst_part_for(world, entity, "clean") != "" or _worst_part_for(world, entity, "close") != ""


# `banked` is R8's one exception hatch: a stagger passes false and every other end to a channel
# takes the default. Completion calls it too -- _tick_channel completes and then cancels -- and
# banking there is a no-op twice over: _complete has already cleared the key and stopped the
# bleeding, so _open_wounds finds nothing left to write to.
static func cancel(world: Variant, entity: int, banked: bool = true) -> void:
	var t: Variant = world.components.get_component(entity, "treatment")
	if t is Dictionary:
		if banked:
			_bank_pressure(world, t as Dictionary)
		world.components.remove(int((t as Dictionary).get("patient", -1)), "treated")
	world.components.remove(entity, "treatment")


# R8. Writes the ticks this channel actually served onto every open wound of the part it was
# aimed at, capped at the part's own pressure cost so a run of interrupted presses cannot bank
# past what one uninterrupted press would have paid. Pressure only: a dressing is applied, not
# accumulated.
static func _bank_pressure(world: Variant, state: Dictionary) -> void:
	if String(state.get("verb", "")) != "pressure":
		return
	var served: int = int(state.get("ticks", 0)) - int(state.get("ticksLeft", 0))
	if served <= 0:
		return
	var patient: int = int(state.get("patient", -1))
	for wound in _open_wounds(world, patient, String(state.get("part", ""))):
		var wd: Dictionary = wound as Dictionary
		var cost: int = int(SimWounds.PRESSURE_TICKS.get(int(wd.get("severity", SimWounds.Severity.Scratch)), 0))
		wd[BANK_KEY] = mini(cost, _banked(wd) + served)


static func _banked(wound: Dictionary) -> int:
	return int(wound.get(BANK_KEY, 0))


# --- channel ------------------------------------------------------------------------

static func _engage(world: Variant, actor: int, patient: int, part: String, verb: String, ticks: int) -> void:
	# `ticks` is carried alongside `ticksLeft` so R8 can derive what a cancelled channel served
	# without a second counter to keep in step with the decrement.
	world.components.set_component(actor, "treatment", {"verb": verb, "patient": patient, "part": part, "ticksLeft": ticks, "ticks": ticks})
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
	var targets: Array = _targets(world, patient, part, verb)
	if targets.is_empty():
		return

	# The supply, chosen and spent at completion for all three verbs that cost one. Same
	# re-validate-then-consume order fortify._place_scrap uses: an interrupted channel has cost
	# nothing, and a channel that finishes after the last dressing went elsewhere simply fails.
	var tier: String = "none"
	match verb:
		"bandage":
			var best: Dictionary = _best_bandage(world, actor)
			tier = String(best.get("tier", ""))
			if tier == "" or not SimNeeds.consume_base(world, actor, String(best.get("baseId", ""))):
				_refuse(world, actor, verb, "no-bandage")
				return
		"clean":
			var supply: Dictionary = _best_clean(world, actor)
			tier = String(supply.get("tier", ""))
			if tier == "" or not SimNeeds.consume_base(world, actor, String(supply.get("baseId", ""))):
				_refuse(world, actor, verb, "no-supply")
				return
		"close":
			var kit: Dictionary = _best_closer(world, actor)
			tier = String(kit.get("kind", ""))
			if tier == "" or not SimNeeds.consume_base(world, actor, String(kit.get("baseId", ""))):
				_refuse(world, actor, verb, "no-kit")
				return

	for wound in targets:
		var wd: Dictionary = wound as Dictionary
		match verb:
			"pressure", "bandage":
				wd["bleeding"] = false
				# R8: this wound has been answered, so the bank it accumulated is spent. Cleared
				# rather than left to be ignored, because SimWounds.reopen can make the same record
				# bleed again and a stale bank would hand the second press the first one's work.
				wd.erase(BANK_KEY)
				if verb == "bandage":
					wd["bandage"] = tier
			"clean":
				# Deliberately does not touch `bleeding`: cleaning a wound is not stopping it, and
				# a clean that closed a bleed would make the first rung optional.
				wd["cleaned"] = true
				wd["cleanTier"] = tier
			"close":
				wd["closed"] = true
	world.events.publish({"type": "wound.treated", "entity": patient, "treater": actor, "bodyPart": part, "verb": verb, "tier": tier, "wounds": targets.size()})


# A stagger lands on one entity, and that entity may be either end of a treatment: being
# staggered mid-bandage ruins your own work, and being staggered while someone is bandaging *you*
# ruins theirs. Both directions cancel the one channel.
#
# R3 and R8 meet here, and this is the only place they do: `banked` is false, so a stagger is the
# one end to a press that keeps nothing. That is what stops R8 from making pressure free -- every
# other interruption is the world moving you along, and a stagger is you losing the wound.
static func _interrupt(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	if world.components.has_component(entity, "treatment"):
		cancel(world, entity, false)
	var treated: Variant = world.components.get_component(entity, "treated")
	if treated is Dictionary:
		cancel(world, int((treated as Dictionary).get("treater", -1)), false)


# R2. A grab is not a stagger, and this is the one place the two part company. Everything a new
# hold touches comes apart -- the victim's own bandage, the dressing somebody else was holding on
# them -- except the victim pressing on their own wound, which is the thing they are allowed to
# keep doing (R1) and which a second set of hands closing on them does not physically undo.
#
# The symmetry with `_interrupt_escape` below is exact and deliberate, and it is the whole of the
# arbitration in two lines: `grab.started` cancels everything touching the victim EXCEPT their own
# self-pressure; `grab.broken` cancels ONLY their own self-pressure. A second holder does not peel
# your palm off your arm; becoming free is what takes it off, because that is the moment you have
# somewhere to be.
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


# R5. The victim's own self-pressure and nothing else: one entity, one component, no scan of the
# bodies around them. A free treater's channel on somebody who has just torn loose is *more*
# viable than it was a tick ago, not less -- the patient is no longer being dragged -- and
# `_tick_channel` re-checks reach every tick, so the case where flight actually does break that
# dressing is already answered by the geometry rather than needing a rule here.
#
# No `treatment.refused` is published, matching `_interrupt` and `_interrupt_grab`: the interrupts
# are things the world did to a channel, not the channel being denied, and the screen learns about
# them from the component going away.
static func _interrupt_escape(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	var running: Variant = world.components.get_component(entity, "treatment")
	if running is Dictionary and _is_self_pressure(running as Dictionary, entity):
		cancel(world, entity)


# R9. The _interrupt shape with the bank kept (cancel's default): the hit takes your hands off
# the wound, it does not unwind what the press already served.
static func _interrupt_struck(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	if world.components.has_component(entity, "treatment"):
		cancel(world, entity)
	var treated: Variant = world.components.get_component(entity, "treated")
	if treated is Dictionary:
		cancel(world, int((treated as Dictionary).get("treater", -1)))


# R10's reach test: a live shambler inside its own SWIPE_METRES of this body. Reads the swipe's
# radius rather than declaring one, so "close enough to be struck" and "too close to kneel" are
# the same number by construction -- see R10 for why it is the claw's reach and not contact.
static func _claw_in_reach(world: Variant, entity: int) -> bool:
	var at: Variant = world.components.get_component(entity, "position")
	if not (at is Dictionary):
		return false
	var reach_sq: float = SimShambler.SWIPE_METRES * SimShambler.SWIPE_METRES
	for z in world.components.query(["shambler", "position"]):
		var zbody: Variant = world.components.get_component(int(z), "body")
		if zbody is Dictionary and not SimHealth.is_alive(zbody as Dictionary):
			continue
		var zp: Dictionary = world.components.get_component(int(z), "position") as Dictionary
		var dx: float = float(zp["x"]) - float((at as Dictionary)["x"])
		var dy: float = float(zp["y"]) - float((at as Dictionary)["y"])
		if dx * dx + dy * dy <= reach_sq:
			return true
	return false


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


# What each verb has to work on, on this part. One selector per rung, and every caller goes through
# it: `_plan` for the channel length, `_complete` for what it writes, `context` for whether the rung
# is reachable at all. Treating a part is one act of first aid, not one per laceration, so all four
# answer with every wound the verb applies to.
static func _targets(world: Variant, entity: int, part: String, verb: String) -> Array:
	match verb:
		"clean":
			return _cleanable_wounds(world, entity, part)
		"close":
			return _closable_wounds(world, entity, part)
	return _open_wounds(world, entity, part)


# The channel's length comes from the worst wound on the part.
static func _worst_target(world: Variant, entity: int, part: String, verb: String = "pressure") -> Variant:
	var worst: Variant = null
	for wound in _targets(world, entity, part, verb):
		var wd: Dictionary = wound as Dictionary
		if worst == null or int(wd.get("severity", 0)) > int((worst as Dictionary).get("severity", 0)):
			worst = wd
	return worst


static func _worst_open_wound(world: Variant, entity: int, part: String) -> Variant:
	return _worst_target(world, entity, part, "pressure")


# Open or undressed, and not already cleaned. A wound under a dressing is out of reach of a bottle
# of antiseptic without taking the dressing off, and taking it off is not a verb -- which is
# exactly what makes "dress it dirty now" a decision with a price rather than a free ordering
# choice (docs/30). A closed injury (a fracture, a concussion) has nothing to clean.
static func _cleanable_wounds(world: Variant, entity: int, part: String) -> Array:
	var out: Array = []
	for wound in _wounds_on(world, entity, part):
		var wd: Dictionary = wound as Dictionary
		if bool(wd.get("cleaned", false)) or bool(wd.get("closed", false)):
			continue
		if not bool(SimWounds.kind_spec(String(wd.get("kind", "cut"))).get("bleeds", true)):
			continue
		if not bool(wd.get("bleeding", false)) and String(wd.get("bandage", "none")) != "none":
			continue
		out.append(wd)
	return out


# Stopped, not yet sutured, and the kind of injury a suture applies to.
static func _closable_wounds(world: Variant, entity: int, part: String) -> Array:
	var out: Array = []
	for wound in _wounds_on(world, entity, part):
		var wd: Dictionary = wound as Dictionary
		if bool(wd.get("bleeding", false)) or bool(wd.get("closed", false)):
			continue
		if not bool(SimWounds.kind_spec(String(wd.get("kind", "cut"))).get("bleeds", true)):
			continue
		out.append(wd)
	return out


static func _wounds_on(world: Variant, entity: int, part: String) -> Array:
	var out: Array = []
	var inj: Variant = world.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return out
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		if String((wound as Dictionary).get("bodyPart", "")) == part:
			out.append(wound)
	return out


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


# The best cleaning supply carried, as {tier, baseId}, or {} if none. Same shape and same rule as
# _best_bandage: the rank in CLEAN_ORDER is the pick order, and adding a grade is a data edit.
static func _best_clean(world: Variant, actor: int) -> Dictionary:
	return _best_by_key(world, actor, CLEAN_KEY, CLEAN_ORDER, "tier")


# The best closing kit carried, as {kind, baseId}, or {} if none. CLOSE_KINDS is one entry today,
# so this is a filter rather than a ranking -- but it is written as the ranking so `splint` landing
# beside `suture` is a content edit and an entry in the array, not a branch here.
static func _best_closer(world: Variant, actor: int) -> Dictionary:
	return _best_by_key(world, actor, CLOSE_KEY, CLOSE_KINDS, "kind")


static func _best_by_key(world: Variant, actor: int, key: String, order: Array[String], label: String) -> Dictionary:
	var best_rank: int = order.size()
	var out: Dictionary = {}
	for item in SimInventory.carried_items(world, actor):
		var base: Variant = SimItems.item_base_of(world, int(item))
		if not (base is Dictionary):
			continue
		var value: String = String((base as Dictionary).get(key, ""))
		if value == "":
			continue
		var rank: int = order.find(value)
		if rank < 0 or rank >= best_rank:
			continue
		best_rank = rank
		out = {label: value, "baseId": String((base as Dictionary).get("id", ""))}
	return out


# The treater's Medicine, read from the one place that owns it. The actor's, not the patient's:
# it is the hands doing the suturing that need to know what they are doing.
static func _medicine_of(world: Variant, actor: int) -> int:
	return int(SimSkills.points(world, actor, "Medicine"))


# The read model the panel uses to decide which verbs to offer. Same {ok, reason} the sim
# returns, computed by the sim, so the screen and the sim cannot disagree about whether a
# verb is available -- and no numbers cross the boundary.
static func options_for(world: Variant, actor: int, patient: int, part: String) -> Array:
	var out: Array = []
	for verb in CHANNEL_VERBS:
		var res: Dictionary = _dry_run(world, actor, patient, part, verb)
		out.append({"verb": verb, "ok": bool(res.get("ok", false)), "reason": String(res.get("reason", ""))})
	return out


# The other read model the screen offers from, and `options_for`'s companion: which of the
# infection responses is worth showing this survivor right now, as prose rows the body screen can
# draw and click. Same contract -- the sim decides what is on offer, so the screen cannot show a
# word the sim would refuse, and nothing numeric crosses the boundary.
#
# **Antibiotics only, deliberately.** The other four responses are not omissions to be tidied up
# later, and each is left out for its own reason, which is written down here rather than in a
# commit message: `quarantine` writes a record nothing reads (a no-op with a surface would be worse
# than a no-op without one); `cauterize` and `amputate` are aimed at a body *part* and `put_down` at
# a *person*, and none of the three has a way to say which -- a patient-and-part selection surface
# is its own piece of work, named in docs/23.
#
# The presence rule is the honesty core, and it is two questions, both of which the player could
# answer for themselves from what is already on their screen:
#
#   supply   is there a course in the pack (`SimInfection.carries_course`) -- work_panel.gd's rule,
#            that a name you can afford is simply present and one you cannot is absent, rather than
#            a greyed word with a reason attached;
#   symptom  is anything showing that a course might answer (`SimInfection.symptom_of`) -- which is
#            the fever, from either cause, and never `transmitted` and never `is_septic`. A bite
#            still in its latent stage reads "clear" and is offered nothing, which is the point:
#            a word that appeared the moment you were bitten would hand the player the one thing
#            docs/01 clause 4 says they do not get.
#
# So the row is offered iff it would succeed, and it says the same thing whichever infection is
# underneath it.
static func response_view(world: Variant, actor: int) -> Array:
	var out: Array = []
	if world == null or actor < 0:
		return out
	if not SimInfection.carries_course(world, actor):
		return out
	if not bool(SimInfection.symptom_of(world, actor, 0).get("symptomatic", false)):
		return out
	out.append({"verb": "antibiotics", "text": "take the antibiotics"})
	return out


static func _dry_run(world: Variant, actor: int, patient: int, part: String, verb: String) -> Dictionary:
	var pre: Dictionary = _can_begin(world, actor, patient, verb)
	if not bool(pre.get("ok", false)):
		return pre
	# The same plan `begin` runs, minus the engaging. Two hand-kept lists of preconditions is how
	# the panel ends up offering a verb the sim refuses.
	var plan: Dictionary = _plan(world, actor, patient, part, verb)
	if not bool(plan.get("ok", false)):
		return plan
	return {"ok": true}
