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

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _attention_speaks_in_words() and ok
	ok = _hud_lines_carry_no_numbers() and ok
	ok = _a_healthy_survivor_says_little() and ok
	ok = _the_raw_sheet_stays_behind_m() and ok
	ok = _the_scanner_can_actually_fail() and ok
	var sheet_ok: bool = await _the_hidden_sheet_costs_nothing()
	ok = sheet_ok and ok
	if ok:
		print("HUD_OK prose only, day counter excepted, raw sheet gated")
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
	]
	for line in must_fail:
		if _digits(_without_day_counter(line)).is_empty():
			push_error("the digit scanner passed a line it exists to catch: '%s'" % line)
			return false
	# And the exemption must still exempt: the day counter alone, and nothing else on the line.
	for clean in ["day 3, Dusk", "day 1, Dawn", "You're bleeding.", "hungry"]:
		if not _digits(_without_day_counter(clean)).is_empty():
			push_error("the digit scanner failed a legal line: '%s'" % clean)
			return false
	print("NEGATIVE OK")
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
