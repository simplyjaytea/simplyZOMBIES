extends SceneTree
# Attachment slots -- docs/10-items.md#attachment-slots. "Attachments are found, not crafted, and
# move freely between compatible bases."
#
# The content validator is shallow: it checks that `attachment` is an object and stops there, so
# every claim about what is *inside* one is this gate's job. CONTENT below is that check, and it
# is written to fail on the two ways an attachment can be quietly inert -- a `fits` naming a slot
# no shipped base declares, and a multiplier keyed to a profile field nothing scales.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimSave = preload("res://sim/save.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Clock = preload("res://sim/time/clock.gd")

const SUPPRESSOR: String = "item.attach.suppressor"
const RED_DOT: String = "item.attach.optic.red_dot"
const EXT_MAG: String = "item.attach.magazine.extended"
const WRAP: String = "item.attach.wrap.leather"
const SPIKES: String = "item.attach.head.spiked"
const PISTOL: String = "item.pistol.service"
const AXE: String = "item.axe.fire"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _content_is_wired_to_something() and ok
	ok = _a_slot_accepts_what_fits_it_and_refuses_what_does_not() and ok
	ok = _an_attachment_changes_the_weapon() and ok
	ok = _it_moves_between_compatible_bases() and ok
	ok = _melee_attachments_do_the_same_thing() and ok
	ok = _the_commands_reach_it_and_refuse_out_loud() and ok
	ok = _a_fitted_attachment_survives_a_save() and ok
	if ok:
		print("M2_ATTACH_OK content fit effect move melee command save")
		quit(0)
	else:
		push_error("M2_ATTACH_FAIL")
		quit(1)


func _world() -> Variant:
	var f: Dictionary = {"seed": 31, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
	var w: Variant = World.new(f)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	SimBoot.attach_kernel(w, SimTileMap.blank_map(24, 24))
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimAttachments.register_module(w)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	return w


func _spawn(w: Variant, id: String) -> int:
	return SimItems.spawn_item(w, id, {"tier": "scavenged"})


# --- CONTENT ----------------------------------------------------------------------------------

func _content_is_wired_to_something() -> bool:
	var w: Variant = _world()
	# Every slot name any shipped base declares, so an attachment can be checked against reality
	# rather than against a list in this file that would drift from the content.
	var declared: Dictionary = {}
	var attachments: Array = []
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		for s in e.get("slots", []) as Array:
			declared[String(s)] = true
		if e.get("attachment") is Dictionary:
			attachments.append(e)
	if attachments.is_empty():
		push_error("CONTENT: no attachment items are shipped, so nothing below is testing anything")
		return false
	if declared.is_empty():
		push_error("CONTENT: no item base declares a slot")
		return false
	for e in attachments:
		var spec: Dictionary = (e as Dictionary)["attachment"] as Dictionary
		var id: String = String((e as Dictionary).get("id", "?"))
		var fits: Array = spec.get("fits", []) as Array
		if fits.is_empty():
			push_error("CONTENT: %s fits nothing" % id)
			return false
		var reachable: bool = false
		for s in fits:
			if declared.has(String(s)):
				reachable = true
		if not reachable:
			push_error("CONTENT: %s fits %s, and no shipped base declares any of those slots" % [id, str(fits)])
			return false
		for kind in ["melee", "ranged"]:
			var table: Variant = spec.get(kind)
			if not table is Dictionary:
				continue
			for key in (table as Dictionary).keys():
				if not (SimAttachments.SCALABLE[kind] as Array).has(String(key)):
					push_error("CONTENT: %s scales %s.%s, which no profile field is named" % [id, kind, String(key)])
					return false
		if spec.get("melee") == null and spec.get("ranged") == null:
			push_error("CONTENT: %s declares no effect at all" % id)
			return false
	# Findable, per docs/10: "attachments are found, not crafted". An attachment in no loot table
	# is content nobody will ever hold -- the same dead-socket shape this milestone keeps turning
	# up, and the cheapest possible place to catch it.
	# Read off the tree by path, the way check_loot.gd reads loot: `SimItems.content_entries`
	# resolves a flat content tree by shape and knows the shape of an item and an affix, not of a
	# loot table.
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
		push_error("CONTENT: no loot table entries were read, so findability is asserting nothing")
		return false
	for e in attachments:
		var aid: String = String((e as Dictionary).get("id", "?"))
		if not droppable.has(aid):
			push_error("CONTENT: %s is in no loot table, so it cannot be found" % aid)
			return false

	print("CONTENT OK %d attachments, all findable, %d slot names declared by bases" % [attachments.size(), declared.size()])
	return true


# --- FIT --------------------------------------------------------------------------------------

func _a_slot_accepts_what_fits_it_and_refuses_what_does_not() -> bool:
	var w: Variant = _world()
	var pistol: int = _spawn(w, PISTOL)
	var axe: int = _spawn(w, AXE)
	var can: int = _spawn(w, SUPPRESSOR)
	var can2: int = _spawn(w, SUPPRESSOR)

	if SimAttachments.attach(w, pistol, can, "magazine"):
		push_error("FIT: a suppressor went into a magazine slot")
		return false
	if SimAttachments.attach(w, pistol, can, "string"):
		push_error("FIT: a slot the pistol does not declare accepted an attachment")
		return false
	if SimAttachments.attach(w, axe, can, "haft"):
		push_error("FIT: a suppressor went onto an axe")
		return false
	if not SimAttachments.attach(w, pistol, can, "barrel"):
		push_error("FIT: a suppressor was refused a barrel, so every refusal above proves nothing")
		return false
	if SimAttachments.attach(w, pistol, can2, "barrel"):
		push_error("FIT: two suppressors share one barrel")
		return false
	# Already fitted somewhere: the same object cannot be on two weapons.
	var pistol2: int = _spawn(w, PISTOL)
	if SimAttachments.attach(w, pistol2, can, "barrel"):
		push_error("FIT: a fitted suppressor was fitted again to a second pistol")
		return false
	if int(SimAttachments.in_slot(w, pistol, "barrel")) != can:
		push_error("FIT: the barrel is not holding the suppressor after all that")
		return false
	print("FIT OK barrel accepts, magazine/furniture/haft refuse, one slot one item, no double-fitting")
	return true


# --- EFFECT -----------------------------------------------------------------------------------

func _noise_of(w: Variant, shooter: int) -> float:
	var loudest: float = 0.0
	# Wait for the weapon to come back to Idle. `try_begin_fire` refuses anything mid-sequence and
	# the command is consumed on the tick it is pushed, so pushing at a Recover tick asks for a
	# shot that never happens -- which read as "a suppressed pistol makes no noise" the first time.
	for i in 40:
		var rw0: Variant = w.components.get_component(shooter, "rangedWeapon")
		if rw0 is Dictionary and int((rw0 as Dictionary)["state"]) == SimRanged.FireState.Idle:
			break
		w.step()
	w.commands.push({"type": "fire"})
	for i in 60:
		w.step()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "noise.emitted" and int((e as Dictionary).get("source", -1)) == shooter:
				loudest = maxf(loudest, float((e as Dictionary).get("magnitude", 0)))
		var rw: Variant = w.components.get_component(shooter, "rangedWeapon")
		if i > 2 and loudest > 0.0 and rw is Dictionary and int((rw as Dictionary)["state"]) == SimRanged.FireState.Idle:
			break
	return loudest


# The felt cone at the tightest point of the aim, which is where an accuracy change is legible.
# Reading it at Idle proves nothing: `_refresh_cone` saturates at WIDE_HALF there, so a suppressor
# and a red dot both come back 0.5500 and the assertion passes for a multiplier of any sign. This
# cost a red gate to notice, and the shape of the mistake -- measuring where the quantity is
# clamped -- is worth more than the assertion.
func _cone_while_aiming(w: Variant) -> float:
	w.commands.push({"type": "fire"})
	var best: float = 1e9
	for i in 20:
		w.step()
		var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
		if not rw is Dictionary:
			continue
		if int((rw as Dictionary)["state"]) == SimRanged.FireState.Steady:
			best = minf(best, SimRanged.cone_half(w, w.player))
		elif best < 1e9:
			break
	return best


func _armed_pistol(w: Variant) -> int:
	var pistol: int = _spawn(w, PISTOL)
	SimInventory.equip(w, w.player, pistol)
	var ammo: int = SimItems.spawn_item(w, "item.ammo.9mm", {"tier": "scavenged", "count": 40})
	if not SimInventory.stow(w, w.player, ammo):
		w.components.set_component(ammo, "stored", {"container": w.player})
	w.events.drain()
	return pistol


func _an_attachment_changes_the_weapon() -> bool:
	var bare: Variant = _world()
	_armed_pistol(bare)
	var bare_cone: float = _cone_while_aiming(bare)
	var loud: float = _noise_of(bare, bare.player)

	var quiet: Variant = _world()
	var pistol: int = _armed_pistol(quiet)
	if not SimAttachments.attach(quiet, pistol, _spawn(quiet, SUPPRESSOR), "barrel"):
		push_error("EFFECT: could not fit the suppressor")
		return false
	var quiet_cone: float = _cone_while_aiming(quiet)
	var hushed: float = _noise_of(quiet, quiet.player)

	if loud <= 0.0 or hushed <= 0.0:
		push_error("EFFECT: no shot was heard at all (%.1f, %.1f)" % [loud, hushed])
		return false
	if hushed >= loud:
		push_error("EFFECT: a suppressed pistol is not quieter (%.1f vs %.1f)" % [hushed, loud])
		return false
	# docs/09's quiet branch: "suppressed firearm ~40 (vs. 180)". The content is what decides the
	# exact figure; this asserts it landed in that band rather than merely somewhere lower.
	if hushed > 60.0:
		push_error("EFFECT: suppressed noise %.1f is nowhere near docs/09's ~40" % hushed)
		return false
	if quiet_cone <= bare_cone:
		push_error("EFFECT: the suppressor cost no accuracy (%.4f vs %.4f)" % [quiet_cone, bare_cone])
		return false

	# The other direction, because a `cone` multiplier that only ever widened would pass the line
	# above with the sign wrong.
	var scoped: Variant = _world()
	var p2: int = _armed_pistol(scoped)
	if not SimAttachments.attach(scoped, p2, _spawn(scoped, RED_DOT), "optic"):
		push_error("EFFECT: a red dot was refused the pistol's optic slot")
		return false
	var scoped_cone: float = _cone_while_aiming(scoped)
	if scoped_cone >= bare_cone:
		push_error("EFFECT: an optic did not tighten the cone (%.4f vs %.4f)" % [scoped_cone, bare_cone])
		return false

	# An integer field, which folds differently from a float one.
	var fed: Variant = _world()
	var p3: int = _armed_pistol(fed)
	var base_mag: int = int((fed.components.get_component(fed.player, "rangedWeapon") as Dictionary)["magSize"])
	if not SimAttachments.attach(fed, p3, _spawn(fed, EXT_MAG), "magazine"):
		push_error("EFFECT: the extended magazine was refused")
		return false
	var big_mag: int = int((fed.components.get_component(fed.player, "rangedWeapon") as Dictionary)["magSize"])
	if big_mag <= base_mag:
		push_error("EFFECT: an extended magazine holds no more (%d vs %d)" % [big_mag, base_mag])
		return false
	print("EFFECT OK noise %.1f -> %.1f, cone %.4f -> %.4f suppressed / %.4f scoped, mag %d -> %d" % [loud, hushed, bare_cone, quiet_cone, scoped_cone, base_mag, big_mag])
	return true


# --- MOVES ------------------------------------------------------------------------------------

func _it_moves_between_compatible_bases() -> bool:
	var w: Variant = _world()
	var first: int = _armed_pistol(w)
	var can: int = _spawn(w, SUPPRESSOR)
	if not SimAttachments.attach(w, first, can, "barrel"):
		push_error("MOVES: could not fit the suppressor to begin with")
		return false
	var suppressed: float = _noise_of(w, w.player)

	if not SimAttachments.detach(w, can):
		push_error("MOVES: could not take the suppressor off")
		return false
	var bare_again: float = _noise_of(w, w.player)

	# A second, separate pistol. This is the whole point of the mechanism: the investment survives
	# the upgrade.
	var second: Variant = _world()
	var host: int = _armed_pistol(second)
	var moved: int = _spawn(second, SUPPRESSOR)
	if not SimAttachments.attach(second, host, moved, "barrel"):
		push_error("MOVES: the second pistol refused it")
		return false
	var moved_noise: float = _noise_of(second, second.player)

	if bare_again <= suppressed:
		push_error("MOVES: taking the suppressor off did not restore the noise (%.1f vs %.1f)" % [bare_again, suppressed])
		return false
	if absf(moved_noise - suppressed) > 0.01:
		push_error("MOVES: the same suppressor on another base gives %.1f rather than %.1f" % [moved_noise, suppressed])
		return false
	print("MOVES OK fitted %.1f, removed %.1f, refitted elsewhere %.1f" % [suppressed, bare_again, moved_noise])
	return true


# --- MELEE ------------------------------------------------------------------------------------

func _melee_attachments_do_the_same_thing() -> bool:
	var w: Variant = _world()
	var bare_axe: int = _spawn(w, AXE)
	var before: Variant = SimItems.melee_profile_of(w, bare_axe)
	if not before is Dictionary:
		push_error("MELEE: the axe has no melee profile")
		return false
	var spiked: int = _spawn(w, AXE)
	if not SimAttachments.attach(w, spiked, _spawn(w, SPIKES), "head"):
		push_error("MELEE: the spiked head was refused the axe's head slot")
		return false
	if not SimAttachments.attach(w, spiked, _spawn(w, WRAP), "wrap"):
		push_error("MELEE: the wrap was refused the axe's wrap slot")
		return false
	var after: Variant = SimItems.melee_profile_of(w, spiked)

	var d0: float = float((before as Dictionary)["damage"])
	var d1: float = float((after as Dictionary)["damage"])
	var s0: int = int((before as Dictionary)["staggerTicks"])
	var s1: int = int((after as Dictionary)["staggerTicks"])
	if d1 <= d0:
		push_error("MELEE: spikes and a wrap did not raise damage (%.2f vs %.2f)" % [d1, d0])
		return false
	if s1 <= s0:
		push_error("MELEE: spikes did not raise stagger (%d vs %d)" % [s1, s0])
		return false
	# Two attachments compose: the wrap speeds the swing up by more than the spikes slow it down
	# would be the wrong claim, so this asserts only that both were folded rather than one.
	var expected_speed: float = float((before as Dictionary)["speed"]) * 1.12 * 0.85
	if absf(float((after as Dictionary)["speed"]) - expected_speed) > 0.0001:
		push_error("MELEE: speed %.4f is not both multipliers folded (%.4f)" % [float((after as Dictionary)["speed"]), expected_speed])
		return false
	print("MELEE OK damage %.2f -> %.2f, stagger %d -> %d, both multipliers folded into speed" % [d0, d1, s0, s1])
	return true


# --- COMMAND ----------------------------------------------------------------------------------

func _the_commands_reach_it_and_refuse_out_loud() -> bool:
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var can: int = _spawn(w, SUPPRESSOR)
	w.commands.push({"type": "item.attach", "host": pistol, "item": can, "slot": "barrel"})
	w.step()
	if int(SimAttachments.in_slot(w, pistol, "barrel")) != can:
		push_error("COMMAND: item.attach did nothing")
		return false

	var refused: Array = []
	w.commands.push({"type": "item.attach", "host": pistol, "item": _spawn(w, SUPPRESSOR), "slot": "barrel"})
	w.step()
	for e in w.events.drained:
		if String((e as Dictionary).get("type", "")) == "attachment.refused":
			refused.append(e)
	if refused.is_empty():
		push_error("COMMAND: a refused attach said nothing")
		return false

	w.commands.push({"type": "item.detach", "item": can})
	w.step()
	if int(SimAttachments.in_slot(w, pistol, "barrel")) >= 0:
		push_error("COMMAND: item.detach did nothing")
		return false
	print("COMMAND OK attach, refusal published, detach")
	return true


# --- SAVE -------------------------------------------------------------------------------------

func _a_fitted_attachment_survives_a_save() -> bool:
	# The `attachments` component is keyed by slot *name* precisely so this passes -- a dictionary
	# keyed by entity id comes back from JSON with String keys and reads empty. See CLAUDE.md.
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	if not SimAttachments.attach(w, pistol, _spawn(w, SUPPRESSOR), "barrel"):
		push_error("SAVE: could not fit the suppressor")
		return false
	var before: float = float((SimItems.ranged_profile_of(w, pistol) as Dictionary)["noise"])
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	var decoded: Dictionary = SimSave.decode_save_or_throw(text)
	w.restore(decoded["snapshot"] as Dictionary)
	var after: float = float((SimItems.ranged_profile_of(w, pistol) as Dictionary)["noise"])
	if absf(after - before) > 0.01:
		push_error("SAVE: the suppressor stopped applying across a save (%.1f -> %.1f)" % [before, after])
		return false
	if SimAttachments.attached(w, pistol).is_empty():
		push_error("SAVE: the slot came back empty")
		return false
	print("SAVE OK noise %.1f survives the round trip" % after)
	return true
