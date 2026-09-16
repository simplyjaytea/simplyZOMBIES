extends SceneTree
# One roll for everybody: the survivor roll moved out of `recruits.gd` into `people.gd` so a
# stranger, a raider and a settler can draw from the same shape. The move is byte-identical and
# this gate is what makes that a fact rather than a claim -- the PIN lane holds the canonical
# seed's first two rolls, taken from the pre-extraction code with a throwaway driver on
# 2026-09-14, and compares the new code's output against them as strings.

const SimBoot = preload("res://sim/boot.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const SimPeople = preload("res://sim/modules/people.gd")

# Seed 20260805, `SimBoot.playable(seed, 64)`, two consecutive `SimRecruits.roll` calls on the
# `recruits` stream, serialised with JSON.stringify (sorted keys). Taken before the roll moved.
const PIN_SEED: int = 20260805
const PIN_FIRST: String = '{"age":36,"aptitudes":{"con":4,"dex":5,"str":6},"backstory":"night auditor","backstoryId":"night_auditor","features":["broad shoulders","tired eyes","crooked nose"],"kit":[],"look":"colony.look.03","name":"Asha Chen","traits":["light_sleeper","optimist","iron_stomach"]}'
const PIN_SECOND: String = '{"age":53,"aptitudes":{"con":7,"dex":4,"str":4},"backstory":"cyclist","backstoryId":"cyclist","features":["tired eyes","broad shoulders","crooked nose"],"kit":[],"look":"colony.look.04","name":"Dmitri Novak","traits":["steady_hands","fast_healer","squeamish"]}'
# A second seed, pinned the same way, so the negative is "a different seed differs from the
# canonical pin AND matches its own" -- a pin that only ever equals a constant cannot fail.
const OTHER_SEED: int = 404
const PIN_OTHER: String = '{"age":24,"aptitudes":{"con":4,"dex":6,"str":5},"backstory":"cyclist","backstoryId":"cyclist","features":["sun-worn face","broad shoulders"],"kit":[],"look":"colony.look.02","name":"Gwen Haddad","traits":["squeamish","light_sleeper","night_blind"]}'


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _pin() and ok
	ok = _diverges() and ok
	ok = _pool() and ok
	ok = _reader() and ok
	if ok:
		print("M2_PEOPLE_OK pin diverges pool reader")
		quit(0)
	else:
		push_error("M2_PEOPLE_FAIL")
		quit(1)


func _world(seed_val: int) -> Variant:
	return SimBoot.playable(seed_val, 64)["world"]


# PIN: the canonical seed's first two rolls are the pre-extraction bytes. Two rolls, not one,
# because the second proves the first consumed exactly the draws it used to -- a roll that
# returned the right Dictionary off one extra `int_range` would pass a one-roll pin and move
# every later call on the stream, including `accept`'s transmit roll.
func _pin() -> bool:
	var w: Variant = _world(PIN_SEED)
	var first: String = JSON.stringify(SimRecruits.roll(w, w.rng.stream("recruits")))
	var second: String = JSON.stringify(SimRecruits.roll(w, w.rng.stream("recruits")))
	if first != PIN_FIRST:
		push_error("PIN: first roll moved off the pre-extraction bytes\n  got  %s\n  want %s" % [first, PIN_FIRST])
		return false
	if second != PIN_SECOND:
		push_error("PIN: second roll moved -- the first consumed a different number of draws\n  got  %s\n  want %s" % [second, PIN_SECOND])
		return false
	print("PIN OK seed %d rolls 1 and 2 byte-identical to the pre-extraction roll" % PIN_SEED)
	return true


# DIVERGES: the true negative for PIN. Another seed must not equal the canonical pin (so the
# pin is not something every roll satisfies) and must equal its own pin (so this lane is not
# satisfied by any roll that merely differs).
func _diverges() -> bool:
	var w: Variant = _world(OTHER_SEED)
	var other: String = JSON.stringify(SimRecruits.roll(w, w.rng.stream("recruits")))
	if other == PIN_FIRST:
		push_error("DIVERGES: seed %d rolled the canonical pin -- the roll is not reading its seed" % OTHER_SEED)
		return false
	if other != PIN_OTHER:
		push_error("DIVERGES: seed %d moved off its own pin\n  got  %s\n  want %s" % [OTHER_SEED, other, PIN_OTHER])
		return false
	print("DIVERGES OK seed %d differs from the canonical pin and matches its own" % OTHER_SEED)
	return true


# POOL: the one scan both callers use finds the survivors block by id, and an id nothing
# declares comes back empty rather than as the first block with any id.
func _pool() -> bool:
	var w: Variant = _world(PIN_SEED)
	var found: Dictionary = SimPeople.pool(w, SimPeople.SURVIVORS_POOL_ID)
	if not found.has("given") or not found.has("backstories"):
		push_error("POOL: SimPeople.pool did not find the survivors generator (keys %s)" % str(found.keys()))
		return false
	var missing: Dictionary = SimPeople.pool(w, "colony.generator.nobody")
	if not missing.is_empty():
		push_error("POOL: an unknown id returned a block (%s)" % str(missing.get("id", "")))
		return false
	print("POOL OK survivors block found by id, unknown id empty")
	return true


# READER: the roll actually lives in `people.gd` and the two callers reach it -- the dead-socket
# assertion, read off the source. `recruits.gd`'s `roll` body must call `SimPeople.roll` and
# must contain no `int_range` of its own (a re-inlined copy would keep PIN green while the
# shared roll went unread); `survivors.gd`'s `_generator_pool` must call `SimPeople.pool`.
# Each function body is isolated first -- from its `static func` line to the next one -- so a
# comment elsewhere in the file cannot satisfy the needle (CLAUDE.md's `READ_KEYS` lesson).
func _reader() -> bool:
	var recruits: String = _body_of("res://sim/modules/recruits.gd", "static func roll(")
	if recruits.is_empty():
		push_error("READER: recruits.gd has no `static func roll(` -- reading the wrong file")
		return false
	if recruits.find("SimPeople.roll(") < 0:
		push_error("READER: recruits.gd's roll does not call SimPeople.roll")
		return false
	if recruits.find("int_range") >= 0:
		push_error("READER: recruits.gd's roll draws for itself -- the shared roll is unread")
		return false
	var survivors: String = _body_of("res://sim/modules/survivors.gd", "static func _generator_pool(")
	if survivors.is_empty():
		push_error("READER: survivors.gd has no `static func _generator_pool(` -- reading the wrong file")
		return false
	if survivors.find("SimPeople.pool(") < 0:
		push_error("READER: survivors.gd's _generator_pool does not call SimPeople.pool")
		return false
	var people: String = _body_of("res://sim/modules/people.gd", "static func roll(")
	if people.count("int_range") < 8:
		push_error("READER: people.gd's roll has %d draws where the survivor roll makes at least eight" % people.count("int_range"))
		return false
	print("READER OK recruits.roll -> SimPeople.roll, survivors._generator_pool -> SimPeople.pool, the draws live in people.gd")
	return true


# The text of one static function: from the line beginning with `head` up to the next line
# beginning with `static func`, or the end of the file. Empty when `head` is not found.
func _body_of(path: String, head: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: Array = []
	var inside: bool = false
	for line in lines:
		var l: String = String(line)
		if l.begins_with(head):
			inside = true
			out.append(l)
			continue
		if inside and l.begins_with("static func"):
			break
		if inside:
			out.append(l)
	return "\n".join(out)
