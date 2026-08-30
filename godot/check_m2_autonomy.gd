extends SceneTree
# Who manages a survivor's skill web, and how the player says so.
#
# docs/07's Focus is the whole surface: the five self-managing focuses mean "you decide", Manual
# means "I decide", and there is deliberately no second toggle beside it. That makes provenance --
# `jobPriorities.focusSetBy` -- the load-bearing field, and this gate is about the three ways it
# can quietly stop working: a command that stamps the wrong value, a drift that ignores it, and a
# save that loses it.
#
# Seven lanes, each with a true positive and a true negative, and a loud skip wherever a
# precondition cannot be built -- an assertion with no data to judge says so, it never passes
# quietly (CLAUDE.md).

const SimBoot = preload("res://sim/boot.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const Clock = preload("res://sim/time/clock.gd")

const WEB_PATH: String = "res://content/colony/skill_web.json"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var boot: Dictionary = SimBoot.playable(20260829, 64)
	var w: Variant = boot["world"]
	var ok: bool = true
	ok = _cycle_lane(w) and ok
	ok = _drift_lane(w) and ok
	ok = _manual_holds_lane(w) and ok
	ok = _buy_lane(w) and ok
	ok = _content_lane() and ok
	ok = _view_lane(w) and ok
	ok = _save_lane(w) and ok
	if ok:
		print("M2_AUTONOMY_OK cycle drift manual-holds buy content view save")
		quit(0)
	else:
		push_error("M2_AUTONOMY_FAIL")
		quit(1)


# --- helpers -----------------------------------------------------------------------------------

func _spawn_colonist(w: Variant, dx: float) -> int:
	var rng: Variant = w.rng.stream("recruit")
	var pos: Variant = w.components.get_component(w.player, "position")
	var px: float = float((pos as Dictionary).get("x", 5.0)) if pos is Dictionary else 5.0
	var py: float = float((pos as Dictionary).get("y", 5.0)) if pos is Dictionary else 5.0
	return int(SimRecruits.spawn_generated(w, SimRecruits.roll(w, rng), px + dx, py))


func _focus_of(w: Variant, ent: int) -> String:
	var jp: Variant = w.components.get_component(ent, "jobPriorities")
	return String((jp as Dictionary).get("focus", "?")) if jp is Dictionary else "?"


func _set_by(w: Variant, ent: int) -> String:
	var jp: Variant = w.components.get_component(ent, "jobPriorities")
	return String((jp as Dictionary).get("focusSetBy", "auto")) if jp is Dictionary else "?"


func _nodes_of(w: Variant, ent: int) -> Array:
	var web: Variant = w.components.get_component(ent, "skillWeb")
	return ((web as Dictionary).get("nodes", []) as Array).duplicate() if web is Dictionary else []


# Everything published this step, as an Array of records -- a reference type, because a lambda
# capturing an int or a bool mutates its own copy and reads back unchanged (CLAUDE.md).
func _collect(w: Variant, types: Array) -> Array:
	var seen: Array = []
	for t in types:
		w.events.subscribe({"id": "autonomy.probe." + String(t), "type": String(t), "handler": func(e: Dictionary) -> void:
			seen.append(e.duplicate(true))
		})
	return seen


# Give this survivor points to spend without walking a whole job loop. `_earn` runs the autospend
# behind it, which is exactly what a Manual survivor is supposed to decline.
func _grant(w: Variant, ent: int, region: String, amount: int) -> void:
	SimSkills._earn(w, ent, region, amount)


# --- 1. CYCLE ----------------------------------------------------------------------------------
#
# The player's choice arrives as a command and lands with provenance on it. The negatives are the
# two ways that has already been got wrong: the sim's own drift path must NOT read as a player
# act, and choosing Auto -- the handback -- must not lock the survivor out of drift forever.
func _cycle_lane(w: Variant) -> bool:
	var chosen: int = _spawn_colonist(w, 1.0)
	var drifted: int = _spawn_colonist(w, 2.0)
	if chosen < 0 or drifted < 0:
		push_error("CYCLE: could not generate colonists, so nothing about provenance was judged")
		return false
	w.commands.push({"type": "job.focus", "entity": chosen, "focus": "Medic"})
	w.step()
	if _focus_of(w, chosen) != "Medic" or _set_by(w, chosen) != "player":
		push_error("CYCLE: job.focus Medic left focus %s setBy %s" % [_focus_of(w, chosen), _set_by(w, chosen)])
		return false
	# True negative: the same effect leaf, reached the way drift reaches it, is not a player act.
	SimJobs.set_focus(w, drifted, "Worker")
	if _focus_of(w, drifted) != "Worker" or _set_by(w, drifted) != "auto":
		push_error("CYCLE: the sim's own set_focus wrote setBy %s -- the seam cannot tell its callers apart" % _set_by(w, drifted))
		return false
	# The handback. Clicking round to Auto means "you decide", so it must clear the lock rather
	# than set one; stamped "player" it would freeze this survivor out of drift for the whole run.
	w.commands.push({"type": "job.focus", "entity": chosen, "focus": "Auto"})
	w.step()
	if _focus_of(w, chosen) != "Auto" or _set_by(w, chosen) != "auto":
		push_error("CYCLE: choosing Auto left setBy %s, so the handback locks instead of releasing" % _set_by(w, chosen))
		return false
	# And back again, through the dict-replacement branch of set_focus -- the branch that builds a
	# fresh jobPriorities and could drop the key entirely without anything noticing.
	w.commands.push({"type": "job.focus", "entity": chosen, "focus": "Scout"})
	w.step()
	if _focus_of(w, chosen) != "Scout" or _set_by(w, chosen) != "player":
		push_error("CYCLE: a second player focus read %s / %s -- the replacement branch drops provenance" % [
			_focus_of(w, chosen), _set_by(w, chosen)])
		return false
	# The Manual early-return branch writes it too, and it is the branch the whole feature rests on.
	w.commands.push({"type": "job.focus", "entity": chosen, "focus": "Manual"})
	w.step()
	if _focus_of(w, chosen) != "Manual" or _set_by(w, chosen) != "player":
		push_error("CYCLE: Manual read %s / %s" % [_focus_of(w, chosen), _set_by(w, chosen)])
		return false
	# The surface cycles this list; if it ever names a focus the sim will not take, the word on
	# screen and the word in the component part company.
	var ui: GDScript = load("res://ui/work_panel.gd") as GDScript
	if ui == null:
		push_error("CYCLE: work_panel.gd would not load, so the cycle the player clicks was not judged")
		return false
	var cycle: Array = ui.get("FOCUS_CYCLE") as Array
	if cycle == null or cycle.size() != 6 or not cycle.has("Manual") or not cycle.has("Auto"):
		push_error("CYCLE: the panel's FOCUS_CYCLE is %s" % str(cycle))
		return false
	for f in cycle:
		if SimJobs.preset(String(f)).is_empty():
			push_error("CYCLE: the panel offers %s and jobs.gd has no preset for it" % String(f))
			return false
	print("CYCLE OK command→player, set_focus→auto, Auto hands back, Manual and the replacement branch both keep it; %d focuses offered" % cycle.size())
	return true


# --- 2. DRIFT ----------------------------------------------------------------------------------
#
# Auto is honoured and the player is never overridden -- and the positive half matters most,
# because "drift never overrides the player" is vacuous if drift never fires at all.
func _drift_lane(w: Variant) -> bool:
	var free: int = _spawn_colonist(w, 3.0)
	var locked: int = _spawn_colonist(w, 4.0)
	if free < 0 or locked < 0:
		push_error("DRIFT: could not generate colonists, so nothing about drift was judged")
		return false
	if _set_by(w, free) != "auto":
		push_error("DRIFT: a fresh colonist already reads setBy %s" % _set_by(w, free))
		return false
	# The lock, through the command that stamps it. Medic is the focus drift would pick anyway,
	# so it is deliberately NOT used here -- `locked` is put on Fighter, which the Doctor work
	# below argues against, so "did not move" is a real refusal and not a coincidence.
	w.commands.push({"type": "job.focus", "entity": locked, "focus": "Fighter"})
	w.step()
	if _set_by(w, locked) != "player":
		push_error("DRIFT: the lock did not take (setBy %s)" % _set_by(w, locked))
		return false
	for _i in 5:
		w.events.publish({"type": "job.completed", "entity": free, "kind": "Doctor"})
		w.events.publish({"type": "job.completed", "entity": locked, "kind": "Doctor"})
	w.events.drain()
	if SimSkills.earned(w, free, "Medicine") < 2 or SimSkills.earned(w, locked, "Medicine") < 2:
		push_error("DRIFT: the earn lead never built (%d / %d Medicine), so neither half was judged" % [
			SimSkills.earned(w, free, "Medicine"), SimSkills.earned(w, locked, "Medicine")])
		return false
	w.tick = 3 * Clock.DAY_TICKS + 11
	w.step()
	if _focus_of(w, free) != "Medic":
		push_error("DRIFT: five Doctor jobs and a day boundary left an auto survivor on %s -- drift does not fire, so the negative below proves nothing" % _focus_of(w, free))
		return false
	if _focus_of(w, locked) != "Fighter":
		push_error("DRIFT: a player-set focus was overridden to %s" % _focus_of(w, locked))
		return false
	print("DRIFT OK auto moved Auto→Medic on the same evidence a player-set Fighter held")
	return true


# --- 3. MANUAL HOLDS ---------------------------------------------------------------------------
#
# A Manual survivor's points stay banked. The Auto twin is the true positive beside it: without
# somebody spending the same grant, "did not spend" could just mean the grant never arrived.
func _manual_holds_lane(w: Variant) -> bool:
	var mine: int = _spawn_colonist(w, 5.0)
	var theirs: int = _spawn_colonist(w, 6.0)
	if mine < 0 or theirs < 0:
		push_error("MANUAL: could not generate colonists, so nothing about holding was judged")
		return false
	w.commands.push({"type": "job.focus", "entity": mine, "focus": "Manual"})
	w.step()
	if _focus_of(w, mine) != "Manual":
		push_error("MANUAL: the survivor is on %s, so the hold was not judged" % _focus_of(w, mine))
		return false
	var held_before: int = SimSkills.node_count(w, mine)
	_grant(w, mine, "Survival", 3)
	_grant(w, theirs, "Survival", 3)
	if SimSkills.node_count(w, mine) != held_before or SimSkills.points(w, mine, "Survival") != 3:
		push_error("MANUAL: a Manual survivor spent -- %d nodes, %d points left" % [
			SimSkills.node_count(w, mine), SimSkills.points(w, mine, "Survival")])
		return false
	if SimSkills.node_count(w, theirs) < 1 or SimSkills.points(w, theirs, "Survival") >= 3:
		push_error("MANUAL: the Auto twin banked its points too (%d nodes, %d left), so 'Manual holds' proves nothing" % [
			SimSkills.node_count(w, theirs), SimSkills.points(w, theirs, "Survival")])
		return false
	print("MANUAL OK 3 Survival held whole; the Auto twin spent the same grant down to %d" % SimSkills.points(w, theirs, "Survival"))
	return true


# --- 4. BUY ------------------------------------------------------------------------------------
#
# The player's own purchase, and each of the four refusals, every one of them paired with an
# unchanged component -- a refusal that still spent the points would be the worst kind of green.
func _buy_lane(w: Variant) -> bool:
	var buyer: int = _spawn_colonist(w, 7.0)
	var auto: int = _spawn_colonist(w, 8.0)
	if buyer < 0 or auto < 0:
		push_error("BUY: could not generate colonists, so no buy was judged")
		return false
	w.commands.push({"type": "job.focus", "entity": buyer, "focus": "Manual"})
	w.step()
	_grant(w, buyer, "Survival", 1)
	_grant(w, auto, "Survival", 4)
	if SimSkills.points(w, buyer, "Survival") != 1:
		push_error("BUY: the buyer holds %d Survival, so affordability was not judged" % SimSkills.points(w, buyer, "Survival"))
		return false
	var learned: Array = _collect(w, ["web.learned"])
	var refused: Array = _collect(w, ["web.refused"])
	# True positive: affordable, unowned, Manual.
	w.commands.push({"type": "web.buy", "entity": buyer, "node": "surv.haul"})
	w.step()
	if not SimSkills.has_node(w, buyer, "surv.haul"):
		push_error("BUY: an affordable node was not bought; nodes %s" % str(_nodes_of(w, buyer)))
		return false
	if learned.size() != 1 or String((learned[0] as Dictionary).get("node", "")) != "surv.haul":
		push_error("BUY: web.learned did not fire once for surv.haul: %s" % str(learned))
		return false
	if SimSkills.points(w, buyer, "Survival") != 0:
		push_error("BUY: the points were not spent (%d left)" % SimSkills.points(w, buyer, "Survival"))
		return false
	learned.clear()
	# Each refusal, and the component that must not have moved with it.
	var cases: Array = [
		{"e": auto, "node": "surv.cook", "reason": "auto"},
		{"e": buyer, "node": "surv.nonesuch", "reason": "unknown"},
		{"e": buyer, "node": "surv.haul", "reason": "owned"},
		{"e": buyer, "node": "surv.cook", "reason": "points"},
	]
	for case_v in cases:
		var c: Dictionary = case_v as Dictionary
		var ent: int = int(c["e"])
		var before: Array = _nodes_of(w, ent)
		var pts_before: int = SimSkills.points(w, ent, "Survival")
		refused.clear()
		w.commands.push({"type": "web.buy", "entity": ent, "node": String(c["node"])})
		w.step()
		if refused.size() != 1 or String((refused[0] as Dictionary).get("reason", "")) != String(c["reason"]):
			push_error("BUY: buying %s expected refusal \"%s\", got %s" % [String(c["node"]), String(c["reason"]), str(refused)])
			return false
		if _nodes_of(w, ent) != before or SimSkills.points(w, ent, "Survival") != pts_before:
			push_error("BUY: refusal \"%s\" still changed the component: nodes %s→%s, points %d→%d" % [
				String(c["reason"]), str(before), str(_nodes_of(w, ent)), pts_before, SimSkills.points(w, ent, "Survival")])
			return false
		if not learned.is_empty():
			push_error("BUY: refusal \"%s\" published web.learned as well" % String(c["reason"]))
			return false
	print("BUY OK surv.haul bought and announced; auto/unknown/owned/points each refused with nothing spent")
	return true


# --- 5. CONTENT --------------------------------------------------------------------------------
#
# Every node has a prose name and no node's name has a digit in it. Neither validator constrains
# this: `godot:validate` is shallow and does not recurse into `nodes[]`, and nothing under `src/`
# reads this file at all, so Ajv never sees it either. The assertion lives here or nowhere.
func _content_lane() -> bool:
	var f: FileAccess = FileAccess.open(WEB_PATH, FileAccess.READ)
	if f == null:
		push_error("CONTENT: %s missing, so no name was judged" % WEB_PATH)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_error("CONTENT: %s is not an object" % WEB_PATH)
		return false
	var nodes: Array = (parsed as Dictionary).get("nodes", []) as Array
	if nodes.is_empty():
		push_error("CONTENT: no nodes in the web, so no name was judged")
		return false
	var digits: RegEx = RegEx.new()
	digits.compile("[0-9]")
	# The scanner's self-test. Without it a compile that silently failed, or a search that never
	# matched, would pass every real name for the wrong reason.
	if digits.search("melee grip") != null or digits.search("grip 2") == null:
		push_error("CONTENT: the digit scanner does not work, so its verdict on the names means nothing")
		return false
	for n in nodes:
		if not n is Dictionary:
			push_error("CONTENT: a node is not an object")
			return false
		var nd: Dictionary = n as Dictionary
		var nid: String = String(nd.get("id", ""))
		var nm: String = String(nd.get("name", ""))
		if nm.strip_edges().is_empty():
			push_error("CONTENT: %s has no name, so the screen would draw a blank where a phrase goes" % nid)
			return false
		if digits.search(nm) != null:
			push_error("CONTENT: %s is named \"%s\" -- a digit on the work panel is a number the player was not meant to have" % [nid, nm])
			return false
	print("CONTENT OK %d nodes, every one named in digit-free prose" % nodes.size())
	return true


# --- 6. VIEW -----------------------------------------------------------------------------------
#
# The condition-view assertion, applied to the web: serialise the whole read model and assert that
# no number of any kind crosses into it, with a key allowlist that fails the moment one is added.
func _view_lane(w: Variant) -> bool:
	var manual: int = _spawn_colonist(w, 9.0)
	var auto: int = _spawn_colonist(w, 10.0)
	if manual < 0 or auto < 0:
		push_error("VIEW: could not generate colonists, so no view was judged")
		return false
	w.commands.push({"type": "job.focus", "entity": manual, "focus": "Manual"})
	w.step()
	_grant(w, manual, "Medicine", 3)
	_grant(w, auto, "Medicine", 3)
	var view: Dictionary = SimSkills.web_view(w, manual)
	var known: Array = view.get("known", []) as Array
	var learnable: Array = view.get("learnable", []) as Array
	if learnable.is_empty():
		push_error("VIEW: a Manual survivor with 3 Medicine could learn nothing, so the shape was not judged")
		return false
	if view.keys().size() != 2 or not view.has("known") or not view.has("learnable"):
		push_error("VIEW: the view carries %s" % str(view.keys()))
		return false
	for it in learnable:
		var d: Dictionary = it as Dictionary
		if d.keys().size() != 2 or not d.has("node") or not d.has("name"):
			push_error("VIEW: a learnable entry carries %s -- one added numeric field and a cost is back on screen" % str(d.keys()))
			return false
		for k in d.keys():
			if not (d[k] is String):
				push_error("VIEW: learnable.%s is not a word" % String(k))
				return false
	for kn in known:
		if not (kn is String):
			push_error("VIEW: a known entry is not a word")
			return false
	var digits: RegEx = RegEx.new()
	digits.compile("[0-9]")
	var json: String = JSON.stringify(view)
	if digits.search("no digits here") != null or digits.search(json + "1") == null:
		push_error("VIEW: the digit scanner does not work, so its verdict means nothing")
		return false
	if digits.search(json) != null:
		push_error("VIEW: a digit crossed the boundary: %s" % json)
		return false
	# The true negative for the whole lane: the same grant on an Auto survivor offers nothing,
	# because a survivor managing their own web has nothing for the player to click -- and the
	# intake would refuse it anyway.
	var theirs: Dictionary = SimSkills.web_view(w, auto)
	if not ((theirs.get("learnable", []) as Array).is_empty()):
		push_error("VIEW: an Auto survivor offered %s to buy, which the intake refuses" % str(theirs.get("learnable", [])))
		return false
	if (theirs.get("known", []) as Array).is_empty():
		push_error("VIEW: the Auto survivor knows nothing after 3 Medicine, so 'known is still delivered' was not judged")
		return false
	print("VIEW OK %d known / %d learnable, no numeric field and no digit; an Auto survivor offers none" % [
		known.size(), learnable.size()])
	return true


# --- 7. SAVE ROUND-TRIP ------------------------------------------------------------------------
#
# The silent failure this whole design is exposed to: `focusSetBy` is one String inside a
# component, components round-trip through JSON, and a key lost there re-enables drift over a
# player's choice with nothing to report it. So the drift assertion is run a second time on the
# far side of a real JSON encode/decode.
func _save_lane(w: Variant) -> bool:
	var locked: int = _spawn_colonist(w, 11.0)
	if locked < 0:
		push_error("SAVE: could not generate a colonist, so no round trip was judged")
		return false
	w.commands.push({"type": "job.focus", "entity": locked, "focus": "Fighter"})
	w.step()
	for _i in 5:
		w.events.publish({"type": "job.completed", "entity": locked, "kind": "Doctor"})
	w.events.drain()
	if _set_by(w, locked) != "player" or SimSkills.earned(w, locked, "Medicine") < 2:
		push_error("SAVE: the fixture is not the one the lane needs (setBy %s, %d Medicine)" % [
			_set_by(w, locked), SimSkills.earned(w, locked, "Medicine")])
		return false
	# Through actual JSON, not a Dictionary copy: the trap is that JSON has no integer keys and no
	# types beyond its own, so only text can prove what survives.
	var text: String = JSON.stringify(w.snapshot())
	var back: Variant = JSON.parse_string(text)
	if not back is Dictionary:
		push_error("SAVE: the snapshot did not survive JSON at all")
		return false
	w.restore(back as Dictionary)
	if _focus_of(w, locked) != "Fighter":
		push_error("SAVE: the focus itself did not survive the round trip (%s)" % _focus_of(w, locked))
		return false
	if _set_by(w, locked) != "player":
		push_error("SAVE: provenance came back as \"%s\" -- a restored colony would drift a survivor the player had set" % _set_by(w, locked))
		return false
	w.tick = 9 * Clock.DAY_TICKS + 23
	w.step()
	if _focus_of(w, locked) != "Fighter":
		push_error("SAVE: after a load, drift moved a player-set focus to %s" % _focus_of(w, locked))
		return false
	print("SAVE OK a player-set focus survives JSON and still refuses drift on the far side")
	return true
