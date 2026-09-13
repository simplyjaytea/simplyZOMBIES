extends RefCounted
# The skill web's shape, as rules over its content -- where a node sits, which nodes a line joins,
# and what a well-laid web has to satisfy. Pure and static, the roof_look.gd pattern: every
# function takes the web definition it judges, so a gate can hand it a fabricated web without
# touching the sim's cached copy.
#
# Where a node sits is content. docs/08's content shape names `position` beside `cost`, and
# "re-laying-out the web is a data change with no code impact" -- so a node's place is read from
# `skill_web.json` and nothing here invents one. Positions are on the unit square with the hub
# at (0.5, 0.5) and y down; the panel is the one thing that turns them into pixels.
#
# Which nodes a line joins is *not* content, deliberately. The web has no prerequisite links
# (the shallow web, ADR 0012), and a drawn line that meant nothing to the sim would read as a
# rule that does not exist. So the lines are the focus paths -- the arrays `SimSkills._autospend`
# walks, in the order it walks them -- and a line between two nodes says "some focus buys one
# after the other". A node on no path at all (bought only by the surplus pass) is joined to the
# hub by a dotted line, computed here rather than named, so the day a path reaches it the dots
# become a line without anybody editing a list.

const HUB: Vector2 = Vector2(0.5, 0.5)
# The margin a position must keep from the unit square's edge, and the closest two may sit.
const EDGE_MARGIN: float = 0.05
const MIN_SPACING: float = 0.05
# Where a region's word is written: the direction of its nodes' centroid, pushed out past the
# rim. Two radii, because the panel is wider than it is tall around the square -- the header and
# the footer cap what is above and below it, while there is room to the sides -- and a word at
# one radius either crowds the rim node's name on the left and right or the header at the top.
const LABEL_RADIUS_UP: float = 0.5
const LABEL_RADIUS_SIDE: float = 0.58


# id -> Vector2 on the unit square. A node without a well-formed `position` is simply absent,
# and `problems` is what says so.
static func positions(def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for n in def.get("nodes", []) as Array:
		if not n is Dictionary:
			continue
		var nd: Dictionary = n as Dictionary
		var p: Variant = nd.get("position")
		if not p is Dictionary:
			continue
		var pd: Dictionary = p as Dictionary
		if not (pd.has("x") and pd.has("y")):
			continue
		if not ((pd["x"] is float or pd["x"] is int) and (pd["y"] is float or pd["y"] is int)):
			continue
		out[String(nd.get("id", ""))] = Vector2(float(pd["x"]), float(pd["y"]))
	return out


# Every consecutive pair of every focus path, as [a, b] with a and b in content order of the
# path, de-duplicated across paths (the Worker and the Scout both walk surv.haul first, and one
# line is enough). A path's first node has no predecessor here; it is a spoke.
static func edges(def: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	for focus in paths.keys():
		var path: Array = paths[focus] as Array
		for i in range(1, path.size()):
			var a: String = String(path[i - 1])
			var b: String = String(path[i])
			var key: String = a + "|" + b if a < b else b + "|" + a
			if seen.has(key) or a == b:
				continue
			seen[key] = true
			out.append([a, b])
	return out


# The first node of every focus path: where a survivor on that focus starts from the hub.
static func spokes(def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	for focus in paths.keys():
		var path: Array = paths[focus] as Array
		if path.is_empty():
			continue
		var head: String = String(path[0])
		if not out.has(head):
			out.append(head)
	return out


# Nodes on no focus path at all -- the ones only the surplus pass ever buys.
static func drift_only(def: Dictionary) -> Array[String]:
	var on_path: Dictionary = {}
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	for focus in paths.keys():
		for nid in paths[focus] as Array:
			on_path[String(nid)] = true
	var out: Array[String] = []
	for n in def.get("nodes", []) as Array:
		if not n is Dictionary:
			continue
		var nid: String = String((n as Dictionary).get("id", ""))
		if not on_path.has(nid):
			out.append(nid)
	return out


# Where a region's word goes: the direction of its nodes' centroid from the hub, out past the
# rim -- LABEL_RADIUS_UP for a region that sits above or below the hub, LABEL_RADIUS_SIDE for
# one beside it. The hub itself when the region has no placed node, which `problems` reports.
static func region_anchor(def: Dictionary, region: String) -> Vector2:
	var c: Vector2 = _centroid(def, region)
	if c == Vector2.INF:
		return HUB
	var dir: Vector2 = c - HUB
	if dir.length() < 0.0001:
		return HUB
	var n: Vector2 = dir.normalized()
	var radius: float = LABEL_RADIUS_UP if absf(n.y) > absf(n.x) else LABEL_RADIUS_SIDE
	return HUB + n * radius


# Every rule a well-laid web satisfies, as messages; empty when it does. The gate runs the
# shipped web through this and then five broken ones, so each rule is shown able to fail.
static func problems(def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var pos: Dictionary = positions(def)
	var by_id: Dictionary = {}
	var ids: Array[String] = []
	for n in def.get("nodes", []) as Array:
		if not n is Dictionary:
			out.append("a node is not an object")
			continue
		var nd: Dictionary = n as Dictionary
		var nid: String = String(nd.get("id", ""))
		by_id[nid] = nd
		ids.append(nid)
		if not pos.has(nid):
			out.append("%s has no position, so the screen has nowhere to draw it" % nid)
			continue
		var p: Vector2 = pos[nid]
		if p.x < EDGE_MARGIN or p.x > 1.0 - EDGE_MARGIN or p.y < EDGE_MARGIN or p.y > 1.0 - EDGE_MARGIN:
			out.append("%s sits at (%.2f, %.2f), outside the web's square" % [nid, p.x, p.y])
	if ids.is_empty():
		out.append("the web has no nodes")
		return out
	# No two on top of each other.
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if pos.has(ids[i]) and pos.has(ids[j]) and (pos[ids[i]] as Vector2).distance_to(pos[ids[j]]) < MIN_SPACING:
				out.append("%s and %s are drawn on top of each other" % [ids[i], ids[j]])
	# Cheap near the centre, dear toward the rim: within a region, every cheaper node is nearer
	# the hub than every dearer one (docs/08's rings).
	for nid in ids:
		if not pos.has(nid):
			continue
		var nd: Dictionary = by_id[nid]
		for other in ids:
			if other == nid or not pos.has(other):
				continue
			var od: Dictionary = by_id[other]
			if String(od.get("region", "")) != String(nd.get("region", "")):
				continue
			if int(od.get("cost", 1)) > int(nd.get("cost", 1)) and (pos[other] as Vector2).distance_to(HUB) <= (pos[nid] as Vector2).distance_to(HUB):
				out.append("%s costs more than %s but sits no further from the hub" % [other, nid])
	# Each region is one contiguous run round the hub: walking the placed nodes by angle, a
	# region that appears, gives way to another, and appears again is two sectors, and its word
	# would sit between them over somebody else's nodes.
	var by_angle: Array = []
	for nid in ids:
		if pos.has(nid):
			var d: Vector2 = (pos[nid] as Vector2) - HUB
			by_angle.append({"id": nid, "angle": atan2(d.y, d.x), "region": String((by_id[nid] as Dictionary).get("region", ""))})
	by_angle.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["angle"]) < float(b["angle"]))
	var runs: Dictionary = {}
	var last: String = ""
	for entry in by_angle:
		var r: String = String((entry as Dictionary)["region"])
		if r != last:
			runs[r] = int(runs.get(r, 0)) + 1
			last = r
	# The run that wraps past the -pi/pi seam is one run, not two.
	if by_angle.size() > 1 and String((by_angle[0] as Dictionary)["region"]) == String((by_angle[by_angle.size() - 1] as Dictionary)["region"]):
		var wrap: String = String((by_angle[0] as Dictionary)["region"])
		runs[wrap] = int(runs.get(wrap, 1)) - 1
	for r in runs.keys():
		if int(runs[r]) > 1:
			out.append("%s's nodes are split into %d sectors round the hub" % [String(r), int(runs[r])])
	# A region's word needs a direction to sit in.
	for r in def.get("regions", []) as Array:
		var c: Vector2 = _centroid(def, String(r))
		if c == Vector2.INF:
			out.append("%s has no placed node, so its word has nowhere to go" % String(r))
		elif c.distance_to(HUB) < EDGE_MARGIN:
			out.append("%s's nodes centre on the hub, so its word has no side to sit on" % String(r))
	# Every path names real nodes, and every node is on a line: an edge, a spoke, or the dotted
	# line for a node no path reaches.
	var covered: Dictionary = {}
	var paths: Dictionary = def.get("focusPaths", {}) as Dictionary
	for focus in paths.keys():
		for nid_v in paths[focus] as Array:
			if not by_id.has(String(nid_v)):
				out.append("the %s path names %s, which is not a node" % [String(focus), String(nid_v)])
	for e in edges(def):
		covered[String((e as Array)[0])] = true
		covered[String((e as Array)[1])] = true
	for s in spokes(def):
		covered[s] = true
	for d in drift_only(def):
		covered[d] = true
	for nid in ids:
		if not covered.has(nid):
			out.append("%s is on no line at all" % nid)
	return out


static func _centroid(def: Dictionary, region: String) -> Vector2:
	var pos: Dictionary = positions(def)
	var sum: Vector2 = Vector2.ZERO
	var count: int = 0
	for n in def.get("nodes", []) as Array:
		if not n is Dictionary:
			continue
		var nd: Dictionary = n as Dictionary
		if String(nd.get("region", "")) != region:
			continue
		var nid: String = String(nd.get("id", ""))
		if pos.has(nid):
			sum += pos[nid] as Vector2
			count += 1
	if count == 0:
		return Vector2.INF
	return sum / float(count)
