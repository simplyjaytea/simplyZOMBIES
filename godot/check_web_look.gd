extends SceneTree
# The skill web screen: the web drawn as a web, and what may and may not cross into it.
#
# Two things ship. `ui/web_layout.gd` is rules over the content -- where a node sits is a
# `position` in skill_web.json, and the lines are the focus paths `SimSkills._autospend` walks,
# so a drawn line is something the sim does. `ui/web_panel.gd` draws that layout with one
# survivor's standing laid over it from `SimSkills.web_map`, a read model of words and booleans
# and nothing a number could be rebuilt from -- the `web_view` argument (docs/30, "Who manages a
# survivor's skill web") applied to a second surface.
#
# Neither validator sees `content/colony/` -- `godot:validate` is shallow and the frozen oracle
# never reads the file -- so every assertion about a position lives here or nowhere. Five lanes,
# each with a true positive and a true negative, and a loud skip wherever a precondition cannot
# be built; a gate that cannot fail is worse than no gate:
#
#   PLACED  the shipped web satisfies every layout rule, and five deliberately broken copies of
#           it each fail the rule they break -- a missing position, one off the square, two on
#           top of each other, a dear node inside its region's cheap ring, two regions interleaved.
#   WOVEN   the lines are exactly the consecutive pairs of every focus path, computed here a
#           second way; the spokes are the path heads; the nodes on no path are found rather than
#           named; every node is on some line -- refused for an uncovered node, a path naming a
#           node that does not exist, and proven on a one-node path; and both `_autospend` and
#           the layout read `focusPaths`, by a needle scanner proved on a fabricated body first.
#   MAP     the read model's shape, pinned with a key allowlist at every level and a digit scan
#           over the whole of it; `lived` on an Auto twin who spent every point (earned, not
#           banked); agreement with `web_view`; `{}` for a body with no web; and the body of
#           `web_map` never mentions `position`.
#   SCREEN  the panel, instantiated: its click targets are exactly the learnable nodes and sit
#           inside it without overlapping; every word it writes is prose with no digit and no raw
#           key; a click pushes `web.buy` and the sim learns the node; the Auto twin gets no
#           targets and a refusal; and the input path is read textually for the command it pushes.
#   WIRED   main.gd loads the panel, binds K, peels it on Esc before the bench, re-pulls it each
#           frame with the selected colonist, the panel really has the methods main.gd calls by
#           name (the has_method trap), and the legend says what K does in digit-free prose.

const SimBoot = preload("res://sim/boot.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimRecruits = preload("res://sim/modules/recruits.gd")
const WebLayout = preload("res://ui/web_layout.gd")

const WEB_PATH: String = "res://content/colony/skill_web.json"
const MAIN_GD: String = "res://presentation/main.gd"
const PANEL_GD: String = "res://ui/web_panel.gd"
const LAYOUT_GD: String = "res://ui/web_layout.gd"
const SKILLS_GD: String = "res://sim/modules/skills.gd"
const LEGEND_GD: String = "res://ui/legend.gd"
const PANEL_SIZE: Vector2 = Vector2(1040, 760)
const BUDGET_SECONDS: float = 60.0

const MAP_KEYS: Array[String] = ["who", "manual", "regions", "nodes"]
const REGION_KEYS: Array[String] = ["region", "lived"]
const NODE_KEYS: Array[String] = ["node", "name", "region", "state"]
const STATES: Array[String] = ["known", "learnable", "unknown"]

var _stash: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var ok: bool = true
	ok = _placed_lane() and ok
	ok = _woven_lane() and ok
	var boot: Dictionary = SimBoot.playable(20260829, 64)
	var w: Variant = boot["world"]
	ok = _map_lane(w) and ok
	ok = await _screen_lane(w) and ok
	ok = _wired_lane() and ok
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	if seconds > BUDGET_SECONDS:
		push_error("check_web_look ran %.1f s against a %.0f s budget" % [seconds, BUDGET_SECONDS])
		ok = false
	if ok:
		print(
			"WEB_LOOK_OK %d nodes placed and every layout rule shown to refuse; %d lines, %d spokes, %d dotted; the map carries words and booleans only; %d click targets on the screen and one buy landed; K, esc and the per-frame pull wired; %.1f s of a %.0f s budget"
			% [
				int(_stash.get("placed", 0)), int(_stash.get("edges", 0)), int(_stash.get("spokes", 0)),
				int(_stash.get("drift", 0)), int(_stash.get("hits", 0)), seconds, BUDGET_SECONDS,
			]
		)
		quit(0)
	else:
		push_error("WEB_LOOK_FAIL")
		quit(1)


# --- helpers -----------------------------------------------------------------------------------


func _shipped() -> Dictionary:
	var f: FileAccess = FileAccess.open(WEB_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _node_of(def: Dictionary, nid: String) -> Dictionary:
	for n in def.get("nodes", []) as Array:
		if n is Dictionary and String((n as Dictionary).get("id", "")) == nid:
			return n as Dictionary
	return {}


func _spawn_colonist(w: Variant, dx: float) -> int:
	var rng: Variant = w.rng.stream("recruit")
	var pos: Variant = w.components.get_component(w.player, "position")
	var px: float = float((pos as Dictionary).get("x", 5.0)) if pos is Dictionary else 5.0
	var py: float = float((pos as Dictionary).get("y", 5.0)) if pos is Dictionary else 5.0
	return int(SimRecruits.spawn_generated(w, SimRecruits.roll(w, rng), px + dx, py))


# Everything published, as an Array of records -- a reference type, because a lambda capturing
# an int mutates its own copy (CLAUDE.md).
func _collect(w: Variant, type: String) -> Array:
	var seen: Array = []
	w.events.subscribe({"id": "web_look.probe." + type, "type": type, "handler": func(e: Dictionary) -> void:
		seen.append(e.duplicate(true))
	})
	return seen


# The body of one function in one file, whether or not it is static, so a textual assertion is
# made against the function it names and not against a comment elsewhere in the file.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out += line + "\n"
	return out


func _missing_needle(body: String, needles: Array) -> String:
	for n in needles:
		if not body.contains(String(n)):
			return String(n)
	return ""


func _digit_scanner() -> RegEx:
	var digits: RegEx = RegEx.new()
	digits.compile("[0-9]")
	if digits.search("no digits here") != null or digits.search("one 1") == null:
		return null
	return digits


# --- 1. PLACED ---------------------------------------------------------------------------------


func _placed_lane() -> bool:
	var def: Dictionary = _shipped()
	if def.is_empty() or (def.get("nodes", []) as Array).is_empty():
		push_error("PLACED: %s has no nodes, so no layout was judged" % WEB_PATH)
		return false
	var faults: Array[String] = WebLayout.problems(def)
	if not faults.is_empty():
		push_error("PLACED: the shipped web is not well laid: %s" % str(faults))
		return false
	var pos: Dictionary = WebLayout.positions(def)
	if pos.size() != (def.get("nodes", []) as Array).size():
		push_error("PLACED: %d nodes but %d positions" % [(def.get("nodes", []) as Array).size(), pos.size()])
		return false
	# Every rule, shown to refuse. Each copy breaks one thing and must be refused for that thing.
	var breaks: Array = [
		["a node with no position", func(d: Dictionary) -> void: (_node_of(d, "melee.grip")).erase("position"), "has no position"],
		["a node off the square", func(d: Dictionary) -> void: (_node_of(d, "melee.grip"))["position"] = {"x": 1.2, "y": 0.5}, "outside the web's square"],
		["two nodes on top of each other", func(d: Dictionary) -> void: (_node_of(d, "melee.tempo"))["position"] = {"x": 0.71, "y": 0.57}, "on top of each other"],
		["a dear node inside the cheap ring", func(d: Dictionary) -> void: (_node_of(d, "craft.scrap"))["position"] = {"x": 0.36, "y": 0.58}, "sits no further from the hub"],
		["two regions interleaved", func(d: Dictionary) -> void:
			var a: Dictionary = _node_of(d, "melee.grip")
			var b: Dictionary = _node_of(d, "ranged.breath")
			var pa: Variant = a["position"]
			a["position"] = b["position"]
			b["position"] = pa, "split into"],
	]
	for br in breaks:
		var broken: Dictionary = def.duplicate(true)
		(br[1] as Callable).call(broken)
		var found: Array[String] = WebLayout.problems(broken)
		var hit: bool = false
		for msg in found:
			if msg.contains(String(br[2])):
				hit = true
		if not hit:
			push_error("PLACED: %s was not refused for it (got %s)" % [String(br[0]), str(found)])
			return false
	_stash["placed"] = pos.size()
	print("PLACED OK %d nodes on the square, cheap inside dear, one sector a region; 5 broken copies each refused for their fault" % pos.size())
	return true


# --- 2. WOVEN ----------------------------------------------------------------------------------


func _woven_lane() -> bool:
	var proof: String = _missing_needle("no keywords appear anywhere in this line", ["TOTALLY_ABSENT_TOKEN"])
	if proof.is_empty():
		push_error("WOVEN: the needle scanner found nothing missing in a body missing everything; it cannot say no")
		return false
	var def: Dictionary = _shipped()
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	if paths.is_empty():
		push_error("WOVEN: the shipped web has no focus paths, so no line was judged")
		return false
	# The pairs, computed a second way: every adjacent pair in every path, as a set of keys.
	var want: Dictionary = {}
	var heads: Dictionary = {}
	var on_path: Dictionary = {}
	for focus in paths.keys():
		var path: Array = paths[focus] as Array
		if not path.is_empty():
			heads[String(path[0])] = true
		for i in path.size():
			on_path[String(path[i])] = true
			if i > 0:
				var a: String = String(path[i - 1])
				var b: String = String(path[i])
				want[a + "|" + b if a < b else b + "|" + a] = true
	var got: Dictionary = {}
	for e in WebLayout.edges(def):
		var a: String = String((e as Array)[0])
		var b: String = String((e as Array)[1])
		got[a + "|" + b if a < b else b + "|" + a] = true
	if got.keys().size() != want.keys().size() or got.keys().size() != WebLayout.edges(def).size():
		push_error("WOVEN: the layout draws %d lines (%d distinct) where the paths have %d pairs" % [WebLayout.edges(def).size(), got.keys().size(), want.keys().size()])
		return false
	for k in want.keys():
		if not got.has(k):
			push_error("WOVEN: the path pair %s is not drawn" % String(k))
			return false
	var spokes: Array[String] = WebLayout.spokes(def)
	if spokes.size() != heads.keys().size():
		push_error("WOVEN: %d spokes for %d path heads" % [spokes.size(), heads.keys().size()])
		return false
	for h in heads.keys():
		if not spokes.has(String(h)):
			push_error("WOVEN: the path head %s has no spoke" % String(h))
			return false
	var drift: Array[String] = WebLayout.drift_only(def)
	for d in drift:
		if on_path.has(d):
			push_error("WOVEN: %s is on a path and was called drift-only" % d)
			return false
	for n in def.get("nodes", []) as Array:
		var nid: String = String((n as Dictionary).get("id", ""))
		if not on_path.has(nid) and not drift.has(nid):
			push_error("WOVEN: %s is on no path and was not found by drift_only" % nid)
			return false
	if drift.is_empty():
		print("WOVEN: the shipped web has no node off every path, so the dotted rule is judged on the fixture below only")
	# The negatives, on a fixture: a node on no path that the dotted rule is told to ignore is
	# uncovered; a path naming a node that is not there is refused; a one-node path is a spoke and
	# nothing else, and its node still counts as covered.
	var fixture: Dictionary = {
		"regions": ["A", "B"],
		"nodes": [
			{"id": "a.one", "name": "one", "region": "A", "cost": 1, "position": {"x": 0.7, "y": 0.5}},
			{"id": "a.two", "name": "two", "region": "A", "cost": 2, "position": {"x": 0.9, "y": 0.5}},
			{"id": "b.one", "name": "three", "region": "B", "cost": 1, "position": {"x": 0.3, "y": 0.5}},
			{"id": "b.lone", "name": "four", "region": "B", "cost": 2, "position": {"x": 0.1, "y": 0.5}},
		],
		"focusPaths": {"Fighter": ["a.one", "a.two"], "Worker": ["b.one"]},
	}
	var fx_edges: Array = WebLayout.edges(fixture)
	if fx_edges.size() != 1 or String((fx_edges[0] as Array)[0]) != "a.one":
		push_error("WOVEN: the fixture's one pair drew as %s" % str(fx_edges))
		return false
	var fx_spokes: Array[String] = WebLayout.spokes(fixture)
	if fx_spokes.size() != 2 or not fx_spokes.has("b.one"):
		push_error("WOVEN: a one-node path did not become a spoke: %s" % str(fx_spokes))
		return false
	var fx_drift: Array[String] = WebLayout.drift_only(fixture)
	if fx_drift != (["b.lone"] as Array[String]):
		push_error("WOVEN: drift_only found %s on a fixture whose only stray is b.lone" % str(fx_drift))
		return false
	if not WebLayout.problems(fixture).is_empty():
		push_error("WOVEN: the fixture is not well laid, so its negatives judge nothing: %s" % str(WebLayout.problems(fixture)))
		return false
	# The dotted rule is what covers b.lone: with the stray node on no path and drift_only
	# refusing to name it (a path that names it and then loses it), coverage must be lost.
	var uncovered: Dictionary = fixture.duplicate(true)
	(uncovered["focusPaths"] as Dictionary)["Scout"] = ["b.lone", "no.such.node"]
	var faults: Array[String] = WebLayout.problems(uncovered)
	var named_missing: bool = false
	for msg in faults:
		if msg.contains("no.such.node"):
			named_missing = true
	if not named_missing:
		push_error("WOVEN: a path naming a node that does not exist was not refused: %s" % str(faults))
		return false
	var stranded: Dictionary = fixture.duplicate(true)
	(stranded["nodes"] as Array).append({"id": "c.stray", "name": "five", "region": "A", "cost": 2, "position": {"x": 0.8, "y": 0.8}})
	if WebLayout.drift_only(stranded) != (["b.lone", "c.stray"] as Array[String]):
		push_error("WOVEN: a second stray node was not found: %s" % str(WebLayout.drift_only(stranded)))
		return false
	# Textual: both readers of the paths reach the same key, so a rename in the content that
	# moved the sim's walk would move the drawn lines with it, or red this lane.
	var walk: String = _function_body(SKILLS_GD, "_autospend")
	var draw: String = _function_body(LAYOUT_GD, "edges")
	if walk.is_empty() or draw.is_empty():
		push_error("WOVEN: could not read _autospend or edges, so the shared key was not judged")
		return false
	if not _missing_needle(walk, ["focusPaths"]).is_empty() or not _missing_needle(draw, ["focusPaths"]).is_empty():
		push_error("WOVEN: _autospend and WebLayout.edges do not both read focusPaths")
		return false
	_stash["edges"] = got.keys().size()
	_stash["spokes"] = spokes.size()
	_stash["drift"] = drift.size()
	print("WOVEN OK %d lines are the paths' %d pairs, %d spokes, %s dotted; the fixture's stray, missing node and one-node path each judged" % [got.keys().size(), want.keys().size(), spokes.size(), str(drift)])
	return true


# --- 3. MAP ------------------------------------------------------------------------------------


func _map_shape_faults(map: Dictionary) -> Array[String]:
	var faults: Array[String] = []
	if map.keys().size() != MAP_KEYS.size():
		faults.append("the map carries %s" % str(map.keys()))
	for k in MAP_KEYS:
		if not map.has(k):
			faults.append("the map lacks %s" % k)
	if not (map.get("who", "") is String):
		faults.append("who is not a word")
	if not (map.get("manual", false) is bool):
		faults.append("manual is not a boolean")
	for r in map.get("regions", []) as Array:
		var rd: Dictionary = r as Dictionary
		if rd.keys().size() != REGION_KEYS.size() or not rd.has("region") or not rd.has("lived"):
			faults.append("a region entry carries %s" % str(rd.keys()))
		elif not (rd["region"] is String) or not (rd["lived"] is bool):
			faults.append("a region entry is not a word and a boolean")
	for n in map.get("nodes", []) as Array:
		var nd: Dictionary = n as Dictionary
		if nd.keys().size() != NODE_KEYS.size():
			faults.append("a node entry carries %s -- one added numeric field and a cost is back on screen" % str(nd.keys()))
			continue
		for k in NODE_KEYS:
			if not nd.has(k) or not (nd[k] is String):
				faults.append("node.%s is missing or not a word" % k)
		if not STATES.has(String(nd.get("state", ""))):
			faults.append("a node is in state %s, which the screen has no colour for" % String(nd.get("state", "")))
	var digits: RegEx = _digit_scanner()
	if digits == null:
		faults.append("the digit scanner does not work, so its verdict means nothing")
	elif digits.search(JSON.stringify(map)) != null:
		faults.append("a digit crossed the boundary: %s" % JSON.stringify(map))
	return faults


func _map_lane(w: Variant) -> bool:
	var manual: int = _spawn_colonist(w, 9.0)
	var auto: int = _spawn_colonist(w, 10.0)
	if manual < 0 or auto < 0:
		push_error("MAP: could not generate colonists, so no map was judged")
		return false
	w.commands.push({"type": "job.focus", "entity": manual, "focus": "Manual"})
	w.step()
	SimSkills._earn(w, manual, "Medicine", 3)
	SimSkills._earn(w, auto, "Medicine", 3)
	var map: Dictionary = SimSkills.web_map(w, manual)
	var faults: Array[String] = _map_shape_faults(map)
	if not faults.is_empty():
		push_error("MAP: %s" % str(faults))
		return false
	# The predicate can fail: a cost on a node, a fourth state, a digit in a name.
	var broken: Dictionary = map.duplicate(true)
	((broken["nodes"] as Array)[0] as Dictionary)["cost"] = 2
	var broken_state: Dictionary = map.duplicate(true)
	((broken_state["nodes"] as Array)[0] as Dictionary)["state"] = "owned"
	var broken_digit: Dictionary = map.duplicate(true)
	((broken_digit["nodes"] as Array)[0] as Dictionary)["name"] = "a surer grip 2"
	if _map_shape_faults(broken).is_empty() or _map_shape_faults(broken_state).is_empty() or _map_shape_faults(broken_digit).is_empty():
		push_error("MAP: the shape predicate passed a cost, a fourth state or a digit, so it cannot fail")
		return false
	var shipped: Dictionary = _shipped()
	var nodes: Array = map.get("nodes", []) as Array
	if nodes.size() != (shipped.get("nodes", []) as Array).size():
		push_error("MAP: %d node entries for %d content nodes" % [nodes.size(), (shipped.get("nodes", []) as Array).size()])
		return false
	var seen: Dictionary = {}
	for n in nodes:
		var nid: String = String((n as Dictionary).get("node", ""))
		if seen.has(nid) or _node_of(shipped, nid).is_empty():
			push_error("MAP: node %s is repeated or is not content" % nid)
			return false
		seen[nid] = true
	if not bool(map.get("manual", false)):
		push_error("MAP: a Manual survivor reads manual false")
		return false
	if String(map.get("who", "")).is_empty():
		push_error("MAP: the survivor has no name on the map")
		return false
	# Agreement with the prose line: the same nodes are known and learnable on both.
	var view: Dictionary = SimSkills.web_view(w, manual)
	var learnable_view: Array = []
	for it in view.get("learnable", []) as Array:
		learnable_view.append(String((it as Dictionary).get("node", "")))
	var learnable_map: Array = []
	var known_map: Array = []
	for n in nodes:
		match String((n as Dictionary).get("state", "")):
			"learnable":
				learnable_map.append(String((n as Dictionary).get("node", "")))
			"known":
				known_map.append(String((n as Dictionary).get("name", "")))
	if learnable_map.is_empty():
		push_error("MAP: a Manual survivor with 3 Medicine could learn nothing, so agreement was not judged")
		return false
	if learnable_map != learnable_view or known_map != (view.get("known", []) as Array):
		push_error("MAP: the map and the prose line disagree: %s / %s vs %s / %s" % [str(learnable_map), str(known_map), str(learnable_view), str(view.get("known", []))])
		return false
	# History: Medicine lived, Craft not, on the survivor who banked the points --
	var lived: Dictionary = {}
	for r in map.get("regions", []) as Array:
		lived[String((r as Dictionary).get("region", ""))] = bool((r as Dictionary).get("lived", false))
	if lived.keys().size() != SimSkills.REGIONS.size():
		push_error("MAP: %d regions on the map for %d in the web" % [lived.keys().size(), SimSkills.REGIONS.size()])
		return false
	if not bool(lived.get("Medicine", false)) or bool(lived.get("Craft", true)):
		push_error("MAP: 3 Medicine and nothing else reads Medicine %s, Craft %s" % [str(lived.get("Medicine")), str(lived.get("Craft"))])
		return false
	# -- and on the Auto twin, who spent every one of them. `lived` from the banked points would
	# pass on the Manual survivor and fail here; this is the assertion that it reads earned.
	if SimSkills.points(w, auto, "Medicine") != 0:
		push_error("MAP: the Auto twin still banks %d Medicine, so 'lived after spending' was not judged" % SimSkills.points(w, auto, "Medicine"))
		return false
	var theirs: Dictionary = SimSkills.web_map(w, auto)
	if not _map_shape_faults(theirs).is_empty():
		push_error("MAP: the Auto twin's map: %s" % str(_map_shape_faults(theirs)))
		return false
	var theirs_lived: bool = false
	var theirs_known: int = 0
	var theirs_learnable: int = 0
	for r in theirs.get("regions", []) as Array:
		if String((r as Dictionary).get("region", "")) == "Medicine":
			theirs_lived = bool((r as Dictionary).get("lived", false))
	for n in theirs.get("nodes", []) as Array:
		match String((n as Dictionary).get("state", "")):
			"known": theirs_known += 1
			"learnable": theirs_learnable += 1
	if not theirs_lived:
		push_error("MAP: the Auto twin spent 3 Medicine on nodes and Medicine reads unlived -- lived is reading banked points, not earned")
		return false
	if bool(theirs.get("manual", true)) or theirs_learnable != 0 or theirs_known == 0:
		push_error("MAP: the Auto twin reads manual %s, %d learnable, %d known" % [str(theirs.get("manual")), theirs_learnable, theirs_known])
		return false
	# A body with no web at all is an empty map, not a map of nothing.
	var probe: int = w.entities.spawn()
	w.components.set_component(probe, "position", {"x": 1.0, "y": 1.0})
	if not SimSkills.web_map(w, probe).is_empty():
		push_error("MAP: a body with no skillWeb produced %s" % str(SimSkills.web_map(w, probe)))
		return false
	# Textual: layout never crosses through the read model.
	var body: String = _function_body(SKILLS_GD, "web_map")
	if body.is_empty():
		push_error("MAP: could not read web_map out of %s" % SKILLS_GD)
		return false
	if body.contains("position"):
		push_error("MAP: web_map mentions position -- layout has crossed into the survivor's read model")
		return false
	print("MAP OK %d nodes, %d regions, words and booleans only; Medicine lived and Craft not; the Auto twin lived Medicine with nothing banked; the prose line agrees" % [nodes.size(), lived.keys().size()])
	return true


# --- 4. SCREEN ---------------------------------------------------------------------------------


func _screen_lane(w: Variant) -> bool:
	var manual: int = _spawn_colonist(w, 11.0)
	var auto: int = _spawn_colonist(w, 12.0)
	if manual < 0 or auto < 0:
		push_error("SCREEN: could not generate colonists, so no screen was judged")
		return false
	w.commands.push({"type": "job.focus", "entity": manual, "focus": "Manual"})
	w.step()
	SimSkills._earn(w, manual, "Medicine", 3)
	SimSkills._earn(w, manual, "Survival", 1)
	SimSkills._earn(w, auto, "Medicine", 1)
	var panel: Control = (load(PANEL_GD) as GDScript).new() as Control
	panel.size = PANEL_SIZE
	root.add_child(panel)
	await process_frame
	panel.call("set_world", w, manual)
	var hits: Array = panel.call("layout_hits")
	var view: Dictionary = SimSkills.web_view(w, manual)
	var want: Array = []
	for it in view.get("learnable", []) as Array:
		want.append(String((it as Dictionary).get("node", "")))
	if want.is_empty():
		push_error("SCREEN: the Manual survivor could learn nothing, so no click target was judged")
		panel.queue_free()
		return false
	var got: Array = []
	var panel_rect := Rect2(Vector2.ZERO, PANEL_SIZE)
	for h in hits:
		var hd: Dictionary = h as Dictionary
		got.append(String(hd.get("node", "")))
		var r: Rect2 = hd.get("rect", Rect2()) as Rect2
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			push_error("SCREEN: %s has an empty click target" % String(hd.get("node", "")))
			panel.queue_free()
			return false
		if not panel_rect.encloses(r):
			push_error("SCREEN: %s's target %s is outside the panel" % [String(hd.get("node", "")), str(r)])
			panel.queue_free()
			return false
	got.sort()
	want.sort()
	if got != want:
		push_error("SCREEN: the click targets are %s where the learnable nodes are %s" % [str(got), str(want)])
		panel.queue_free()
		return false
	for i in hits.size():
		for j in range(i + 1, hits.size()):
			if ((hits[i] as Dictionary)["rect"] as Rect2).intersects((hits[j] as Dictionary)["rect"] as Rect2):
				push_error("SCREEN: the targets for %s and %s overlap" % [String((hits[i] as Dictionary)["node"]), String((hits[j] as Dictionary)["node"])])
				panel.queue_free()
				return false
	# Every word on the screen is prose: no digit, no node id, no snake_case key.
	var words: Array = panel.call("words")
	var faults: Array[String] = _word_faults(words)
	if not faults.is_empty():
		push_error("SCREEN: %s" % str(faults))
		panel.queue_free()
		return false
	if _word_faults(["melee.grip"]).is_empty() or _word_faults(["cost 2"]).is_empty() or _word_faults(["melee_damage"]).is_empty():
		push_error("SCREEN: the word scanner passed a raw key, a digit or a stat name, so it cannot fail")
		panel.queue_free()
		return false
	var shipped: Dictionary = _shipped()
	var joined: String = "\n".join(PackedStringArray(words))
	for n in shipped.get("nodes", []) as Array:
		if not joined.contains(String((n as Dictionary).get("name", ""))):
			push_error("SCREEN: the screen never writes %s" % String((n as Dictionary).get("name", "")))
			panel.queue_free()
			return false
	var ident: Variant = w.components.get_component(manual, "identity")
	var who: String = String((ident as Dictionary).get("name", "")) if ident is Dictionary else ""
	if who.is_empty() or not String(panel.call("header_label")).contains(who):
		push_error("SCREEN: the header does not name the survivor (%s): %s" % [who, String(panel.call("header_label"))])
		panel.queue_free()
		return false
	if not String(panel.call("footer")).contains("amber"):
		push_error("SCREEN: the Manual footer does not say what amber means: %s" % String(panel.call("footer")))
		panel.queue_free()
		return false
	# The dead socket: a click pushes web.buy, and the sim learns the node.
	var learned: Array = _collect(w, "web.learned")
	var refused: Array = _collect(w, "web.refused")
	var target: String = String(want[0])
	panel.call("_act", target)
	w.step()
	if learned.size() != 1 or String((learned[0] as Dictionary).get("node", "")) != target or not SimSkills.has_node(w, manual, target):
		push_error("SCREEN: clicking %s learned %s" % [target, str(learned)])
		panel.queue_free()
		return false
	panel.call("set_world", w, manual)
	var after: Array = panel.call("layout_hits")
	for h in after:
		if String((h as Dictionary).get("node", "")) == target:
			push_error("SCREEN: %s is still a click target after it was learned" % target)
			panel.queue_free()
			return false
	# The Auto twin: nothing to click, a footer that says why, and a refusal if clicked anyway.
	panel.call("set_world", w, auto)
	if not (panel.call("layout_hits") as Array).is_empty():
		push_error("SCREEN: an Auto survivor has click targets: %s" % str(panel.call("layout_hits")))
		panel.queue_free()
		return false
	var footer: String = String(panel.call("footer"))
	if not footer.contains("manual") or footer.contains("amber"):
		push_error("SCREEN: the Auto footer reads: %s" % footer)
		panel.queue_free()
		return false
	var before: int = learned.size()
	panel.call("_act", "med.triage")
	w.step()
	if learned.size() != before or refused.is_empty() or String((refused[refused.size() - 1] as Dictionary).get("reason", "")) != "auto":
		push_error("SCREEN: buying for an Auto survivor was not refused as auto: %s" % str(refused))
		panel.queue_free()
		return false
	# The header names you when the screen is yours, and the map is what set_world pulled.
	panel.call("set_world", w, int(w.player))
	if not String(panel.call("header_label")).contains("you"):
		push_error("SCREEN: your own web is headed %s" % String(panel.call("header_label")))
		panel.queue_free()
		return false
	panel.queue_free()
	# Textual: the input path pushes the command, and _ready loads nothing.
	var input_body: String = _function_body(PANEL_GD, "_gui_input")
	var act_body: String = _function_body(PANEL_GD, "_act")
	var ready_body: String = _function_body(PANEL_GD, "_ready")
	if input_body.is_empty() or act_body.is_empty() or ready_body.is_empty():
		push_error("SCREEN: could not read _gui_input, _act or _ready out of %s" % PANEL_GD)
		return false
	if not _missing_needle(input_body, ["_act(", "accept_event()"]).is_empty():
		push_error("SCREEN: _gui_input does not route a click to _act and swallow it")
		return false
	if not _missing_needle(act_body, ["\"web.buy\"", "commands.push"]).is_empty():
		push_error("SCREEN: _act does not push web.buy through the queue")
		return false
	if not _missing_needle(ready_body, ["MOUSE_FILTER_STOP"]).is_empty() or ready_body.contains("load(") or ready_body.contains("FileAccess") or ready_body.contains("SimSkills."):
		push_error("SCREEN: _ready does not stop the mouse, or does work the hidden panel should not")
		return false
	_stash["hits"] = hits.size()
	print("SCREEN OK %d click targets are the %d learnable nodes, inside the panel, not overlapping; %d words all prose; %s bought by a click; the Auto twin offered none and was refused" % [hits.size(), want.size(), words.size(), target])
	return true


func _word_faults(words: Array) -> Array[String]:
	var faults: Array[String] = []
	var digits: RegEx = _digit_scanner()
	if digits == null:
		faults.append("the digit scanner does not work")
		return faults
	var key: RegEx = RegEx.new()
	key.compile("[a-z]+[._][a-z]+")
	for wd in words:
		var s: String = String(wd)
		if digits.search(s) != null:
			faults.append("a digit on the screen: \"%s\"" % s)
		if key.search(s) != null:
			faults.append("a raw key on the screen: \"%s\"" % s)
	return faults


# --- 5. WIRED ----------------------------------------------------------------------------------


func _wired_lane() -> bool:
	var proof: String = _missing_needle("", ["anything"])
	if proof.is_empty():
		push_error("WIRED: the needle scanner cannot say no")
		return false
	var ensure: String = _function_body(MAIN_GD, "_ensure_ui")
	var input: String = _function_body(MAIN_GD, "_input")
	var hud: String = _function_body(MAIN_GD, "_update_hud")
	var opener: String = _function_body(MAIN_GD, "_set_web_open")
	for pair in [["_ensure_ui", ensure], ["_input", input], ["_update_hud", hud], ["_set_web_open", opener]]:
		if String(pair[1]).is_empty():
			push_error("WIRED: could not read %s out of %s" % [String(pair[0]), MAIN_GD])
			return false
	var m: String = _missing_needle(ensure, ["res://ui/web_panel.gd", "_web_panel"])
	if not m.is_empty():
		push_error("WIRED: _ensure_ui does not contain %s" % m)
		return false
	m = _missing_needle(input, ["KEY_K:", "_set_web_open("])
	if not m.is_empty():
		push_error("WIRED: _input does not contain %s -- nothing opens the web" % m)
		return false
	# The Esc arm alone, so the order is judged inside it and not against a mention elsewhere.
	var esc_from: int = input.find("KEY_ESCAPE:")
	var esc_to: int = input.find("KEY_TAB:")
	if esc_from < 0 or esc_to < 0 or esc_to <= esc_from:
		push_error("WIRED: could not isolate the KEY_ESCAPE arm in _input")
		return false
	var esc: String = input.substr(esc_from, esc_to - esc_from)
	var web_at: int = esc.find("_web_panel")
	var bench_at: int = esc.find("_bench_panel")
	if web_at < 0 or bench_at < 0:
		push_error("WIRED: the Esc arm does not peel both the web and the bench")
		return false
	if web_at > bench_at:
		push_error("WIRED: Esc peels the bench before the web; the thing most recently opened closes first")
		return false
	# The order predicate can fail: the same test on the arm with the two swapped.
	var swapped: String = esc.replace("_web_panel", "@@").replace("_bench_panel", "_web_panel").replace("@@", "_bench_panel")
	if swapped.find("_web_panel") <= swapped.find("_bench_panel"):
		push_error("WIRED: the order predicate passed the reversed arm, so it cannot fail")
		return false
	m = _missing_needle(hud, ["_web_panel.call(\"set_world\", world, who)"])
	if not m.is_empty():
		push_error("WIRED: _update_hud does not re-pull the web each frame with the selected colonist")
		return false
	m = _missing_needle(opener, ["_who()", "set_world"])
	if not m.is_empty():
		push_error("WIRED: _set_web_open does not pull the selected colonist's web on open (%s)" % m)
		return false
	# The has_method trap: the methods main.gd names must exist by those exact names.
	var panel_src: String = FileAccess.get_file_as_string(PANEL_GD)
	for fn in ["set_world", "layout_hits", "words", "footer", "header_label", "map"]:
		if panel_src.find("\nfunc %s(" % fn) < 0:
			push_error("WIRED: web_panel.gd has no `func %s(` -- a has_method guard naming it would be silently false" % fn)
			return false
	# The legend: the K row, inside the GROUPS block, in digit-free prose that says "web".
	var legend: String = FileAccess.get_file_as_string(LEGEND_GD)
	var g_from: int = legend.find("const GROUPS")
	if g_from < 0:
		push_error("WIRED: could not find the GROUPS block in %s" % LEGEND_GD)
		return false
	var block: String = legend.substr(g_from)
	var g_to: int = block.find("\n]")
	if g_to > 0:
		block = block.substr(0, g_to)
	var k_line: String = ""
	for line in block.split("\n"):
		if line.contains("[\"K\","):
			k_line = line
	if k_line.is_empty():
		push_error("WIRED: the legend has no K row")
		return false
	var row_text: String = k_line.substr(k_line.find("[\"K\",") + 5)
	var digits: RegEx = _digit_scanner()
	if digits == null or not row_text.contains("web") or digits.search(row_text) != null:
		push_error("WIRED: the legend's K row does not say web, or carries a digit: %s" % row_text)
		return false
	if block.replace(k_line, "").contains("[\"K\","):
		push_error("WIRED: the legend binds K twice")
		return false
	print("WIRED OK main.gd loads the panel, binds K, peels it on Esc before the bench, re-pulls it each frame; the six methods it names exist; the legend's K row is prose")
	return true
