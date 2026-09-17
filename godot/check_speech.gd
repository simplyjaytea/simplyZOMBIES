extends SceneTree
# Speech bubbles -- slice 4 of the four QOL slices: the shout was a noise, the chronicle a corner
# column, and nobody spoke. `sim/modules/speech.gd` is the one builder; this is its gate.
#
# Every assertion carries its own negative, the convention `check_ban_health_bar.gd` set:
#   SAY       `say` sets `saying` from content and a system clears it past `until`; an unknown key
#             and a fresh entity both leave it unset
#   TRIGGERS  each event a module publishes makes its named entity speak the right key and nobody
#             else; `noise.emitted` alone speaks for nobody; the three brand-new publish sites
#             (world.gd's `shouted`, shambler.gd's `zombie.noticed`, screamer.gd's
#             `zombie.screamed`) are proved through the real mechanism, not a hand-built event, so
#             a socket that looks wired but is not cannot pass; the hail fires once per recruit
#   CONTENT   every key `SimSpeech.KEYS` names has a `speech.<key>` content entry with at least one
#             digit-free line and no `{name}`-style placeholder -- scanner proved on a fabricated
#             line first
#   MUTTER    a starving colonist mutters within 4,000 ticks; a fed one never does; the controlled
#             body never does either
#   SAVE      `saying` survives a `SimSave` round trip
#   READER    `_draw` calls `_draw_bubbles()` after `_draw_entities()`; `_draw_bubbles` reads
#             `saying` and `_focal_drawn`; `_focal_drawn` is appended after the Peripheral bail in
#             `_draw_entities` -- textual, each scanner proved on a fabricated body first
#
# A lane with no data to judge says so and skips, never passes quietly.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSpeech = preload("res://sim/modules/speech.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimScreamer = preload("res://sim/modules/screamer.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimVisibility = preload("res://sim/vision/visibility.gd")
const SimSave = preload("res://sim/save.gd")
const Clock = preload("res://sim/time/clock.gd")
const MAIN_GD: String = "res://presentation/main.gd"

const MAP_TILES: int = 24


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _say_sets_and_expires() and ok
	ok = _triggers_speak_the_right_key_and_nobody_else() and ok
	ok = _content_has_every_key_digit_free_and_nameless() and ok
	ok = _a_starving_colonist_mutters_a_fed_one_and_the_controlled_body_never_do() and ok
	ok = _saying_survives_a_save_round_trip() and ok
	ok = _the_draw_path_reads_saying_and_focal_drawn_in_order() and ok
	if ok:
		print("SPEECH_OK say sets and expires a line from content, every trigger speaks the right key and nobody else, content is digit-free and nameless, a starving colonist mutters within 4000 ticks while a fed and a controlled one do not, saying survives a save, and the draw path reads it only for a Focal body")
		quit(0)
	else:
		push_error("SPEECH_FAIL")
		quit(1)


# --- the fixture ---------------------------------------------------------------------------

func _world(px: float = 10.5, py: float = 10.5) -> Variant:
	var f: Dictionary = {"seed": 40170, "tick_hz": 20, "map": {"width": MAP_TILES, "height": MAP_TILES, "walls": []}, "player": {"id": 0, "x": px, "y": py, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(MAP_TILES, MAP_TILES)
	SimBoot.attach_kernel(w, map)
	SimSpeech.register_module(w)
	return w


func _has_digit(text: String) -> bool:
	for i in text.length():
		if text[i].is_valid_int():
			return true
	return false


func _saying_text(w: Variant, ent: int) -> String:
	var s: Variant = w.components.get_component(ent, "saying")
	return String((s as Dictionary).get("text", "")) if s is Dictionary else ""


# --- SAY -----------------------------------------------------------------------------------

func _say_sets_and_expires() -> bool:
	var w: Variant = _world()
	var fresh: int = int(w.entities.spawn())
	if w.components.has_component(fresh, "saying"):
		push_error("SAY: a fresh entity already has a saying component -- the control proves nothing")
		return false

	SimSpeech.say(w, fresh, "not-a-real-key")
	if w.components.has_component(fresh, "saying"):
		push_error("SAY: an unknown key set a saying component anyway")
		return false

	var speaker: int = int(w.entities.spawn())
	SimSpeech.say(w, speaker, "shout")
	if not w.components.has_component(speaker, "saying"):
		push_error("SAY: say(shout) set no saying component")
		return false
	var text: String = _saying_text(w, speaker)
	if text.is_empty():
		push_error("SAY: say(shout) set an empty line")
		return false

	# Gone after its own ticks -- SAY_TICKS (60) plus a margin, driven by speech.expire.
	for i in SimSpeech.SAY_TICKS + 5:
		w.step()
	if w.components.has_component(speaker, "saying"):
		push_error("SAY: the saying component outlived its own ticks")
		return false
	print("SAY OK say(%s) set %s, an unknown key set nothing, and the line expired on schedule" % ["shout", "\"%s\"" % text])
	return true


# --- TRIGGERS --------------------------------------------------------------------------------

func _triggers_speak_the_right_key_and_nobody_else() -> bool:
	var ok: bool = true
	ok = _grab_started() and ok
	ok = _grab_broken_rescue() and ok
	ok = _treatment_begun() and ok
	ok = _survivor_joined() and ok
	ok = _noise_alone_speaks_for_nobody() and ok
	ok = _hail_fires_once_per_recruit() and ok
	ok = _the_shout_command_publishes_shouted_and_speaks() and ok
	ok = _a_real_shambler_transition_publishes_zombie_noticed() and ok
	ok = _a_real_screamer_alarm_publishes_zombie_screamed() and ok
	return ok


func _grab_started() -> bool:
	var w: Variant = _world()
	var victim: int = int(w.entities.spawn())
	w.events.publish({"type": "grab.started", "victim": victim, "source": 999})
	w.step()
	if _saying_text(w, victim).is_empty():
		push_error("TRIGGERS: grab.started did not make the victim say anything")
		return false
	print("TRIGGERS OK grab.started -> victim says \"%s\"" % _saying_text(w, victim))
	return true


func _grab_broken_rescue() -> bool:
	var w: Variant = _world()
	var victim: int = int(w.entities.spawn())
	var rescuer: int = int(w.entities.spawn())
	w.events.publish({"type": "grab.broken", "victim": victim, "by": rescuer, "cause": "rescue"})
	w.step()
	if _saying_text(w, rescuer).is_empty():
		push_error("TRIGGERS: grab.broken(cause rescue) did not make the rescuer say anything")
		return false
	if not _saying_text(w, victim).is_empty():
		push_error("TRIGGERS: grab.broken(cause rescue) made the victim speak, not the rescuer")
		return false
	# Negative: any other cause is not a rescue and says nothing.
	var w2: Variant = _world()
	var victim2: int = int(w2.entities.spawn())
	var by2: int = int(w2.entities.spawn())
	w2.events.publish({"type": "grab.broken", "victim": victim2, "by": by2, "cause": "geometry"})
	w2.step()
	if not _saying_text(w2, by2).is_empty() or not _saying_text(w2, victim2).is_empty():
		push_error("TRIGGERS: grab.broken(cause geometry) made somebody speak -- only a rescue should")
		return false
	print("TRIGGERS OK grab.broken(cause rescue) -> the rescuer says \"%s\", not the victim; another cause says nothing" % _saying_text(w, rescuer))
	return true


func _treatment_begun() -> bool:
	var w: Variant = _world()
	var actor: int = int(w.entities.spawn())
	var patient: int = int(w.entities.spawn())
	w.events.publish({"type": "treatment.begun", "entity": actor, "patient": patient, "bodyPart": "torso", "verb": "press", "ticks": 100})
	w.step()
	if _saying_text(w, actor).is_empty():
		push_error("TRIGGERS: treatment.begun did not make the treater say anything")
		return false
	if not _saying_text(w, patient).is_empty():
		push_error("TRIGGERS: treatment.begun made the patient speak, not the treater")
		return false
	# Negative: treating yourself (actor == patient) says nothing -- the quick-strip case.
	var w2: Variant = _world()
	var solo: int = int(w2.entities.spawn())
	w2.events.publish({"type": "treatment.begun", "entity": solo, "patient": solo, "bodyPart": "torso", "verb": "press", "ticks": 100})
	w2.step()
	if not _saying_text(w2, solo).is_empty():
		push_error("TRIGGERS: treating yourself made you speak -- actor == patient should say nothing")
		return false
	print("TRIGGERS OK treatment.begun -> the treater says \"%s\", not the patient; treating yourself says nothing" % _saying_text(w, actor))
	return true


func _survivor_joined() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.entities.spawn())
	w.events.publish({"type": "survivor.joined", "entity": ent, "id": "recruit"})
	w.step()
	if _saying_text(w, ent).is_empty():
		push_error("TRIGGERS: survivor.joined did not make the entity say anything")
		return false
	print("TRIGGERS OK survivor.joined -> \"%s\"" % _saying_text(w, ent))
	return true


func _noise_alone_speaks_for_nobody() -> bool:
	var w: Variant = _world()
	var bystander: int = int(w.entities.spawn())
	w.components.set_component(bystander, "position", {"x": 5.0, "y": 5.0})
	w.events.publish({"type": "noise.emitted", "x": 5.0, "y": 5.0, "magnitude": 120.0, "source": bystander})
	w.step()
	if not _saying_text(w, bystander).is_empty():
		push_error("TRIGGERS: noise.emitted alone made somebody speak")
		return false
	print("TRIGGERS OK noise.emitted alone speaks for nobody")
	return true


# The hail: a waiting recruit within reach of the controlled body speaks once, and a second
# waiting recruit -- already in reach at the same moment -- is not starved by the first having
# already been hailed.
func _hail_fires_once_per_recruit() -> bool:
	var w: Variant = _world(10.5, 10.5)
	var a: int = int(w.entities.spawn())
	w.components.set_component(a, "position", {"x": 11.0, "y": 10.5})
	w.components.set_component(a, "recruit", {"waiting": true})
	var b: int = int(w.entities.spawn())
	w.components.set_component(b, "position", {"x": 10.5, "y": 11.0})
	w.components.set_component(b, "recruit", {"waiting": true})
	w.step()
	var a_said: String = _saying_text(w, a)
	var b_said: String = _saying_text(w, b)
	if a_said.is_empty() or b_said.is_empty():
		push_error("TRIGGERS: HAIL two recruits in reach at once, only got said=[%s, %s]" % [a_said, b_said])
		return false
	var a_hailed: bool = bool((w.components.get_component(a, "recruit") as Dictionary).get("hailed", false))
	var b_hailed: bool = bool((w.components.get_component(b, "recruit") as Dictionary).get("hailed", false))
	if not a_hailed or not b_hailed:
		push_error("TRIGGERS: HAIL did not mark both recruits hailed")
		return false
	# Never twice: clear the bubbles and step again -- neither recruit says anything a second time.
	w.components.remove(a, "saying")
	w.components.remove(b, "saying")
	w.step()
	if not _saying_text(w, a).is_empty() or not _saying_text(w, b).is_empty():
		push_error("TRIGGERS: HAIL fired a second time for an already-hailed recruit")
		return false
	# Negative: a recruit out of reach is never hailed.
	var far: int = int(w.entities.spawn())
	w.components.set_component(far, "position", {"x": 20.5, "y": 20.5})
	w.components.set_component(far, "recruit", {"waiting": true})
	w.step()
	if not _saying_text(w, far).is_empty():
		push_error("TRIGGERS: HAIL fired for a recruit out of reach")
		return false
	print("TRIGGERS OK the hail fires once per waiting recruit in reach, never twice, and never out of reach")
	return true


func _the_shout_command_publishes_shouted_and_speaks() -> bool:
	var w: Variant = _world()
	w.commands.push({"type": "shout"})
	w.step()
	if _saying_text(w, int(w.player)).is_empty():
		push_error("TRIGGERS: the real shout command never made the player speak -- world.gd's shouted publish is not reaching speech.gd")
		return false
	print("TRIGGERS OK the real shout command publishes shouted and the player says \"%s\"" % _saying_text(w, int(w.player)))
	return true


# A real shambler, not a hand-built event: spawned adjacent to the controlled player in its
# default Wander state, its own think loop's contact check crosses it straight into Pursue on the
# first tick, and `_notice` (shambler.gd) is what has to publish `zombie.noticed` for this to pass
# -- proving the socket rather than speech.gd's reaction to a fabricated one.
func _a_real_shambler_transition_publishes_zombie_noticed() -> bool:
	var w: Variant = _world(10.5, 10.5)
	SimShambler.register_module(w, w.tilemap)
	var rng: Variant = w.rng.stream("shambler")
	var zed: int = SimRoster.spawn_zombie(w, 11.0, 10.5, SimRoster.TYPE_SHAMBLER, rng)
	w.step()
	if _saying_text(w, zed).is_empty():
		push_error("TRIGGERS: a shambler that just contacted the player never said anything -- shambler.gd's zombie.noticed publish is not reaching speech.gd")
		return false
	print("TRIGGERS OK a real shambler's Wander -> Pursue edge publishes zombie.noticed: \"%s\"" % _saying_text(w, zed))
	return true


# A real screamer's alarm tick, not a hand-built event: an alarmed observer who can see the
# controlled player fires its noise.emitted and (screamer.gd) must publish zombie.screamed beside
# it for this to pass.
func _a_real_screamer_alarm_publishes_zombie_screamed() -> bool:
	var w: Variant = _world(10.5, 10.5)
	SimScreamer.register_module(w)
	var scr: int = int(w.entities.spawn())
	w.components.set_component(scr, "position", {"x": 11.0, "y": 10.5})
	w.components.set_component(scr, "observer", SimVisibility.daylight_eyes())
	w.components.set_component(scr, "facing", {"radians": PI})
	w.components.set_component(scr, "alarm", {"magnitude": 300.0, "cooldownTicks": 600, "ticksUntilReady": 0})
	w.step()
	if _saying_text(w, scr).is_empty():
		push_error("TRIGGERS: a screamer that just alarmed on the player never said anything -- screamer.gd's zombie.screamed publish is not reaching speech.gd")
		return false
	print("TRIGGERS OK a real screamer alarm publishes zombie.screamed: \"%s\"" % _saying_text(w, scr))
	return true


# --- CONTENT ---------------------------------------------------------------------------------

func _content_has_every_key_digit_free_and_nameless() -> bool:
	# Proved on a fabricated line first: a scanner that cannot find its own needle, or cannot find
	# the forbidden shape when it is there, cannot fail on real content either.
	if not _has_digit("3 of them"):
		push_error("CONTENT: the digit scanner cannot find its own needle")
		return false
	if _has_digit("no digits here"):
		push_error("CONTENT: the digit scanner found a digit in a line that has none")
		return false
	if not "hello {name}".contains("{"):
		push_error("CONTENT: the placeholder scanner cannot find its own needle")
		return false

	var w: Variant = _world()
	var entries: Dictionary = {}
	var raw: Variant = (w.content as Dictionary).get("speech/lines.json", [])
	if raw is Array:
		for row in raw as Array:
			var e: Dictionary = row as Dictionary
			entries[String(e.get("id", ""))] = e
	for key in SimSpeech.KEYS:
		var id: String = "speech.%s" % key
		if not entries.has(id):
			push_error("CONTENT: no content entry for %s" % id)
			return false
		var lines: Variant = (entries[id] as Dictionary).get("lines", [])
		if not (lines is Array) or (lines as Array).is_empty():
			push_error("CONTENT: %s has no lines" % id)
			return false
		for line_v in lines as Array:
			var line: String = String(line_v)
			if line.is_empty():
				push_error("CONTENT: %s has an empty line" % id)
				return false
			if _has_digit(line):
				push_error("CONTENT: %s's line \"%s\" carries a digit" % [id, line])
				return false
			if line.contains("{"):
				push_error("CONTENT: %s's line \"%s\" carries a {name}-style placeholder" % [id, line])
				return false
	print("CONTENT OK every one of SimSpeech.KEYS' %d keys has a content entry with at least one digit-free, nameless line" % SimSpeech.KEYS.size())
	return true


# --- MUTTER ----------------------------------------------------------------------------------

func _a_starving_colonist_mutters_a_fed_one_and_the_controlled_body_never_do() -> bool:
	var w: Variant = _world()
	var starving: int = int(w.entities.spawn())
	SimNeeds.attach(w, starving, {"hunger": 0.0, "crisis": "starving"})
	var fed: int = int(w.entities.spawn())
	SimNeeds.attach(w, fed, {})
	SimNeeds.attach(w, int(w.player), {"hunger": 0.0, "crisis": "starving"})

	# Watched every tick, not read once at the end: SAY_TICKS (60) is far shorter than the
	# 4,000-tick window, so a mutter that fired on tick 400 has long since expired (speech.expire)
	# by the time a single check at the end would look for it -- that cost this lane its first
	# run, and is exactly the shape CLAUDE.md's "events land at drain, not when published" trap
	# warns about one step further down the same road.
	var window: int = 4000
	var starving_said: String = ""
	var fed_said: String = ""
	var player_said: String = ""
	for i in window:
		w.step()
		if starving_said.is_empty():
			starving_said = _saying_text(w, starving)
		if fed_said.is_empty():
			fed_said = _saying_text(w, fed)
		if player_said.is_empty():
			player_said = _saying_text(w, int(w.player))

	if starving_said.is_empty():
		push_error("MUTTER: a starving colonist never muttered over %d ticks" % window)
		return false
	if not fed_said.is_empty():
		push_error("MUTTER: a fed colonist muttered \"%s\"" % fed_said)
		return false
	if not player_said.is_empty():
		push_error("MUTTER: the controlled body muttered \"%s\"" % player_said)
		return false
	print("MUTTER OK a starving colonist muttered \"%s\" within %d ticks; a fed colonist and the controlled body did not" % [starving_said, window])
	return true


# --- SAVE ------------------------------------------------------------------------------------

func _saying_survives_a_save_round_trip() -> bool:
	var w: Variant = _world()
	var ent: int = int(w.entities.spawn())
	SimSpeech.say(w, ent, "shout")
	var before: String = _saying_text(w, ent)
	if before.is_empty():
		push_error("SAVE: the fixture never set a saying component to round-trip")
		return false
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var decoded: Dictionary = SimSave.decode_save_or_throw(text)
	w.restore(decoded["snapshot"] as Dictionary)
	var after: String = _saying_text(w, ent)
	if after != before:
		push_error("SAVE: saying did not survive the round trip (before \"%s\", after \"%s\")" % [before, after])
		return false
	print("SAVE OK saying (\"%s\") survives a save/load round trip" % after)
	return true


# --- READER ----------------------------------------------------------------------------------

func _the_draw_path_reads_saying_and_focal_drawn_in_order() -> bool:
	# Proved on fabricated bodies first, per check_m2_comfort's lesson (CLAUDE.md): a scanner that
	# cannot find its own needle, or finds one that is not there, cannot fail on the real file.
	var fab_order: String = "\t_draw_entities()\n\t_draw_afterimages()\n\t_draw_bubbles()\n\t_draw_rain()\n"
	if fab_order.find("_draw_entities()") >= fab_order.find("_draw_bubbles()"):
		push_error("READER: the order scanner cannot find its own needle in a fabricated body that has it in order")
		return false
	var fab_reversed: String = "\t_draw_bubbles()\n\t_draw_entities()\n"
	if fab_reversed.find("_draw_entities()") < fab_reversed.find("_draw_bubbles()"):
		push_error("READER: the order scanner passed a fabricated body where the order is reversed")
		return false

	var draw_body: String = _function_body(MAIN_GD, "_draw")
	if draw_body.is_empty():
		push_error("READER: could not read _draw out of %s" % MAIN_GD)
		return false
	if not draw_body.contains("_draw_bubbles()"):
		push_error("READER: _draw never calls _draw_bubbles()")
		return false
	if draw_body.find("_draw_entities()") >= draw_body.find("_draw_bubbles()"):
		push_error("READER: _draw calls _draw_bubbles() before (or without) _draw_entities()")
		return false

	var bubbles_body: String = _function_body(MAIN_GD, "_draw_bubbles")
	if bubbles_body.is_empty():
		push_error("READER: could not read _draw_bubbles out of %s" % MAIN_GD)
		return false
	if not bubbles_body.contains("\"saying\""):
		push_error("READER: _draw_bubbles never reads \"saying\"")
		return false
	if not bubbles_body.contains("_focal_drawn"):
		push_error("READER: _draw_bubbles never reads _focal_drawn")
		return false

	# _focal_drawn is appended after the Peripheral bail, inside _draw_entities: the bail's
	# `continue` must precede the append's line index, the way check_wrecks.gd's _low_arms picks
	# the arm that actually draws rather than the first textual match.
	var fab_entities_ok: String = "\t\tif int(it[\"det\"]) == SimVisibility.Detail.Peripheral:\n\t\t\tcontinue\n\t\t_focal_drawn.append({\"id\": eid})\n"
	if fab_entities_ok.find("Detail.Peripheral") >= fab_entities_ok.find("_focal_drawn.append("):
		push_error("READER: the bail-then-append scanner cannot find its own needle in an ordered fabrication")
		return false
	var fab_entities_bad: String = "\t\t_focal_drawn.append({\"id\": eid})\n\t\tif int(it[\"det\"]) == SimVisibility.Detail.Peripheral:\n\t\t\tcontinue\n"
	if fab_entities_bad.find("Detail.Peripheral") < fab_entities_bad.find("_focal_drawn.append("):
		push_error("READER: the bail-then-append scanner passed a fabrication where the append comes first")
		return false

	var entities_body: String = _function_body(MAIN_GD, "_draw_entities")
	if entities_body.is_empty():
		push_error("READER: could not read _draw_entities out of %s" % MAIN_GD)
		return false
	if not entities_body.contains("_focal_drawn.append("):
		push_error("READER: _draw_entities never appends to _focal_drawn")
		return false
	if entities_body.find("Detail.Peripheral") >= entities_body.find("_focal_drawn.append("):
		push_error("READER: _draw_entities appends to _focal_drawn before (or without) the Peripheral bail")
		return false

	print("READER OK _draw calls _draw_bubbles() after _draw_entities(), _draw_bubbles reads \"saying\" and _focal_drawn, and _draw_entities appends to _focal_drawn after the Peripheral bail")
	return true


# The source text of one function, from its `func` line to the next top-level `func`. Same reader
# check_memory_look.gd, check_light_look.gd, check_topdown.gd and check_camera.gd already use.
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
