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
const RIFLE: String = "item.rifle.hunting"
const STD_BARREL: String = "item.part.barrel.standard"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _content_is_wired_to_something() and ok
	ok = _every_declared_slot_has_something_that_fits() and ok
	ok = _every_scalable_field_is_scaled_by_something() and ok
	ok = _a_slot_accepts_what_fits_it_and_refuses_what_does_not() and ok
	ok = _an_attachment_changes_the_weapon() and ok
	ok = _it_moves_between_compatible_bases() and ok
	ok = _melee_attachments_do_the_same_thing() and ok
	ok = _the_commands_reach_it_and_refuse_out_loud() and ok
	ok = _a_fitted_attachment_survives_a_save() and ok
	ok = _a_worn_part_does_less_and_a_dead_one_does_nothing() and ok
	ok = _every_wear_word_is_known_and_every_known_word_is_used() and ok
	ok = _a_part_worn_through_comes_off_and_lands_somewhere() and ok
	ok = _a_weapon_arrives_assembled() and ok
	ok = _assembling_a_weapon_draws_no_randomness() and ok
	ok = _an_assembled_weapon_weighs_what_it_always_weighed() and ok
	ok = _the_default_parts_graph_resolves_and_does_not_cycle() and ok
	ok = _a_sound_part_in_a_tired_gun_is_a_repair() and ok
	ok = _every_required_slot_is_one_the_base_declares() and ok
	ok = _a_headless_spear_is_a_stick() and ok
	ok = _a_conversion_part_changes_what_the_gun_eats() and ok
	ok = _two_parts_that_disagree_make_a_gun_nobody_can_load() and ok
	ok = _every_override_names_something_real() and ok
	if ok:
		print("M2_ATTACH_OK content hosts scales fit effect move melee command save condition wears breaks assemble quiet mass cycle repair required headless override mismatch names")
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
		# A part has to do something. Multiplying a profile field is one way; *being* part of the
		# weapon is the other, and a plain barrel does the second without doing the first -- its
		# condition is the gun's condition, which is the whole of its effect.
		if spec.get("melee") == null and spec.get("ranged") == null and not bool(spec.get("structural", false)):
			push_error("CONTENT: %s declares no effect at all and is not structural" % id)
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


# --- HOSTS ------------------------------------------------------------------------------------
# CONTENT above asks whether every attachment reaches a host. This asks the other direction, which
# it was missing: whether every host reaches an attachment. Both have to hold, or the socket is
# dead from one end -- and it was. `haft` was declared by six melee bases, `furniture` by three
# firearms, `limb` and `string` by the bow, and until the second catalogue there was nothing in the
# world that fitted any of the four. Complete, correct, gated content that no player could ever
# fill, which is this milestone's own definition of a dead socket. Same shape as check_m2_gear's
# "slot with no shipped item that can fill it", one level further in.
func _every_declared_slot_has_something_that_fits() -> bool:
	var w: Variant = _world()
	var declared: Dictionary = {}
	var fitted: Dictionary = {}
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var id: String = String(e.get("id", "?"))
		for s in e.get("slots", []) as Array:
			var hosts: Array = declared.get(String(s), []) as Array
			hosts.append(id)
			declared[String(s)] = hosts
		if e.get("attachment") is Dictionary:
			for s2 in (e["attachment"] as Dictionary).get("fits", []) as Array:
				var fitters: Array = fitted.get(String(s2), []) as Array
				fitters.append(id)
				fitted[String(s2)] = fitters
	if declared.is_empty():
		push_error("HOSTS: no shipped base declares a slot, so this lane is asserting nothing")
		return false
	var empty: Array[String] = []
	for slot in declared.keys():
		if not fitted.has(String(slot)):
			empty.append("%s (declared by %d base(s))" % [String(slot), (declared[slot] as Array).size()])
	if not empty.is_empty():
		push_error("HOSTS: %s -- a slot on a shipped weapon with nothing in the world that fits it is a dead socket" % str(empty))
		return false
	# TN: the predicate has to be able to say no, and no real slot is left for it to say no about --
	# that is what the lane above just established -- so the negative is a fabricated slot name.
	if fitted.has("gate.nofitter") or declared.has("gate.nofitter"):
		push_error("HOSTS: the scans found a slot name that does not exist")
		return false
	var probe: Dictionary = declared.duplicate()
	probe["gate.nofitter"] = ["item.gate.host"]
	var caught: Array[String] = []
	for slot2 in probe.keys():
		if not fitted.has(String(slot2)):
			caught.append(String(slot2))
	if caught != ["gate.nofitter"]:
		push_error("HOSTS: the predicate cannot say no -- a fabricated slot with no fitter produced %s" % str(caught))
		return false
	print("  HOSTS OK %d slot names declared by bases, every one with at least one attachment that fits" % declared.size())
	return true


# --- SCALES -----------------------------------------------------------------------------------
# The same question asked of the code side. `SimAttachments.SCALABLE` is the allow-list `fold`
# multiplies through, and an entry in it that no shipped attachment ever names is a field the sim
# stands ready to scale and nothing asks it to -- the dead socket one level further in again, and
# invisible to CONTENT, which only ever checks the reverse (that a declared multiplier is *in*
# SCALABLE). It caught `melee.reachMetres` and `ranged.rangeMetres`: both listed since attachments
# landed, both scaled by nothing at all until the long haft and the long barrel shipped.
func _every_scalable_field_is_scaled_by_something() -> bool:
	var w: Variant = _world()
	var scaled: Dictionary = {}
	var read: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not (e.get("attachment") is Dictionary):
			continue
		read += 1
		var spec: Dictionary = e["attachment"] as Dictionary
		for kind in SimAttachments.SCALABLE.keys():
			var table: Variant = spec.get(String(kind))
			if not (table is Dictionary):
				continue
			for field in (table as Dictionary).keys():
				scaled["%s.%s" % [String(kind), String(field)]] = true
	if read == 0:
		push_error("SCALES: no attachment was read, so this lane is asserting nothing")
		return false
	var unscaled: Array[String] = []
	for kind2 in SimAttachments.SCALABLE.keys():
		for field2 in SimAttachments.SCALABLE[kind2] as Array:
			if not scaled.has("%s.%s" % [String(kind2), String(field2)]):
				unscaled.append("%s.%s" % [String(kind2), String(field2)])
	if not unscaled.is_empty():
		push_error("SCALES: %s named in SimAttachments.SCALABLE and scaled by no shipped attachment -- fold is ready to multiply it and nothing ever asks" % str(unscaled))
		return false
	# TN: the same predicate over a fabricated field list must find the one nothing scales, and
	# must not flag the one that is scaled -- otherwise it would pass by always answering empty.
	var missed: Array[String] = []
	for probe in ["damage", "gateField"]:
		if not scaled.has("melee.%s" % probe):
			missed.append(probe)
	if not missed.has("gateField") or missed.has("damage"):
		push_error("SCALES: the predicate cannot say no -- a fabricated unscaled field produced %s" % str(missed))
		return false
	print("  SCALES OK all %d fields in SimAttachments.SCALABLE are scaled by shipped content (%d attachments read)" % [scaled.size(), read])
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
	if not SimAttachments.attach(w, pistol, can, "muzzle"):
		push_error("FIT: a suppressor was refused a muzzle, so every refusal above proves nothing")
		return false
	if SimAttachments.attach(w, pistol, can2, "muzzle"):
		push_error("FIT: two suppressors share one muzzle")
		return false
	# Already fitted somewhere: the same object cannot be on two weapons.
	var pistol2: int = _spawn(w, PISTOL)
	if SimAttachments.attach(w, pistol2, can, "muzzle"):
		push_error("FIT: a fitted suppressor was fitted again to a second pistol")
		return false
	if int(SimAttachments.in_slot(w, pistol, "muzzle")) != can:
		push_error("FIT: the muzzle is not holding the suppressor after all that")
		return false
	print("FIT OK muzzle accepts, magazine/string/haft refuse, one slot one item, no double-fitting")
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
	var can: int = _spawn(quiet, SUPPRESSOR)
	if not SimAttachments.attach(quiet, pistol, can, "muzzle"):
		push_error("EFFECT: could not fit the suppressor")
		return false
	# Pinned, not assumed. Every number below is the *full* effect of this part, and once a part's
	# condition softens its multipliers (see CONDITION) a lane that did not say so would quietly
	# become a measurement of how worn a freshly spawned suppressor happens to be.
	if not is_equal_approx(_condition_of(quiet, can), SimItems.FULL_CONDITION):
		push_error("EFFECT: the suppressor is not at full condition (%.4f), so the numbers below are not its full effect" % _condition_of(quiet, can))
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
	if not _swap(fed, p3, "magazine", _spawn(fed, EXT_MAG)):
		push_error("EFFECT: the extended magazine could not replace the standard one")
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
	if not SimAttachments.attach(w, first, can, "muzzle"):
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
	if not SimAttachments.attach(second, host, moved, "muzzle"):
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
	# The axe comes with a head in it, so this is a swap rather than an addition -- which is what
	# a spiked head has always been, and what "repair by replacing a part" will be in the bench.
	if not _swap(w, spiked, "head", _spawn(w, SPIKES)):
		push_error("MELEE: the spiked head could not replace the axe's standard head")
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
	w.commands.push({"type": "item.attach", "host": pistol, "item": can, "slot": "muzzle"})
	w.step()
	if int(SimAttachments.in_slot(w, pistol, "muzzle")) != can:
		push_error("COMMAND: item.attach did nothing")
		return false

	var refused: Array = []
	w.commands.push({"type": "item.attach", "host": pistol, "item": _spawn(w, SUPPRESSOR), "slot": "muzzle"})
	w.step()
	for e in w.events.drained:
		if String((e as Dictionary).get("type", "")) == "attachment.refused":
			refused.append(e)
	if refused.is_empty():
		push_error("COMMAND: a refused attach said nothing")
		return false

	w.commands.push({"type": "item.detach", "item": can})
	w.step()
	if int(SimAttachments.in_slot(w, pistol, "muzzle")) >= 0:
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
	if not SimAttachments.attach(w, pistol, _spawn(w, SUPPRESSOR), "muzzle"):
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


# --- CONDITION --------------------------------------------------------------------------------
#
# docs/10: "suppressors wear out fast and cost accuracy". A part is an item, so it has a condition,
# and the question this lane settles is what a worn one does. The answer is *less*, not something
# worse: `effect_scale` walks each declared multiplier back toward 1.0, so a failing suppressor
# quiets less than a sound one and more than no suppressor at all.
#
# Strictly between is the whole assertion, and it needs its true negative stated as a predicate
# rather than as a second number: a *sound* part must not satisfy "strictly between sound and
# bare", or the lane would pass for an implementation where wear did nothing.
func _a_worn_part_does_less_and_a_dead_one_does_nothing() -> bool:
	var lane: String = "CONDITION"
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var bare: float = _folded_noise(w, pistol)
	var can: int = _spawn(w, SUPPRESSOR)
	if not SimAttachments.attach(w, pistol, can, "muzzle"):
		push_error("%s: could not fit the suppressor" % lane)
		return false
	var sound: float = _folded_noise(w, pistol)
	if not (sound < bare):
		push_error("%s: a sound suppressor did not quieten the pistol (%.2f vs %.2f)" % [lane, sound, bare])
		return false

	# Worn down the way the game wears it -- through the same channel a shot uses -- rather than by
	# writing a condition in and hoping the fold notices. Reading the *live* weapon afterwards is
	# what proves the fold re-reads condition on every rebuild instead of caching it at fit time.
	for i in 150:
		SimAttachments.wear_parts(w, pistol, "shot")
	var left: float = _condition_of(w, can)
	if left <= 0.0 or left >= SimItems.FULL_CONDITION:
		push_error("%s: 150 shots left the suppressor at %.4f, so this lane is asserting nothing" % [lane, left])
		return false
	var live: Variant = w.components.get_component(w.player, "rangedWeapon")
	if not live is Dictionary:
		push_error("%s: the player is not holding a built weapon" % lane)
		return false
	var worn: float = float((live as Dictionary).get("noise", 0.0))
	if not _strictly_between(worn, sound, bare):
		push_error("%s: a suppressor at %.4f condition gives %.2f, not between %.2f and %.2f" % [lane, left, worn, sound, bare])
		return false

	# TN: the same predicate, asked about a part that is not worn at all. If this says yes, the
	# assertion above is satisfied by any number lower than bare and proves nothing about wear.
	if _strictly_between(sound, sound, bare):
		push_error("%s: the predicate cannot say no -- a sound suppressor reads as a worn one" % lane)
		return false

	# And the far end: a multiplier at zero condition is exactly 1.0, no effect rather than a
	# reversed one. Asked of the helper directly, because a fitted part never reaches zero -- it
	# comes off first, which is the BREAKS lane below.
	var dead: float = SimAttachments.effect_scale(w, _dead_item(w), 0.22)
	if not is_equal_approx(dead, 1.0):
		push_error("%s: a dead part scales 0.22 to %.4f rather than to 1.0" % [lane, dead])
		return false

	print("  CONDITION OK noise %.1f bare, %.1f sound, %.1f at %.2f condition; a dead part scales to 1.0" % [bare, sound, worn, left])
	return true


# --- WEARS ------------------------------------------------------------------------------------
#
# The SCALES pattern applied to the wear vocabulary, both directions. A word in content that the
# module does not know is a part that silently never wears; a word the module knows that no content
# declares is a dead socket in the code. Neither is visible without asking.
func _every_wear_word_is_known_and_every_known_word_is_used() -> bool:
	var lane: String = "WEARS"
	var w: Variant = _world()
	var declared: Dictionary = {}
	var parts: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var spec: Variant = (entry_v as Dictionary).get("attachment")
		if not spec is Dictionary:
			continue
		parts += 1
		var words: Variant = (spec as Dictionary).get("wearsOn", [])
		if not words is Array:
			continue
		for word in words as Array:
			declared[String(word)] = String((entry_v as Dictionary).get("id", "?"))
	if parts == 0 or declared.is_empty():
		push_error("%s: %d attachments and no wearsOn between them, so this lane is asserting nothing" % [lane, parts])
		return false

	# Every declared word is one the module knows.
	var unknown: Array[String] = _words_outside(declared.keys(), SimAttachments.WEAR_EVENTS)
	if not unknown.is_empty():
		push_error("%s: content declares %s, which SimAttachments.WEAR_EVENTS does not name" % [lane, str(unknown)])
		return false
	# TN: the same predicate over a fabricated word. If it comes back empty the check above is a
	# no-op and a typo in `wearsOn` is indistinguishable from a part that never wears.
	var probe: Array = declared.keys().duplicate()
	probe.append("gate.nosuchevent")
	var caught: Array[String] = _words_outside(probe, SimAttachments.WEAR_EVENTS)
	if caught.size() != 1 or caught[0] != "gate.nosuchevent":
		push_error("%s: the predicate cannot say no about an unknown word" % lane)
		return false

	# And the other direction: every word the module knows is declared by something shipped.
	var unused: Array[String] = _words_outside(SimAttachments.WEAR_EVENTS, declared.keys())
	if not unused.is_empty():
		push_error("%s: SimAttachments.WEAR_EVENTS names %s, and no shipped part wears from it" % [lane, str(unused)])
		return false
	# TN for that direction too.
	var probe2: Array = SimAttachments.WEAR_EVENTS.duplicate()
	probe2.append("gate.unusedevent")
	var caught2: Array[String] = _words_outside(probe2, declared.keys())
	if caught2.size() != 1 or caught2[0] != "gate.unusedevent":
		push_error("%s: the predicate cannot say no about an unused word" % lane)
		return false

	print("  WEARS OK %d parts declare %d of %d wear events, each known and each used" % [parts, declared.size(), SimAttachments.WEAR_EVENTS.size()])
	return true


# --- BREAKS -----------------------------------------------------------------------------------
#
# Two things at once, because they are the same defect from opposite ends. A part worn through has
# to come off -- otherwise a dead suppressor sits in the barrel forever doing nothing. And a part
# that comes off has to land somewhere: `detach` used to leave it with no `stored`, no `position`
# and no slot, which is not "the caller decides where it goes" but "it is gone", with nothing
# raised and nothing to pick up. docs/23 carried that as a defect and this lane closes it.
func _a_part_worn_through_comes_off_and_lands_somewhere() -> bool:
	var lane: String = "BREAKS"
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var can: int = _spawn(w, SUPPRESSOR)
	if not SimAttachments.attach(w, pistol, can, "muzzle"):
		push_error("%s: could not fit the suppressor" % lane)
		return false

	# TN first: a part with condition left is still fitted after a wear tick. Without this the
	# lane below passes for an implementation that detaches on every shot.
	(w.components.get_component(can, "condition") as Dictionary)["current"] = 0.05
	SimAttachments.wear_parts(w, pistol, "shot")
	w.events.drain()
	if SimAttachments.in_slot(w, pistol, "muzzle") != can:
		push_error("%s: a suppressor with condition left came off after one shot" % lane)
		return false

	var broke: Array = []
	for i in 40:
		SimAttachments.wear_parts(w, pistol, "shot")
		w.events.drain()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "attachment.broke":
				broke.append(e)
		if SimAttachments.in_slot(w, pistol, "muzzle") < 0:
			break
	if SimAttachments.in_slot(w, pistol, "muzzle") >= 0:
		push_error("%s: the suppressor never wore through" % lane)
		return false
	if broke.size() != 1 or int((broke[0] as Dictionary).get("item", -1)) != can:
		push_error("%s: %d attachment.broke events, expected exactly one naming the suppressor" % [lane, broke.size()])
		return false
	if w.components.has_component(can, "attachedTo"):
		push_error("%s: a broken part still claims to be attached" % lane)
		return false
	if not _is_somewhere(w, can):
		push_error("%s: the broken suppressor is nowhere -- no stored, no position. This is the defect." % lane)
		return false

	# The same question of a deliberate detach rather than a break, since that is the path the
	# bench will use.
	var w2: Variant = _world()
	var p2: int = _armed_pistol(w2)
	var can2: int = _spawn(w2, SUPPRESSOR)
	if not SimAttachments.attach(w2, p2, can2, "muzzle"):
		push_error("%s: could not fit the second suppressor" % lane)
		return false
	if not SimAttachments.detach(w2, can2):
		push_error("%s: detaching from a carried weapon was refused" % lane)
		return false
	if not _is_somewhere(w2, can2):
		push_error("%s: a detached suppressor is nowhere" % lane)
		return false

	# TN for the re-homing ladder: a host that is itself nowhere -- not carried, not on the
	# ground, not in a container -- has nowhere to put the part, and the detach must refuse and
	# change nothing rather than drop the part out of the world.
	var w3: Variant = _world()
	var loose: int = _spawn(w3, PISTOL)
	var can3: int = _spawn(w3, SUPPRESSOR)
	if not SimAttachments.attach(w3, loose, can3, "muzzle"):
		push_error("%s: could not fit the third suppressor" % lane)
		return false
	if SimAttachments.detach(w3, can3):
		push_error("%s: a part came off a host that is nowhere, so it went nowhere" % lane)
		return false
	if SimAttachments.in_slot(w3, loose, "muzzle") != can3:
		push_error("%s: a refused detach changed the host anyway" % lane)
		return false

	print("  BREAKS OK worn through after %d more shots, announced once, and landed somewhere; a homeless host refuses" % broke.size())
	return true


# --- helpers for the three lanes above ---------------------------------------------------------

func _folded_noise(w: Variant, weapon: int) -> float:
	var p: Variant = SimItems.ranged_profile_of(w, weapon)
	return float((p as Dictionary).get("noise", 0.0)) if p is Dictionary else 0.0


func _condition_of(w: Variant, item: int) -> float:
	var c: Variant = w.components.get_component(item, "condition")
	return float((c as Dictionary).get("current", 1.0)) if c is Dictionary else 1.0


func _strictly_between(x: float, low: float, high: float) -> bool:
	return x > low and x < high


## An item with no condition left, for asking `effect_scale` about the far end of its own range.
func _dead_item(w: Variant) -> int:
	var item: int = _spawn(w, SUPPRESSOR)
	w.components.set_component(item, "condition", {"current": 0.0, "ceiling": 1.0})
	return item


## Whether this item is anywhere at all: on the ground, or inside something.
func _is_somewhere(w: Variant, item: int) -> bool:
	return w.components.has_component(item, "position") or w.components.has_component(item, "stored")


## Words in `these` that are not in `those`, sorted. One predicate, used for both directions of
## the WEARS whitelist and for both of its true negatives.
func _words_outside(these: Array, those: Array) -> Array[String]:
	var out: Array[String] = []
	for a in these:
		var found: bool = false
		for b in those:
			if String(a) == String(b):
				found = true
				break
		if not found:
			out.append(String(a))
	out.sort()
	return out


## Takes whatever is in a slot out and puts this in instead. A weapon arrives assembled, so most
## fitting is a swap; a lane that only ever filled an empty slot would be testing a state the
## world no longer starts in.
func _swap(w: Variant, host: int, slot: String, part: int) -> bool:
	var sitting: int = SimAttachments.in_slot(w, host, slot)
	if sitting >= 0:
		# The old part has to land somewhere before the new one goes in, and `detach` refuses when
		# it cannot -- a loose host in a gate fixture is exactly that case, so give it a place to
		# be first.
		if not w.components.has_component(host, "position") and not w.components.has_component(host, "stored"):
			if SimAttachments.carrier_of(w, host) < 0:
				w.components.set_component(host, "position", {"x": 8.5, "y": 12.5})
		if not SimAttachments.detach(w, sitting):
			return false
	return SimAttachments.attach(w, host, part, slot)


# --- ASSEMBLE ---------------------------------------------------------------------------------
#
# The base template is the receiver; the weapon in the world is an assembly. Every firearm, both
# bows and the four melee bases that are genuinely a head on a shaft declare `defaultParts`, and
# `spawn_item` fits them on the way out. What this lane has to establish is that the parts are
# *real items* -- own entity, own condition, own `attachedTo` -- and not a bookkeeping entry,
# because everything downstream (wear, swapping, the bench) depends on their being items.
func _a_weapon_arrives_assembled() -> bool:
	var lane: String = "ASSEMBLE"
	var w: Variant = _world()
	var assembled: int = 0
	var checked: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var defaults: Variant = e.get("defaultParts")
		if not defaults is Dictionary or (defaults as Dictionary).is_empty():
			continue
		checked += 1
		var host: int = _spawn(w, String(e.get("id", "")))
		var fitted: Dictionary = SimAttachments.attached(w, host)
		for slot_v in (defaults as Dictionary).keys():
			var slot: String = String(slot_v)
			if not fitted.has(slot):
				push_error("%s: %s declares a default %s and spawned without one" % [lane, String(e.get("id", "?")), slot])
				return false
			var part: int = int(fitted[slot])
			if not w.components.has_component(part, "condition"):
				push_error("%s: %s's %s is not a real item -- it has no condition" % [lane, String(e.get("id", "?")), slot])
				return false
			var link: Variant = w.components.get_component(part, "attachedTo")
			if not link is Dictionary or int((link as Dictionary)["host"]) != host:
				push_error("%s: %s's %s does not point back at its host" % [lane, String(e.get("id", "?")), slot])
				return false
			var base: Variant = SimItems.item_base_of(w, part)
			if not base is Dictionary or String((base as Dictionary).get("id", "")) != String((defaults as Dictionary)[slot]):
				push_error("%s: %s's %s is not the base it declared" % [lane, String(e.get("id", "?")), slot])
				return false
			assembled += 1
	if checked == 0:
		push_error("%s: no shipped base declares defaultParts, so this lane is asserting nothing" % lane)
		return false

	# TN: the opt-out. Without it the lane passes for an implementation that fits parts to
	# everything unconditionally, and there would be no way to spawn a bare receiver at all.
	var bare: int = SimItems.spawn_item(w, PISTOL, {"tier": "scavenged", "assemble": false})
	if not SimAttachments.attached(w, bare).is_empty():
		push_error("%s: a pistol asked to spawn unassembled came back with parts in it" % lane)
		return false

	print("  ASSEMBLE OK %d bases arrive with %d real parts between them; assemble:false comes back bare" % [checked, assembled])
	return true


# --- QUIET ------------------------------------------------------------------------------------
#
# Assembly spawns entities, and spawning an item normally rolls a tier off the `loot` stream. If
# assembling drew from it, every weapon in the world would shift the stream for everything spawned
# after it -- a change to district generation that no gate about attachments would ever notice, and
# the kind of determinism break this codebase has already paid for once. Each part is spawned at an
# explicit tier, which skips the roll; this asserts it.
func _assembling_a_weapon_draws_no_randomness() -> bool:
	var lane: String = "QUIET"
	var loud: Variant = _world()
	var quiet: Variant = _world()
	for i in 10:
		SimItems.spawn_item(loud, RIFLE, {"tier": "scavenged"})
		SimItems.spawn_item(quiet, RIFLE, {"tier": "scavenged", "assemble": false})
	var with_parts: int = _loot_state(loud)
	var without: int = _loot_state(quiet)
	if with_parts != without:
		push_error("%s: ten assembled rifles left the loot stream at %d and ten bare ones at %d" % [lane, with_parts, without])
		return false

	# TN: the same comparison against a spawn that deliberately *does* roll a tier. If the probe
	# cannot see the stream move, the equality above proves nothing about assembly.
	var rolling: Variant = _world()
	for i in 10:
		SimItems.spawn_item(rolling, RIFLE, {"assemble": false})
	if _loot_state(rolling) == without:
		push_error("%s: the probe cannot see the loot stream move -- ten tier rolls left it where it started" % lane)
		return false

	print("  QUIET OK ten assembled rifles and ten bare ones both leave the loot stream at %d; ten rolled ones move it" % with_parts)
	return true


# --- MASS -------------------------------------------------------------------------------------
#
# Fitted parts weigh what they weigh, which means every weapon in the world would have got heavier
# the day slice 3 landed -- encumbrance, movement, the whole campaign -- unless each receiver's own
# massKg came down by what its parts now carry. It did. The expectation is written out here rather
# than read back off the content, on check_worn.gd's EXPECT_ORDER precedent: a gate that reads the
# value under test and compares it to itself is a gate that cannot fail.
const MASS_BEFORE_ASSEMBLY: Dictionary = {
	"item.bow.hunting": 1.10, "item.pistol.service": 0.90, "item.shotgun.pump": 3.40,
	"item.rifle.hunting": 3.60, "item.crossbow.hunting": 2.60, "item.revolver.snub": 0.80,
	"item.rifle.rimfire": 2.40, "item.spear.improvised": 1.40, "item.axe.fire": 3.20,
	"item.sledge.demolition": 6.40, "item.axe.splitting": 4.10,
	# Bases that never existed unassembled carry their *intended* assembled mass instead. The
	# lane's job is the same either way -- catching a receiver or a part whose weight drifted --
	# and the alternative is a table that silently stops covering everything it should.
	"item.smg.compact": 2.55,
}

func _an_assembled_weapon_weighs_what_it_always_weighed() -> bool:
	var lane: String = "MASS"
	var w: Variant = _world()
	var contents := func(item: int) -> Array: return SimInventory.contents_of(w, item)
	var checked: int = 0
	for id_v in MASS_BEFORE_ASSEMBLY.keys():
		var id: String = String(id_v)
		var host: int = _spawn(w, id)
		if SimAttachments.attached(w, host).is_empty():
			push_error("%s: %s is in the table and spawned with no parts, so its mass is not an assembly's" % [lane, id])
			return false
		var now: float = SimItems.item_mass_kg(w, host, contents)
		var then: float = float(MASS_BEFORE_ASSEMBLY[id])
		if absf(now - then) > 0.005:
			push_error("%s: %s assembles to %.3f kg, and weighed %.3f before it came apart" % [lane, id, now, then])
			return false
		checked += 1
	if checked == 0:
		push_error("%s: nothing was weighed" % lane)
		return false

	# The table has to stay total, or it stops being a gate and becomes a list of the weapons
	# somebody remembered. Until 2026-09-10 it covered all eleven assembled bases by accident
	# rather than by rule, and a twelfth could have been added weighing anything at all.
	for entry_v in SimItems.content_entries(w, "item"):
		var entry: Dictionary = entry_v as Dictionary
		if not (entry.get("defaultParts") is Dictionary):
			continue
		if (entry["defaultParts"] as Dictionary).is_empty():
			continue
		if not MASS_BEFORE_ASSEMBLY.has(String(entry.get("id", ""))):
			push_error("%s: %s spawns with parts and is in no mass table, so nothing checks what it weighs" % [lane, String(entry.get("id", ""))])
			return false

	# TN: stripping a part has to actually change the number, or item_mass_kg is not counting
	# parts at all and every equality above is the receiver's own mass matching itself.
	var rifle: int = _spawn(w, RIFLE)
	var full: float = SimItems.item_mass_kg(w, rifle, contents)
	var barrel: int = SimAttachments.in_slot(w, rifle, "barrel")
	w.components.set_component(rifle, "position", {"x": 8.5, "y": 12.5})
	if barrel < 0 or not SimAttachments.detach(w, barrel):
		push_error("%s: could not take the rifle's barrel off" % lane)
		return false
	var stripped: float = SimItems.item_mass_kg(w, rifle, contents)
	if not (stripped < full):
		push_error("%s: taking the barrel off changed nothing (%.3f vs %.3f) -- parts are not being weighed" % [lane, stripped, full])
		return false

	print("  MASS OK %d assembled bases weigh what they were authored at; stripping a barrel drops %.3f kg" % [checked, full - stripped])
	return true


# --- CYCLE ------------------------------------------------------------------------------------
#
# `defaultParts` names bases by id, so the content can describe a graph the depth guard would have
# to catch at runtime. Better to refuse it here: every slot named is one the host declares, every
# value is an attachment that fits that slot, and nothing reaches itself.
func _the_default_parts_graph_resolves_and_does_not_cycle() -> bool:
	var lane: String = "CYCLE"
	var w: Variant = _world()
	var graph: Dictionary = {}
	var entries: Dictionary = {}
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		entries[String(e.get("id", ""))] = e
		var defaults: Variant = e.get("defaultParts")
		if defaults is Dictionary and not (defaults as Dictionary).is_empty():
			graph[String(e.get("id", ""))] = defaults
	if graph.is_empty():
		push_error("%s: no base declares defaultParts, so this lane is asserting nothing" % lane)
		return false
	for id_v in graph.keys():
		var id: String = String(id_v)
		var host: Dictionary = entries[id] as Dictionary
		var slots: Array = host.get("slots", []) as Array
		for slot_v in (graph[id] as Dictionary).keys():
			var slot: String = String(slot_v)
			var part_id: String = String((graph[id] as Dictionary)[slot])
			if not _has(slots, slot):
				push_error("%s: %s defaults a %s and does not declare that slot" % [lane, id, slot])
				return false
			if not entries.has(part_id):
				push_error("%s: %s defaults %s, which is not a shipped base" % [lane, id, part_id])
				return false
			var spec: Variant = (entries[part_id] as Dictionary).get("attachment")
			if not spec is Dictionary or not _has((spec as Dictionary).get("fits", []) as Array, slot):
				push_error("%s: %s defaults %s into %s, and it does not fit there" % [lane, id, part_id, slot])
				return false
	var cycles: Array[String] = _cyclic_in(graph)
	if not cycles.is_empty():
		push_error("%s: defaultParts cycles through %s" % [lane, str(cycles)])
		return false

	# TN: a fabricated cycle through the same detector.
	var probe: Dictionary = graph.duplicate(true)
	probe["gate.a"] = {"slot": "gate.b"}
	probe["gate.b"] = {"slot": "gate.a"}
	var caught: Array[String] = _cyclic_in(probe)
	if caught.size() != 2:
		push_error("%s: the detector cannot see a cycle -- a fabricated pair produced %s" % [lane, str(caught)])
		return false

	print("  CYCLE OK %d bases default %d parts, every slot declared, every part fitting, no cycles" % [graph.size(), _graph_edges(graph)])
	return true


# --- REPAIR -----------------------------------------------------------------------------------
#
# What "repair by swapping a part" means mechanically, and the reason `structural` exists. A gun is
# only as good as the barrel in it: a worn structural part drags the whole assembly's condition
# down, and fitting a sound one puts it back -- without touching the repair ceiling, because
# nothing was mended. An optic is not structural and must not do either.
func _a_sound_part_in_a_tired_gun_is_a_repair() -> bool:
	var lane: String = "REPAIR"
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var whole: float = SimItems.assembly_condition(w, pistol)
	var damage_whole: float = _folded_damage(w, pistol)

	var barrel: int = SimAttachments.in_slot(w, pistol, "barrel")
	if barrel < 0:
		push_error("%s: the pistol spawned with no barrel to tire out" % lane)
		return false
	(w.components.get_component(barrel, "condition") as Dictionary)["current"] = 0.3
	SimItems.refresh_armed(w, pistol)
	var tired: float = SimItems.assembly_condition(w, pistol)
	var damage_tired: float = _folded_damage(w, pistol)
	if not (tired < whole):
		push_error("%s: a barrel at 0.30 left the assembly at %.4f, the same as whole" % [lane, tired])
		return false
	if not (damage_tired < damage_whole):
		push_error("%s: a worn barrel cost the pistol no damage (%.4f vs %.4f)" % [lane, damage_tired, damage_whole])
		return false

	# The repair: a sound barrel in place of the tired one, and the gun is itself again.
	if not _swap(w, pistol, "barrel", _spawn(w, STD_BARREL)):
		push_error("%s: could not fit a fresh barrel" % lane)
		return false
	var mended: float = _folded_damage(w, pistol)
	if absf(mended - damage_whole) > 0.0001:
		push_error("%s: a fresh barrel did not restore the pistol (%.4f vs %.4f)" % [lane, mended, damage_whole])
		return false
	var ceiling: float = float((w.components.get_component(pistol, "condition") as Dictionary).get("ceiling", 1.0))
	if absf(ceiling - SimItems.FULL_CONDITION) > 0.0001:
		push_error("%s: swapping a part cost the weapon %.4f of its ceiling, and nothing was mended" % [lane, SimItems.FULL_CONDITION - ceiling])
		return false

	# TN: the same treatment of a part that is *not* structural must move nothing. Without this
	# the lane passes for an implementation where every part's condition drags the gun down, and
	# `structural` would be a flag nothing reads.
	var w2: Variant = _world()
	var p2: int = _armed_pistol(w2)
	var sight: int = _spawn(w2, RED_DOT)
	if not SimAttachments.attach(w2, p2, sight, "optic"):
		push_error("%s: the red dot was refused" % lane)
		return false
	var before: float = SimItems.assembly_condition(w2, p2)
	(w2.components.get_component(sight, "condition") as Dictionary)["current"] = 0.05
	SimItems.refresh_armed(w2, p2)
	if absf(SimItems.assembly_condition(w2, p2) - before) > 0.0001:
		push_error("%s: a worn optic dragged the assembly down, and an optic is not structural" % lane)
		return false

	print("  REPAIR OK a barrel at 0.30 takes the assembly to %.2f and the damage with it; a fresh one restores both, ceiling untouched" % tired)
	return true


# --- helpers for the slice-3 lanes -------------------------------------------------------------

func _folded_damage(w: Variant, weapon: int) -> float:
	var p: Variant = SimItems.ranged_profile_of(w, weapon)
	return float((p as Dictionary).get("damage", 0.0)) if p is Dictionary else 0.0


## Where the `loot` stream has got to. SimRngStream keeps no draw counter, but `_state` *is* the
## position -- one `next()` advances it and nothing else does -- so two worlds that drew the same
## number of times from the same seed hold the same number here.
func _loot_state(w: Variant) -> int:
	return int((w.rng.stream("loot") as Object).get("_state"))


func _has(list: Array, want: String) -> bool:
	for x in list:
		if String(x) == want:
			return true
	return false


func _graph_edges(graph: Dictionary) -> int:
	var n: int = 0
	for k in graph.keys():
		n += (graph[k] as Dictionary).size()
	return n


## Ids that can reach themselves through defaultParts, sorted. Plain reachability rather than a
## colouring walk: the graph is a dozen nodes deep at most.
func _cyclic_in(graph: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	for start_v in graph.keys():
		var start: String = String(start_v)
		var seen: Dictionary = {}
		var queue: Array[String] = []
		for slot in (graph[start] as Dictionary).keys():
			queue.append(String((graph[start] as Dictionary)[slot]))
		while not queue.is_empty():
			var here: String = queue.pop_back()
			if here == start:
				bad.append(start)
				break
			if seen.has(here) or not graph.has(here):
				continue
			seen[here] = true
			for slot2 in (graph[here] as Dictionary).keys():
				queue.append(String((graph[here] as Dictionary)[slot2]))
	bad.sort()
	return bad


# --- REQUIRED ---------------------------------------------------------------------------------
#
# `requiredSlots` is a list of slot names on a base, and nothing in the schema can check it against
# the sibling `slots` list, or against the nouns the refusal sentence needs. A slot required but
# never declared would block the weapon forever with no way to unblock it -- the worst possible
# shape for this feature -- and a required slot with no noun would read as "has no ".
func _every_required_slot_is_one_the_base_declares() -> bool:
	var lane: String = "REQUIRED"
	var w: Variant = _world()
	var bases: int = 0
	var required: Dictionary = {}
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var req: Variant = e.get("requiredSlots")
		if not req is Array or (req as Array).is_empty():
			continue
		bases += 1
		var id: String = String(e.get("id", "?"))
		var slots: Array = e.get("slots", []) as Array
		var defaults: Variant = e.get("defaultParts")
		for slot_v in req as Array:
			var slot: String = String(slot_v)
			required[slot] = true
			if not _has(slots, slot):
				push_error("%s: %s requires a %s and does not declare that slot -- nothing could ever fill it" % [lane, id, slot])
				return false
			# And it has to arrive filled, or every one of these weapons spawns as a brick.
			if not defaults is Dictionary or not (defaults as Dictionary).has(slot):
				push_error("%s: %s requires a %s and does not default one, so it spawns unusable" % [lane, id, slot])
				return false
			if not SimAttachments.SLOT_NOUN.has(slot):
				push_error("%s: %s requires a %s and SLOT_NOUN has no word for it" % [lane, id, slot])
				return false
		# The sentence goes on the HUD, where check_hud.gd allows no digits at all.
		var name: String = String(e.get("name", ""))
		for c in name:
			if c >= "0" and c <= "9":
				push_error("%s: %s is named '%s', and its refusal sentence would put a digit on the HUD" % [lane, id, name])
				return false
	if bases == 0:
		push_error("%s: no shipped base requires a slot, so requiredSlots is read by nothing" % lane)
		return false
	# Both halves of the game, or the melee reader ships unexercised by content.
	if not (required.has("barrel") and required.has("head")):
		push_error("%s: required slots are %s -- one side of the game declares none" % [lane, str(required.keys())])
		return false

	print("  REQUIRED OK %d bases require %d distinct slots, each declared, each defaulted, each with a word" % [bases, required.size()])
	return true


# --- HEADLESS ---------------------------------------------------------------------------------
#
# The melee half of the required-slot rule. `SimMelee.try_begin_swing` is the mirror of
# `SimRanged._idle_weapon` and needs its own assertion, or `requiredSlots` on the four melee bases
# that declare it is a content edit nothing reads. A spear with no head is a shaft.
func _a_headless_spear_is_a_stick() -> bool:
	var lane: String = "HEADLESS"
	var w: Variant = _world()
	var spear: int = _spawn(w, "item.spear.improvised")
	if not SimInventory.equip(w, w.player, spear, "primary"):
		push_error("%s: the spear would not go in the hand" % lane)
		return false
	w.events.drain()

	# TN first: a whole spear swings, so a refusal below is about the head and not about the arena.
	if not SimMelee.try_begin_swing(w, w.player):
		push_error("%s: a whole spear would not swing, so the refusal below proves nothing" % lane)
		return false
	var swing: Dictionary = w.components.get_component(w.player, "swing") as Dictionary
	swing["state"] = SimMelee.SwingState.Idle
	swing["ticksLeft"] = 0

	var head: int = SimAttachments.in_slot(w, spear, "head")
	if head < 0 or not SimAttachments.detach(w, head):
		push_error("%s: could not take the spear's head off" % lane)
		return false
	if SimMelee.try_begin_swing(w, w.player):
		push_error("%s: a shaft with no head swung anyway" % lane)
		return false
	w.events.drain()
	var refused: String = ""
	for e in w.events.drained:
		if String((e as Dictionary).get("type", "")) == "weapon.refused" and int((e as Dictionary).get("entity", -1)) == w.player:
			refused = String((e as Dictionary).get("reason", ""))
	if refused != "missing:head":
		push_error("%s: the refusal was '%s', not missing:head" % [lane, refused])
		return false

	# And the sentence the screen would print, since a reason id is not a thing a player reads.
	var said: String = SimAttachments.refusal_clause(w, w.player)
	if said.is_empty() or not said.contains("head"):
		push_error("%s: the refusal clause reads '%s'" % [lane, said])
		return false

	print("  HEADLESS OK a whole spear swings, a headless one refuses as missing:head and says \"%s\"" % said)
	return true


# --- OVERRIDE ---------------------------------------------------------------------------------
#
# A caliber is not a multiplier, so `overrides` replaces the field outright. What this lane has to
# establish is not that the profile *says* a different round -- that is one dictionary assignment
# -- but that firing actually **spends** that round, because a field nothing reads is the failure
# this milestone has paid for eleven times.
func _a_conversion_part_changes_what_the_gun_eats() -> bool:
	var lane: String = "OVERRIDE"
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var stock_ammo: String = _profile_ammo(w, pistol)
	if stock_ammo != "item.ammo.9mm":
		push_error("%s: a service pistol takes %s, so this lane starts from the wrong place" % [lane, stock_ammo])
		return false
	if not _swap(w, pistol, "barrel", _spawn(w, "item.part.barrel.rimfire")):
		push_error("%s: the conversion barrel would not go on" % lane)
		return false
	if _profile_ammo(w, pistol) != "item.ammo.22":
		push_error("%s: a rimfire barrel left the pistol taking %s" % [lane, _profile_ammo(w, pistol)])
		return false

	# The reader: give it only the new round and it must fire; that is `_has_ammo` and
	# `_consume_ammo` both agreeing with the override rather than with the base.
	var w2: Variant = _world()
	var p2: int = _spawn(w2, PISTOL)
	SimInventory.equip(w2, w2.player, p2)
	if not _swap(w2, p2, "barrel", _spawn(w2, "item.part.barrel.rimfire")):
		push_error("%s: the conversion barrel would not go on the second pistol" % lane)
		return false
	var small: int = SimItems.spawn_item(w2, "item.ammo.22", {"tier": "scavenged", "count": 20})
	if not SimInventory.stow(w2, w2.player, small):
		w2.components.set_component(small, "stored", {"container": w2.player})
	w2.events.drain()
	if _noise_of(w2, w2.player) <= 0.0:
		push_error("%s: a converted pistol with the right rounds did not fire" % lane)
		return false

	# TN: the same pistol with only the round it *used* to take. If it fires on those, nothing is
	# reading the override and the assertion above is a dictionary comparing itself.
	var w3: Variant = _world()
	var p3: int = _spawn(w3, PISTOL)
	SimInventory.equip(w3, w3.player, p3)
	if not _swap(w3, p3, "barrel", _spawn(w3, "item.part.barrel.rimfire")):
		push_error("%s: the conversion barrel would not go on the third pistol" % lane)
		return false
	var big: int = SimItems.spawn_item(w3, "item.ammo.9mm", {"tier": "scavenged", "count": 20})
	if not SimInventory.stow(w3, w3.player, big):
		w3.components.set_component(big, "stored", {"container": w3.player})
	w3.events.drain()
	if _noise_of(w3, w3.player) > 0.0:
		push_error("%s: a converted pistol fired the round it no longer takes" % lane)
		return false

	# And a replacement keyed to a field OVERRIDABLE does not name is dropped, exactly as an
	# unknown multiplier is -- the same whitelist discipline, asked of the other table.
	if not (SimAttachments.OVERRIDABLE["ranged"] as Array).has("ammo"):
		push_error("%s: OVERRIDABLE no longer names ammo" % lane)
		return false
	if SimAttachments.OVERRIDABLE.has("melee"):
		push_error("%s: OVERRIDABLE grew a melee table -- if something reads it, this lane needs a case; if not, it is a dead socket" % lane)
		return false

	print("  OVERRIDE OK 9mm -> .22, fires on the new round and refuses the old one")
	return true


# --- MISMATCH ---------------------------------------------------------------------------------
#
# Overrides are resolved by *agreement*, not by order. One distinct value wins however many parts
# said it; two distinct values are a gun nobody can load, and it says so rather than silently
# picking the alphabetically-first slot.
#
# The half that matters is the negative: two parts declaring the **same** round must not block. A
# lane that only checked the disagreement would pass for a rule that blocks any two overriding
# parts at all -- which would make the matched conversion kit, the good case, unbuildable.
func _two_parts_that_disagree_make_a_gun_nobody_can_load() -> bool:
	var lane: String = "MISMATCH"

	# The matched set first: a conversion barrel and the magazine that feeds it.
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	if not _swap(w, pistol, "barrel", _spawn(w, "item.part.barrel.rimfire")):
		push_error("%s: the conversion barrel would not go on" % lane)
		return false
	if not _swap(w, pistol, "magazine", _spawn(w, "item.part.magazine.rimfire")):
		push_error("%s: the matching magazine would not go on" % lane)
		return false
	if SimAttachments.blocked_reason(w, pistol) != "":
		push_error("%s: a barrel and a magazine that agree blocked the pistol as '%s'" % [lane, SimAttachments.blocked_reason(w, pistol)])
		return false
	if _profile_ammo(w, pistol) != "item.ammo.22":
		push_error("%s: two parts agreeing on .22 gave %s" % [lane, _profile_ammo(w, pistol)])
		return false

	# Now the disagreement: a magnum cylinder in the action of a rimfire-barrelled pistol.
	var w2: Variant = _world()
	var p2: int = _armed_pistol(w2)
	if not _swap(w2, p2, "barrel", _spawn(w2, "item.part.barrel.rimfire")):
		push_error("%s: the conversion barrel would not go on the second pistol" % lane)
		return false
	if not _swap(w2, p2, "internal", _spawn(w2, "item.part.internal.magnum")):
		push_error("%s: the magnum cylinder would not go in" % lane)
		return false
	if SimAttachments.blocked_reason(w2, p2) != "mismatch:ammo":
		push_error("%s: a .22 barrel and a .38 cylinder blocked as '%s'" % [lane, SimAttachments.blocked_reason(w2, p2)])
		return false
	if SimRanged.can_fire(w2, w2.player):
		push_error("%s: a mismatched pistol reports that it can fire" % lane)
		return false
	if _noise_of(w2, w2.player) > 0.0:
		push_error("%s: a mismatched pistol fired anyway" % lane)
		return false
	var said: String = SimAttachments.refusal_clause(w2, w2.player)
	if said.is_empty():
		push_error("%s: a mismatched weapon says nothing to the player" % lane)
		return false

	# Order-independence, stated rather than assumed: fit them the other way round and get the
	# same answer. This is what "by agreement, not by order" buys and it is one line to check.
	var w3: Variant = _world()
	var p3: int = _armed_pistol(w3)
	if not _swap(w3, p3, "internal", _spawn(w3, "item.part.internal.magnum")):
		push_error("%s: the magnum cylinder would not go in first" % lane)
		return false
	if not _swap(w3, p3, "barrel", _spawn(w3, "item.part.barrel.rimfire")):
		push_error("%s: the conversion barrel would not go on second" % lane)
		return false
	if SimAttachments.blocked_reason(w3, p3) != "mismatch:ammo":
		push_error("%s: fitting the same two parts in the other order gave '%s'" % [lane, SimAttachments.blocked_reason(w3, p3)])
		return false

	# The `jams` half of OVERRIDABLE, or it is a whitelist entry nothing exercises.
	var w4: Variant = _world()
	var p4: int = _armed_pistol(w4)
	(w4.components.get_component(p4, "condition") as Dictionary)["current"] = 0.3
	SimItems.refresh_armed(w4, p4)
	var jumpy: float = float((SimItems.ranged_profile_of(w4, p4) as Dictionary).get("jamChance", 0.0))
	if jumpy <= 0.0:
		push_error("%s: a worn pistol has no jam chance, so the match action proves nothing" % lane)
		return false
	if not _swap(w4, p4, "internal", _spawn(w4, "item.attach.internal.match")):
		push_error("%s: the match action would not go in" % lane)
		return false
	var built: Dictionary = SimItems.ranged_profile_of(w4, p4) as Dictionary
	if bool(built.get("jams", true)):
		push_error("%s: a match action left the pistol still able to jam" % lane)
		return false
	if float(built.get("jamChance", 1.0)) != 0.0:
		push_error("%s: jams went false and jamChance stayed %.4f -- the re-derivation after the fold is missing" % [lane, float(built.get("jamChance", 1.0))])
		return false

	print("  MISMATCH OK a matched kit works, .22 against .38 blocks either way round, and a match action zeroes a %.2f jam chance" % jumpy)
	return true


# --- NAMES ------------------------------------------------------------------------------------
#
# An override naming a round that does not exist is a weapon that can never be loaded, and the
# validator cannot see inside `overrides` to say so.
func _every_override_names_something_real() -> bool:
	var lane: String = "NAMES"
	var w: Variant = _world()
	var bases: Dictionary = {}
	for entry_v in SimItems.content_entries(w, "item"):
		bases[String((entry_v as Dictionary).get("id", ""))] = entry_v
	var droppable: Dictionary = _loot_ids()
	var declared: int = 0
	var fields: Dictionary = {}
	for id_v in bases.keys():
		var spec: Variant = (bases[id_v] as Dictionary).get("attachment")
		if not spec is Dictionary:
			continue
		var block: Variant = (spec as Dictionary).get("overrides")
		if not block is Dictionary:
			continue
		for kind_v in (block as Dictionary).keys():
			var kind: String = String(kind_v)
			if not SimAttachments.OVERRIDABLE.has(kind):
				push_error("%s: %s overrides a '%s' profile, which OVERRIDABLE does not name" % [lane, String(id_v), kind])
				return false
			for field_v in ((block as Dictionary)[kind] as Dictionary).keys():
				var field: String = String(field_v)
				if not (SimAttachments.OVERRIDABLE[kind] as Array).has(field):
					push_error("%s: %s overrides %s.%s, which is not overridable" % [lane, String(id_v), kind, field])
					return false
				fields[field] = true
				declared += 1
				if field != "ammo":
					continue
				var round_id: String = String(((block as Dictionary)[kind] as Dictionary)[field])
				if not bases.has(round_id):
					push_error("%s: %s converts to %s, which is not a shipped base" % [lane, String(id_v), round_id])
					return false
				if not droppable.has(round_id):
					push_error("%s: %s converts to %s, which is in no loot table -- a caliber nobody can find" % [lane, String(id_v), round_id])
					return false
	if declared == 0:
		push_error("%s: nothing shipped declares an override, so OVERRIDABLE is read by no content" % lane)
		return false
	for field_v in SimAttachments.OVERRIDABLE["ranged"]:
		if not fields.has(String(field_v)):
			push_error("%s: OVERRIDABLE names ranged.%s and no shipped part replaces it" % [lane, String(field_v)])
			return false

	print("  NAMES OK %d overrides across %d fields, every caliber shipped and findable" % [declared, fields.size()])
	return true


func _profile_ammo(w: Variant, weapon: int) -> String:
	var p: Variant = SimItems.ranged_profile_of(w, weapon)
	return String((p as Dictionary).get("ammo", "")) if p is Dictionary else ""


## Every item id any loot table can yield. The same walk the CONTENT lane does, lifted out so the
## NAMES lane can ask the findability question about a caliber rather than about a part.
func _loot_ids() -> Dictionary:
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
	return droppable
