extends SceneTree
# The splint, and the limp a bad fracture leaves.
#
# Guards the splint slice (2026-09-06). Before it, `closeKind: "splint"` sat in the item schema
# with no item declaring it, `SimTreatment.CLOSE_KINDS` accepted `suture` alone, and
# `_closable_wounds` asked "does this kind bleed" -- so a fracture, the one injury a splint is for,
# was the one injury `close` refused to look at. The splint is the first closer that is not a
# suture, and the closer became a property of the wound kind (`SimWounds.WOUND_KINDS.closeKind`)
# rather than a ranking in treatment.gd: a suture holds skin, a splint holds a bone, and the two
# are matched exactly.
#
# The second half is docs/05's "badly-set fracture -> permanent limp", the first of its permanent
# consequences to land: a leg fracture that knits without ever being splinted leaves a `lasting`
# record that outlives the wound, costs `move_speed` for good, and reads as one word on the body
# screen. The owner's rule is deterministic -- splint it and it mends clean -- so the negative here
# is the splinted twin of every limping leg.
#
# What this gate holds down:
#
#  1. **Assert the effect, never the mechanism** (docs/30:513-524). The limp is measured as
#     ground actually covered against a clean baseline and a splinted twin, not as a `resolve()`
#     call; the splint's pace is measured as the tick a wound actually leaves the list.
#  2. **A kit closes the wound it is for and nothing else.** A suture kit does not splint a
#     fracture, a splint does not sew a cut, and closing one kind on a leg leaves the other kind
#     open beside it.
#  3. **The record outlives everything a wound does not.** A save, a load, and a despawn.
#
# Every assertion carries a true negative beside its positive.

const World = preload("res://sim/world.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimCondition = preload("res://sim/condition.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimClock = preload("res://sim/time/clock.gd")
const ContentLoader = preload("res://platform/content_loader.gd")

const SPLINT: String = "item.splint.kit"
const SUTURE: String = "item.suture.kit"
const DEEP_DAMAGE: float = 20.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _the_splint_is_content_and_findable() and ok
	ok = _a_splint_closes_a_fracture_and_nothing_else() and ok
	ok = _one_kit_closes_one_kind_on_a_leg_carrying_two() and ok
	ok = _a_splinted_fracture_knits_at_the_closed_pace() and ok
	ok = _an_unsplinted_leg_fracture_leaves_a_limp_and_a_splinted_one_does_not() and ok
	ok = _a_limp_survives_a_save_and_leaves_with_the_body() and ok
	ok = _the_view_says_limp_as_a_word() and ok
	ok = _the_one_key_reaches_for_the_splint_and_never_for_the_wrong_kit() and ok
	ok = _deterministic_replay() and ok
	if ok:
		print("M2_SPLINT_OK the closer is the wound kind's, a splint holds a fracture, an unsplinted leg limps for good and a splinted one does not")
		quit(0)
	else:
		push_error("M2_SPLINT_FAIL")
		quit(1)


# --- fixture ----------------------------------------------------------------------------

# check_m2_treatment.gd's bare world: no kernel, three modules, one survivor with a body, stamina
# and a pack.
func _world(seed_val: int = 5151) -> Variant:
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


func _bystander(w: Variant, x: float, y: float) -> int:
	var e: int = int(w.entities.spawn())
	w.components.set_component(e, "position", {"x": x, "y": y})
	w.components.set_component(e, "velocity", {"dx": 0.0, "dy": 0.0})
	SimHealth.make_survivor_body(w, e)
	SimHealth.make_stamina(w, e, 100)
	SimInventory.make_inventory(w, e)
	return e


# A fracture in the shape roll_impact_injury writes: closed injury, Laceration band, no blood.
func _fracture(w: Variant, entity: int, part: String) -> Dictionary:
	return SimWounds.append_wound(w, entity, "fracture", part, -1, 0.0, "fracture", SimWounds.Severity.Laceration)


func _sprain(w: Variant, entity: int, part: String) -> Dictionary:
	return SimWounds.append_wound(w, entity, "sprain", part, -1, 0.0, "sprain", SimWounds.Severity.Laceration)


# A deep cut somebody has already stopped -- what pressure leaves behind, and what a suture is for.
func _stopped_cut(w: Variant, entity: int, part: String) -> Dictionary:
	var wd: Dictionary = SimWounds.append_wound(w, entity, "cut", part, -1, DEEP_DAMAGE)
	wd["bleeding"] = false
	return wd


func _give(w: Variant, actor: int, base_id: String, count: int = 2) -> int:
	var item: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, actor, item):
		push_error("could not stow %s" % base_id)
	return item


func _medicine(w: Variant, entity: int, points: int) -> void:
	w.components.set_component(entity, "skillWeb", {"points": {"Medicine": points}, "nodes": []})


func _run_ticks(w: Variant, ticks: int) -> void:
	for _i in ticks:
		w.step()


func _stack_count(w: Variant, item: int) -> int:
	var s: Variant = w.components.get_component(item, "stack")
	if not (s is Dictionary):
		return 1
	return int((s as Dictionary).get("count", 1))


func _wounds(w: Variant, entity: int) -> Array:
	var inj: Variant = w.components.get_component(entity, "injuries")
	if not (inj is Dictionary):
		return []
	return (inj as Dictionary).get("wounds", []) as Array


func _walk(w: Variant, ticks: int) -> float:
	var start: float = float((w.components.get_component(w.player, "position") as Dictionary)["x"])
	for _i in ticks:
		w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
		w.step()
	return float((w.components.get_component(w.player, "position") as Dictionary)["x"]) - start


func _budget() -> int:
	return SimWounds.recovery_days_for("fracture", SimWounds.Severity.Laceration) * SimClock.DAY_TICKS


func _lasting_records(w: Variant, entity: int) -> Array:
	var comp: Variant = w.components.get_component(entity, "lasting")
	if not (comp is Dictionary):
		return []
	return (comp as Dictionary).get("records", []) as Array


# --- lanes ------------------------------------------------------------------------------

# The splint kit resolves, declares its closer, sits in a loot table so a survivor can actually
# find one, and spawns through the loot path. The negative is a made-up id that is none of those,
# so the loop is asserting something. check_m2_attach.gd's "findable in any loot table" rule.
func _the_splint_is_content_and_findable() -> bool:
	var droppable: Dictionary = {}
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("loot/"):
			continue
		var value: Variant = tree[path]
		if not value is Array:
			continue
		for table_v in value as Array:
			for entry_v in (table_v as Dictionary).get("entries", []) as Array:
				droppable[String((entry_v as Dictionary).get("item", ""))] = true
	if droppable.is_empty():
		push_error("no loot table entries were read, so findability is asserting nothing")
		return false
	var w: Variant = _world()
	var base: Variant = SimItems.content_entry(w, "item", SPLINT)
	if not (base is Dictionary):
		push_error("%s resolves to no item base" % SPLINT)
		return false
	if String((base as Dictionary).get(SimTreatment.CLOSE_KEY, "")) != "splint":
		push_error("%s declares closeKind='%s'" % [SPLINT, (base as Dictionary).get(SimTreatment.CLOSE_KEY, "")])
		return false
	if not SimTreatment.CLOSE_KINDS.has("splint"):
		push_error("SimTreatment.CLOSE_KINDS does not accept 'splint', so the kit is refused")
		return false
	if not droppable.has(SPLINT):
		push_error("%s is in no loot table, so it cannot be found" % SPLINT)
		return false
	var item: int = SimItems.spawn_item(w, SPLINT, {"tier": "scavenged", "count": 1})
	var resolved: Variant = SimItems.item_base_of(w, item)
	if not (resolved is Dictionary) or String((resolved as Dictionary).get("id", "")) != SPLINT:
		push_error("%s did not resolve through SimItems after spawning" % SPLINT)
		return false
	# The kind table names its closer, and a fracture's is the splint -- the read the ladder
	# actually makes. A sprain's is nothing, which is what keeps "closable" from meaning "any
	# closed injury".
	if SimWounds.close_kind_of({"kind": "fracture"}) != "splint" or SimWounds.close_kind_of({"kind": "cut"}) != "suture" or SimWounds.close_kind_of({"kind": "sprain"}) != "":
		push_error("WOUND_KINDS closers are not fracture=splint, cut=suture, sprain=none")
		return false
	if droppable.has("item.splint.imaginary") or SimItems.content_entry(w, "item", "item.splint.imaginary") is Dictionary:
		push_error("a made-up base id was found, so findability is asserting nothing")
		return false
	print("CONTENT OK %s declares splint, is in a loot table, spawns and resolves; a made-up id is neither" % SPLINT)
	return true


# A splint closes a fracture and spends one kit. Four refusals beside it, each the one a different
# wrong pairing earns: a suture on a fracture and a splint on a cut are both `no-kit`, a sprain is
# `nothing-to-do` whatever is carried, and a bleeding cut is `still-bleeding` before any kit is
# asked about.
func _a_splint_closes_a_fracture_and_nothing_else() -> bool:
	var w: Variant = _world()
	var fx: Dictionary = _fracture(w, w.player, "leg_left")
	var kit: int = _give(w, w.player, SPLINT, 2)
	var res: Dictionary = SimTreatment.begin(w, w.player, w.player, "leg_left", "close")
	var want: int = int(SimWounds.CLOSE_TICKS[SimWounds.Severity.Laceration])
	if not bool(res.get("ok", false)) or int(res.get("ticks", 0)) != want:
		push_error("splinting a leg fracture returned %s, wanted ok with %d ticks" % [str(res), want])
		return false
	_run_ticks(w, want)
	if not bool(fx.get("closed", false)):
		push_error("the fracture is not closed after the splint channel ran its %d ticks" % want)
		return false
	if _stack_count(w, kit) != 1:
		push_error("splinting spent %d kits, not one" % (2 - _stack_count(w, kit)))
		return false

	var suture_only: Variant = _world()
	_fracture(suture_only, suture_only.player, "leg_left")
	_give(suture_only, suture_only.player, SUTURE, 2)
	var r1: Dictionary = SimTreatment.begin(suture_only, suture_only.player, suture_only.player, "leg_left", "close")
	if bool(r1.get("ok", false)) or String(r1.get("reason", "")) != "no-kit":
		push_error("a suture kit was accepted for a fracture: %s" % str(r1))
		return false

	var splint_only: Variant = _world()
	_stopped_cut(splint_only, splint_only.player, "torso")
	_give(splint_only, splint_only.player, SPLINT, 2)
	_medicine(splint_only, splint_only.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	var r2: Dictionary = SimTreatment.begin(splint_only, splint_only.player, splint_only.player, "torso", "close")
	if bool(r2.get("ok", false)) or String(r2.get("reason", "")) != "no-kit":
		push_error("a splint was accepted for a deep cut: %s" % str(r2))
		return false

	var sprained: Variant = _world()
	_sprain(sprained, sprained.player, "leg_left")
	_give(sprained, sprained.player, SPLINT, 2)
	_give(sprained, sprained.player, SUTURE, 2)
	var r3: Dictionary = SimTreatment.begin(sprained, sprained.player, sprained.player, "leg_left", "close")
	if bool(r3.get("ok", false)) or String(r3.get("reason", "")) != "nothing-to-do":
		push_error("a sprain was offered a closer: %s" % str(r3))
		return false

	var bleeding: Variant = _world()
	SimWounds.append_wound(bleeding, bleeding.player, "cut", "leg_left", -1, DEEP_DAMAGE)
	_give(bleeding, bleeding.player, SPLINT, 2)
	_give(bleeding, bleeding.player, SUTURE, 2)
	_medicine(bleeding, bleeding.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	var r4: Dictionary = SimTreatment.begin(bleeding, bleeding.player, bleeding.player, "leg_left", "close")
	if bool(r4.get("ok", false)) or String(r4.get("reason", "")) != "still-bleeding":
		push_error("a bleeding cut was closed rather than refused: %s" % str(r4))
		return false
	print("SPLINT CLOSES OK fracture splinted in %d ticks for one kit; suture-on-fracture '%s', splint-on-cut '%s', sprain '%s', bleeding '%s'" % [want, r1.get("reason", ""), r2.get("reason", ""), r3.get("reason", ""), r4.get("reason", "")])
	return true


# One leg, a stopped deep cut and a fracture on it, both kits in the pack. The first close sews
# the cut -- the worse wound -- and leaves the fracture open; the second splints it. The negative
# is that a completed suture channel never wrote `closed` onto the fracture beside it.
func _one_kit_closes_one_kind_on_a_leg_carrying_two() -> bool:
	var w: Variant = _world()
	var cut: Dictionary = _stopped_cut(w, w.player, "leg_left")
	var fx: Dictionary = _fracture(w, w.player, "leg_left")
	var sutures: int = _give(w, w.player, SUTURE, 2)
	var splints: int = _give(w, w.player, SPLINT, 2)
	_medicine(w, w.player, SimWounds.CLOSE_MEDICINE_FLOOR)
	var first: Dictionary = SimTreatment.begin(w, w.player, w.player, "leg_left", "close")
	if not bool(first.get("ok", false)) or int(first.get("ticks", 0)) != int(SimWounds.CLOSE_TICKS[SimWounds.Severity.DeepWound]):
		push_error("the first close on a leg carrying a deep cut and a fracture was %s, wanted the deep cut's channel" % str(first))
		return false
	_run_ticks(w, int(first.get("ticks", 0)))
	if not bool(cut.get("closed", false)) or bool(fx.get("closed", false)):
		push_error("after the suture channel: cut closed=%s, fracture closed=%s" % [cut.get("closed", false), fx.get("closed", false)])
		return false
	if _stack_count(w, sutures) != 1 or _stack_count(w, splints) != 2:
		push_error("the suture channel spent sutures %d->%d and splints %d->%d" % [2, _stack_count(w, sutures), 2, _stack_count(w, splints)])
		return false
	var second: Dictionary = SimTreatment.begin(w, w.player, w.player, "leg_left", "close")
	if not bool(second.get("ok", false)) or int(second.get("ticks", 0)) != int(SimWounds.CLOSE_TICKS[SimWounds.Severity.Laceration]):
		push_error("the second close was %s, wanted the fracture's channel" % str(second))
		return false
	_run_ticks(w, int(second.get("ticks", 0)))
	if not bool(fx.get("closed", false)) or _stack_count(w, splints) != 1:
		push_error("the second channel did not splint the fracture (closed=%s, splints left %d)" % [fx.get("closed", false), _stack_count(w, splints)])
		return false
	print("TWO KINDS OK the suture took the cut and left the fracture, the splint took the fracture; one kit each")
	return true


# What a splint buys in time: a splinted fracture earns two ticks a resting tick, an unsplinted one
# earns one. Set ten short of the six-week budget so the whole recovery need not be simulated --
# check_m2_treatment.gd's CLOSE lane, on the fracture's own budget.
func _a_splinted_fracture_knits_at_the_closed_pace() -> bool:
	var splinted: Variant = _world()
	var a: Dictionary = _fracture(splinted, splinted.player, "leg_left")
	a["healedTicks"] = _budget() - 10
	a["closed"] = true
	_run_ticks(splinted, 5)
	if not _wounds(splinted, splinted.player).is_empty():
		push_error("a splinted fracture five earned ticks from done did not close")
		return false

	var raw: Variant = _world()
	var b: Dictionary = _fracture(raw, raw.player, "leg_left")
	b["healedTicks"] = _budget() - 10
	_run_ticks(raw, 5)
	if _wounds(raw, raw.player).is_empty():
		push_error("an unsplinted fracture closed in the same five ticks, so the splint bought no speed")
		return false
	_run_ticks(raw, 5)
	if not _wounds(raw, raw.player).is_empty():
		push_error("an unsplinted fracture did not close after its full ten earned ticks -- the ordinary rate changed")
		return false
	print("PACE OK splinted closed in 5 earned ticks, unsplinted in 10, budget %d" % _budget())
	return true


# The consequence. An unsplinted leg fracture that knits leaves a `lasting` limp; the same fracture
# splinted, and the same fracture on an arm, leave nothing. Measured as ground covered: the limping
# leg walks less than a clean one, the splinted leg walks exactly as far as a clean one, and two
# limping legs walk less than one.
func _an_unsplinted_leg_fracture_leaves_a_limp_and_a_splinted_one_does_not() -> bool:
	var clean: Variant = _world()
	var baseline: float = _walk(clean, 100)

	var limping: Variant = _world()
	var closed_events: Array = []
	limping.events.subscribe({"id": "gate.closed", "type": "wound.closed", "handler": func(e: Dictionary) -> void:
		closed_events.append(e)
	})
	_fracture(limping, limping.player, "leg_left")["healedTicks"] = _budget() - 1
	_run_ticks(limping, 2)
	if not _wounds(limping, limping.player).is_empty():
		push_error("the fracture did not close on its budget")
		return false
	var records: Array = _lasting_records(limping, limping.player)
	if records.size() != 1 or String((records[0] as Dictionary).get("kind", "")) != "limp" or String((records[0] as Dictionary).get("bodyPart", "")) != "leg_left":
		push_error("an unsplinted leg fracture left %s, not one limp on leg_left" % str(records))
		return false
	if closed_events.size() != 1 or String((closed_events[0] as Dictionary).get("kind", "")) != "fracture" or bool((closed_events[0] as Dictionary).get("closed", true)):
		push_error("wound.closed did not say an unsplinted fracture closed: %s" % str(closed_events))
		return false
	var limp_distance: float = _walk(limping, 100)

	var splinted: Variant = _world()
	var s: Dictionary = _fracture(splinted, splinted.player, "leg_left")
	s["healedTicks"] = _budget() - 1
	s["closed"] = true
	_run_ticks(splinted, 2)
	if not _wounds(splinted, splinted.player).is_empty():
		push_error("the splinted fracture did not close")
		return false
	if not _lasting_records(splinted, splinted.player).is_empty():
		push_error("a splinted leg fracture left a lasting record: %s" % str(_lasting_records(splinted, splinted.player)))
		return false
	var splinted_distance: float = _walk(splinted, 100)

	var arm: Variant = _world()
	_fracture(arm, arm.player, "arm_left")["healedTicks"] = _budget() - 1
	_run_ticks(arm, 2)
	if not _wounds(arm, arm.player).is_empty() or not _lasting_records(arm, arm.player).is_empty():
		push_error("an unsplinted arm fracture left %s (wounds %d)" % [str(_lasting_records(arm, arm.player)), _wounds(arm, arm.player).size()])
		return false

	var both: Variant = _world()
	_fracture(both, both.player, "leg_left")["healedTicks"] = _budget() - 1
	_fracture(both, both.player, "leg_right")["healedTicks"] = _budget() - 1
	_run_ticks(both, 2)
	if _lasting_records(both, both.player).size() != 2:
		push_error("two unsplinted leg fractures left %d limps" % _lasting_records(both, both.player).size())
		return false
	var both_distance: float = _walk(both, 100)

	if limp_distance >= baseline:
		push_error("a limp cost no ground: %.4f vs baseline %.4f" % [limp_distance, baseline])
		return false
	if absf(splinted_distance - baseline) > 0.0001:
		push_error("a splinted, healed leg still walks short: %.4f vs baseline %.4f" % [splinted_distance, baseline])
		return false
	if both_distance >= limp_distance:
		push_error("two limps walk as far as one: %.4f vs %.4f" % [both_distance, limp_distance])
		return false
	# The limp is idempotent per leg: breaking the same leg again does not stack a second record.
	if SimWounds.add_lasting(limping, limping.player, "limp", "leg_left") or _lasting_records(limping, limping.player).size() != 1:
		push_error("a second limp record was added to the same leg")
		return false
	print("LIMP OK clean %.4f, one limp %.4f, two limps %.4f, splinted %.4f; arm left nothing" % [baseline, limp_distance, both_distance, splinted_distance])
	return true


# A limp is state, not a wound: it rides the component snapshot into a save and is still felt on
# the restored body. The negative: despawning the body strips its limp modifier from the store, so
# no save carries a modifier for a survivor who is no longer there.
func _a_limp_survives_a_save_and_leaves_with_the_body() -> bool:
	var w: Variant = _world(6161)
	_fracture(w, w.player, "leg_left")["healedTicks"] = _budget() - 1
	_run_ticks(w, 2)
	var before: float = _walk(w, 100)
	var snap: Dictionary = w.snapshot()

	var w2: Variant = _world(6161)
	w2.restore(snap)
	if _lasting_records(w2, w2.player).size() != 1:
		push_error("the limp did not survive the save: %s" % str(_lasting_records(w2, w2.player)))
		return false
	var after: float = _walk(w2, 100)
	if absf(after - before) > 0.0001:
		push_error("the restored body walks %.4f against %.4f before the save" % [after, before])
		return false
	var clean: Variant = _world(6161)
	if after >= _walk(clean, 100):
		push_error("the restored limp costs no ground, so the comparison above proves nothing")
		return false

	var saved: String = JSON.stringify(w2.modifiers.save())
	if not saved.contains(SimWounds.LASTING_SOURCE):
		push_error("a limping body's modifier store carries no %s" % SimWounds.LASTING_SOURCE)
		return false
	w2.despawn(w2.player)
	var gone: String = JSON.stringify(w2.modifiers.save())
	if gone.contains(SimWounds.LASTING_SOURCE):
		push_error("a despawned body left its %s in the modifier store" % SimWounds.LASTING_SOURCE)
		return false
	print("PERSISTENCE OK restored limp walks %.4f as before, and a despawn takes the modifier with it" % after)
	return true


# The word on the body screen. `lasting` is "limp" on the leg that carries one and "none" on every
# other part, every value is a String from LASTING_WORDS, and nothing about how much slower the
# leg is crosses -- check_ban_health_bar.gd holds the numeric half.
func _the_view_says_limp_as_a_word() -> bool:
	var w: Variant = _world()
	_fracture(w, w.player, "leg_left")["healedTicks"] = _budget() - 1
	_run_ticks(w, 2)
	var by_part: Dictionary = {}
	for entry in SimCondition.view(w, w.player)["parts"] as Array:
		var d: Dictionary = entry as Dictionary
		by_part[String(d["part"])] = d
	for part in by_part.keys():
		var v: Variant = (by_part[part] as Dictionary).get("lasting")
		if not (v is String) or not SimCondition.LASTING_WORDS.has(String(v)):
			push_error("%s.lasting is not a lasting word: %s" % [part, str(v)])
			return false
	if String(by_part["leg_left"]["lasting"]) != "limp":
		push_error("leg_left healed unsplinted and reads lasting='%s'" % by_part["leg_left"]["lasting"])
		return false
	if String(by_part["leg_right"]["lasting"]) != "none":
		push_error("leg_right reads lasting='%s' with no record" % by_part["leg_right"]["lasting"])
		return false
	if bool(by_part["leg_left"]["wounded"]):
		push_error("the healed leg still reads wounded, so `lasting` is not distinct from `wounded`")
		return false
	print("VIEW OK leg_left 'limp' and unwounded, leg_right 'none'")
	return true


# The one key. `treat.context` with a splint in the pack and a fracture on the leg opens the close
# rung; an NPC who carries only a suture kit and has only a fracture never starts a channel and
# never publishes a refusal for it -- the ladder skips the rung it cannot pay for rather than
# stalling on it every tick. The NPC positive: give them the splint and they set their own leg.
func _the_one_key_reaches_for_the_splint_and_never_for_the_wrong_kit() -> bool:
	var w: Variant = _world()
	_fracture(w, w.player, "leg_left")
	_give(w, w.player, SPLINT, 2)
	w.commands.push({"type": "treat.context"})
	w.step()
	var t: Variant = w.components.get_component(w.player, "treatment")
	if not (t is Dictionary) or String((t as Dictionary).get("verb", "")) != "close" or String((t as Dictionary).get("part", "")) != "leg_left":
		push_error("the context key with a splint and a fracture opened %s" % str(t))
		return false

	var wrong: Variant = _world()
	var them: int = _bystander(wrong, 9.5, 16.5)
	_fracture(wrong, them, "leg_left")
	_give(wrong, them, SUTURE, 2)
	var refusals: Array = []
	wrong.events.subscribe({"id": "gate.refused", "type": "treatment.refused", "handler": func(e: Dictionary) -> void:
		refusals.append(e)
	})
	_run_ticks(wrong, 50)
	if wrong.components.has_component(them, "treatment"):
		push_error("a suture-only survivor started a channel on their own fracture: %s" % str(wrong.components.get_component(them, "treatment")))
		return false
	if not refusals.is_empty():
		push_error("a suture-only survivor with a fracture published %d refusals" % refusals.size())
		return false

	var right: Variant = _world()
	var her: int = _bystander(right, 9.5, 16.5)
	var fx: Dictionary = _fracture(right, her, "leg_left")
	_give(right, her, SPLINT, 2)
	_run_ticks(right, int(SimWounds.CLOSE_TICKS[SimWounds.Severity.Laceration]) + 5)
	if not bool(fx.get("closed", false)):
		push_error("a survivor carrying a splint did not set their own fracture in %d ticks" % (int(SimWounds.CLOSE_TICKS[SimWounds.Severity.Laceration]) + 5))
		return false
	print("LADDER OK the key opens close on the fracture with a splint; a suture-only NPC neither channels nor complains; a splint-carrying NPC sets their own leg")
	return true


# Same seed and same commands, byte-identical; the close command moved seven ticks must differ.
func _deterministic_replay() -> bool:
	var runs: Array[String] = []
	for offset in [0, 0, 7]:
		var w: Variant = _world(99)
		_fracture(w, w.player, "leg_left")["healedTicks"] = _budget() - 400
		_give(w, w.player, SPLINT, 2)
		for i in 700:
			if i == 10 + int(offset):
				w.commands.push({"type": "treat.begin", "patient": w.player, "part": "leg_left", "verb": "close"})
			w.commands.push({"type": "move", "dx": 1.0, "dy": 0.0})
			w.step()
		runs.append(JSON.stringify(w.serialize()))
	if runs[0] != runs[1]:
		push_error("two identical runs serialised differently")
		return false
	if runs[0] == runs[2]:
		push_error("moving the close 7 ticks changed nothing, so the comparison proves nothing")
		return false
	print("DETERMINISM OK identical runs match, a 7-tick shift does not")
	return true
