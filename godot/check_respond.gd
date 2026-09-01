extends SceneTree
# The one infection response the player can reach, and the rule that decides when they can see it.
#
# `infection.respond` had been a live command handler that nothing pushed -- no key, no button, no
# NPC decision -- which meant antibiotics, the only cure sepsis has, were unreachable in ordinary
# play at the same moment the `GRABS_ENABLED` flip made sepsis and bites ordinary. This gate holds
# down the surface that answers that, and the two things about it that are easy to get wrong:
#
#  1. **The word is offered iff it would work.** `SimTreatment.response_view` asks two questions --
#     is there a course in the pack, and is anything showing that a course might answer -- and the
#     body screen draws exactly what comes back. work_panel.gd's rule: a name you can afford is
#     simply present, one you cannot is absent. So NO SUPPLY and NO NEED are as much of the
#     contract as TRUE POSITIVE is, and each is asserted with the other two halves held fixed.
#
#  2. **The word must not say which infection it is.** docs/05 gives sepsis and an early bite the
#     same presentation, and `SimInfection.use_antibiotics`' own comment names the failure mode:
#     the player must not be able to tell sepsis from a bite by which button lights up. That is
#     what NO LEAK is for, and it is asserted the strong way -- the view is a function of the
#     *stage*, and two worlds differing only in `transmitted` produce byte-identical rows.
#
# The free-course hole this landed with is asserted here too. The zombie-infection path used to
# record a course with no item spent ("still allow course without item in tests"), so a bitten
# survivor dosed for free while a septic one paid; NO SUPPLY's exposure half is red against that
# sim and green against this one.
#
# Every lane carries its true negative. A gate that cannot fail is worse than no gate.

const World = preload("res://sim/world.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")

const PANEL_GD: String = "res://ui/inventory_panel.gd"
const PART: String = "torso"
# Torso max is 40, so 20 is half of it -- a deep wound, the same figure check_m2_treatment.gd uses
# and comfortably clear of the Scratch boundary if the bands ever move a little.
const DEEP_DAMAGE: float = 20.0
# Two so a spend is visible as a decrement rather than as an entity going away, which is the same
# way check_m2_wounds.gd's SEPSIS COST lane proves the stock is shared.
const COURSE_COUNT: int = 2


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_course_is_a_real_item() and ok
	ok = _a_symptom_and_a_course_offer_the_word() and ok
	ok = _nothing_wrong_offers_nothing() and ok
	ok = _no_course_offers_nothing_and_refuses_the_push() and ok
	ok = _a_latent_bite_offers_nothing_and_transmission_changes_nothing() and ok
	ok = _every_offered_row_is_prose() and ok
	ok = _the_body_screen_is_what_pushes_it() and ok
	if ok:
		print("RESPOND_OK antibiotics reachable from the body screen, offered only when it would work, and it never says which infection")
		quit(0)
	else:
		push_error("RESPOND_FAIL")
		quit(1)


# --- fixture ----------------------------------------------------------------------------

# The bare-world shape check_m2_treatment.gd and check_m2_wounds.gd use, for the same reason:
# nothing here needs a kernel, a district or a boot.
func _world(seed_val: int) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 16.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	SimHealth.register_module(w)
	SimWounds.register_module(w)
	SimTreatment.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	SimInventory.make_inventory(w, w.player)
	return w


# A real wound through the real path (the event health.gd and wounds.gd both listen for), then
# stopped and turned septic -- the same two-line fixture check_m2_wounds.gd's SEPSIS COST lane
# uses. Stopped so nothing in these lanes is measuring blood loss.
func _make_septic(w: Variant) -> bool:
	w.events.publish({"type": "attack.connected", "attacker": -1, "target": w.player, "bodyPart": PART, "damage": DEEP_DAMAGE})
	w.step()
	var inj: Variant = w.components.get_component(w.player, "injuries")
	if not (inj is Dictionary):
		return false
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	if wounds.is_empty():
		return false
	var wd: Dictionary = wounds[0] as Dictionary
	wd["bleeding"] = false
	wd["septic"] = true
	return bool(SimWounds.is_septic(w, w.player))


# One exposure, at whatever stage the caller wants and with transmission the caller's business.
# Written directly rather than through a bite, because the point of the NO LEAK lane is to hold
# every field but one fixed and a rolled transmission cannot be held.
func _expose(w: Variant, stage: int, transmitted: bool) -> void:
	w.components.set_component(w.player, "zombieInfection", {"exposures": [{
		"source": -1,
		"bodyPart": PART,
		"exposedAtTick": int(w.tick),
		"transmitted": transmitted,
		"stage": stage,
		"stageEnteredAtTick": int(w.tick),
		"cauterized": false,
		"amputated": false,
	}]})


func _give_course(w: Variant, count: int) -> int:
	var item: int = SimItems.spawn_item(w, SimInfection.ANTIBIOTICS_ID, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, w.player, item):
		return -1
	return item


func _stack_count(w: Variant, item: int) -> int:
	var stk: Variant = w.components.get_component(item, "stack")
	if not (stk is Dictionary):
		return -1
	return int((stk as Dictionary).get("count", 0))


func _courses_recorded(w: Variant) -> int:
	var st: Variant = w.components.get_component(w.player, "zombieInfection")
	if not (st is Dictionary):
		return 0
	return ((st as Dictionary).get("antibioticsCourses", []) as Array).size()


# Events go into an Array because a GDScript lambda captures an `int` or a `bool` by value and an
# accumulator written inside a handler reads back unchanged -- CLAUDE.md's trap, and the one whose
# failure mode is the gate going red and blaming the code under test.
func _watch(w: Variant, type: String, sink: Array) -> void:
	w.events.subscribe({"id": "gate.watch." + type, "type": type, "handler": func(event: Dictionary) -> void:
		sink.append(event)
	})


func _digits(text: String) -> String:
	var found: String = ""
	for c in text:
		if c >= "0" and c <= "9":
			found += c
	return found


# --- lanes ------------------------------------------------------------------------------

# Everything below spends a course out of the pack, so a content tree without one would turn every
# lane here into "the view offered nothing", which is exactly what four of them assert. Judged
# first and loudly rather than left to poison the rest.
func _the_course_is_a_real_item() -> bool:
	var w: Variant = _world(9101)
	var item: int = _give_course(w, COURSE_COUNT)
	if item < 0:
		push_error("could not stow a course in the player's own pack; every lane below has nothing to judge")
		return false
	var base: Variant = SimItems.item_base_of(w, item)
	if not (base is Dictionary) or String((base as Dictionary).get("id", "")) != SimInfection.ANTIBIOTICS_ID:
		push_error("'%s' resolves no content entry; the supply half of the presence rule cannot be exercised" % SimInfection.ANTIBIOTICS_ID)
		return false
	if _stack_count(w, item) != COURSE_COUNT:
		push_error("a course spawned with a stack of %d, not %d -- a spend would not be visible as a decrement" % [_stack_count(w, item), COURSE_COUNT])
		return false
	if not SimInfection.carries_course(w, w.player):
		push_error("a course is in the pack and carries_course says otherwise")
		return false
	print("SUPPLY OK '%s' resolves, stacks to %d, and reads as carried" % [SimInfection.ANTIBIOTICS_ID, COURSE_COUNT])
	return true


# TRUE POSITIVE. A fever and a course in the pack: the word is there, the command the click makes
# spends exactly one course through the real intake, the use event goes out, and the fever it
# answered is gone -- so the word goes with it.
#
# Asserted *after* `step()`, because `events.publish()` only queues and handlers run at `drain()`,
# at the end of the tick. A fixture that pushes a command and reads the result without stepping
# sees nothing.
func _a_symptom_and_a_course_offer_the_word() -> bool:
	var w: Variant = _world(9201)
	if not _make_septic(w):
		push_error("the fixture survivor did not go septic; this lane had nothing to judge")
		return false
	var course: int = _give_course(w, COURSE_COUNT)
	if course < 0:
		push_error("could not stow the course")
		return false

	var rows: Array = SimTreatment.response_view(w, w.player)
	if rows.size() != 1 or String((rows[0] as Dictionary).get("verb", "")) != "antibiotics":
		push_error("a feverish survivor carrying a course was offered %s" % str(rows))
		return false

	var used: Array = []
	var refused: Array = []
	_watch(w, "antibiotics.used", used)
	_watch(w, "treatment.refused", refused)
	# Byte for byte the command the click builds -- see the DEAD SOCKET lane, which is what keeps
	# this string and the panel's the same string.
	w.commands.push({"type": "infection.respond", "verb": "antibiotics"})
	w.step()

	if used.size() != 1:
		push_error("pushing the command the word makes published %d antibiotics.used events, expected 1 (refusals: %s)" % [used.size(), str(refused)])
		return false
	if not refused.is_empty():
		push_error("the offered word was refused: %s" % str(refused))
		return false
	if _stack_count(w, course) != COURSE_COUNT - 1:
		push_error("the stock went %d -> %d; an offered course must cost exactly one" % [COURSE_COUNT, _stack_count(w, course)])
		return false
	if SimWounds.is_septic(w, w.player):
		push_error("a course was spent and the sepsis remained")
		return false
	var after: Array = SimTreatment.response_view(w, w.player)
	if not after.is_empty():
		push_error("the fever is answered and the word is still on offer: %s" % str(after))
		return false
	print("TRUE POSITIVE OK the word appeared, the click's own command spent 1 of %d and published antibiotics.used, and the word went with the fever" % COURSE_COUNT)
	return true


# NO NEED. The other half of the presence rule, with the supply held fixed: a survivor with nothing
# wrong and a full pack is offered nothing. Without this lane a `response_view` that answered "yes"
# on the supply alone would satisfy TRUE POSITIVE exactly.
#
# The true negative rides along: the same world, one fever later, offers the word -- so this is not
# passing because the view is broken.
func _nothing_wrong_offers_nothing() -> bool:
	var w: Variant = _world(9301)
	if _give_course(w, COURSE_COUNT) < 0:
		push_error("could not stow the course")
		return false
	if SimWounds.is_septic(w, w.player) or w.components.get_component(w.player, "zombieInfection") != null:
		push_error("the fixture survivor is not well, so this lane is not the healthy case")
		return false
	if bool(SimInfection.symptom_of(w, w.player, 0).get("symptomatic", false)):
		push_error("a survivor with no wound and no exposure reads as symptomatic")
		return false
	var rows: Array = SimTreatment.response_view(w, w.player)
	if not rows.is_empty():
		push_error("a well survivor with a full pack was offered %s" % str(rows))
		return false

	if not _make_septic(w):
		push_error("the fixture survivor did not go septic; the control for this lane had nothing to judge")
		return false
	var now: Array = SimTreatment.response_view(w, w.player)
	if now.size() != 1:
		push_error("the same survivor, now feverish and still carrying the course, was offered %s" % str(now))
		return false
	print("NO NEED OK a full pack alone offers nothing; the same pack with a fever under it offers the word")
	return true


# NO SUPPLY, and the free-course hole. Both stocks, because the whole reason antibiotics have one
# stock is that the player must not learn which infection they have from what the sim charges them:
#
#   * a symptomatic bite with an empty pack, which is the lane that is **red against the sim this
#     landed with** -- `use_antibiotics`' zombie-infection path recorded a course whether or not an
#     item was spent, so a forced push succeeded, published `antibiotics.used`, and wrote a course
#     into `antibioticsCourses` out of nothing;
#   * a fever with an empty pack, which the sepsis path has always refused.
#
# Both must come back with the same word. A refusal that differed by cause would leak exactly what
# the button lighting up would have leaked.
#
# The positive control closes it: hand the same bitten survivor a course and the identical push
# now works, so this is not a sim that refuses everything.
func _no_course_offers_nothing_and_refuses_the_push() -> bool:
	var reasons: Array[String] = []
	for case in [{"what": "a symptomatic bite", "bite": true}, {"what": "a fever", "bite": false}]:
		var w: Variant = _world(9401 + (1 if bool(case["bite"]) else 2))
		if bool(case["bite"]):
			_expose(w, SimInfection.Stage.Onset, true)
		elif not _make_septic(w):
			push_error("the fixture survivor did not go septic; the sepsis half of this lane had nothing to judge")
			return false
		if not bool(SimInfection.symptom_of(w, w.player, 0).get("symptomatic", false)):
			push_error("%s does not read as symptomatic; this lane is judging the wrong thing" % case["what"])
			return false
		if SimInfection.carries_course(w, w.player):
			push_error("%s: the fixture survivor is carrying a course, so this is not the empty-pack case" % case["what"])
			return false

		var rows: Array = SimTreatment.response_view(w, w.player)
		if not rows.is_empty():
			push_error("%s with an empty pack was offered %s" % [case["what"], str(rows)])
			return false

		var used: Array = []
		var refused: Array = []
		_watch(w, "antibiotics.used", used)
		_watch(w, "treatment.refused", refused)
		w.commands.push({"type": "infection.respond", "verb": "antibiotics"})
		w.step()

		if not used.is_empty():
			push_error("%s with nothing in the pack was dosed anyway: %s" % [case["what"], str(used)])
			return false
		if refused.size() != 1:
			push_error("%s: %d refusals published, expected exactly 1" % [case["what"], refused.size()])
			return false
		if _courses_recorded(w) != 0:
			push_error("%s: %d courses recorded with nothing spent -- a course out of thin air" % [case["what"], _courses_recorded(w)])
			return false
		reasons.append(String((refused[0] as Dictionary).get("reason", "")))

	if reasons[0] != "no-antibiotics" or reasons[1] != "no-antibiotics":
		push_error("the empty pack was refused %s, expected SimInfection's own 'no-antibiotics' for both" % str(reasons))
		return false

	# The control. Same survivor, same push, one course in the pack.
	var w2: Variant = _world(9411)
	_expose(w2, SimInfection.Stage.Onset, true)
	var course: int = _give_course(w2, COURSE_COUNT)
	if course < 0:
		push_error("could not stow the course for the control")
		return false
	var used2: Array = []
	_watch(w2, "antibiotics.used", used2)
	w2.commands.push({"type": "infection.respond", "verb": "antibiotics"})
	w2.step()
	if used2.size() != 1 or _stack_count(w2, course) != COURSE_COUNT - 1:
		push_error("the bitten survivor with a course in the pack was not dosed: %d events, stock %d" % [used2.size(), _stack_count(w2, course)])
		return false
	print("NO SUPPLY OK both stocks refuse '%s' with nothing spent and no course recorded; the same push with a course in the pack doses and costs one" % reasons[0])
	return true


# NO LEAK. The presence rule reads the diagnosis, never `transmitted`, and this asserts it the
# strong way rather than the convenient way: the offered rows are a function of the *stage* alone,
# so two worlds identical but for the one hidden field produce identical views at every stage.
#
#   Latent, transmitted true and false  -> "clear", and nothing offered. A bitten survivor with no
#                                          symptom yet gets no word, which is the half of this
#                                          slice that deliberately did not ship a surface.
#   Onset, transmitted true and false   -> the word, both times.
#
# A view that peeked at `transmitted` would offer the word to the first world and not the second,
# and both halves of this lane would go red.
func _a_latent_bite_offers_nothing_and_transmission_changes_nothing() -> bool:
	for stage in [SimInfection.Stage.Latent, SimInfection.Stage.Onset]:
		var seen: Array[String] = []
		var labels: Array[String] = []
		for transmitted in [true, false]:
			var w: Variant = _world(9501 + int(stage) * 10 + (1 if transmitted else 2))
			_expose(w, int(stage), transmitted)
			if _give_course(w, COURSE_COUNT) < 0:
				push_error("could not stow the course")
				return false
			labels.append(String(SimInfection.diagnosis_of(w, w.player, 0).get("label", "")))
			seen.append(str(SimTreatment.response_view(w, w.player)))
		if seen[0] != seen[1]:
			push_error("stage %d offered %s when the bite transmitted and %s when it did not -- the surface can tell them apart" % [stage, seen[0], seen[1]])
			return false
		if labels[0] != labels[1]:
			push_error("stage %d diagnosed '%s' / '%s'; the read model itself leaks transmission" % [stage, labels[0], labels[1]])
			return false
		var offered: bool = seen[0] != "[]"
		if stage == SimInfection.Stage.Latent:
			if labels[0] != "clear":
				push_error("a latent exposure diagnosed '%s'; this lane assumed the read model calls it clear" % labels[0])
				return false
			if offered:
				push_error("a latent bite with a course in the pack was offered %s -- suspicion dosing has no surface by design" % seen[0])
				return false
		elif not offered:
			push_error("an onset exposure with a course in the pack was offered nothing; the leak lane above would pass on a view that never offers anything")
			return false
	print("NO LEAK OK latent reads clear and offers nothing, onset offers the word, and `transmitted` moves neither")
	return true


# PROSE. Every row the screen can draw carries no digit -- check_hud.gd's rule and its scanner,
# because this text lands on a player-facing surface and the ban is on the surface, not on the HUD
# control. A count, a dose or a day would all fail it.
#
# The true negative is the scanner itself: an absence assertion passes just as happily when the
# thing doing the looking is broken.
func _every_offered_row_is_prose() -> bool:
	var rows: Array = []
	var w: Variant = _world(9601)
	if not _make_septic(w):
		push_error("the fixture survivor did not go septic; this lane had no rows to judge")
		return false
	if _give_course(w, COURSE_COUNT) < 0:
		push_error("could not stow the course")
		return false
	rows.append_array(SimTreatment.response_view(w, w.player))
	var w2: Variant = _world(9602)
	_expose(w2, SimInfection.Stage.Critical, true)
	if _give_course(w2, COURSE_COUNT) < 0:
		push_error("could not stow the course")
		return false
	rows.append_array(SimTreatment.response_view(w2, w2.player))
	if rows.is_empty():
		push_error("no rows were offered anywhere; this lane had nothing to judge")
		return false
	for row in rows:
		var d: Dictionary = row as Dictionary
		var text: String = String(d.get("text", ""))
		if text.strip_edges().is_empty():
			push_error("an offered row carries no words at all: %s" % str(d))
			return false
		if not _digits(text).is_empty():
			push_error("an offered row carries digits (%s): '%s'" % [_digits(text), text])
			return false
	for must_fail in ["take 2 antibiotics", "6 doses left", "antibiotics x1"]:
		if _digits(must_fail).is_empty():
			push_error("the digit scanner passed a row it exists to catch: '%s'" % must_fail)
			return false
	print("PROSE OK %d offered rows, all words; the scanner still catches the three it should" % rows.size())
	return true


# DEAD SOCKET. Everything above is true of a read model nothing draws -- which is the state
# `infection.respond` was already in, as a command handler nothing pushed. The chain has to be
# whole: the screen draws the view, the view's rows become click rects, and a click on one pushes
# the command. None of it can be exercised headless (it is a CanvasItem draw pass and a mouse
# event), so what the functions contain is read, the way check_topdown.gd reads main.gd.
func _the_body_screen_is_what_pushes_it() -> bool:
	var needles: Array[Dictionary] = [
		{"func": "_draw", "needle": "_draw_responses(", "why": "the body screen never draws the responses"},
		{"func": "_draw_responses", "needle": "SimTreatment.response_view(", "why": "the rows are not the sim's read model"},
		{"func": "_draw_responses", "needle": "_hit.append(", "why": "the drawn words become no click target"},
		{"func": "_press_at", "needle": "_hit", "why": "a press never looks at the words"},
		{"func": "_press_at", "needle": "\"infection.respond\"", "why": "a click on the word pushes no command"},
	]
	for n in needles:
		var body: String = _function_body(PANEL_GD, String(n["func"]))
		if body.is_empty():
			push_error("could not read %s out of %s -- this assertion had nothing to judge" % [n["func"], PANEL_GD])
			return false
		if not body.contains(String(n["needle"])):
			push_error("%s does not contain %s: %s" % [n["func"], n["needle"], n["why"]])
			return false
	# And the verb the panel pushes has to be one the router answers, or the word is a button that
	# publishes a refusal.
	if not SimTreatment.INSTANT_VERBS.has("antibiotics"):
		push_error("'antibiotics' is not among the verbs SimTreatment.respond routes: %s" % str(SimTreatment.INSTANT_VERBS))
		return false
	print("DEAD SOCKET OK draw -> response_view -> click rects -> `infection.respond`, and the router answers the verb")
	return true


# The source text of one function, from its `func` line to the next top-level `func`.
# check_topdown.gd's, unchanged -- the same reach assertion needs the same reader.
func _function_body(path: String, name: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var out: String = ""
	var inside: bool = false
	for line in lines:
		if line.begins_with("func %s(" % name):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out
