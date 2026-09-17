extends SceneTree
# The HUD tells you things in words.
#
# docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable, and the same
# reasoning that produced check_ban_health_bar.gd: a number on screen invites optimising
# the number, and the design would rather you made a decision. The HUD it replaced printed
# raw pools, aptitude integers, positions to one decimal and a serialisation fingerprint.
#
# The rule this enforces: **no digits in the HUD except the day counter.** That is blunt on
# purpose. "hunger 34" fails it, "1 bite" fails it, and both should -- the first is a pool
# the player is not owed and the second is a count the prose can carry. A day number is the
# one figure the player genuinely needs to say out loud, so it is the single exception, and
# it must appear on a line of its own that begins with "day ".
#
# The developer sheet is exempt. It is full of numbers, that is its job, and it only appears
# behind M.

const World = preload("res://sim/world.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimAttentionRead = preload("res://sim/attention_read.gd")
const Hud = preload("res://ui/hud.gd")
const SimChronicle = preload("res://sim/modules/chronicle.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const Pick = preload("res://presentation/pick.gd")
const ContentReload = preload("res://platform/content_reload.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const Shell = preload("res://ui/shell.gd")
const Session = preload("res://presentation/session.gd")

const RELOAD_GD: String = "res://platform/content_reload.gd"
const FORTIFY_GD: String = "res://sim/modules/fortify.gd"
const HUD_GD: String = "res://ui/hud.gd"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _attention_speaks_in_words() and ok
	ok = _hud_lines_carry_no_numbers() and ok
	ok = _a_healthy_survivor_says_little() and ok
	ok = _the_body_speaks_for_itself() and ok
	ok = _the_raw_sheet_stays_behind_m() and ok
	ok = _the_scanner_can_actually_fail() and ok
	ok = _the_chronicle_speaks_of_the_colony() and ok
	ok = _the_action_line_names_keys_only() and ok
	ok = _the_action_line_names_the_top_rung() and ok
	ok = _a_selected_colonist_is_spoken_of() and ok
	ok = _a_click_finds_a_colonist() and ok
	ok = _the_shell_speaks_in_words() and ok
	var sheet_ok: bool = await _the_hidden_sheet_costs_nothing()
	ok = sheet_ok and ok
	var reload_ok: bool = await _an_untouched_tree_is_not_reloaded()
	ok = reload_ok and ok
	if ok:
		print("HUD_OK prose only, day counter excepted, raw sheet gated, the body speaks for itself, the action bar names the top rung, an untouched tree is not reloaded")
		quit(0)
	else:
		push_error("HUD_FAIL")
		quit(1)

func _fixture() -> Dictionary:
	return {"seed": 31, "tick_hz": 20, "map": {"width": 16, "height": 16, "walls": []}, "player": {"id": 0, "x": 8.0, "y": 8.0, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}

# A survivor in trouble on every axis, so every clause the HUD can produce is produced.
func _suffering_world() -> Variant:
	var w: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(w, w.player)
	var body: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	for part in body.keys():
		if body[part] is float or body[part] is int:
			body[String(part)] = float(body[part]) * 0.15
	SimNeeds.attach(w, w.player, {"hunger": 9.0, "thirst": 4.0, "rest": 11.0})
	return w

func _digits(text: String) -> String:
	var found: String = ""
	for c in text:
		if c >= "0" and c <= "9":
			found += c
	return found


# The day counter is the one exception, and it is an exception for **one token**, not for the
# whole line. This used to `continue` past any line beginning with "day ", and hud.gd emits
# "day 3, Dusk" -- so anything numeric appended to that one line ("day 3, Dusk, 4 seen") sailed
# through the ban gate untouched. Strip exactly the leading `day <n>` and judge the remainder.
func _without_day_counter(text: String) -> String:
	if not text.begins_with("day "):
		return text
	var i: int = 4
	while i < text.length() and text[i] >= "0" and text[i] <= "9":
		i += 1
	if i == 4:
		return text # "day " with no number is not the counter; judge the whole line
	return text.substr(i)

func _attention_speaks_in_words() -> bool:
	var w: Variant = _suffering_world()
	var att: Dictionary = SimAttentionRead.clause(w, w.player)
	for key in ["noise", "scent", "light", "worst"]:
		var line: String = String(att.get(key, ""))
		if not _digits(line).is_empty():
			push_error("attention.%s carries digits: '%s'" % [key, line])
			return false
		if line.is_empty() and key != "worst":
			push_error("attention.%s produced no phrase at all" % key)
			return false
	print("ATTENTION OK")
	return true

func _hud_lines_carry_no_numbers() -> bool:
	var w: Variant = _suffering_world()
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, w.player, "tick 123 pos 4.5,6.7 STR 5")
	var left: Array = hud.get("_left") as Array
	var right: Array = hud.get("_right") as Array
	var bad: bool = false
	for line in left + right:
		var text: String = String(line)
		var rest: String = _without_day_counter(text)
		var digits: String = _digits(rest)
		if not digits.is_empty():
			push_error("HUD line carries digits (%s): '%s'" % [digits, text])
			bad = true
	# And the pools themselves must not have leaked verbatim.
	var joined: String = " ".join(PackedStringArray(left)) + " " + " ".join(PackedStringArray(right))
	for pool in ["9", "4", "11"]:
		if joined.contains("hunger %s" % pool) or joined.contains("thirst %s" % pool):
			push_error("a raw need pool reached the HUD: '%s'" % joined)
			bad = true
	hud.queue_free()
	if bad:
		return false
	print("LINES OK")
	return true

# The corollary of "no gauges": a survivor with nothing wrong should occupy almost no HUD.
# If this starts failing, something is padding the screen with status for its own sake.
func _a_healthy_survivor_says_little() -> bool:
	var w: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(w, w.player)
	SimNeeds.attach(w, w.player, {"hunger": 100.0, "thirst": 100.0, "rest": 100.0})
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, w.player, "")
	var left: Array = hud.get("_left") as Array
	hud.queue_free()
	if left.size() > 2:
		push_error("an unhurt, unstarved survivor produced %d HUD lines: %s" % [left.size(), str(left)])
		return false
	print("QUIET OK")
	return true

func _the_raw_sheet_stays_behind_m() -> bool:
	var w: Variant = _suffering_world()
	var hud: Control = Hud.new()
	root.add_child(hud)
	var sheet: String = "tick 4242 pos 8.0,8.0 STR 5 CON 5 DEX 5"
	hud.set("show_raw", false)
	hud.call("refresh", w, w.player, sheet)
	if bool(hud.get("show_raw")):
		push_error("the raw sheet defaulted to visible")
		hud.queue_free()
		return false
	# It must still be *held* -- M reveals it without needing a refresh to happen first.
	if String(hud.get("_raw")) != sheet:
		push_error("the HUD dropped the developer sheet instead of holding it for M")
		hud.queue_free()
		return false
	hud.queue_free()
	print("RAW OK")
	return true


# CLAUDE.md: a gate that cannot fail is worse than no gate, and every assertion wants a true
# negative. Everything above asserts an absence -- "no digits" passes just as happily when the
# scanner is broken as when the HUD is clean. These are the lines that must be caught. The
# "day 3, Dusk, 4 seen" row is the one that mattered: the day exemption used to skip the whole
# line, so a count smuggled onto the day line was invisible to this gate.
func _the_scanner_can_actually_fail() -> bool:
	var must_fail: Array[String] = [
		"hunger 34",
		"1 bite",
		"day 3, Dusk, 4 seen",
		"day 12 and 3 shamblers",
		"light 0.85",
		"rain for 3 hours",
	]
	for line in must_fail:
		if _digits(_without_day_counter(line)).is_empty():
			push_error("the digit scanner passed a line it exists to catch: '%s'" % line)
			return false
	# And the exemption must still exempt: the day counter alone, and nothing else on the line.
	for clean in ["day 3, Dusk", "day 1, Dawn", "You're bleeding.", "hungry", "It's raining.", "You're soaked.", "A storm is over the district.", "It's bitterly cold.", "It's snowing.", "The heat is brutal.", "You're uncomfortable — hot.", "You're overheating.", "Heatstroke — get out of the sun.", "Fog has closed in."]:
		if not _digits(_without_day_counter(clean)).is_empty():
			push_error("the digit scanner failed a legal line: '%s'" % clean)
			return false
	print("NEGATIVE OK")
	return true


# A person the lanes below can kill, select and click: an identity, a position, a body.
func _person(w: Variant, name: String, x: float, y: float) -> int:
	var e: int = int(w.entities.spawn())
	w.components.set_component(e, "identity", {"id": "survivor.test." + name.to_lower(), "name": name})
	w.components.set_component(e, "position", {"x": x, "y": y})
	SimHealth.make_survivor_body(w, e)
	return e


# Decision 12 of docs/30's "The playable state": a death, a succession, an arrival reach the
# screen as words. True positive: killing Ellis writes exactly one line, and the HUD's world
# column carries it (the dead-socket half -- a read model nothing reads is the pattern this
# milestone paid for ten times). True negatives: `entity.killed` twice for one body is one line,
# not two; a zombie's death is nobody's news; a line ages out of the screen but not the record;
# and the record survives a save.
func _the_chronicle_speaks_of_the_colony() -> bool:
	var w: Variant = World.new(_fixture())
	SimChronicle.register_module(w)
	var ellis: int = _person(w, "Ellis Okafor", 6.0, 6.0)
	var zed: int = int(w.entities.spawn())
	w.components.set_component(zed, "shambler", {"state": 0})
	w.components.set_component(zed, "position", {"x": 4.0, "y": 4.0})
	w.tick = 1000
	w.events.publish({"type": "entity.killed", "entity": ellis})
	w.events.publish({"type": "entity.killed", "entity": ellis})
	w.events.publish({"type": "entity.killed", "entity": zed})
	w.step()
	var lines: Array = SimChronicle.lines(w)
	if lines.size() != 1 or String(lines[0]) != "Ellis Okafor is dead.":
		push_error("one death, twice published, plus a zombie's, should be one line: %s" % str(lines))
		return false
	for line in lines:
		if not _digits(String(line)).is_empty():
			push_error("a chronicle line carries digits: '%s'" % String(line))
			return false
	# Something reads it: the HUD's world column.
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, w.player, "")
	var right: Array = hud.get("_right") as Array
	hud.queue_free()
	if not right.has("Ellis Okafor is dead."):
		push_error("the HUD's world column does not carry the chronicle: %s" % str(right))
		return false
	# Arrival says what it is, in words, and newest comes first. A spawn is not a joining
	# (survivors.gd publishes `survivor.joined` for every body it builds), an acceptance is;
	# a death nobody saw is not a bereavement, one somebody saw is.
	w.events.publish({"type": "recruit.arrived", "entity": 99, "day": 3})
	w.events.publish({"type": "survivor.joined", "entity": ellis, "id": "survivor.unique.ellis"})
	w.events.publish({"type": "colony.bereaved", "entity": ellis, "witnesses": 0, "putDown": false})
	w.step()
	lines = SimChronicle.lines(w)
	if lines.size() != 2 or String(lines[0]) != "Someone is waiting at the gate.":
		push_error("an arrival should be the newest line, a spawn and an unseen death no line: %s" % str(lines))
		return false
	w.events.publish({"type": "survivor.joined", "entity": ellis, "id": "recruit"})
	w.events.publish({"type": "colony.bereaved", "entity": ellis, "witnesses": 2, "putDown": false})
	w.step()
	lines = SimChronicle.lines(w)
	if lines.size() != 3 or String(lines[0]) != "The colony saw Ellis Okafor die." or String(lines[1]) != "Ellis Okafor has joined you.":
		push_error("an acceptance and a witnessed death should each be a line: %s" % str(lines))
		return false
	w.step()
	# A save keeps the record whole.
	var snap: Dictionary = w.snapshot()
	var w2: Variant = World.new(_fixture())
	w2.restore(snap)
	if (w2.chronicle as Array).size() != (w.chronicle as Array).size() or SimChronicle.lines(w2) != lines:
		push_error("the chronicle did not survive a save: %s vs %s" % [str(w2.chronicle), str(w.chronicle)])
		return false
	# The screen forgets; the record does not.
	w.tick += SimChronicle.LINE_TICKS + 1
	if not SimChronicle.lines(w).is_empty():
		push_error("a line older than LINE_TICKS is still on the screen: %s" % str(SimChronicle.lines(w)))
		return false
	if (w.chronicle as Array).size() != 4:
		push_error("ageing out of the screen dropped the record: %s" % str(w.chronicle))
		return false
	print("CHRONICLE OK one line a death, aged out, saved")
	return true


# The action bar's line: which key does what, right here. docs/30's "The alpha shell" -- the sim
# decides the verb, presentation names the key -- so this lane asks two things of it.
#
# The prose half: the line names E for a boarded window and carries no digit, with the scanner
# proved on the literal "E — 3 boards", which is what the line would look like if somebody
# swapped a read model's prose for a count. The em dash is not decoration here: the bar splits on
# it to draw the key in amber and the words in khaki, so a clause without one loses its accent.
#
# The reach half: every source is asked for a true positive, because a clause that can never
# appear is a key the bar will never name -- the look-at first, the `hint` main.gd resolved for
# this frame behind it (the parameter would otherwise be a dead socket in the signature), T for a
# bleeding body and H for a held one. True negatives all round: a content-error hint is not an
# action, a survivor standing in an empty street with nothing wrong gets no line at all, and the
# whole line is "" for a null world.
#
# And the dead-socket half, textually: `_update_hud` in main.gd has to hand the line over, or
# every clause above is prose nothing draws. The needle is the call as written rather than
# `set_action(` alone, because `_hud` is typed `Control` and the call goes through `call()` --
# and a needle a comment could satisfy cannot fail (CLAUDE.md, the READ_KEYS lesson).
func _the_action_line_names_keys_only() -> bool:
	var w: Variant = _suffering_world()
	SimWounds.append_wound(w, w.player, "laceration", "torso", -1, 30.0)
	var look: Dictionary = {"window": "boarded, holding"}
	var line: String = Hud.action_line(w, w.player, look, "a hint nobody should need")
	if line.is_empty():
		push_error("ACTION: a survivor at a boarded window is offered nothing")
		return false
	if line.find("E — boarded, holding") < 0:
		push_error("ACTION: the line does not name E for the window in reach: '%s'" % line)
		return false
	if not _digits(line).is_empty():
		push_error("ACTION: the action line carries digits (%s): '%s'" % [_digits(line), line])
		return false
	# The scanner that just passed it has to be able to fail: the same line with a count in it.
	if _digits("E — 3 boards").is_empty():
		push_error("ACTION: the digit scanner passed the line it exists to catch: 'E — 3 boards'")
		return false
	# T, from the bleeding torso -- a rung the sim would allow, named in the sim's own terms.
	if line.find("T — ") < 0:
		push_error("ACTION: a bleeding survivor is offered no aid key: '%s'" % line)
		return false
	# H, for a neighbour with something holding her, by name.
	var mara: int = _person(w, "Mara Sato", 8.5, 8.0)
	w.components.set_component(mara, "grabbed", {"by": 4242, "sinceTick": 0})
	var held: String = Hud.action_line(w, w.player, look, "")
	if held.find("H — pull Mara Sato free") < 0:
		push_error("ACTION: nobody is offered the rescue key for a held colonist: '%s'" % held)
		return false
	# The clauses join, in the order the keys sit under the hand.
	if held.find("E — ") > held.find("T — ") or held.find("T — ") > held.find("H — "):
		push_error("ACTION: the clauses are not in E, T, H order: '%s'" % held)
		return false
	# `hint` is read: with the look-at silent it is the E clause, and it never wins over one.
	var hinted: String = Hud.action_line(w, w.player, {}, "the gate stands open")
	if hinted.find("E — the gate stands open") < 0:
		push_error("ACTION: main.gd's own context line never reaches the bar: '%s'" % hinted)
		return false
	if line.find("the gate") >= 0 or Hud.action_line(w, w.player, look, "the gate stands open").find("the gate") >= 0:
		push_error("ACTION: the hint displaced the look-at clause it is a fallback for")
		return false
	# A content error is a fault report main.gd borrows the hint for, not something E does.
	if Hud.action_line(w, w.player, {}, "content: boom").find("E") >= 0:
		push_error("ACTION: a content error was offered as an action")
		return false
	# The true negative that matters: nothing to do, no line.
	var quiet: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(quiet, quiet.player)
	SimNeeds.attach(quiet, quiet.player, {"hunger": 100.0, "thirst": 100.0, "rest": 100.0})
	var nothing: String = Hud.action_line(quiet, int(quiet.player), {}, "")
	if not nothing.is_empty():
		push_error("ACTION: a survivor in an empty street with nothing wrong is offered '%s'" % nothing)
		return false
	if not Hud.action_line(null, 0, {}, "").is_empty():
		push_error("ACTION: a null world produced a line")
		return false
	# The reader. Without this every clause above is prose nothing draws.
	var body: String = _function_body("res://presentation/main.gd", "_update_hud")
	if body.is_empty():
		push_error("ACTION: could not read _update_hud out of main.gd -- the reach assertion had nothing to judge")
		return false
	# Comment lines dropped first: the whole point of a reach assertion is that it fails when the
	# call goes, and a needle a commented-out call still satisfies would not.
	var code: String = ""
	for row in body.split("\n"):
		if not String(row).strip_edges().begins_with("#"):
			code += String(row) + "\n"
	if code.find("_hud.call(\"set_action\"") < 0:
		push_error("ACTION: _update_hud never hands the action line to the HUD")
		return false
	if body.find("_hud.call(\"set_actionx\"") >= 0:
		push_error("ACTION: the needle matched a call that does not exist, so this lane is not reading what it thinks")
		return false
	# And the HUD has to draw what it was handed.
	var hud_src: String = FileAccess.get_file_as_string("res://ui/hud.gd")
	if hud_src.find("func _draw_action_bar(") < 0 or _function_body("res://ui/hud.gd", "_draw").find("_draw_action_bar(") < 0:
		push_error("ACTION: the HUD holds an action line that nothing draws")
		return false
	print("ACTION OK '%s', digit-free, E/T/H in order, the hint behind the look-at, and _update_hud hands it over" % held)
	return true


# A world with a real map rather than a fabricated `look` dict, so the rung this builds names is
# `SimFortify.rung_of`'s own decision and not a string this file made up for it. Player facing a
# window at (10, 12) from (10.5, 13.5) -- the same tile and reach check_m2_fortify.gd's `_world()`
# uses, so a change to either fixture's arithmetic is visible in both gates rather than only one.
#
# `wall_face` blocks the true negative's own facing tile: on open floor, empty ground with no
# alarm laid yet is itself a free rung ("lay a trip alarm", `_use_context`'s last-resort clause),
# so the one way to ask for truly nothing in reach is a facing tile that is not floor at all.
func _rung_window_world(px: float = 10.5, py: float = 13.5, wall_face: bool = false) -> Variant:
	var f: Dictionary = {"seed": 31, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": px, "y": py, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	var map: Variant = SimTileMap.blank_map(24, 24)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimFortify.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": -PI / 2.0})
	SimHealth.make_survivor_body(w, w.player)
	w.tilemap.tiles[12 * int(w.tilemap.w) + 10] = SimTileMap.Tile.Window
	if wall_face:
		var here: Vector2i = Vector2i(floori(px), floori(py))
		w.tilemap.tiles[(here.y - 1) * int(w.tilemap.w) + here.x] = SimTileMap.Tile.Wall
	return w


# docs/23's follow-up "the ladder names its rung": `_use_context` decides and acts on six upper
# rungs in one breath and the rest of the ladder in a second, `rung_of`, that names what it found
# rather than doing it. This lane asks both the words and the wiring.
#
# True positive: standing at reach of a boardable window with an otherwise empty `look` dict (so
# the pre-existing window clause above cannot be the one answering), the bar still names E with
# rung_of's own word and no digit. True negative: three tiles off the same window, nothing is
# named at all -- healthy, unheld, nothing in reach. The fabricated half proves the scanner this
# lane leans on would catch a rung that broke the rule, the way the window lane already proved it
# on "E — 3 boards". And the reader half: `_use_context` calls `rung_of` on a line of its own
# rather than inlining the decision back into itself, and `action_line`'s reach clause asks it too
# -- both isolated past a stripped comment, so a commented-out call cannot satisfy either needle.
func _the_action_line_names_the_top_rung() -> bool:
	var near: Variant = _rung_window_world()
	var near_line: String = Hud.action_line(near, near.player, {}, "")
	if near_line.find("E — board up the window") < 0:
		push_error("RUNG: beside a boardable window with no look-at, the bar does not name rung_of's word: '%s'" % near_line)
		return false
	if not _digits(near_line).is_empty():
		push_error("RUNG: the rung's own clause carries digits (%s): '%s'" % [_digits(near_line), near_line])
		return false
	# The true negative: three tiles off the window and facing a wall, healthy, alone, nothing to
	# open, sleep at or board -- and the facing tile is not floor, so the free "lay a trip alarm"
	# fallback that open ground would otherwise offer cannot fire either. Not the same body as the
	# true positive -- position is read at construction, not moved.
	var far: Variant = _rung_window_world(10.5, 16.5, true)
	var far_line: String = Hud.action_line(far, far.player, {}, "")
	if not far_line.is_empty():
		push_error("RUNG: a survivor with nothing in reach is offered '%s'" % far_line)
		return false
	# The scanner proved on the window clause above catches a fabricated line built out of
	# rung_of's own vocabulary just as it caught "E — 3 boards" -- a different rung, the same rule.
	if _digits("E — sleep for 8 hours").is_empty():
		push_error("RUNG: the digit scanner passed a fabricated rung line it exists to catch")
		return false
	# The reader, on `_use_context`'s side: one line, past a stripped comment, calling rung_of --
	# not the decision folded back into the acting function.
	var use_ctx_body: String = _function_body(FORTIFY_GD, "_use_context")
	if use_ctx_body.is_empty():
		push_error("RUNG: could not read _use_context out of %s -- the reach assertion had nothing to judge" % FORTIFY_GD)
		return false
	var rung_call_found: bool = false
	for row in use_ctx_body.split("\n"):
		if String(row).strip_edges().begins_with("var rung: Dictionary = rung_of("):
			rung_call_found = true
			break
	if not rung_call_found:
		push_error("RUNG: _use_context never calls rung_of on a line of its own -- the decision and the act have drifted back together")
		return false
	# The reader, on the HUD's side: `_reach_clause` has to ask the same function, past a stripped
	# comment so a mention in prose cannot satisfy it.
	var reach_body: String = _function_body(HUD_GD, "_reach_clause")
	if reach_body.is_empty():
		push_error("RUNG: could not read _reach_clause out of %s -- the reach assertion had nothing to judge" % HUD_GD)
		return false
	var reach_code: String = ""
	for row in reach_body.split("\n"):
		if not String(row).strip_edges().begins_with("#"):
			reach_code += String(row) + "\n"
	if reach_code.find("SimFortify.rung_of(") < 0:
		push_error("RUNG: action_line's reach clause never asks rung_of for the top rung")
		return false
	print("RUNG OK '%s' beside the window, nothing three tiles off it, digit-free both ways, and both readers reach rung_of" % near_line)
	return true


# The same slice check_camera.gd takes out of main.gd, for the same reason: an assertion about
# what a function contains has to be reading that function and not a mention of it elsewhere.
# Matches a bare "func" or a "static func" opener -- hud.gd's action clauses and fortify's rung
# read are both static, and a needle that only found instance methods would silently skip them.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var out: String = ""
	var inside: bool = false
	for line in f.get_as_text().split("\n"):
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out += line + "\n"
	return out


# The other half of decision 12: the HUD refreshed for a colonist speaks of her, never as "You".
# Mara is hurt on every axis the left column reads -- needs, pain, sepsis, condition -- so every
# clause that used to say "You" about the player is produced about her. True negative: the
# player's own refresh still says "You".
func _a_selected_colonist_is_spoken_of() -> bool:
	var w: Variant = _suffering_world()
	var mara: int = _person(w, "Mara Sato", 9.0, 8.0)
	SimNeeds.attach(w, mara, {"hunger": 9.0, "thirst": 4.0, "rest": 11.0})
	var wound: Dictionary = SimWounds.append_wound(w, mara, "laceration", "torso", -1, 30.0)
	wound["septic"] = true
	SimWounds.append_wound(w, w.player, "laceration", "torso", -1, 30.0)
	var pain: String = SimWounds.pain_clause(w, mara)
	var fever: String = SimWounds.sepsis_clause(w, mara)
	if pain.is_empty() or fever.is_empty():
		push_error("the fixture gave Mara no pain or no fever: '%s' / '%s'" % [pain, fever])
		return false
	if not pain.begins_with("Mara Sato") or not fever.begins_with("Mara Sato"):
		push_error("a colonist's pain or fever is not spoken of in the third person: '%s' / '%s'" % [pain, fever])
		return false
	if not SimWounds.pain_clause(w, w.player).begins_with("You") or not SimWounds.sepsis_clause(w, w.player).is_empty():
		push_error("the player's own pain lost its 'You', or a clean player read septic")
		return false
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", w, mara, "")
	var left: Array = hud.get("_left") as Array
	hud.call("refresh", w, w.player, "")
	var own: Array = hud.get("_left") as Array
	hud.queue_free()
	var named: bool = false
	for line in left:
		var text: String = String(line)
		if text.begins_with("You") or text.contains(" you"):
			push_error("the HUD for a selected colonist says 'You': '%s'" % text)
			return false
		if text.contains("Mara Sato"):
			named = true
	if not named or left.size() < 3:
		push_error("the HUD for a selected colonist does not speak of her: %s" % str(left))
		return false
	var says_you: bool = false
	for line in own:
		if String(line).begins_with("You"):
			says_you = true
	if not says_you:
		push_error("the player's own HUD stopped saying 'You': %s" % str(own))
		return false
	print("SELECTED OK %d lines about Mara" % left.size())
	return true


# The click that makes the selection: a pure hit-test on the pawn rect at the draw pass's
# scale. Mara's pawn hit; three tiles off, the street; a zombie and a corpse never, even with an
# identity; the player's own pawn answers the player (main.gd reads that as "clear").
func _a_click_finds_a_colonist() -> bool:
	var w: Variant = World.new(_fixture())
	var mara: int = _person(w, "Mara Sato", 8.0, 8.0)
	var zed: int = _person(w, "A Shambler", 12.0, 8.0)
	w.components.set_component(zed, "shambler", {"state": 0})
	var dead: int = _person(w, "Ellis Okafor", 8.0, 12.0)
	w.components.set_component(dead, "corpse", {"sinceTick": 0})
	var player_pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	player_pos["x"] = 4.0
	player_pos["y"] = 4.0
	var camera: Dictionary = {"x": 8.0, "y": 8.0, "width": 800.0, "height": 600.0, "zoom": 64.0}
	# Mara's ground point is the screen centre; the pawn stands above it, feet on the shadow line.
	var on_mara: Vector2 = Vector2(400.0, 260.0)
	if Pick.pick_colonist(w, camera, on_mara) != mara:
		push_error("a click on Mara's pawn did not select her: %d" % Pick.pick_colonist(w, camera, on_mara))
		return false
	if Pick.pick_colonist(w, camera, Vector2(400.0 + 3.0 * 64.0, 260.0)) != -1:
		push_error("a click three tiles from anybody selected somebody")
		return false
	if Pick.pick_colonist(w, camera, Vector2(400.0 + 4.0 * 64.0, 260.0)) != -1:
		push_error("a click on a zombie selected it")
		return false
	if Pick.pick_colonist(w, camera, Vector2(400.0, 300.0 + 4.0 * 64.0 - 40.0)) != -1:
		push_error("a click on a corpse selected it")
		return false
	var on_player: Vector2 = Vector2(400.0 - 4.0 * 64.0, 300.0 - 4.0 * 64.0 - 40.0)
	if Pick.pick_colonist(w, camera, on_player) != int(w.player):
		push_error("a click on your own pawn did not answer the player: %d" % Pick.pick_colonist(w, camera, on_player))
		return false
	print("PICK OK Mara hit, street and the dead missed, self answers self")
	return true


# The three screens that are not the game -- the title, the pause menu and the run-over screen --
# are under the same ban as the HUD, and the owner said so in the same breath: "no digit anywhere
# on the shell" (docs/30, "The alpha shell, 2026-09-16"). Not even the day the run ended, which is
# the one digit the HUD is allowed and the one this screen would most naturally reach for.
#
# `ui/shell.gd` exposes `words()` for the same reason `SimSkills.web_map` exposes its own: a
# screen that can only be judged by its pixels cannot be gated. Every heading, every line of
# prose, every row label and the notice go through it, so a digit added to any of them is caught
# here and not by somebody reading a screenshot.
#
# Driven, not read: the panel is stood up and asked for each of its three states in turn, with a
# fabricated epitaph so the run-over screen has prose to say. And the scanner is shown failing on
# the line it exists to catch -- an epitaph with a count in it.
func _the_shell_speaks_in_words() -> bool:
	var shell: Control = Shell.new()
	root.add_child(shell)
	var screens: Array = [
		["the title, with a run to continue", Shell.TITLE, {"has_continue": true, "is_web": false}],
		["the title in a browser, refusing a save", Shell.TITLE, {"has_continue": false, "is_web": true, "notice": Session.STALE_NOTICE}],
		["the pause menu", Shell.PAUSED, {}],
		["the run-over screen", Shell.RUN_OVER, {"epitaph": ["Mara Sato is dead.", "You are dead.", "There is nobody left to be."]}],
	]
	var counted: int = 0
	for screen in screens:
		var what: String = String((screen as Array)[0])
		shell.call("show_state", int((screen as Array)[1]), (screen as Array)[2] as Dictionary)
		var words: Array = Array(shell.call("words"))
		if words.is_empty():
			shell.queue_free()
			push_error("SHELL: %s draws no words at all, so nothing here is judged" % what)
			return false
		if Array(shell.call("rows")).is_empty():
			shell.queue_free()
			push_error("SHELL: %s offers no rows, so the screen cannot be left" % what)
			return false
		for word in words:
			counted += 1
			var digits: String = _digits(String(word))
			if not digits.is_empty():
				shell.queue_free()
				push_error("SHELL: %s carries digits (%s): '%s'" % [what, digits, String(word)])
				return false
	# The rows follow their context, which is what makes the words above the *right* words: a
	# title with no save does not offer to continue one, and a browser tab has nothing to quit to.
	shell.call("show_state", Shell.TITLE, {"has_continue": false, "is_web": true})
	var bare: Array = Array(shell.call("rows"))
	if bare.has("continue") or bare.has("quit"):
		shell.queue_free()
		push_error("SHELL: a web title with no save still offers %s" % str(bare))
		return false
	shell.call("show_state", Shell.TITLE, {"has_continue": true, "is_web": false})
	var full: Array = Array(shell.call("rows"))
	if not full.has("continue") or not full.has("quit"):
		shell.queue_free()
		push_error("SHELL: a desktop title with a save offers only %s" % str(full))
		return false
	# And the scanner can fail. The same screen with a count in its epitaph -- which is what it
	# would say the day somebody decides the run-over screen should name the day it ended.
	shell.call("show_state", Shell.RUN_OVER, {"epitaph": ["You lasted 3 days."]})
	var caught: bool = false
	for word in Array(shell.call("words")):
		if not _digits(String(word)).is_empty():
			caught = true
	shell.queue_free()
	if not caught:
		push_error("SHELL: the scanner passed 'You lasted 3 days.' on the run-over screen, so it is judging nothing")
		return false
	print("SHELL OK %d words across the title, the pause menu and the run-over screen, not a digit among them, and the rows follow the save and the platform" % counted)
	return true


# The sheet behind M is exempt from the prose rule, but it is not exempt from the frame budget
# (docs/00 pillar 6). Its fingerprint is a hash of `world.serialize()` -- the entire save path,
# measured at 12.58 ms on a two-hour-old world -- and it was recomputed four times a second
# whether or not anybody had pressed M. This pins that it is computed only while the sheet is up.
# True positive: hidden, the field holds no live hash. True negative: shown, it does.
func _the_hidden_sheet_costs_nothing() -> bool:
	var packed := load("res://presentation/main.tscn") as PackedScene
	if packed == null:
		push_error("cannot load the main scene")
		return false
	var main := packed.instantiate()
	root.add_child(main)
	# The scene builds its world in _ready; one processed frame is what project_smoke.gd waits
	# for and is enough here too.
	await process_frame
	if main.get("world") == null:
		push_error("the main scene did not construct a world")
		main.queue_free()
		return false
	main.set("show_sheets", false)
	main.call("_update_hud")
	var hidden: String = String(main.get("_fingerprint"))
	main.set("show_sheets", true)
	main.call("_update_hud")
	var shown: String = String(main.get("_fingerprint"))
	main.queue_free()
	if _is_live_hash(hidden):
		push_error("the world was serialised for a sheet nobody had opened: fp '%s'" % hidden)
		return false
	if not _is_live_hash(shown):
		push_error("M did not produce a fingerprint: fp '%s'" % shown)
		return false
	print("SHEET-COST OK hidden '%s', shown '%s'" % [hidden, shown])
	return true


func _is_live_hash(fp: String) -> bool:
	if fp.length() != 8:
		return false
	for c in fp:
		var hex: bool = (c >= "0" and c <= "9") or (c >= "a" and c <= "f")
		if not hex:
			return false
	return true


# The tag beside the player's own body: docs/23's "condition and stamina readouts in the world,
# not a corner", and the boundary that keeps it from becoming a name plate.
#
# Three things are being held down. It says something when there is something to say; it says
# **nothing** when there is not, which is what stops a permanent label appearing over the player;
# and it never enters `_left`, so the quiet-survivor and selected-colonist lanes above still have
# the corner column to judge and this cannot quietly empty them.
func _the_body_speaks_for_itself() -> bool:
	var hurt: String = Hud.pawn_tag(_suffering_world(), 0)
	if hurt.is_empty():
		push_error("a survivor at fifteen percent on every part had nothing written beside them")
		return false
	if _digits(hurt) != "":
		push_error("the pawn tag carries a digit: \"%s\"" % hurt)
		return false
	# It names a part, in the words condition.gd humanises them to -- never the sim's own key,
	# which is the same class of leak as a raw number.
	if hurt.find("_") >= 0:
		push_error("the pawn tag shows a raw part key: \"%s\"" % hurt)
		return false
	if hurt.find("favouring") < 0:
		push_error("a badly hurt survivor's tag says nothing about a limb: \"%s\"" % hurt)
		return false

	# The true negative, and the important half: a healthy body says nothing at all.
	var well: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(well, well.player)
	SimNeeds.attach(well, well.player, {"hunger": 100.0, "thirst": 100.0, "rest": 100.0})
	var quiet: String = Hud.pawn_tag(well, int(well.player))
	if not quiet.is_empty():
		push_error("an unhurt survivor had \"%s\" written beside them" % quiet)
		return false
	# And a body with no body at all -- a zombie, a prop, a car -- is not describable.
	if Hud.pawn_tag(well, 9999) != "":
		push_error("something with no body got a tag")
		return false

	# Bleeding reads on the tag even when nothing is badly hurt yet, because blood loss is the one
	# thing on this screen that kills and a glance at yourself would catch it first.
	var cut: Variant = World.new(_fixture())
	SimHealth.make_survivor_body(cut, cut.player)
	SimNeeds.attach(cut, cut.player, {"hunger": 100.0, "thirst": 100.0, "rest": 100.0})
	cut.components.set_component(cut.player, "injuries", {"wounds": [{
		"bodyPart": "arm_left", "kind": "cut", "severity": 1, "bleeding": true, "closed": false,
	}]})
	var bleeding: String = Hud.pawn_tag(cut, int(cut.player))
	if bleeding.find("bleeding") < 0:
		push_error("a bleeding survivor's tag does not say so: \"%s\"" % bleeding)
		return false

	# The corner column is untouched by all of this. The tag is drawn beside the body and is not a
	# HUD line, so `_left` must not have grown one -- otherwise QUIET above would be judging the
	# tag rather than the column it exists to hold down.
	var hud: Control = Hud.new()
	root.add_child(hud)
	hud.call("refresh", well, int(well.player), "")
	var left: Array = hud.get("_left") as Array
	hud.queue_free()
	for line in left:
		if String(line).find("favouring") >= 0:
			push_error("the pawn tag reached the corner column: %s" % str(left))
			return false

	# And the reader, textually: something has to draw it, and only for the player.
	var main_src: String = FileAccess.get_file_as_string("res://presentation/main.gd")
	if main_src.find("pawn_tag") < 0:
		push_error("nothing draws the pawn tag")
		return false
	var arm: int = main_src.find("pawn_tag")
	var before: String = main_src.substr(maxi(0, arm - 400), 400)
	if before.find("it[\"player\"]") < 0:
		push_error("the pawn tag is not drawn inside a player-only branch, so it is a name plate over everybody")
		return false
	print("TAG OK a hurt body reads \"%s\", a well one reads nothing, bleeding shows, and the corner column is untouched" % hurt)
	return true


# The debug build's content-reload poll is not exempt from the frame budget either. It used to
# validate the whole tree, then validate it again and load it again, twice a second, whether or
# not a file had changed -- three full parses of every content file per poll. It fingerprints the
# tree now (paths, modified times, lengths; a directory walk and no parse) and reloads only when
# the fingerprint moves. True positive: with nothing touched, a forced poll leaves the live tree
# alone -- a marker planted in `world.content` survives, where a reload replaces the Dictionary.
# True negative: the reload path itself still replaces it when called, and the fold tells a
# moved mtime from an unmoved one on a fabricated list, so "not reloaded" is not "cannot reload".
func _an_untouched_tree_is_not_reloaded() -> bool:
	# The fold can say no, without touching the shipped tree.
	var same: Array = [["a.json", 100, 10], ["b.json", 200, 20]]
	var moved: Array = [["a.json", 101, 10], ["b.json", 200, 20]]
	var longer: Array = [["a.json", 100, 11], ["b.json", 200, 20]]
	var a: int = ContentReload.fold_fingerprint(same)
	if a != ContentReload.fold_fingerprint(same.duplicate(true)):
		push_error("RELOAD-COST: the same list folds to two different fingerprints")
		return false
	if a == ContentReload.fold_fingerprint(moved) or a == ContentReload.fold_fingerprint(longer):
		push_error("RELOAD-COST: a moved mtime or a changed length folds to the same fingerprint, so the poll would never reload")
		return false
	if ContentReload.content_fingerprint("res://content") != ContentReload.content_fingerprint("res://content"):
		push_error("RELOAD-COST: the shipped tree fingerprints differently on two consecutive looks")
		return false
	var packed := load("res://presentation/main.tscn") as PackedScene
	if packed == null:
		push_error("cannot load the main scene")
		return false
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	var world: Variant = main.get("world")
	if world == null:
		push_error("the main scene did not construct a world")
		main.queue_free()
		return false
	# One poll has run in _process by now and cached the fingerprint; if not, force it.
	main.set("_content_poll_at", -1e9)
	main.call("_poll_content_reload")
	(world.content as Dictionary)["__probe"] = 1
	main.set("_content_poll_at", -1e9)
	main.call("_poll_content_reload")
	var survived: bool = (world.content as Dictionary).has("__probe")
	# The negative: the reload path, called directly, does replace the tree.
	var res: Dictionary = ContentReload.try_reload_world(world)
	var replaced: bool = bool(res.get("ok", false)) and not (world.content as Dictionary).has("__probe")
	main.queue_free()
	if not survived:
		push_error("RELOAD-COST: a poll over an untouched tree reloaded it -- every debug frame pays for a parse nobody asked for")
		return false
	if not replaced:
		push_error("RELOAD-COST: try_reload_world no longer replaces the tree, so the marker's survival proves nothing")
		return false
	# And the dead poller is gone: a function that answered "changed" whenever the tree was non-empty.
	var src: String = FileAccess.get_file_as_string(RELOAD_GD)
	if src.is_empty() or src.contains("return not paths.is_empty()"):
		push_error("RELOAD-COST: content_reload.gd still carries the poller that answered true for any non-empty tree")
		return false
	print("RELOAD-COST OK a forced poll over an untouched tree left it alone, a direct reload replaced it, and the fold tells a moved file from an unmoved one")
	return true
