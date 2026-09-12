extends SceneTree
# The gunsmithing bench: a place, and what the place is for.
#
# Everything this judges is about *where*. `SimAttachments` has known how to fit a part since the
# attachment slice and `SimModification` has known how to reroll an affix for longer than that;
# what neither had was a reason to go home, and both were reachable only from a gate. This asserts
# that the bench gets built through the same ladder that boards a window, that it costs materials
# and time and can be interrupted, and that the commands the screen pushes ask for it -- except
# for the parts content says a person can change with their hands.
#
# Every lane runs on its own world. The `and ok` order is deliberate: one red lane must not hide
# the five behind it.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimModification = preload("res://sim/modules/modification.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const SimSerialize = preload("res://sim/kernel/serialize.gd")
const Clock = preload("res://sim/time/clock.gd")

const PISTOL: String = "item.pistol.service"
const SUPPRESSOR: String = "item.attach.suppressor"
const STD_BARREL: String = "item.part.barrel.standard"
const LONG_BARREL: String = "item.attach.barrel.long"
const SCRAP: String = "item.scrap.metal"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _a_bench_is_built_from_scrap_and_time() and ok
	ok = _a_channel_that_is_interrupted_builds_nothing() and ok
	ok = _nobody_holds_two_jobs_at_once() and ok
	ok = _structural_work_wants_the_bench_and_a_magazine_does_not() and ok
	ok = _the_affix_bench_is_the_same_bench() and ok
	ok = _a_bench_survives_a_save() and ok
	ok = _every_field_has_a_direction_and_the_direction_is_read() and ok
	ok = _the_screen_is_handed_words_and_handles_and_nothing_else() and ok
	ok = _the_panel_pushes_what_the_sim_answers() and ok
	if ok:
		print("M2_BENCH_OK build channel exclusive refuse modify save polarity view panel")
		quit(0)
	else:
		push_error("M2_BENCH_FAIL")
		quit(1)


func _world() -> Variant:
	var f: Dictionary = {"seed": 53, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	SimBoot.attach_kernel(w, SimTileMap.blank_map(24, 24))
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimAttachments.register_module(w)
	SimFortify.register_module(w)
	SimModification.register_module(w)
	SimGunsmith.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	SimSkills.attach(w, w.player)
	return w


func _give_scrap(w: Variant, count: int) -> void:
	var scrap: int = SimItems.spawn_item(w, SCRAP, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, w.player, scrap):
		w.components.set_component(scrap, "stored", {"container": w.player})
	w.events.drain()


func _benches(w: Variant) -> int:
	return (w.components.query(["workbench"]) as Array).size()


func _facing_tile(w: Variant) -> Vector2i:
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	return Vector2i(floori(float(pos["x"])) + 1, floori(float(pos["y"])))


# --- BUILD ------------------------------------------------------------------------------------
#
# It is furniture and it is built the way the boarding is: the same command vocabulary, the same
# channel, the same material. The true negative is the same press with an empty pack -- a bench
# that could be conjured is not a colony investment, which is the whole reason it is a place.
func _a_bench_is_built_from_scrap_and_time() -> bool:
	var lane: String = "BUILD"
	var w: Variant = _world()
	_give_scrap(w, SimGunsmith.BENCH_SCRAP)
	var tile: Vector2i = _facing_tile(w)
	w.commands.push({"type": "bench.build", "tx": tile.x, "ty": tile.y})
	w.step()
	if not w.components.has_component(w.player, "construct"):
		push_error("%s: a press with materials in hand started no channel" % lane)
		return false
	# It takes time, and the figure is the module's own rather than a number copied here.
	var started: int = int((w.components.get_component(w.player, "construct") as Dictionary)["ticksLeft"])
	if started < SimFortify.CHANNEL_TICKS:
		push_error("%s: a bench channel is %d ticks, no longer than a plank across a window" % [lane, started])
		return false
	for i in SimGunsmith.BENCH_TICKS + 4:
		w.step()
		if _benches(w) > 0:
			break
	if _benches(w) != 1:
		push_error("%s: %d benches after a full channel" % [lane, _benches(w)])
		return false
	if SimGunsmith.bench_in_reach(w, w.player) < 0:
		push_error("%s: the bench was built out of reach of the person who built it" % lane)
		return false
	if SimFortify.material_count(w, w.player, SimFortify.recipe_kind("bench")) != 0:
		push_error("%s: the bench cost %d scrap, not %d" % [lane, SimGunsmith.BENCH_SCRAP - SimFortify.material_count(w, w.player, SimFortify.recipe_kind("bench")), SimGunsmith.BENCH_SCRAP])
		return false

	# TN: one scrap short is no channel and no bench.
	var w2: Variant = _world()
	_give_scrap(w2, SimGunsmith.BENCH_SCRAP - 1)
	var t2: Vector2i = _facing_tile(w2)
	w2.commands.push({"type": "bench.build", "tx": t2.x, "ty": t2.y})
	for i in SimGunsmith.BENCH_TICKS + 4:
		w2.step()
	if _benches(w2) != 0:
		push_error("%s: a bench was built with %d scrap when it costs %d" % [lane, SimGunsmith.BENCH_SCRAP - 1, SimGunsmith.BENCH_SCRAP])
		return false

	print("  BUILD OK %d scrap and %d ticks; one short builds nothing" % [SimGunsmith.BENCH_SCRAP, started])
	return true


# --- CHANNEL ----------------------------------------------------------------------------------
#
# It inherits SimFortify's channel, so it inherits the stagger interrupt -- which is worth
# asserting rather than assuming, because inheriting a behaviour is exactly the kind of claim that
# stops being true when somebody adds a second channel implementation.
func _a_channel_that_is_interrupted_builds_nothing() -> bool:
	var lane: String = "CHANNEL"
	var w: Variant = _world()
	_give_scrap(w, SimGunsmith.BENCH_SCRAP)
	var tile: Vector2i = _facing_tile(w)
	w.commands.push({"type": "bench.build", "tx": tile.x, "ty": tile.y})
	w.step()
	if not w.components.has_component(w.player, "construct"):
		push_error("%s: no channel to interrupt" % lane)
		return false
	w.events.publish({"type": "entity.staggered", "entity": w.player, "ticks": 8})
	w.step()
	if w.components.has_component(w.player, "construct"):
		push_error("%s: a stagger did not cancel the bench channel" % lane)
		return false
	for i in SimGunsmith.BENCH_TICKS + 4:
		w.step()
	if _benches(w) != 0:
		push_error("%s: an interrupted channel built a bench anyway" % lane)
		return false
	# The scrap is still in the pack: a cancelled job costs nothing but the time already spent.
	if SimFortify.material_count(w, w.player, SimFortify.recipe_kind("bench")) != SimGunsmith.BENCH_SCRAP:
		push_error("%s: an interrupted channel spent the scrap" % lane)
		return false

	# TN: the same world, uninterrupted, completes -- or "no bench" above proves nothing.
	w.commands.push({"type": "bench.build", "tx": tile.x, "ty": tile.y})
	for i in SimGunsmith.BENCH_TICKS + 8:
		w.step()
		if _benches(w) > 0:
			break
	if _benches(w) != 1:
		push_error("%s: an uninterrupted channel built nothing either, so the interruption proves nothing" % lane)
		return false

	print("  CHANNEL OK a stagger cancels it and keeps the scrap; left alone it finishes")
	return true


# --- EXCLUSIVE --------------------------------------------------------------------------------
#
# A body mid-channel is inert to E -- SimFortify's own rule, and the bench has to obey it from both
# directions or a press could stack a bench on top of a half-boarded window.
func _nobody_holds_two_jobs_at_once() -> bool:
	var lane: String = "EXCLUSIVE"
	var w: Variant = _world()
	_give_scrap(w, SimGunsmith.BENCH_SCRAP * 2)
	var tile: Vector2i = _facing_tile(w)
	w.commands.push({"type": "bench.build", "tx": tile.x, "ty": tile.y})
	w.step()
	var first: Dictionary = (w.components.get_component(w.player, "construct") as Dictionary).duplicate()
	# A second press, mid-channel, must change nothing about the job already running.
	w.commands.push({"type": "bench.build", "tx": tile.x + 1, "ty": tile.y})
	w.step()
	var now: Variant = w.components.get_component(w.player, "construct")
	if not now is Dictionary:
		push_error("%s: a second press cancelled the job in hand" % lane)
		return false
	if int((now as Dictionary).get("tx", -1)) != int(first.get("tx", -2)):
		push_error("%s: a second press moved the job from %d to %d" % [lane, int(first.get("tx", -2)), int((now as Dictionary).get("tx", -1))])
		return false
	if int((now as Dictionary)["ticksLeft"]) >= int(first["ticksLeft"]):
		push_error("%s: the channel did not advance, so 'unchanged' above means nothing" % lane)
		return false
	print("  EXCLUSIVE OK a second press mid-channel neither restarts nor moves the job")
	return true


# --- REFUSE -----------------------------------------------------------------------------------
#
# The point of the whole slice. Structural work wants the bench; what content marks `fieldSwap` --
# a magazine, a sight, a can on a thread -- does not. Both halves matter: without the first the
# bench is decoration, and without the second the player cannot reload a thought in the field.
func _structural_work_wants_the_bench_and_a_magazine_does_not() -> bool:
	var lane: String = "REFUSE"

	# Away from any bench: a barrel is refused.
	var w: Variant = _world()
	var pistol: int = SimItems.spawn_item(w, PISTOL, {"tier": "scavenged"})
	SimInventory.equip(w, w.player, pistol)
	var long: int = SimItems.spawn_item(w, LONG_BARREL, {"tier": "scavenged"})
	SimInventory.stow(w, w.player, long)
	w.events.drain()
	var fitted_barrel: int = SimAttachments.in_slot(w, pistol, "barrel")
	w.commands.push({"type": "item.detach", "item": fitted_barrel})
	w.step()
	if SimAttachments.in_slot(w, pistol, "barrel") != fitted_barrel:
		push_error("%s: a barrel came off in a field, with no bench anywhere" % lane)
		return false
	var reasons: Array = []
	for e in w.events.drained:
		if String((e as Dictionary).get("type", "")) == "attachment.refused":
			reasons.append(String((e as Dictionary).get("reason", "")))
	if not reasons.has("no-bench"):
		push_error("%s: the refusal did not say why: %s" % [lane, str(reasons)])
		return false

	# A field-swappable part, same place, no bench: allowed.
	var can: int = SimItems.spawn_item(w, SUPPRESSOR, {"tier": "scavenged"})
	SimInventory.stow(w, w.player, can)
	w.events.drain()
	w.commands.push({"type": "item.attach", "host": pistol, "item": can, "slot": "muzzle"})
	w.step()
	if SimAttachments.in_slot(w, pistol, "muzzle") != can:
		push_error("%s: a can that content says screws on by hand was refused in the field" % lane)
		return false

	# TN for the first half: the same barrel, at a bench, comes off. Without this "refused"
	# above could simply mean the command never worked at all.
	var w2: Variant = _world()
	var p2: int = SimItems.spawn_item(w2, PISTOL, {"tier": "scavenged"})
	SimInventory.equip(w2, w2.player, p2)
	w2.events.drain()
	SimGunsmith.make_bench(w2, 8.5, 12.5)
	var b2: int = SimAttachments.in_slot(w2, p2, "barrel")
	w2.commands.push({"type": "item.detach", "item": b2})
	w2.step()
	if SimAttachments.in_slot(w2, p2, "barrel") >= 0:
		push_error("%s: a barrel would not come off at a bench either" % lane)
		return false
	# And it went somewhere, rather than out of the world.
	if not (w2.components.has_component(b2, "stored") or w2.components.has_component(b2, "position")):
		push_error("%s: the barrel that came off at a bench is nowhere" % lane)
		return false
	# Then the long one goes on, which is the operation this whole arc exists for.
	var long2: int = SimItems.spawn_item(w2, LONG_BARREL, {"tier": "scavenged"})
	SimInventory.stow(w2, w2.player, long2)
	w2.events.drain()
	w2.commands.push({"type": "item.attach", "host": p2, "item": long2, "slot": "barrel"})
	w2.step()
	if SimAttachments.in_slot(w2, p2, "barrel") != long2:
		push_error("%s: the long barrel would not go on at a bench" % lane)
		return false

	print("  REFUSE OK a barrel needs the bench, a suppressor does not, and at a bench the swap goes through")
	return true


# --- MODIFY -----------------------------------------------------------------------------------
#
# docs/11 has always called SimModification's consumables a bench, and now there is one. Its
# refusal uses the module's own {ok, reason} shape rather than a new vocabulary.
func _the_affix_bench_is_the_same_bench() -> bool:
	var lane: String = "MODIFY"
	var w: Variant = _world()
	# A knife rather than an axe: the axe is 2x4 and arrives with a head and a haft fitted, and a
	# pack too full to hold the tape would fail this lane for a reason that is not the bench.
	var knife: int = SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "modified"})
	if not SimInventory.stow(w, w.player, knife):
		push_error("%s: the knife would not go in the pack" % lane)
		return false
	var tape: int = SimItems.spawn_item(w, "item.tape.duct", {"tier": "scavenged", "count": 2})
	if not SimInventory.stow(w, w.player, tape):
		push_error("%s: the tape would not go in the pack" % lane)
		return false
	w.events.drain()
	var away: Dictionary = SimModification.apply(w, w.player, knife, tape)
	if bool(away.get("ok", false)) or String(away.get("reason", "")) != "no-bench":
		push_error("%s: duct tape away from a bench returned %s" % [lane, str(away)])
		return false

	# TN: the same call at a bench must get past this refusal. It may still fail its roll -- that
	# is check_mods.gd's business -- so the assertion is only that the reason changes.
	SimGunsmith.make_bench(w, 8.5, 12.5)
	var here: Dictionary = SimModification.apply(w, w.player, knife, tape)
	if String(here.get("reason", "")) == "no-bench":
		push_error("%s: standing at a bench still refused for no-bench" % lane)
		return false
	# It got past every *precondition*, not merely past the bench one: a roll it loses is
	# check_mods.gd's business, but "no-consumable" or "wrong-item-class" here would mean this
	# lane never reached the question it exists to ask.
	var reason: String = String(here.get("reason", ""))
	if not bool(here.get("ok", false)) and reason != "failed" and reason != "broke":
		push_error("%s: at a bench the tape returned '%s', which is not a roll" % [lane, reason])
		return false

	print("  MODIFY OK away from a bench 'no-bench', at one %s" % ("applied" if bool(here.get("ok", false)) else String(here.get("reason", "a roll"))))
	return true


# --- SAVE -------------------------------------------------------------------------------------
#
# A bench is an entity with one component, so this is cheap -- and it is the component the whole
# feature hangs off, so a save that quietly dropped it would take the colony's gunsmithing with it.
func _a_bench_survives_a_save() -> bool:
	var lane: String = "SAVE"
	var w: Variant = _world()
	var bench: int = SimGunsmith.make_bench(w, 8.5, 12.5)
	var blob: String = SimSerialize.canonicalize(w.snapshot())
	if not blob.contains("workbench"):
		push_error("%s: a snapshot of a colony with a bench does not mention one" % lane)
		return false
	var comp: Variant = w.components.get_component(bench, "workbench")
	if not comp is Dictionary or String((comp as Dictionary).get("kind", "")) != SimGunsmith.KIND:
		push_error("%s: the bench does not say what kind it is" % lane)
		return false

	# TN: a colony with no bench must not mention one, or `contains` is matching something else
	# in the blob entirely.
	var w2: Variant = _world()
	if SimSerialize.canonicalize(w2.snapshot()).contains("workbench"):
		push_error("%s: a colony with no bench serialises one anyway" % lane)
		return false

	print("  SAVE OK the bench and its kind are in the snapshot; a colony without one is not")
	return true


# --- POLARITY ---------------------------------------------------------------------------------
#
# The screen says "better" and "worse", so something has to know which way is up for every field a
# part can move. Both directions of the whitelist, the SCALES pattern -- a field that can be scaled
# with no polarity would draw an arrow pointing the wrong way, and a polarity for a field nothing
# scales is a dead socket in the other direction.
#
# The third check needs no fixture at all: ask `better` about every field in both directions and
# require the two answers to differ and to match the sign. That is a true positive and a true
# negative for every field at once, in arithmetic.
func _every_field_has_a_direction_and_the_direction_is_read() -> bool:
	var lane: String = "POLARITY"
	for kind_v in SimAttachments.SCALABLE.keys():
		var kind: String = String(kind_v)
		var scalable: Array = SimAttachments.SCALABLE[kind] as Array
		var polarity: Dictionary = SimAttachments.POLARITY.get(kind, {}) as Dictionary
		var words: Dictionary = SimAttachments.FIELD_WORD.get(kind, {}) as Dictionary
		for field_v in scalable:
			var field: String = String(field_v)
			if not polarity.has(field):
				push_error("%s: %s.%s can be scaled and has no direction" % [lane, kind, field])
				return false
			if not words.has(field):
				push_error("%s: %s.%s has a direction and no word for the screen" % [lane, kind, field])
				return false
			var up: bool = SimAttachments.better(kind, field, 1.0, 2.0)
			var down: bool = SimAttachments.better(kind, field, 2.0, 1.0)
			if up == down:
				push_error("%s: %s.%s answers '%s' in both directions" % [lane, kind, field, str(up)])
				return false
			if up != (int(polarity[field]) > 0):
				push_error("%s: %s.%s says more is %s and its polarity is %d" % [lane, kind, field, "better" if up else "worse", int(polarity[field])])
				return false
		for field_v2 in polarity.keys():
			if not scalable.has(String(field_v2)):
				push_error("%s: %s.%s has a direction and nothing scales it" % [lane, kind, String(field_v2)])
				return false
	# TN: the predicate must say no about a field it has never heard of, or the loop above is
	# satisfied by a `better` that returns true for everything.
	if SimAttachments.better("ranged", "gate.nosuchfield", 1.0, 2.0):
		push_error("%s: better() has an opinion about a field that does not exist" % lane)
		return false
	# And the words must reach the screen: a comparison of two real parts has to come back
	# carrying them, or FIELD_WORD is a table nothing reads.
	var w: Variant = _world()
	var pistol: int = SimItems.spawn_item(w, PISTOL, {"tier": "scavenged"})
	var changes: Array = SimAttachments.compare_view(w, pistol, "barrel", SimItems.spawn_item(w, LONG_BARREL, {"tier": "scavenged"}))
	if changes.is_empty():
		push_error("%s: swapping a standard barrel for a long one changes nothing" % lane)
		return false
	var seen_better: bool = false
	var seen_worse: bool = false
	for c in changes:
		var row: Dictionary = c as Dictionary
		if String(row.get("word", "")).is_empty():
			push_error("%s: a change came back with no word for it" % lane)
			return false
		if String(row.get("change", "")) == "better":
			seen_better = true
		elif String(row.get("change", "")) == "worse":
			seen_worse = true
	# The long barrel reaches further and is heard doing it, so a comparison that is all one way
	# is a comparison that is not reading the content.
	if not (seen_better and seen_worse):
		push_error("%s: a long barrel reads as all-good or all-bad: %s" % [lane, str(changes)])
		return false

	print("  POLARITY OK every scalable field has a direction and a word, both ways round; a long barrel reads %d changes" % changes.size())
	return true


# --- VIEW -------------------------------------------------------------------------------------
#
# The bench screen's read model, held to the condition view's rule in its strictest form: words
# and booleans, and integers only where they are named handles the screen hands straight back on a
# command. There is no magnitude in this view at all, which is what makes "no digits on the bench"
# structural rather than something somebody has to remember.
const HANDLE_KEYS: Array[String] = ["bench", "host", "part", "item"]
const VIEW_KEYS: Array[String] = ["bench", "host", "name", "condition", "refusal", "slots", "offers"]

func _the_screen_is_handed_words_and_handles_and_nothing_else() -> bool:
	var lane: String = "VIEW"
	var w: Variant = _world()
	var pistol: int = SimItems.spawn_item(w, PISTOL, {"tier": "scavenged"})
	SimInventory.equip(w, w.player, pistol)
	var long: int = SimItems.spawn_item(w, LONG_BARREL, {"tier": "scavenged"})
	SimInventory.stow(w, w.player, long)
	w.events.drain()
	SimGunsmith.make_bench(w, 8.5, 12.5)
	var view: Dictionary = SimGunsmith.bench_view(w, w.player, pistol)
	if view.is_empty():
		push_error("%s: the bench has nothing to say about a pistol" % lane)
		return false
	for key in VIEW_KEYS:
		if not view.has(key):
			push_error("%s: the view is missing '%s'" % [lane, key])
			return false
	for key in view.keys():
		if not VIEW_KEYS.has(String(key)):
			push_error("%s: the view grew an unexpected key '%s'" % [lane, String(key)])
			return false
	var faults: Array = _view_faults(view, "")
	if not faults.is_empty():
		push_error("%s: %s" % [lane, ", ".join(PackedStringArray(faults))])
		return false
	if (view["slots"] as Array).is_empty() or (view["offers"] as Array).is_empty():
		push_error("%s: %d slots and %d offers, so the scan above judged nothing" % [lane, (view["slots"] as Array).size(), (view["offers"] as Array).size()])
		return false

	# TN: the same scanner over a fabricated view carrying a number where a word belongs. If it
	# comes back clean, every "no digits" claim above is a scan that cannot fail.
	var probe: Dictionary = view.duplicate(true)
	((probe["slots"] as Array)[0] as Dictionary)["condition"] = "worn 40%"
	if _view_faults(probe, "").is_empty():
		push_error("%s: the scanner cannot see a digit -- a fabricated 'worn 40%%' passed" % lane)
		return false
	var probe2: Dictionary = view.duplicate(true)
	probe2["damage"] = 18.0
	if _view_faults(probe2, "").is_empty():
		push_error("%s: the scanner cannot see a number where a word belongs" % lane)
		return false

	print("  VIEW OK %d slots and %d offers, all words but the named handles" % [(view["slots"] as Array).size(), (view["offers"] as Array).size()])
	return true


## Every value in the view, recursively: strings carry no digits, numbers appear only under a
## named handle key, and nothing else is allowed at all.
func _view_faults(value: Variant, key: String) -> Array:
	var out: Array = []
	if value is Dictionary:
		for k in (value as Dictionary).keys():
			out.append_array(_view_faults((value as Dictionary)[k], String(k)))
		return out
	if value is Array:
		for row in value as Array:
			out.append_array(_view_faults(row, key))
		return out
	if value is String:
		for c in String(value):
			if c >= "0" and c <= "9":
				out.append("\"%s\" carries a digit: \"%s\"" % [key, String(value)])
				break
		return out
	if value is bool:
		return out
	if value is int:
		if not HANDLE_KEYS.has(key):
			out.append("\"%s\" is a number, and only a handle may be one" % key)
		return out
	out.append("\"%s\" is a %s" % [key, type_string(typeof(value))])
	return out


# --- PANEL ------------------------------------------------------------------------------------
#
# The dead-socket question, asked of the surface: the screen exists to reach commands the sim
# already had and nobody could push. So this drives the two the panel pushes -- a strip and a fit
# -- through the command queue, at a bench, and requires the world to move.
#
# It also asserts, textually, that `ui/bench_panel.gd` is the thing pushing them and that it draws
# `bench_view` rather than computing anything. A textual needle has to be able to find its reader
# after a refactor, so it follows the call rather than pinning a line number -- CLAUDE.md's note
# about `check_respond` and `check_weather` both going red for needles that had merely moved.
func _the_panel_pushes_what_the_sim_answers() -> bool:
	var lane: String = "PANEL"
	var w: Variant = _world()
	var pistol: int = SimItems.spawn_item(w, PISTOL, {"tier": "scavenged"})
	SimInventory.equip(w, w.player, pistol)
	var long: int = SimItems.spawn_item(w, LONG_BARREL, {"tier": "scavenged"})
	SimInventory.stow(w, w.player, long)
	w.events.drain()
	SimGunsmith.make_bench(w, 8.5, 12.5)

	# E opens it, through the ladder rather than through a key of its own.
	w.commands.push({"type": "use.context"})
	w.step()
	if SimGunsmith.focus_of(w, w.player) != pistol:
		push_error("%s: E at a bench, holding a pistol, opened nothing" % lane)
		return false

	# The strip the panel pushes for a row on the left.
	var standard: int = SimAttachments.in_slot(w, pistol, "barrel")
	w.commands.push({"type": "item.detach", "item": standard})
	w.step()
	if SimAttachments.in_slot(w, pistol, "barrel") >= 0:
		push_error("%s: the strip the panel pushes did nothing" % lane)
		return false
	# And the fit it pushes for a row on the right.
	w.commands.push({"type": "item.attach", "host": pistol, "item": long, "slot": "barrel"})
	w.step()
	if SimAttachments.in_slot(w, pistol, "barrel") != long:
		push_error("%s: the fit the panel pushes did nothing" % lane)
		return false

	# Walking away closes it. A screen about a place you are no longer standing in is a lie, and
	# this is the rule SimContainers already follows for an open box.
	var pos: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	pos["x"] = float(pos["x"]) + 8.0
	w.step()
	if SimGunsmith.focus_of(w, w.player) >= 0:
		push_error("%s: walking away from the bench left it open" % lane)
		return false

	# The textual half: the panel draws the read model and pushes the commands, and computes
	# neither. Sliced from the file rather than pinned to a line.
	var src: String = FileAccess.get_file_as_string("res://ui/bench_panel.gd")
	if src.is_empty():
		push_error("%s: ui/bench_panel.gd could not be read" % lane)
		return false
	for needle in ["bench_view", "item.detach", "item.attach"]:
		if not src.contains(needle):
			push_error("%s: ui/bench_panel.gd never mentions %s" % [lane, needle])
			return false
	# It must not reach past the read model into the sim's own arithmetic: no profile builder, no
	# fold, no condition factor. The panel prints; it does not decide.
	for banned in ["ranged_profile_of", "melee_profile_of", "condition_factor", "effect_scale"]:
		if src.contains(banned):
			push_error("%s: ui/bench_panel.gd calls %s -- the panel is computing, not drawing" % [lane, banned])
			return false

	print("  PANEL OK E opens it, a strip and a fit both move the world, and walking away closes it")
	return true
