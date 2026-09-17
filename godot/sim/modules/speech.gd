class_name SimSpeech
extends RefCounted

# Speech bubbles: what a body says out loud, the fourth of the four QOL slices the owner asked
# for after the alpha shell (the shout was a noise, the chronicle a corner column, and nobody
# spoke). `saying {text, since, until}` is a flat, JSON-round-trippable component on the speaker;
# `say` picks a line for a key from `content/speech/lines.json` on its own named RNG stream
# (CLAUDE.md: new randomness gets its own stream) and a system past `until` clears it. One line at
# a time -- a newer line replaces whatever the body was saying, the same "the sim keeps one
# intent" shape `walkTo` and `treatment` already use.
#
# Every trigger below is an existing event this file only listens to -- `world.gd` publishes
# `shouted` beside the noise its own `shout` arm already emits (the same shape `stance.collapsed`
# is published there and never subscribed to), and `shambler.gd`/`screamer.gd` publish
# `zombie.noticed`/`zombie.screamed` beside their own state changes. This module never writes
# anything but `saying`, `recruit.hailed` and reads content -- it owns no other state, the same
# shape `chronicle.gd` set for "a small sim module that turns events into digit-free prose".
#
# Every line content declares is digit-free, names nobody, and says nothing the hardcore contract
# hides (never "I'm bitten" for a grab -- a grab is not yet a bite, and treatment is what finds
# out); `check_speech.gd`'s CONTENT lane scans the tree for both. A missing key says nothing
# (`say` silently no-ops) rather than falling back to a placeholder sentence that would be a lie
# about what content actually shipped.

const Clock = preload("res://sim/time/clock.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")

const CONTENT_PATH: String = "speech/lines.json"
const RNG_STREAM: String = "speech"

# Three seconds at 20 Hz -- long enough to read, short enough that a fight does not leave a wall
# of stale bubbles behind it. A scream is shorter (SCREAM_TICKS): it is one syllable, not a line.
const SAY_TICKS: int = 60
const SCREAM_TICKS: int = 40

# How often a colonist not at the wheel rolls a mutter, and how likely that roll is to say
# anything: 400 ticks (20 s) between rolls, 15% per roll, so a starving colonist is heard within
# a few minutes and a fed one, whose `SimNeeds.worst_band` is always "", never rolls at all
# (`_line_for` on an empty band returns "" and `say` no-ops before the RNG stream is ever drawn).
const MUTTER_EVERY: int = 400
const MUTTER_P: float = 0.15

# Every id `say` can be asked for. `check_speech.gd`'s CONTENT lane walks this list against the
# content tree, so a key added here with no matching `speech.<key>` entry is a gate failure, not a
# silent no-op discovered in play.
const KEYS: Array[String] = [
	"shout", "grabbed", "rescued", "treating", "joined", "hail",
	"zombie.noticed", "zombie.scream",
	"mutter.hungry", "mutter.thirsty", "mutter.tired", "mutter.cold", "mutter.hot", "mutter.soaked", "mutter.shaken",
]


static func register_module(world: Variant) -> void:
	world.events.subscribe({"type": "shouted", "id": "speech.shout", "order": 0, "handler": func(ev: Dictionary) -> void:
		say(world, int(ev.get("entity", -1)), "shout")
	})
	world.events.subscribe({"type": "grab.started", "id": "speech.grabbed", "order": 0, "handler": func(ev: Dictionary) -> void:
		say(world, int(ev.get("victim", -1)), "grabbed")
	})
	world.events.subscribe({"type": "grab.broken", "id": "speech.rescued", "order": 0, "handler": func(ev: Dictionary) -> void:
		# Only a rescue: the victim's own struggle, a holder dying, or a stagger breaking the hold
		# are all `grab.broken` too, and none of them is somebody else pulling a body free.
		if String(ev.get("cause", "")) != "rescue":
			return
		say(world, int(ev.get("by", -1)), "rescued")
	})
	world.events.subscribe({"type": "treatment.begun", "id": "speech.treating", "order": 0, "handler": func(ev: Dictionary) -> void:
		var actor: int = int(ev.get("entity", -1))
		if actor == int(ev.get("patient", -1)):
			return
		say(world, actor, "treating")
	})
	world.events.subscribe({"type": "survivor.joined", "id": "speech.joined", "order": 0, "handler": func(ev: Dictionary) -> void:
		say(world, int(ev.get("entity", -1)), "joined")
	})
	world.events.subscribe({"type": "zombie.noticed", "id": "speech.noticed", "order": 0, "handler": func(ev: Dictionary) -> void:
		say(world, int(ev.get("entity", -1)), "zombie.noticed")
	})
	world.events.subscribe({"type": "zombie.screamed", "id": "speech.screamed", "order": 0, "handler": func(ev: Dictionary) -> void:
		say(world, int(ev.get("entity", -1)), "zombie.scream", SCREAM_TICKS)
	})
	world.systems.register("speech.hail", "ai", 0, func(w: Variant) -> void:
		_hail(w)
	)
	# "needs", after every band the needs phase computes (need.temperature is the last-ordered at
	# 14; MUTTER_EVERY/MUTTER_P below is what keeps this cheap, not the phase slot) -- so
	# `worst_band` reads the same tick's readings `SimNeeds.hud_clause` would.
	world.systems.register("speech.mutter", "needs", 20, func(w: Variant) -> void:
		_mutter(w)
	)
	world.systems.register("speech.expire", "cleanup", 0, func(w: Variant) -> void:
		_expire(w)
	)


# Sets `saying` from a line for `speech.<key>`, or does nothing at all when the key has no
# content entry or that entry's `lines` is empty -- never a placeholder sentence standing in for
# content that was never written. `ent < 0` (an event with nobody to credit, e.g. an unheld
# rescue) is the same no-op.
static func say(world: Variant, ent: int, key: String, ticks: int = -1) -> void:
	if ent < 0:
		return
	var entry: Dictionary = _entry_for(world, key)
	if entry.is_empty():
		return
	var lines: Variant = entry.get("lines", [])
	if not (lines is Array) or (lines as Array).is_empty():
		return
	var rng: Variant = world.rng.stream(RNG_STREAM)
	var line: String = String((lines as Array)[int(rng.call("int_range", 0, (lines as Array).size() - 1))])
	if line.is_empty():
		return
	var span: int = ticks if ticks > 0 else int(entry.get("ticks", SAY_TICKS))
	world.components.set_component(ent, "saying", {"text": line, "since": int(world.tick), "until": int(world.tick) + span})


static func _entry_for(world: Variant, key: String) -> Dictionary:
	var id: String = "speech.%s" % key
	for row in _entries(world):
		var e: Dictionary = row as Dictionary
		if String(e.get("id", "")) == id:
			return e
	return {}


static func _entries(world: Variant) -> Array:
	if world == null or not ("content" in world) or not (world.content is Dictionary):
		return []
	var raw: Variant = (world.content as Dictionary).get(CONTENT_PATH, [])
	return raw as Array if raw is Array else []


# The hail: a waiting recruit or stranger who has just come into the controlled body's reach
# speaks once, ever, per recruit -- `hailed` on the `recruit` record is what makes it "once", the
# same shape a shambler's own re-grab cooldown or a fortify bait's `ticksUntilReady` uses (a flag
# or a clock the mechanism itself owns, never a side table this file would have to keep in step).
# Queries `["recruit", "position"]` only -- cheap, and correct with more than one recruit waiting
# at once, unlike routing every tick through `SimRecruits.waiting_in_reach` (which returns the
# first match regardless of whether it has already been hailed, and would starve a second waiting
# body standing in reach beside an already-hailed first one).
static func _hail(world: Variant) -> void:
	var actor: int = -1
	for a in world.components.query(["controlled"]):
		actor = int(a)
		break
	if actor < 0:
		return
	for e in world.components.query(["recruit", "position"]):
		var r: Variant = world.components.get_component(int(e), "recruit")
		if not (r is Dictionary):
			continue
		var rec: Dictionary = r as Dictionary
		if not bool(rec.get("waiting", false)) or bool(rec.get("hailed", false)):
			continue
		if not SimFortify._entity_in_reach(world, actor, int(e)):
			continue
		rec["hailed"] = true
		say(world, int(e), "hail")


# Every colonist with `needs` who is not at the wheel (`controlled`), not a corpse and not
# themselves a waiting recruit, rolls a mutter every MUTTER_EVERY ticks at MUTTER_P -- gated by
# tick modulo first (free) so the RNG stream, and `SimNeeds.worst_band`'s own scan of the needs
# board, are only paid for on a roll tick. A colonist whose worst_band is "" (fed, rested, warm)
# never reaches the roll at all: `say` on an empty key already no-ops, but the RNG draw is the
# cost this order avoids paying for every content colonist every twenty seconds.
static func _mutter(world: Variant) -> void:
	if int(world.tick) % MUTTER_EVERY != 0:
		return
	var rng: Variant = world.rng.stream(RNG_STREAM)
	for ent in world.components.query(["needs"]):
		var e: int = int(ent)
		if world.components.has_component(e, "controlled"):
			continue
		if world.components.has_component(e, "corpse"):
			continue
		if world.components.has_component(e, "recruit"):
			continue
		var band: String = SimNeeds.worst_band(world, e)
		if band.is_empty():
			continue
		if not bool(rng.call("bool_chance", MUTTER_P)):
			continue
		say(world, e, "mutter.%s" % band)


static func _expire(world: Variant) -> void:
	var now: int = int(world.tick)
	for ent in world.components.query(["saying"]):
		var s: Variant = world.components.get_component(int(ent), "saying")
		if not (s is Dictionary):
			continue
		if now >= int((s as Dictionary).get("until", 0)):
			world.components.remove(int(ent), "saying")
