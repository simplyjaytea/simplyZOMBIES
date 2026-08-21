extends SceneTree
# Shallow skill web: kill/haul earn points; Focus auto-allocates (ADR 0012).

const SimBoot = preload("res://sim/boot.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimHealth = preload("res://sim/modules/health.gd")

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
	print("M2_WEB_OK earn focus mods")
	quit(0)
