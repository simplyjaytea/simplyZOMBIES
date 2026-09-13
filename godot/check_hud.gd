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

const RELOAD_GD: String = "res://platform/content_reload.gd"

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
	ok = _a_selected_colonist_is_spoken_of() and ok
	ok = _a_click_finds_a_colonist() and ok
	var sheet_ok: bool = await _the_hidden_sheet_costs_nothing()
	ok = sheet_ok and ok
	var reload_ok: bool = await _an_untouched_tree_is_not_reloaded()
	ok = reload_ok and ok
	if ok:
		print("HUD_OK prose only, day counter excepted, raw sheet gated, the body speaks for itself, an untouched tree is not reloaded")
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
