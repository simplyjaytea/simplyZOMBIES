extends SceneTree
# Bare hands -- docs/09's F and a left click did nothing with nothing equipped, because
# `melee.intake` queries `["swing","meleeWeapon","controlled"]` and an empty-handed body raised no
# `meleeWeapon` at all. `combat.gd`'s BARE_HANDS and `melee.gd`'s `ensure_hands` close that: a
# punch is a weak, always-present profile rather than a special case threaded through every
# reader that used to ask "does this body have a meleeWeapon" to mean "can this body fight".
#
# That old question and the new one differ everywhere a component's mere *presence* used to stand
# in for it, so this gate spends most of its lanes proving the readers moved with the mechanism
# rather than proving the mechanism alone: `SimMelee.is_unarmed` is now the one predicate, and
# HANDS/PREDICATE/REARM/NOISE/SPAWN each carry the true negative the convention
# `check_ban_health_bar.gd` set -- a lane that only ever sees a punch land would pass exactly as
# happily if `is_unarmed` always returned true.
#
# READERS follows `check_m2_comfort.gd`'s lesson the hard way round: a needle that a *comment*
# can satisfy is a needle that cannot fail, so the isolator here strips `#`-comments out of a
# function's body before searching it, and is proved against a fabricated function whose only
# mention of the call sits in a comment, first.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _hands_lane() and ok
	ok = _predicate_lane() and ok
	ok = _readers_lane() and ok
	ok = _rearm_lane() and ok
	ok = _noise_lane() and ok
	ok = _spawn_lane() and ok
	if ok:
		print("M2_HANDS_OK a booted survivor with nothing equipped punches, is_unarmed is the one predicate, jobs.gd and the balance gate both read it, an unarmed colonist re-arms from the ground, a punch is heard, and every colonist boots with a meleeWeapon")
		quit(0)
	else:
		push_error("M2_HANDS_FAIL")
		quit(1)


# --- fixtures ------------------------------------------------------------------------------

func _bare_world(seed_val: int) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 16.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	SimInventory.make_inventory(w, w.player)
	# Nothing in World._init gives the player a facing -- boot_playable does, but a bare fixture
	# does not, and `_resolve_strike` returns early with none. Every lane below is about whether
	# a swing connects, so the fixture has to be one a swing *can* connect from.
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	return w


# A standing body with nothing else: no `shambler` component, so no AI is registered to move it
# and the target simply waits in reach. `_resolve_strike` only asks for `body` and `position`.
func _target(w: Variant, x: float, y: float) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "body", SimCombat.ZOMBIE_BODY.duplicate())
	return ent


func _bare_entity(w: Variant) -> int:
	return int(w.entities.spawn())


func _watch(w: Variant, id: String, type: String, out: Array) -> void:
	w.events.subscribe({"id": id, "type": type, "handler": func(e: Dictionary) -> void:
		out.append((e as Dictionary).duplicate())
	})


# `attack.connected`'s own damage already carries whatever `melee_damage` modifier was live the
# moment it landed -- the swing itself spends stamina, and `melee.exhaustion` reads the tank on
# every tick, so even a fresh 100/100 survivor is not swinging at a bare multiplier of 1.0 by the
# time a punch resolves a few ticks later. Reading the same modifier back inside the handler, at
# drain time on the tick that published the hit, is what lets "damage == BARE_HANDS.damage x
# modifiers" mean the actual number rather than an assumption that nothing was live.
func _watch_connects(w: Variant, id: String, attacker: int, out: Array) -> void:
	w.events.subscribe({"id": id, "type": "attack.connected", "handler": func(e: Dictionary) -> void:
		if int((e as Dictionary).get("attacker", -1)) != attacker:
			return
		var rec: Dictionary = (e as Dictionary).duplicate()
		var mult: float = 1.0
		if w.modifiers != null and (w.modifiers as Object).has_method("resolve"):
			mult = float(w.modifiers.call("resolve", "melee_damage", attacker))
		rec["modifier"] = mult
		out.append(rec)
	})


# --- HANDS -----------------------------------------------------------------------------------

func _hands_lane() -> bool:
	var lane: String = "HANDS"
	var w: Variant = _bare_world(9001)
	SimMelee.ensure_hands(w, w.player)
	var mw: Variant = w.components.get_component(w.player, "meleeWeapon")
	if not mw is Dictionary or not bool((mw as Dictionary).get("unarmed", false)):
		push_error("%s: a survivor with nothing equipped has no unarmed meleeWeapon" % lane)
		return false
	_target(w, 17.3, 16.5)
	var seen: Array = []
	_watch_connects(w, "gate-hands-connect", int(w.player), seen)
	w.commands.push({"type": "swing"})
	for i in 20:
		w.step()
	if seen.is_empty():
		push_error("%s: a bare-handed swing on a target 0.8 m ahead never connected" % lane)
		return false
	var hit: Dictionary = seen[0] as Dictionary
	var expected: float = float(SimCombat.BARE_HANDS["damage"]) * (float(SimCombat.HEAD_DAMAGE_MULTIPLIER) if String(hit.get("bodyPart", "")) == "head" else 1.0) * float(hit.get("modifier", 1.0))
	if absf(float(hit.get("damage", -1.0)) - expected) > 0.0001:
		push_error("%s: a punch on %s carried %.4f, expected BARE_HANDS.damage x modifiers = %.4f" % [lane, String(hit.get("bodyPart", "")), float(hit.get("damage", -1.0)), expected])
		return false

	# Negative: the same body with a bat equipped publishes the bat's own damage, never the punch's.
	var w2: Variant = _bare_world(9002)
	var bat_item: int = SimItems.spawn_item(w2, "item.bat.aluminium", {"tier": "scavenged"})
	SimInventory.equip(w2, w2.player, bat_item)
	w2.events.drain()
	var bat_profile: Variant = w2.components.get_component(w2.player, "meleeWeapon")
	if not bat_profile is Dictionary or bool((bat_profile as Dictionary).get("unarmed", false)):
		push_error("%s: an equipped bat read as unarmed -- the negative measures nothing" % lane)
		return false
	var bat_damage: float = float((bat_profile as Dictionary).get("damage", 0.0))
	_target(w2, 17.3, 16.5)
	var seen2: Array = []
	_watch_connects(w2, "gate-hands-connect-2", int(w2.player), seen2)
	w2.commands.push({"type": "swing"})
	for i in 20:
		w2.step()
	if seen2.is_empty():
		push_error("%s: an armed swing never connected -- the negative measures nothing" % lane)
		return false
	var hit2: Dictionary = seen2[0] as Dictionary
	var bat_expected: float = bat_damage * (float(SimCombat.HEAD_DAMAGE_MULTIPLIER) if String(hit2.get("bodyPart", "")) == "head" else 1.0) * float(hit2.get("modifier", 1.0))
	if absf(float(hit2.get("damage", -1.0)) - bat_expected) > 0.0001:
		push_error("%s: an armed punch carried %.4f, expected the bat's own %.4f" % [lane, float(hit2.get("damage", -1.0)), bat_expected])
		return false
	if absf(bat_damage - float(SimCombat.BARE_HANDS["damage"])) > 0.0001 and absf(float(hit2.get("damage", -1.0)) - float(SimCombat.BARE_HANDS["damage"]) * float(hit2.get("modifier", 1.0))) < 0.0001:
		push_error("%s: an armed swing published BARE_HANDS' own damage number" % lane)
		return false

	# Unequipping the bat returns hands -- never an absent component.
	SimInventory.unequip(w2, w2.player, "primary")
	w2.events.drain()
	var mw2: Variant = w2.components.get_component(w2.player, "meleeWeapon")
	if not mw2 is Dictionary:
		push_error("%s: unequipping a weapon left no meleeWeapon at all" % lane)
		return false
	if not bool((mw2 as Dictionary).get("unarmed", false)):
		push_error("%s: unequipping a weapon left a meleeWeapon that does not read as unarmed" % lane)
		return false
	print("  HANDS bare hands wind up and land BARE_HANDS.damage on %s; an equipped bat lands its own %.1f; unequipping it returns hands, never an empty slot" % [String(hit.get("bodyPart", "")), bat_damage])
	return true


# --- PREDICATE --------------------------------------------------------------------------------

func _predicate_lane() -> bool:
	var lane: String = "PREDICATE"
	var w: Variant = _bare_world(9101)
	var hands_ent: int = _bare_entity(w)
	SimMelee.ensure_hands(w, hands_ent)
	if not SimMelee.is_unarmed(w, hands_ent):
		push_error("%s: hands did not read as unarmed" % lane)
		return false
	var bat_ent: int = _bare_entity(w)
	SimInventory.make_inventory(w, bat_ent)
	SimInventory.equip(w, bat_ent, SimItems.spawn_item(w, "item.bat.aluminium", {"tier": "scavenged"}))
	w.events.drain()
	if SimMelee.is_unarmed(w, bat_ent):
		push_error("%s: a bat read as unarmed" % lane)
		return false
	var pistol_ent: int = _bare_entity(w)
	SimMelee.ensure_hands(w, pistol_ent)
	# A minimal stub is enough: `is_unarmed` only asks whether the component is present.
	w.components.set_component(pistol_ent, "rangedWeapon", {"state": 0})
	if SimMelee.is_unarmed(w, pistol_ent):
		push_error("%s: hands plus a ranged weapon still read as unarmed" % lane)
		return false
	print("  PREDICATE is_unarmed: true for hands, false for a bat, false for hands plus a ranged weapon")
	return true


# --- READERS (textual, proved on a fabricated body first) --------------------------------------

func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


# Everything indented after a top-level signature line, up to the next non-blank line that is
# not indented -- the same "isolate the line, or the function, first" discipline CLAUDE.md's
# dead-socket note names for `check_m2_teach.gd`'s READ_KEYS line, one level up: a whole function
# body rather than one line.
func _function_body(code: String, signature_prefix: String) -> String:
	var lines: PackedStringArray = code.split("\n")
	var start: int = -1
	for i in range(lines.size()):
		if String(lines[i]).begins_with(signature_prefix):
			start = i
			break
	if start < 0:
		return ""
	var body: Array[String] = []
	for i in range(start + 1, lines.size()):
		var line: String = String(lines[i])
		if line.strip_edges() != "" and not line.begins_with("\t") and not line.begins_with(" "):
			break
		body.append(line)
	return "\n".join(body)


# A bare `#` split is enough for the bodies this gate reads -- none of them carry a `#` inside a
# string -- and it is what makes the READERS lane immune to a comment satisfying its needle, the
# trap `check_m2_comfort.gd` was rewritten to avoid.
func _without_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var l: String = String(line)
		var hash_at: int = l.find("#")
		if hash_at >= 0:
			l = l.substr(0, hash_at)
		out.append(l)
	return "\n".join(out)


# null when the function itself cannot be found (the caller is reading the wrong file); true or
# false, off the comment-stripped body, once it can.
func _function_calls(code: String, signature_prefix: String, needle: String) -> Variant:
	var body: String = _function_body(code, signature_prefix)
	if body.is_empty():
		return null
	return _without_comments(body).contains(needle)


func _readers_lane() -> bool:
	var lane: String = "READERS"
	# The scanner has to fail on a comment before it is trusted on real code: the only mention
	# of the call in this fabricated body is prose above a `return true`.
	var fake_comment: String = "static func _fake(world: Variant, ent: int) -> bool:\n\t# SimMelee.is_unarmed(world, ent) would be nice here\n\treturn true\n"
	var fake_hit: Variant = _function_calls(fake_comment, "static func _fake(", "SimMelee.is_unarmed(")
	if fake_hit == null:
		push_error("%s: the isolator could not find the fabricated function at all" % lane)
		return false
	if bool(fake_hit):
		push_error("%s: a comment mentioning the call satisfied the scanner -- it reads prose, not code" % lane)
		return false
	var fake_real: String = "static func _fake(world: Variant, ent: int) -> bool:\n\treturn SimMelee.is_unarmed(world, ent)\n"
	var fake_real_hit: Variant = _function_calls(fake_real, "static func _fake(", "SimMelee.is_unarmed(")
	if not bool(fake_real_hit):
		push_error("%s: the scanner cannot see a real call either -- it is broken, not strict" % lane)
		return false

	var jobs_code: String = _code_of("res://sim/modules/jobs.gd")
	var jobs_hit: Variant = _function_calls(jobs_code, "static func _unarmed(", "SimMelee.is_unarmed(")
	if jobs_hit == null:
		push_error("%s: jobs.gd has no _unarmed(...) function -- this assertion is reading the wrong file" % lane)
		return false
	if not bool(jobs_hit):
		push_error("%s: jobs.gd's _unarmed no longer routes through SimMelee.is_unarmed" % lane)
		return false

	var balance_code: String = _code_of("res://check_m2_balance.gd")
	var balance_hit: Variant = _function_calls(balance_code, "func _unarmed_colonists(", "SimMelee.is_unarmed(")
	if balance_hit == null:
		push_error("%s: check_m2_balance.gd has no _unarmed_colonists(...) function -- this assertion is reading the wrong file" % lane)
		return false
	if not bool(balance_hit):
		push_error("%s: check_m2_balance.gd's _unarmed_colonists no longer routes through SimMelee.is_unarmed" % lane)
		return false
	print("  READERS jobs.gd's _unarmed and check_m2_balance.gd's _unarmed_colonists both call SimMelee.is_unarmed, proved on a fabricated body first")
	return true


# --- REARM -------------------------------------------------------------------------------------

func _bare_colonist(w: Variant, x: float, y: float, id: String) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "identity", {"id": id, "name": "Test", "traits": []})
	SimHealth.make_survivor_body(w, ent)
	SimHealth.make_stamina(w, ent)
	SimInventory.make_inventory(w, ent)
	SimNeeds.attach(w, ent)
	SimJobs.attach(w, ent, "Auto")
	return ent


func _took_rearm(w: Variant, ent: int, ticks: int) -> bool:
	for i in ticks:
		w.step()
		var job: Variant = w.components.get_component(ent, "job")
		if job is Dictionary and String((job as Dictionary).get("kind", "")) == "Rearm":
			return true
	return false


func _rearm_lane() -> bool:
	var lane: String = "REARM"
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var start: Vector2i = SimTileMap.player_start(w.tilemap)
	var sx: float = float(start.x) + 0.5
	var sy: float = float(start.y) + 0.5
	var ent: int = _bare_colonist(w, sx, sy, "survivor.test.rearm")
	SimMelee.ensure_hands(w, ent)
	if not SimMelee.is_unarmed(w, ent):
		push_error("%s: a fresh colonist with only hands did not read as unarmed" % lane)
		return false
	var bat: int = SimItems.spawn_item(w, "item.bat.aluminium", {"tier": "scavenged"})
	w.components.set_component(bat, "position", {"x": sx + 3.0, "y": sy})
	if not _took_rearm(w, ent, 300):
		push_error("%s: an unarmed colonist with a working weapon 3 m away never took the Rearm job" % lane)
		return false

	# Negative: the identical placement, but already armed -- the hands did satisfy "armed" once
	# and would have made this a false pass; now they never do, and no Rearm job is ever taken.
	var w2: Variant = SimBoot.playable(20260805, 64)["world"]
	var start2: Vector2i = SimTileMap.player_start(w2.tilemap)
	var sx2: float = float(start2.x) + 0.5
	var sy2: float = float(start2.y) + 0.5
	var ent2: int = _bare_colonist(w2, sx2, sy2, "survivor.test.rearm2")
	SimInventory.equip(w2, ent2, SimItems.spawn_item(w2, "item.bat.aluminium", {"tier": "scavenged"}))
	w2.events.drain()
	if SimMelee.is_unarmed(w2, ent2):
		push_error("%s: an equipped colonist still read as unarmed -- the negative measures nothing" % lane)
		return false
	var bat2: int = SimItems.spawn_item(w2, "item.bat.aluminium", {"tier": "scavenged"})
	w2.components.set_component(bat2, "position", {"x": sx2 + 3.0, "y": sy2})
	if _took_rearm(w2, ent2, 300):
		push_error("%s: an armed colonist took a Rearm job anyway" % lane)
		return false
	print("  REARM an unarmed colonist with a working weapon nearby takes Rearm; the same colonist armed never does")
	return true


# --- NOISE -------------------------------------------------------------------------------------

func _noise_lane() -> bool:
	var lane: String = "NOISE"
	var w: Variant = _bare_world(9003)
	SimMelee.ensure_hands(w, w.player)
	_target(w, 17.3, 16.5)
	var noises: Array = []
	_watch(w, "gate-hands-noise", "noise.emitted", noises)
	w.commands.push({"type": "swing"})
	for i in 20:
		w.step()
	if noises.is_empty():
		push_error("%s: a punch published no noise.emitted at all" % lane)
		return false
	var n: Dictionary = noises[0] as Dictionary
	if int(n.get("source", -1)) != int(w.player):
		push_error("%s: the punch's noise named source %d, not the puncher %d" % [lane, int(n.get("source", -1)), int(w.player)])
		return false
	if absf(float(n.get("magnitude", -1.0)) - float(SimCombat.MELEE_CONNECT_NOISE)) > 0.0001:
		push_error("%s: a punch's connect noise was %.2f, expected MELEE_CONNECT_NOISE %.2f" % [lane, float(n.get("magnitude", -1.0)), float(SimCombat.MELEE_CONNECT_NOISE)])
		return false
	print("  NOISE a punch publishes noise.emitted at MELEE_CONNECT_NOISE from the puncher")
	return true


# --- SPAWN -------------------------------------------------------------------------------------

# The people the boot names, the way `person_clause` finds somebody to describe: `identity` and
# `needs`, excluding a corpse. Deliberately narrower than `check_m2_balance.gd`'s own
# `_colonists` (which also counts the player, who has no `identity`) -- this lane is about the
# named colony, not the whole census.
func _colonists(w: Variant) -> Array[int]:
	var out: Array[int] = []
	for ent in w.components.query(["identity", "needs"]):
		if w.components.has_component(int(ent), "corpse"):
			continue
		out.append(int(ent))
	return out


func _unarmed_count(w: Variant, colonists: Array[int]) -> int:
	var n: int = 0
	for ent in colonists:
		if SimMelee.is_unarmed(w, ent):
			n += 1
	return n


func _spawn_lane() -> bool:
	var lane: String = "SPAWN"
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var colonists: Array[int] = _colonists(w)
	if colonists.size() < 2:
		push_error("%s: the playable boot has %d named colonists -- this needs a colony, not a person" % [lane, colonists.size()])
		return false
	for ent in colonists:
		if not w.components.has_component(int(ent), "meleeWeapon"):
			push_error("%s: colonist %d has no meleeWeapon at all -- a kit or hands, but one is required" % [lane, int(ent)])
			return false
	var before: int = _unarmed_count(w, colonists)
	if before != 0:
		push_error("%s: a fresh boot already reports %d unarmed colonists" % [lane, before])
		return false
	SimInventory.unequip(w, int(colonists[colonists.size() - 1]), "primary")
	w.events.drain()
	var after: int = _unarmed_count(w, colonists)
	if after != 1:
		push_error("%s: stripping one colonist's kit moved the unarmed count to %d, expected 1 -- the counter is not measuring hands" % [lane, after])
		return false
	print("  SPAWN %d colonists all carry a meleeWeapon at boot (kit or hands); stripping one moves the unarmed count 0 -> %d" % [colonists.size(), after])
	return true
