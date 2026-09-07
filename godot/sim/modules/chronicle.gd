extends RefCounted
# The chronicle: what happened to the colony, as the screen can say it.
#
# The owner's twelfth decision (docs/30, "The playable state", 2026-09-06): death, succession,
# run-over, arrival and bereavement reach the screen as world-lines. Before this every one of
# those events -- `entity.killed`, `player.succeeded`, `run.over`, `recruit.arrived`,
# `colony.bereaved`, `recruit.left` -- was published, gated, and read by nothing outside a gate:
# a player whose survivor died found themselves driving somebody else with no sentence to say
# so, and "RUN OVER" lived only on the developer sheet behind M.
#
# Shape: the sim owns the record. `world.chronicle` is an Array of `{tick, kind, name, e}`
# records -- an Array of records and never an id-keyed Dictionary, because JSON has no integer
# keys and a keyed component comes back from a save with String keys (CLAUDE.md's trap list) --
# saved and restored with the world (SAVE_VERSION 25). `lines(world)` is the read model the HUD
# appends to its world column: prose, no digits, newest first, and only what is recent enough
# to still be news. The record itself is kept whole: a save reloaded a week later still knows
# who died on day two, and a later screen (a grave, a memorial, the run's own epitaph) can read
# it without the sim having to remember twice.
#
# `entity.killed` fires more than once for one body (health.gd on a destroyed head, infection.gd
# on a put-down and again on turning -- CLAUDE.md's trap list), so a death is recorded once per
# entity id; and it fires for zombies, whose deaths are not the colony's news, so a body with no
# `identity` is not written down. The shape is attention_read.gd's: one static read model, no
# state of its own -- everything lives on the world, never in a `static var` (the two-worlds
# trap).

const Clock = preload("res://sim/time/clock.gd")

# How long a line stays on the screen after its event: two game hours. Long enough to be read
# by somebody who was busy when it happened, short enough that a death on day two is not still
# the first thing on the screen on day four. The record keeps the event forever; only the
# screen forgets.
const LINE_TICKS: int = Clock.DAY_TICKS / 12
# At most this many lines at once, newest first. A siege that kills three in a minute says three
# things; the fourth waits for the first to age out, and is still in the record.
const LINES_MAX: int = 3

# Subscription order: after every handler that reads the same event to change the world
# (succession runs inside `finish_death` before the event is even drained, and the grief
# handlers in needs.gd write mood), so a name is read off a body that has already become what
# the event made it -- a corpse still carries its `identity`.
const ORDER: int = 900

const KINDS: Array[String] = ["died", "succeeded", "over", "arrived", "joined", "bereaved", "left"]


static func register_module(world: Variant) -> void:
	world.events.subscribe({"type": "entity.killed", "id": "chronicle.killed", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		_on_killed(world, ev)
	})
	world.events.subscribe({"type": "player.succeeded", "id": "chronicle.succeeded", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		var to: int = int(ev.get("to", -1))
		_write(world, "succeeded", _name_of(world, to), to)
	})
	world.events.subscribe({"type": "run.over", "id": "chronicle.over", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		_write(world, "over", "", int(ev.get("entity", -1)))
	})
	world.events.subscribe({"type": "recruit.arrived", "id": "chronicle.arrived", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		_write(world, "arrived", "", int(ev.get("entity", -1)))
	})
	world.events.subscribe({"type": "survivor.joined", "id": "chronicle.joined", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		# `survivor.joined` is published twice over: by survivors.gd for every body it spawns
		# (its content id -- the boot colony, a stranger generated to wait at the gate) and by
		# recruits.gd with `id: recruit` when the player accepts one. Only the second is anybody
		# joining; the first is the world being built.
		if String(ev.get("id", "")) != "recruit":
			return
		var ent: int = int(ev.get("entity", -1))
		_write(world, "joined", _name_of(world, ent), ent)
	})
	world.events.subscribe({"type": "colony.bereaved", "id": "chronicle.bereaved", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		var dead: int = int(ev.get("entity", -1))
		# Bereavement is somebody *seeing* it (`witnesses` is needs.gd's count of mourners who
		# saw); a death nobody witnessed is the "died" line alone.
		if int(ev.get("witnesses", 0)) <= 0:
			return
		_write(world, "bereaved", _name_of(world, dead), dead)
	})
	world.events.subscribe({"type": "recruit.left", "id": "chronicle.left", "order": ORDER, "handler": func(ev: Dictionary) -> void:
		var ent: int = int(ev.get("entity", -1))
		# A stranger who gave up waiting at dawn, or was turned away, has no name the colony
		# learned; a colonist who walked out over mood (`reason: mood`) does. The despawn has
		# already run by drain time, so the name is whatever the body still answers to -- "" for
		# the stranger, which `lines` reads as the stranger's line.
		var name: String = _name_of(world, ent) if String(ev.get("reason", "")) == "mood" else ""
		_write(world, "left", name, ent)
	})


static func _on_killed(world: Variant, ev: Dictionary) -> void:
	var ent: int = int(ev.get("entity", -1))
	if ent < 0:
		return
	# People only: a body with an identity. A zombie has a `zombieType`, a raider a `raider`
	# archetype, and neither is the colony's to mourn. The player's body on a run-over has been
	# despawned before this drains and has no identity left to read -- but it is still
	# `world.player`, and the run-over line says the rest.
	var ident: Variant = world.components.get_component(ent, "identity")
	if not (ident is Dictionary) and ent != int(world.player):
		return
	for rec in world.chronicle as Array:
		if String((rec as Dictionary).get("kind", "")) == "died" and int((rec as Dictionary).get("e", -1)) == ent:
			return
	_write(world, "died", _name_of(world, ent), ent)


static func _write(world: Variant, kind: String, name: String, ent: int) -> void:
	(world.chronicle as Array).append({"tick": int(world.tick), "kind": kind, "name": name, "e": ent})


static func _name_of(world: Variant, ent: int) -> String:
	var ident: Variant = world.components.get_component(ent, "identity")
	if ident is Dictionary:
		return String((ident as Dictionary).get("name", ""))
	return ""


# The screen's read of the record: prose, newest first, at most LINES_MAX, nothing older than
# LINE_TICKS. Every sentence is words -- a name, never a count or a day -- because check_hud.gd
# allows no digit on the HUD but the day counter, and the chronicle is on the HUD.
static func lines(world: Variant) -> Array[String]:
	var out: Array[String] = []
	if world == null:
		return out
	var recs: Array = world.chronicle as Array
	var now: int = int(world.tick)
	for i in range(recs.size() - 1, -1, -1):
		var rec: Dictionary = recs[i] as Dictionary
		if now - int(rec.get("tick", 0)) > LINE_TICKS:
			break
		var line: String = _line_of(world, rec)
		if line.is_empty():
			continue
		out.append(line)
		if out.size() >= LINES_MAX:
			break
	return out


static func _line_of(world: Variant, rec: Dictionary) -> String:
	var name: String = String(rec.get("name", ""))
	var ent: int = int(rec.get("e", -1))
	match String(rec.get("kind", "")):
		"died":
			if ent == int(world.player) and not world.components.has_component(ent, "identity"):
				return "You are dead."
			if name.is_empty():
				return "Someone is dead."
			return "%s is dead." % name
		"succeeded":
			if name.is_empty():
				return "You are someone else now."
			return "You are %s now." % name
		"over":
			return "There is nobody left to be."
		"arrived":
			return "Someone is waiting at the gate."
		"joined":
			if name.is_empty():
				return "Someone has joined you."
			return "%s has joined you." % name
		"bereaved":
			if name.is_empty():
				return "The colony saw it happen."
			return "The colony saw %s die." % name
		"left":
			if name.is_empty():
				return "The stranger at the gate has gone."
			return "%s has walked out." % name
	return ""
