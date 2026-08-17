extends SceneTree
# HANDOFF.md's own bookkeeping. Port of test/unit/handoff.test.ts, which leaves with the
# TypeScript oracle -- the same situation paperdoll.test.ts was in before it became
# check_ban_health_bar.gd.
#
# The backlog groups every task under a `**Done (n):**` / `**In progress (n):**` /
# `**Open (n):**` header. Those headers are a second copy of a fact, and a second copy
# nothing checks is a copy waiting to disagree. It disagreed within one session of being
# written, and has drifted repeatedly since.
#
# The ported assertions catch *arithmetic* drift. They do not catch the worse kind, which
# this file also now guards against: a document that adds up perfectly and is simply false
# about the code. Four sections were found listing gated, working features as open -- every
# one of them passing the old test, because they were correctly *counted* as open and merely
# wrong about reality.
#
# Nothing cheap verifies truth. What is cheap is making the claim falsifiable, so
# _every_done_box_cites_its_evidence requires a ticked box to say what proves it. That is
# the convention the audit relied on to be possible at all.

const HEADER := "^\\*\\*(Done|In progress|Open) \\((\\d+)\\):\\*\\*$"
const ITEM := "^- \\[([x~ ])\\]"
const HEADING := "^#{1,6}\\s"
# A continuation line under an item: indented prose, italic evidence, or a nested bullet.
const EVIDENCE := "^\\s+\\*\\(.*"

var _lines: PackedStringArray = PackedStringArray()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _load():
		push_error("HANDOFF_FAIL could not read HANDOFF.md")
		quit(1)
		return
	var ok: bool = true
	ok = _there_are_groups_to_check() and ok
	ok = _group_counts_match_their_contents() and ok
	ok = _no_checkbox_is_misfiled() and ok
	ok = _milestone_rows_sum_to_total() and ok
	ok = _summary_table_matches_the_file() and ok
	ok = _every_done_box_cites_its_evidence() and ok
	if ok:
		print("HANDOFF_OK counts, filing, totals, evidence")
		quit(0)
	else:
		push_error("HANDOFF_FAIL")
		quit(1)

# res:// is the godot/ folder; HANDOFF.md is its parent's. globalize_path is the only way
# up, since Godot cannot open a res:// path above the project root.
func _load() -> bool:
	var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var path: String = root.get_base_dir().path_join("HANDOFF.md")
	if not FileAccess.file_exists(path):
		push_error("no HANDOFF.md at %s" % path)
		return false
	_lines = FileAccess.get_file_as_string(path).split("\n")
	return true

# Every group header with the checkbox marks belonging to it. A group owns every checkbox
# until the next group header or the next heading, whichever comes first -- the heading
# boundary matters because "Beyond the slice" lists tasks under no group header at all, and
# without it they would count into the previous section's last group.
func _groups() -> Array:
	var out: Array = []
	var header := RegEx.new(); header.compile(HEADER)
	var item := RegEx.new(); item.compile(ITEM)
	var heading := RegEx.new(); heading.compile(HEADING)
	var current: Dictionary = {}
	for i in _lines.size():
		var line: String = _lines[i]
		if heading.search(line) != null:
			current = {}
			continue
		var h: RegExMatch = header.search(line)
		if h != null:
			current = {"label": h.get_string(1), "declared": int(h.get_string(2)), "line": i + 1, "marks": []}
			out.append(current)
			continue
		var it: RegExMatch = item.search(line)
		if it != null and not current.is_empty():
			(current["marks"] as Array).append(it.get_string(1))
	return out

func _label_for(mark: String) -> String:
	if mark == "x":
		return "Done"
	if mark == "~":
		return "In progress"
	return "Open"

# Otherwise every assertion below passes vacuously if the file is ever restructured.
func _there_are_groups_to_check() -> bool:
	var groups: Array = _groups()
	if groups.size() < 20:
		push_error("only %d groups found; the file's shape must have changed" % groups.size())
		return false
	var labels: Array[String] = []
	for g in groups:
		labels.append(String((g as Dictionary)["label"]))
	if not labels.has("Done") or not labels.has("Open"):
		push_error("no Done or Open groups found at all")
		return false
	print("GROUPS OK %d" % groups.size())
	return true

func _group_counts_match_their_contents() -> bool:
	var wrong: Array[String] = []
	for g in _groups():
		var d: Dictionary = g as Dictionary
		if int(d["declared"]) != (d["marks"] as Array).size():
			wrong.append("HANDOFF.md:%d \"%s (%d)\" holds %d" % [int(d["line"]), String(d["label"]), int(d["declared"]), (d["marks"] as Array).size()])
	if not wrong.is_empty():
		push_error("group counts disagree with their contents: %s" % str(wrong))
		return false
	print("COUNTS OK")
	return true

# The drift that actually happens: a box gets ticked in place and stays under `Open`. It
# happened again during the very audit that corrected this file.
func _no_checkbox_is_misfiled() -> bool:
	var misfiled: Array[String] = []
	for g in _groups():
		var d: Dictionary = g as Dictionary
		for mark in d["marks"] as Array:
			var belongs: String = _label_for(String(mark))
			if belongs != String(d["label"]):
				var msg: String = "HANDOFF.md:%d — \"%s\" group holds a [%s] item, which is \"%s\"" % [int(d["line"]), String(d["label"]), String(mark), belongs]
				if not misfiled.has(msg):
					misfiled.append(msg)
	if not misfiled.is_empty():
		push_error("misfiled checkboxes: %s" % str(misfiled))
		return false
	print("FILING OK")
	return true

func _milestone_rows_sum_to_total() -> bool:
	var row := RegEx.new()
	row.compile("^\\|\\s*(\\d+\\+?)\\s*—[^|]*\\|\\s*(\\d+)\\s*\\|\\s*(\\d+)\\s*\\|\\s*(\\d+)\\s*\\|")
	var done: int = 0
	var in_progress: int = 0
	var open: int = 0
	var seen: int = 0
	for line in _lines:
		var m: RegExMatch = row.search(line)
		if m != null:
			done += int(m.get_string(2))
			in_progress += int(m.get_string(3))
			open += int(m.get_string(4))
			seen += 1
	# Four milestone rows: 0, 1, 2 and 3+.
	if seen != 4:
		push_error("expected 4 milestone rows, found %d" % seen)
		return false
	var totals: Array[int] = _total_row()
	if totals.is_empty():
		push_error("no Total row found")
		return false
	if done != totals[0] or in_progress != totals[1] or open != totals[2]:
		push_error("milestone rows sum to %d/%d/%d but Total says %d/%d/%d" % [done, in_progress, open, totals[0], totals[1], totals[2]])
		return false
	print("ROWS OK %d/%d/%d" % [done, in_progress, open])
	return true

func _total_row() -> Array[int]:
	var total := RegEx.new()
	total.compile("\\|\\s*\\*\\*Total\\*\\*\\s*\\|\\s*\\*\\*(\\d+)\\*\\*\\s*\\|\\s*\\*\\*(\\d+)\\*\\*\\s*\\|\\s*\\*\\*(\\d+)\\*\\*")
	for line in _lines:
		var m: RegExMatch = total.search(line)
		if m != null:
			return [int(m.get_string(1)), int(m.get_string(2)), int(m.get_string(3))]
	return []

func _summary_table_matches_the_file() -> bool:
	var totals: Array[int] = _total_row()
	if totals.is_empty():
		push_error("no Total row found")
		return false
	var counts: Dictionary = {"x": 0, "~": 0, " ": 0}
	var item := RegEx.new(); item.compile(ITEM)
	for line in _lines:
		var m: RegExMatch = item.search(line)
		if m != null:
			counts[m.get_string(1)] = int(counts[m.get_string(1)]) + 1
	if int(counts["x"]) != totals[0] or int(counts["~"]) != totals[1] or int(counts[" "]) != totals[2]:
		push_error("file holds %d/%d/%d checkboxes but Total says %d/%d/%d" % [int(counts["x"]), int(counts["~"]), int(counts[" "]), totals[0], totals[1], totals[2]])
		return false
	print("TABLE OK %d/%d/%d" % [totals[0], totals[1], totals[2]])
	return true

# The assertion the oracle's test never had, and the one that would have caught four
# sections drifting: a box you tick must say what proves it. This cannot verify the claim --
# nothing cheap can -- but it makes the claim checkable by the next reader instead of taking
# a tick mark on faith.
#
# Scoped to Milestone 2, the live one. Milestones 0 and 1 are closed and their boxes were
# written as terse one-liners before this convention existed; retrofitting 41 notes onto
# finished work would be busywork, and the drift this guards against only matters where the
# work is still moving.
func _every_done_box_cites_its_evidence() -> bool:
	var item := RegEx.new(); item.compile(ITEM)
	var evidence := RegEx.new(); evidence.compile(EVIDENCE)
	var bare: Array[String] = []
	var in_m2: bool = false
	for i in _lines.size():
		var line_i: String = _lines[i]
		if line_i.begins_with("## "):
			in_m2 = line_i.begins_with("## Milestone 2")
		if not in_m2:
			continue
		var m: RegExMatch = item.search(line_i)
		if m == null or m.get_string(1) != "x":
			continue
		# Evidence sits one of three places, and all three count: an inline `*(...)*` on the
		# item's own line, a backticked identifier naming the function or file that does the
		# thing, or an indented `*(...)*` note on a following line.
		var cited: bool = line_i.contains("*(") or line_i.contains("`")
		var j: int = i + 1
		while j < _lines.size():
			var line: String = _lines[j]
			if item.search(line) != null or line.begins_with("**") or line.begins_with("#"):
				break
			if evidence.search(line) != null:
				cited = true
				break
			if line.strip_edges().is_empty():
				break
			j += 1
		if not cited:
			bare.append("HANDOFF.md:%d %s" % [i + 1, _lines[i].strip_edges().substr(0, 72)])
	if not bare.is_empty():
		push_error("%d ticked boxes cite no evidence; add an italic *(...)* note naming the gate or file:\n  %s" % [bare.size(), "\n  ".join(bare)])
		return false
	print("EVIDENCE OK")
	return true
