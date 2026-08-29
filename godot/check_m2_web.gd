extends SceneTree
# Shallow skill web: kill/haul earn points; Focus auto-allocates (ADR 0012).

const SimBoot = preload("res://sim/boot.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const Clock = preload("res://sim/time/clock.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var boot: Dictionary = SimBoot.playable(20260805, 64)
	var w: Variant = boot["world"]
	var player: int = int(w.player)
	if not w.components.has_component(player, "skillWeb"):
		push_error("player missing skillWeb")
		quit(1)
		return
	var before: int = SimSkills.node_count(w, player)
	# Earn Survival via job.completed (queued until drain)
	w.events.publish({"type": "job.completed", "entity": player, "kind": "Haul"})
	w.events.publish({"type": "job.completed", "entity": player, "kind": "Haul"})
	# Fake melee kill
	var zed: int = int(w.entities.spawn())
	w.components.set_component(zed, "zombieType", {"id": "zombie.shambler"})
	w.components.set_component(zed, "body", {"head": 1.0, "torso": 40.0, "arms": 40.0, "legs": 40.0})
	w.components.set_component(zed, "position", {"x": 1.0, "y": 1.0})
	w.components.set_component(player, "meleeWeapon", {"damage": 10})
	w.events.publish({"type": "entity.killed", "entity": zed, "killer": player, "x": 1.0, "y": 1.0, "zombieType": "zombie.shambler"})
	w.events.drain()
	var after: int = SimSkills.node_count(w, player)
	var melee_pts: int = SimSkills.points(w, player, "Melee")
	var surv_pts: int = SimSkills.points(w, player, "Survival")
	if after <= before and melee_pts + surv_pts <= 0:
		push_error("expected nodes or unspent points after earn (nodes %d→%d)" % [before, after])
		quit(1)
		return
	print("WEB OK nodes %d→%d meleePts %d survPts %d" % [before, after, melee_pts, surv_pts])
	# Focus path changes allocation preference
	var mara: int = -1
	for e in w.components.query(["identity", "skillWeb"]):
		var idn: Variant = w.components.get_component(int(e), "identity")
		if idn is Dictionary and bool((idn as Dictionary).get("unique", false)):
			mara = int(e)
			break
	if mara < 0:
		# CLAUDE.md: an assertion with no data to judge says so and skips, it never passes
		# quietly. This lane used to be an `if mara >= 0:` with no else, so a fixture that
		# stopped producing a unique survivor would have taken the whole FOCUS claim with it
		# and still printed M2_WEB_OK.
		push_error("no unique survivor in the fixture, so the FOCUS lane asserted nothing")
		quit(1)
		return
	if true:
		SimJobs.set_focus(w, mara, "Medic")
		for i in 4:
			w.events.publish({"type": "job.completed", "entity": mara, "kind": "Doctor"})
		w.events.drain()
		if SimSkills.node_count(w, mara) < 1 and SimSkills.points(w, mara, "Medicine") < 1:
			push_error("medic path earned nothing")
			quit(1)
			return
		print("FOCUS OK medic nodes %d" % SimSkills.node_count(w, mara))
	# Modifier applies when node owned
	SimSkills._earn(w, player, "Melee", 5)
	var dmg: float = float(w.modifiers.call("resolve", "melee_damage", player))
	# `> 1.0`, not `< 1.0`. `melee_damage` has base 1.0 (sim/modifiers/stats.gd), so a resolve
	# with **no** skill modifier at all returns exactly 1.0 and sailed past the old comparison --
	# the assertion for "the modifier applies when the node is owned" was satisfied by the
	# modifier not applying.
	if dmg <= 1.0:
		push_error("melee_damage mul missing after spend: resolved %.3f against a base of 1.0" % dmg)
		quit(1)
		return
	print("MOD OK melee_damage %.3f" % dmg)
	# Manual must not auto-spend; Rest earns Endurance (docs/08).
	SimJobs.set_focus(w, player, "Manual")
	var nodes_before_manual: int = SimSkills.node_count(w, player)
	w.events.publish({"type": "job.completed", "entity": player, "kind": "Rest"})
	w.events.publish({"type": "job.completed", "entity": player, "kind": "Rest"})
	w.events.drain()
	if SimSkills.node_count(w, player) != nodes_before_manual:
		push_error("Manual focus auto-spent")
		quit(1)
		return
	if SimSkills.points(w, player, "Endurance") < 2:
		push_error("Rest did not earn Endurance")
		quit(1)
		return
	print("MANUAL OK endPts %d nodes held %d" % [SimSkills.points(w, player, "Endurance"), nodes_before_manual])

	if not _npc_lane(w):
		quit(1)
		return
	if not _surplus_lane(w):
		quit(1)
		return
	if not _reach_lane(w):
		quit(1)
		return
	if not _drift_lane(w):
		quit(1)
		return
	print("M2_WEB_OK earn focus mods npc surplus reach drift")
	quit(0)


# --- helpers -----------------------------------------------------------------------------------

# A body-less survivor: identity, a job row and a web, which is everything auto-allocation reads.
# The reachability lane needs sixteen of these and none of them needs legs; the generated
# colonists the NPC and drift lanes use are the real thing, spawned the way the recruit beat
# spawns them.
func _probe(w: Variant, focus: String, backstory: String) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "identity", {
		"id": "survivor.probe", "name": "Probe", "unique": false, "backstory": backstory,
	})
	SimJobs.attach(w, ent, focus)
	SimSkills.attach(w, ent)
	return ent


func _spawn_colonist(w: Variant, rng: Variant, dx: float) -> int:
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


# --- lanes -------------------------------------------------------------------------------------

# An NPC spends its own points. The roadmap said "nobody but the player can walk the web", which
# was never true -- the FOCUS lane above has always spent Mara's -- but nothing had ever asserted
# it for a *generated* colonist, the kind a campaign is actually made of.
func _npc_lane(w: Variant) -> bool:
	var rng: Variant = w.rng.stream("recruit")
	var earner: int = _spawn_colonist(w, rng, 1.0)
	var idler: int = _spawn_colonist(w, rng, 2.0)
	if earner < 0 or idler < 0:
		push_error("could not generate a colonist, so the NPC lane asserted nothing")
		return false
	# The claim is about somebody who is neither the player nor player-driven; assert it rather
	# than assume it, since `spawn_generated` is not this file's code.
	if earner == int(w.player) or w.components.has_component(earner, "controlled"):
		push_error("NPC lane picked the player, so it proved nothing about an NPC")
		return false
	SimJobs.set_focus(w, idler, "Manual")
	for _i in 6:
		w.events.publish({"type": "job.completed", "entity": earner, "kind": "Haul"})
		w.events.publish({"type": "job.completed", "entity": idler, "kind": "Haul"})
	w.events.drain()
	var nodes: int = SimSkills.node_count(w, earner)
	var left: int = SimSkills.points(w, earner, "Survival")
	if nodes < 1 or left >= 6:
		push_error("an Auto NPC earned 6 Survival and bought %d nodes with %d left" % [nodes, left])
		return false
	if SimSkills.node_count(w, idler) != 0 or SimSkills.points(w, idler, "Survival") != 6:
		push_error("a Manual NPC spent points: %d nodes, %d left" % [
			SimSkills.node_count(w, idler), SimSkills.points(w, idler, "Survival")])
		return false
	print("NPC OK auto %d nodes %d survPts left; manual twin 0 nodes 6 held" % [nodes, left])
	return true


# Points earned off the focus path used to be stranded for the life of the survivor.
func _surplus_lane(w: Variant) -> bool:
	var def: Dictionary = SimSkills._web()
	var auto_path: Array = (def.get("focusPaths", {}) as Dictionary).get("Auto", []) as Array
	# The whole lane rests on the Auto path naming no Craft node, so say so out loud: if a
	# content edit puts one there, this stops being evidence for the second pass and the gate
	# says so instead of passing on a technicality.
	if auto_path.has("craft.tape") or auto_path.has("craft.scrap"):
		push_error("the Auto path now names a Craft node, so the surplus lane proves nothing")
		return false
	var rng: Variant = w.rng.stream("recruit")
	var crafter: int = _spawn_colonist(w, rng, 3.0)
	if crafter < 0:
		push_error("could not generate a colonist, so the surplus lane asserted nothing")
		return false
	SimSkills._earn(w, crafter, "Craft", 5)
	if not SimSkills.has_node(w, crafter, "craft.tape") or not SimSkills.has_node(w, crafter, "craft.scrap"):
		push_error("5 Craft points bought no Craft node on a path that has none: nodes %s" % str(
			(w.components.get_component(crafter, "skillWeb") as Dictionary).get("nodes", [])))
		return false
	# And the second pass buys what is affordable, not whatever it likes: craft.tape (1) and
	# craft.scrap (2) is the whole region, so exactly 2 of the 5 are left standing.
	if SimSkills.points(w, crafter, "Craft") != 2:
		push_error("surplus spending left %d Craft points, expected 2" % SimSkills.points(w, crafter, "Craft"))
		return false
	print("SURPLUS OK craft.tape + craft.scrap off-path, 2 of 5 points left")
	return true


# Every node in the web is owned by somebody, eventually: on a focus path, or by the surplus
# pass. Before this slice `ranged.calm` and `craft.scrap` were on no path and there is no web
# screen, so they were nodes no survivor in the game could ever own.
func _reach_lane(w: Variant) -> bool:
	var def: Dictionary = SimSkills._web()
	var nodes: Array = def.get("nodes", []) as Array
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	if nodes.is_empty() or paths.is_empty():
		push_error("no web content, so the reachability lane asserted nothing")
		return false
	var region_total: Dictionary = {}
	for n in nodes:
		var reg: String = String((n as Dictionary).get("region", ""))
		region_total[reg] = int(region_total.get(reg, 0)) + int((n as Dictionary).get("cost", 1))
	var by_path: Array = []
	var by_surplus: Array = []
	for n in nodes:
		var nd: Dictionary = n as Dictionary
		var nid: String = String(nd.get("id", ""))
		var region: String = String(nd.get("region", ""))
		var focus: String = ""
		for f in paths.keys():
			if (paths[f] as Array).has(nid):
				focus = String(f)
				break
		var probe: int = _probe(w, focus if focus != "" else "Auto", "")
		# A region's whole cost, so the probe can afford every node in it and the only question
		# left is whether anything ever offers to buy this one.
		SimSkills._earn(w, probe, region, int(region_total.get(region, 1)))
		if not SimSkills.has_node(w, probe, nid):
			push_error("%s (%s, cost %d) is on no focus path and the surplus pass never buys it: nobody in the game can own it" % [
				nid, region, int(nd.get("cost", 1))])
			return false
		if focus == "":
			by_surplus.append(nid)
		else:
			by_path.append(nid)
	# The true negative for the whole lane: the same probe with nothing earned owns nothing, so
	# "every node reachable" is not being satisfied by a spender that buys regardless of points.
	var broke: int = _probe(w, "Auto", "")
	if SimSkills.node_count(w, broke) != 0:
		push_error("a probe with no points owns %d nodes" % SimSkills.node_count(w, broke))
		return false
	print("REACH OK %d nodes: %d by path, %d by surplus %s" % [
		nodes.size(), by_path.size(), by_surplus.size(), str(by_surplus)])
	return true


# Drift: an NPC's focus follows what they have actually been doing, once a day, unless a person
# set it.
func _drift_lane(w: Variant) -> bool:
	var rng: Variant = w.rng.stream("recruit")
	var drifter: int = _spawn_colonist(w, rng, 4.0)
	var locked: int = _spawn_colonist(w, rng, 5.0)
	var twin: int = _spawn_colonist(w, rng, 6.0)
	if drifter < 0 or locked < 0 or twin < 0:
		push_error("could not generate colonists, so the drift lane asserted nothing")
		return false
	# The player's choice arrives as a command, which is the one path that stamps provenance.
	w.commands.push({"type": "job.focus", "entity": locked, "focus": "Auto"})
	w.step()
	if _set_by(w, locked) != "player" or _set_by(w, drifter) != "auto":
		push_error("provenance: the job.focus command wrote \"%s\" and an untouched NPC reads \"%s\"" % [
			_set_by(w, locked), _set_by(w, drifter)])
		return false
	for _i in 5:
		w.events.publish({"type": "job.completed", "entity": drifter, "kind": "Doctor"})
		w.events.publish({"type": "job.completed", "entity": locked, "kind": "Doctor"})
	w.events.drain()
	# Cadence, negative half: a day already considered is not reconsidered, however many ticks
	# of it are left.
	w.step()
	if _focus_of(w, drifter) != "Auto":
		push_error("drift ran twice in one day: focus %s" % _focus_of(w, drifter))
		return false
	# Cadence, positive half, and the compression case with it: the clock jumps three days in
	# one step and never lands on a boundary tick. A cadence written as "the tick the day turns
	# over" would fire for nobody here, which is exactly what a compressed campaign does.
	w.tick = 4 * Clock.DAY_TICKS + 17
	w.step()
	if _focus_of(w, drifter) != "Medic":
		push_error("5 Doctor jobs and a day boundary left the NPC on %s" % _focus_of(w, drifter))
		return false
	if _focus_of(w, locked) != "Auto":
		push_error("drift overrode a player-set focus: %s" % _focus_of(w, locked))
		return false
	# And the new focus is what allocates from now on. Two Endurance points at once is the one
	# grant that tells the paths apart: Medic reaches end.grit (2) before the surplus pass can
	# spend the same two on end.legs (1), and Auto buys end.legs and cannot afford end.grit.
	# Granted in one call rather than as two Rest jobs because two jobs are two earns, and the
	# first would already have bought the cheap node under either focus.
	SimSkills._earn(w, drifter, "Endurance", 2)
	SimSkills._earn(w, twin, "Endurance", 2)
	if not SimSkills.has_node(w, drifter, "end.grit") or SimSkills.has_node(w, drifter, "end.legs"):
		push_error("the drifted Medic did not spend down the Medic path: %s" % str(
			(w.components.get_component(drifter, "skillWeb") as Dictionary).get("nodes", [])))
		return false
	if not SimSkills.has_node(w, twin, "end.legs") or SimSkills.has_node(w, twin, "end.grit"):
		push_error("the Auto twin spent like a Medic: %s" % str(
			(w.components.get_component(twin, "skillWeb") as Dictionary).get("nodes", [])))
		return false
	# One point of Medicine and a history that names it drifts; the same point with a history
	# that names nothing does not. The backstories are written here rather than drawn from the
	# generator pool, so a change to that pool cannot quietly delete this assertion.
	var nurse: int = _probe(w, "Auto", "veterinary nurse")
	var auditor: int = _probe(w, "Auto", "night auditor")
	SimSkills._earn(w, nurse, "Medicine", 1)
	SimSkills._earn(w, auditor, "Medicine", 1)
	w.tick = 6 * Clock.DAY_TICKS + 17
	w.step()
	if _focus_of(w, nurse) != "Medic":
		push_error("the nurse's history bought nothing: focus %s" % _focus_of(w, nurse))
		return false
	if _focus_of(w, auditor) != "Auto":
		push_error("one Medicine point with no history drifted anyway: focus %s" % _focus_of(w, auditor))
		return false
	# Endurance is in no focus's regions, on purpose: everybody sleeps, so a region everybody
	# earns is a vote for nobody. The twin has earned two Endurance and nothing else.
	if _focus_of(w, twin) != "Auto":
		push_error("Endurance voted: the twin drifted to %s on Rest alone" % _focus_of(w, twin))
		return false
	print("DRIFT OK medic after a day boundary; player-set held; nurse 1pt drifts, auditor 1pt does not; Rest votes for nobody")
	return true
