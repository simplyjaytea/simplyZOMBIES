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
		if text.begins_with("day "):
			continue
		var digits: String = _digits(text)
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
