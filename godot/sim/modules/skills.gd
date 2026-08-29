class_name SimSkills
extends RefCounted

# Shallow six-region web (ADR 0012). Points from doing; Focus auto-spend; dies with person.

const Clock = preload("res://sim/time/clock.gd")

const WEB_PATH: String = "res://content/colony/skill_web.json"
const SOURCE_PREFIX: String = "web."

const REGIONS: Array[String] = ["Melee", "Ranged", "Medicine", "Craft", "Survival", "Endurance"]

# --- Focus drift ---------------------------------------------------------------------------
# docs/07's anti-micromanagement rule says an NPC on a Focus auto-allocates "along a sensible path
# for that focus" and never touches what you locked. Choosing the focus was the missing half: every
# NPC booted on "Auto" and stayed there for the whole campaign, so six survivors bought the same
# five nodes in the same order regardless of what they had spent their lives doing.
#
# DRIFT_LEAD is the anti-thrash margin: the suggested focus must beat the runner-up by this much
# before anyone is moved, so a survivor one job either side of a tie does not flip roles nightly.
# HISTORY_NUDGE is what a survivor's past is worth against what they have actually done -- one
# point, so it breaks a near-tie and never outvotes a career. Both are in docs/30.
const DRIFT_LEAD: int = 2
const HISTORY_NUDGE: int = 1

static var _cached: Dictionary = {}


static func _web() -> Dictionary:
	if not _cached.is_empty():
		return _cached
	var f := FileAccess.open(WEB_PATH, FileAccess.READ)
	if f == null:
		push_error("skill web missing: %s" % WEB_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_error("skill web corrupt")
		return {}
	_cached = parsed as Dictionary
	return _cached


static func attach(world: Variant, entity: int) -> void:
	var points: Dictionary = {}
	for r in REGIONS:
		points[r] = 0
	world.components.set_component(entity, "skillWeb", {
		"points": points,
		"nodes": [],
		# The day this survivor's focus was last considered. A day *number*, never the tick the
		# day turns over: a compressed campaign steps the clock past any single tick, so a
		# cadence written as "the tick day_number changes" fires for nobody. Read with a
		# default, because a component minted before this field existed (a save, a fixture that
		# writes skillWeb by hand) has to mean "never considered" rather than crash.
		"driftDay": 0,
	})
	_autospend(world, entity)


static func register_module(world: Variant) -> void:
	world.events.subscribe({"id": "skills.kill-points", "type": "entity.killed", "handler": func(e: Dictionary) -> void:
		var killer: int = int(e.get("killer", -1))
		if killer < 0 or not world.components.has_component(killer, "skillWeb"):
			return
		if not world.components.has_component(int(e.get("entity", -1)), "zombieType"):
			return
		var region: String = "Melee"
		if world.components.has_component(killer, "rangedWeapon"):
			var rw: Variant = world.components.get_component(killer, "rangedWeapon")
			if rw is Dictionary and int((rw as Dictionary).get("state", 0)) != 0:
				region = "Ranged"
			elif world.components.has_component(killer, "meleeWeapon"):
				region = "Melee"
			else:
				region = "Ranged"
		_earn(world, killer, region, 1)
	})
	world.events.subscribe({"id": "skills.job-points", "type": "job.completed", "handler": func(e: Dictionary) -> void:
		var ent: int = int(e.get("entity", -1))
		if ent < 0 or not world.components.has_component(ent, "skillWeb"):
			return
		var kind: String = String(e.get("kind", ""))
		match kind:
			"Haul":
				_earn(world, ent, "Survival", 1)
			"Cook":
				_earn(world, ent, "Survival", 1)
			"Construct":
				_earn(world, ent, "Craft", 1)
			"Doctor":
				_earn(world, ent, "Medicine", 1)
			"Rest":
				# Docs/08: Endurance from hard nights / recovery — Rest is the slice hook.
				_earn(world, ent, "Endurance", 1)
			_:
				pass
	})
	world.events.subscribe({"id": "skills.focus-respend", "type": "job.focus_changed", "handler": func(e: Dictionary) -> void:
		var ent: int = int(e.get("entity", -1))
		if ent >= 0:
			_autospend(world, ent)
	})
	# Who a survivor is becoming, reconsidered once a game day. `last_day` is a one-element
	# Array held by this closure rather than a `static var`: a static would be shared between
	# the two worlds a gate boots (CLAUDE.md, and docs/30 twice over), and a closure over an
	# int would capture the int by value. The Array is the reference type that makes it
	# per-world state. It is a fast path only -- the authoritative "already considered today"
	# guard is `driftDay` on each survivor's own component, which survives a save and a load
	# into a fresh world where this closure starts over at 0.
	var last_day: Array = [0]
	world.systems.register("skills.drift", "ai", -1, func(w: Variant) -> void:
		var day: int = Clock.day_number(int(w.tick))
		if day == int(last_day[0]):
			return
		last_day[0] = day
		_drift_all(w, day)
	)


static func _earn(world: Variant, entity: int, region: String, amount: int) -> void:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return
	var pts: Dictionary = (web as Dictionary).get("points", {}) as Dictionary
	pts[region] = int(pts.get(region, 0)) + amount
	(web as Dictionary)["points"] = pts
	world.components.set_component(entity, "skillWeb", web)
	_autospend(world, entity)


static func _focus_of(world: Variant, entity: int) -> String:
	var jp: Variant = world.components.get_component(entity, "jobPriorities")
	if jp is Dictionary:
		return String((jp as Dictionary).get("focus", "Auto"))
	return "Auto"


static func _autospend(world: Variant, entity: int) -> void:
	var def: Dictionary = _web()
	if def.is_empty():
		return
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return
	var w: Dictionary = web as Dictionary
	var pts: Dictionary = (w.get("points", {}) as Dictionary).duplicate()
	var owned: Array = (w.get("nodes", []) as Array).duplicate()
	var focus: String = _focus_of(world, entity)
	if focus == "Manual":
		return
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	var path: Array = paths.get(focus, paths.get("Auto", [])) as Array
	var nodes_by_id: Dictionary = _nodes_by_id(def)
	var changed: bool = false
	for nid_v in path:
		var nid: String = String(nid_v)
		if owned.has(nid):
			continue
		var node: Variant = nodes_by_id.get(nid)
		if not node is Dictionary:
			continue
		var region: String = String((node as Dictionary).get("region", ""))
		var cost: int = int((node as Dictionary).get("cost", 1))
		if int(pts.get(region, 0)) < cost:
			continue
		pts[region] = int(pts.get(region, 0)) - cost
		owned.append(nid)
		changed = true
	# Second pass: what the focus path cannot take. Points are region-tagged (docs/08) and a
	# path names five nodes at most, so everything earned off the path used to sit in the
	# component forever -- an Auto survivor who spent the campaign on Construct banked Craft
	# points against a path with no Craft node in it, and `ranged.calm` and `craft.scrap` were
	# on no path at all, which made them nodes no survivor in the game could ever own.
	#
	# Cheapest affordable node first, ties broken by content order, and only ever with points
	# of that node's own region -- so this can never spend a path's savings on something else,
	# and a survivor drifts outward from the centre the way docs/08 describes ("near the
	# centre: cheap, broad ... anyone drifts here") instead of stalling. The loop terminates
	# because every pass appends to `owned`, which the scan then skips.
	while true:
		var best_id: String = ""
		var best_region: String = ""
		var best_cost: int = 0
		for n in def.get("nodes", []) as Array:
			if not n is Dictionary:
				continue
			var nd: Dictionary = n as Dictionary
			var cid: String = String(nd.get("id", ""))
			if owned.has(cid):
				continue
			var creg: String = String(nd.get("region", ""))
			var ccost: int = int(nd.get("cost", 1))
			if int(pts.get(creg, 0)) < ccost:
				continue
			if best_id == "" or ccost < best_cost:
				best_id = cid
				best_region = creg
				best_cost = ccost
		if best_id == "":
			break
		pts[best_region] = int(pts.get(best_region, 0)) - best_cost
		owned.append(best_id)
		changed = true
	if not changed and owned == (w.get("nodes", []) as Array):
		return
	w["points"] = pts
	w["nodes"] = owned
	world.components.set_component(entity, "skillWeb", w)
	_apply_mods(world, entity, owned, nodes_by_id)


static func _apply_mods(world: Variant, entity: int, owned: Array, nodes_by_id: Dictionary) -> void:
	if world.modifiers == null:
		return
	# Wipe prior web sources then re-add owned.
	for n in nodes_by_id.values():
		if n is Dictionary:
			var src: String = SOURCE_PREFIX + String((n as Dictionary).get("id", ""))
			world.modifiers.call("remove_by_source", src, entity)
	for nid_v in owned:
		var node: Variant = nodes_by_id.get(String(nid_v))
		if not node is Dictionary:
			continue
		var nd: Dictionary = node as Dictionary
		world.modifiers.call("add", {
			"stat": String(nd.get("stat", "move_speed")),
			"op": String(nd.get("op", "mul")),
			"value": float(nd.get("value", 1.0)),
			"source": SOURCE_PREFIX + String(nd.get("id", "")),
		}, entity)


static func node_count(world: Variant, entity: int) -> int:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return 0
	return ((web as Dictionary).get("nodes", []) as Array).size()


static func points(world: Variant, entity: int, region: String) -> int:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return 0
	var pts: Dictionary = (web as Dictionary).get("points", {}) as Dictionary
	return int(pts.get(region, 0))


static func has_node(world: Variant, entity: int, node_id: String) -> bool:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return false
	return ((web as Dictionary).get("nodes", []) as Array).has(node_id)


static func _nodes_by_id(def: Dictionary) -> Dictionary:
	var by_id: Dictionary = {}
	for n in def.get("nodes", []) as Array:
		if n is Dictionary:
			by_id[String((n as Dictionary).get("id", ""))] = n
	return by_id


# Everything this survivor has ever earned in a region: what is still banked, plus what the
# nodes they own cost. Derived rather than stored, deliberately -- a second "earned" tally on
# the component would be a number that can disagree with the two it is made of, and a
# Dictionary keyed per region is one more thing to keep alive across a save.
static func earned(world: Variant, entity: int, region: String) -> int:
	var web: Variant = world.components.get_component(entity, "skillWeb")
	if not web is Dictionary:
		return 0
	var total: int = int(((web as Dictionary).get("points", {}) as Dictionary).get(region, 0))
	var by_id: Dictionary = _nodes_by_id(_web())
	for nid_v in (web as Dictionary).get("nodes", []) as Array:
		var node: Variant = by_id.get(String(nid_v))
		if node is Dictionary and String((node as Dictionary).get("region", "")) == region:
			total += int((node as Dictionary).get("cost", 1))
	return total


# The focus this survivor's life so far argues for: `{focus, lead, work}`, where `lead` is the
# margin over the runner-up and `work` is the earned points behind the winner with the history
# nudge taken back out. Empty focus means the web has nothing to say.
#
# Which regions argue for which focus is content (`focusRegions` in the web), because it is the
# same kind of statement as `focusPaths` beside it. Endurance is deliberately in none of them:
# every survivor sleeps, so Rest earns Endurance for everybody, and a region everyone earns
# equally is a vote for nobody.
static func suggest_focus(world: Variant, entity: int) -> Dictionary:
	var empty: Dictionary = {"focus": "", "lead": 0, "work": 0}
	var def: Dictionary = _web()
	var by_focus: Dictionary = def.get("focusRegions", {}) as Dictionary
	if by_focus.is_empty():
		return empty
	var history: String = _history_focus(world, entity)
	var scores: Array = []
	for focus_v in by_focus.keys():
		var work: int = 0
		for region_v in by_focus[focus_v] as Array:
			work += earned(world, entity, String(region_v))
		var score: int = work
		if String(focus_v) == history:
			score += HISTORY_NUDGE
		scores.append({"focus": String(focus_v), "work": work, "score": score})
	if scores.is_empty():
		return empty
	# By index, never by handing the record back: `Array.find` on Dictionaries matches by value
	# (CLAUDE.md), so "which of these is the top one" has to be an index or it is a guess.
	var top: int = 0
	for i in scores.size():
		if int((scores[i] as Dictionary)["score"]) > int((scores[top] as Dictionary)["score"]):
			top = i
	var runner_up: int = 0
	for i in scores.size():
		if i == top:
			continue
		runner_up = maxi(runner_up, int((scores[i] as Dictionary)["score"]))
	var best: Dictionary = scores[top] as Dictionary
	return {
		"focus": String(best["focus"]),
		"lead": int(best["score"]) - runner_up,
		"work": int(best["work"]),
	}


# One point for who they were before the outbreak, from the first word in `focusHistory` their
# backstory contains. A nudge, not an assignment: it can decide a near-tie and can never beat a
# survivor who has actually done the work, and `_drift_one` refuses to move anybody whose
# winning focus has no earned points behind it at all.
static func _history_focus(world: Variant, entity: int) -> String:
	var ident: Variant = world.components.get_component(entity, "identity")
	if not ident is Dictionary:
		return ""
	var story: String = String((ident as Dictionary).get("backstory", "")).to_lower()
	if story == "":
		return ""
	for row_v in _web().get("focusHistory", []) as Array:
		if not row_v is Dictionary:
			continue
		var word: String = String((row_v as Dictionary).get("word", ""))
		if word != "" and story.contains(word):
			return String((row_v as Dictionary).get("focus", ""))
	return ""


static func _drift_all(world: Variant, day: int) -> void:
	# `load` rather than a `preload` constant: jobs.gd already preloads half of sim/modules, and
	# a const preload back the other way is the cyclic-preload shape wounds.gd documents for
	# treatment.gd. needs.gd reaches wounds.gd and this file the same way, for the same reason.
	var JobsRes: GDScript = load("res://sim/modules/jobs.gd") as GDScript
	if JobsRes == null:
		return
	for ent_v in world.components.query(["skillWeb", "jobPriorities"]):
		var ent: int = int(ent_v)
		if ent == int(world.player):
			continue
		if world.components.has_component(ent, "controlled"):
			continue
		# `despawn` leaves components behind and `query` does not check alive (CLAUDE.md), so
		# without this the dead go on choosing careers.
		if world.components.has_component(ent, "corpse"):
			continue
		var web: Variant = world.components.get_component(ent, "skillWeb")
		if not web is Dictionary:
			continue
		if int((web as Dictionary).get("driftDay", 0)) == day:
			continue
		(web as Dictionary)["driftDay"] = day
		world.components.set_component(ent, "skillWeb", web)
		_drift_one(world, ent, JobsRes)


static func _drift_one(world: Variant, entity: int, JobsRes: GDScript) -> void:
	var jp: Variant = world.components.get_component(entity, "jobPriorities")
	if not jp is Dictionary:
		return
	var current: String = String((jp as Dictionary).get("focus", "Auto"))
	if current == "Manual":
		return
	# docs/07: "never touch anything you've manually locked". A focus the player set is a lock,
	# so provenance decides this and not the focus name -- a player who deliberately puts a
	# medic back on Auto has made a choice, and drift moving them off it again the next morning
	# would be the game arguing with them.
	if String((jp as Dictionary).get("focusSetBy", "auto")) == "player":
		return
	var s: Dictionary = suggest_focus(world, entity)
	var focus: String = String(s.get("focus", ""))
	if focus == "" or focus == current:
		return
	if int(s.get("work", 0)) < 1:
		return
	if int(s.get("lead", 0)) < DRIFT_LEAD:
		return
	JobsRes.call("set_focus", world, entity, focus, "auto")
