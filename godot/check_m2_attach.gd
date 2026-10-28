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
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimBarrel = preload("res://sim/barrel.gd")
const SimInfection = preload("res://sim/modules/infection.gd")
const SimLightModule = preload("res://sim/modules/light.gd")
const SimSave = preload("res://sim/save.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")

const SUPPRESSOR: String = "item.attach.suppressor"
const RED_DOT: String = "item.attach.optic.red_dot"
const EXT_MAG: String = "item.attach.magazine.extended"
const WRAP: String = "item.attach.wrap.leather"
const SPIKES: String = "item.attach.head.spiked"
const PISTOL: String = "item.pistol.service"
const AXE: String = "item.axe.fire"
const RIFLE: String = "item.rifle.hunting"
const STD_BARREL: String = "item.part.barrel.standard"
const WEAPON_LIGHT: String = "item.attach.underbarrel.light"
const FOREGRIP: String = "item.attach.underbarrel.grip"
const WOOD_BAT: String = "item.bat.wood"
const ALU_BAT: String = "item.bat.aluminium"
const PIPE: String = "item.pipe.steel"
const SABRE: String = "item.sabre.cavalry"
const NAILS: String = "item.attach.stud.nails"
const GLASS: String = "item.attach.stud.glass"
const SCREWS: String = "item.attach.stud.screws"
const BOLTS: String = "item.attach.stud.bolts"
const BATON: String = "item.baton.police"
const CLAW_HAMMER: String = "item.hammer.claw"
const KNUCKLE: String = "item.attach.guard.knuckle"
const PIPE_CAP: String = "item.attach.weight.pipe_cap"
const SCYTHE: String = "item.attach.head.scythe"
const PITCHFORK_HEAD: String = "item.attach.head.pitchfork"
const CORD_WRAP: String = "item.attach.wrap.cord"
const MELEE_FAMILIES: Array[String] = ["club", "blade", "polearm", "tool"]
const NEW_SLOTS: Array[String] = ["stud", "guard", "weight"]


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
	ok = _a_fitted_light_lights_whoever_is_holding_it() and ok
	ok = _armour_slots_carry_armour() and ok
	ok = _an_affix_reaches_the_swing_it_names() and ok
	ok = _an_affix_reaches_the_wear_it_names() and ok
	ok = _an_affix_reaches_the_repair_it_names() and ok
	ok = _the_ranged_prefixes_reach_what_they_name() and ok
	ok = _the_ranged_clocks_and_accuracy_reach_the_gun_they_name() and ok
	ok = _every_melee_base_has_a_family_and_the_new_slots_have_hosts() and ok
	ok = _every_applies_to_names_a_real_family_or_base_and_every_recipe_has_a_host() and ok
	ok = _a_part_goes_on_where_its_slot_and_its_family_say_and_nowhere_else() and ok
	ok = _an_improvised_part_is_made_from_what_is_carried_and_fitted() and ok
	ok = _a_glass_blade_cuts_the_hand_that_holds_it_until_it_is_wrapped() and ok
	ok = _studs_come_out_at_their_rate_and_the_swing_after_is_bare() and ok
	ok = _a_lashed_head_flies_off_at_the_swingers_feet() and ok
	ok = _a_blade_dulls_on_each_connect_and_a_club_takes_no_edge() and ok
	ok = _a_whetstone_hones_a_blade_and_each_refusal_says_why() and ok
	ok = _a_real_connect_sheds_a_stud_through_the_swing_command() and ok
	ok = _wear_rolls_draw_only_the_melee_wear_stream() and ok
	ok = _the_vocabulary_refuses_a_typo_out_loud() and ok
	ok = _the_shipped_six_keep_their_numbers() and ok
	ok = _length_moves_the_shot_it_names() and ok
	ok = _quality_moves_the_cone_it_names() and ok
	ok = _material_moves_the_wear_it_names() and ok
	ok = _a_slow_round_loses_damage_past_its_falloff() and ok
	ok = _barrel_words_are_said_in_words() and ok
	ok = _every_firearm_is_built_with_its_internals() and ok
	if ok:
		print("M2_ATTACH_OK content hosts scales fit effect move melee command save condition wears breaks assemble quiet mass cycle repair required headless override mismatch names light armor swing wear salvage family applies plausible improvise cut stud lash edge hone connect stream barrel barrel_words internals")
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
	SimLightModule.register_module(w)
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
		# Every kind SCALABLE knows, read off SCALABLE itself rather than off a list here: the
		# `armor` table joined it with the armour-slot slice, and a hand-written pair of kinds
		# would have let an armour part scale `foot_left` -- a part which no body armour declares
		# and `fold` would silently drop -- with nothing to say so.
		for kind_v in SimAttachments.SCALABLE.keys():
			var kind: String = String(kind_v)
			var table: Variant = spec.get(kind)
			if not table is Dictionary:
				continue
			for key in (table as Dictionary).keys():
				if not (SimAttachments.SCALABLE[kind] as Array).has(String(key)):
					push_error("CONTENT: %s scales %s.%s, which no profile field is named" % [id, kind, String(key)])
					return false
		# A part has to do something. Multiplying a profile field is one way; *being* part of the
		# weapon is the other, and a plain barrel does the second without doing the first -- its
		# condition is the gun's condition, which is the whole of its effect. Throwing light is
		# the third, added 2026-09-10 with the weapon light: it multiplies nothing and the weapon
		# is not made of it, and it is the most visible thing any attachment does. The block is
		# top-level rather than under `attachment` because it is the same `light` a lamp declares,
		# read by the same `SimLightModule.light_reach_of`.
		# The fourth and fifth ways, both added with the armour slots: a plate, a lining or a visor
		# multiplies its host's coverage, and a pouch holds things. Like `light`, `container` is a
		# top-level block rather than one under `attachment`, because it is the same `container` a
		# pack declares, read by the same SimInventory.reachable_containers.
		var lights: bool = (e as Dictionary).get("light") is Dictionary
		var holds: bool = (e as Dictionary).get("container") is Dictionary
		var scales: bool = false
		for kind2 in SimAttachments.SCALABLE.keys():
			if spec.get(String(kind2)) is Dictionary:
				scales = true
		if not scales and not bool(spec.get("structural", false)) and not lights and not holds:
			push_error("CONTENT: %s declares no effect at all, is not structural, throws no light and holds nothing" % id)
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
		# A recipe part is made, not found. The melee arc's exemption is narrow on purpose: it is
		# not a way out of findability, it is a claim that the part is improvised, and the MELEE
		# RECIPE lane holds that claim to a real recipe that `item.improvise` can run.
		if (e as Dictionary)["attachment"].get("recipe") is Dictionary:
			continue
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
		# Resolved, not raw: a barrel's `ranged` numbers are its words' product, and the words are what
		# the content says. Read raw, a barrel would look like it scales nothing.
		var spec: Dictionary = SimBarrel.resolve(e["attachment"] as Dictionary)
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
	SimRanged.load_held(w, w.player)
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
	"item.smg.compact": 2.55, "item.carbine.lever": 3.20, "item.pistol.target": 1.10,
	"item.shotgun.sawnoff": 2.20, "item.bow.recurve": 0.78, "item.crossbow.repeating": 2.68,
	"item.pitchfork.barn": 2.70,
	# The first entry here that is not a weapon. A plate carrier is an assembly on the same terms
	# a rifle is -- 1.40 of webbing plus the 1.80 plate in the front pouch -- and that is the
	# whole reason it is worth weighing: the plate is most of what the wearer is carrying, so a
	# carrier that stopped counting its plate would be the mass bug this lane exists to catch.
	"item.vest.carrier": 3.20,
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
	SimRanged.load_held(w2, w2.player)
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
	SimRanged.load_held(w3, w3.player)
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


# --- LIGHT --------------------------------------------------------------------------------------
#
# docs/10 has promised since attachments landed that "a weapon light is an attention emitter aimed
# at whatever you're looking at", and docs/23 has carried the open half of it ever since. This is
# the light-source half: a torch under a barrel lights the person holding the barrel.
#
# The lane exists as much for the *collision* as for the feature. `light_source` has two writers on
# a survivor -- what they carry, and the muzzle flash -- and the flash used to overwrite the
# component and then delete it when it expired, guarded on the magnitude still equalling the flash,
# which the overwrite had just guaranteed. A mounted light therefore went out permanently on the
# first shot, silently. Nothing would have caught that except an assertion that fires the gun.

func _a_fitted_light_lights_whoever_is_holding_it() -> bool:
	var w: Variant = _world()
	var rifle: int = _spawn(w, RIFLE)
	if not SimInventory.equip(w, w.player, rifle):
		push_error("LIGHT: the rifle would not equip")
		return false
	w.events.drain()
	if w.components.has_component(w.player, "light_source"):
		push_error("LIGHT: a bare rifle lights the room")
		return false

	# The first negative: a part that is not a light must not become one just by being fitted.
	var grip: int = _spawn(w, FOREGRIP)
	if not SimAttachments.attach(w, rifle, grip, "underbarrel"):
		push_error("LIGHT: the foregrip would not fit the underbarrel")
		return false
	w.events.drain()
	if w.components.has_component(w.player, "light_source"):
		push_error("LIGHT: a foregrip lit the room, so this lane is measuring the fitting and not the light")
		return false
	SimAttachments.detach(w, grip)
	w.events.drain()

	var lamp: int = _spawn(w, WEAPON_LIGHT)
	var want: Variant = SimLightModule.light_reach_of(w, lamp)
	if want == null or float(want) <= 0.0:
		push_error("LIGHT: the weapon light declares no light, so there is nothing to judge")
		return false
	if not SimAttachments.attach(w, rifle, lamp, "underbarrel"):
		push_error("LIGHT: the weapon light would not fit the underbarrel")
		return false
	w.events.drain()
	var src: Variant = w.components.get_component(w.player, "light_source")
	if not src is Dictionary or absf(float((src as Dictionary)["magnitude"]) - float(want)) > 0.001:
		push_error("LIGHT: a fitted light left the holder at %s, want %s -- the part is a dead socket" % [str(src), str(want)])
		return false

	# The collision. Fire, let the flash burn out, and the mounted light must still be there.
	var ammo: int = SimItems.spawn_item(w, "item.ammo.rifle", {"tier": "scavenged", "count": 20})
	if not SimInventory.stow(w, w.player, ammo):
		w.components.set_component(ammo, "stored", {"container": w.player})
	SimRanged.load_held(w, w.player)
	w.events.drain()
	if not SimRanged.try_begin_fire(w, w.player):
		push_error("LIGHT: the rifle refused to fire, so the flash is never reached")
		return false
	var flashed: bool = false
	for _i in range(240):
		w.step()
		var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
		if rw is Dictionary and int((rw as Dictionary).get("flashTicks", 0)) > 0:
			flashed = true
		if flashed and rw is Dictionary and int((rw as Dictionary).get("flashTicks", 0)) <= 0:
			break
	if not flashed:
		print("LIGHT SKIP the rifle never flashed, so the collision has nothing to judge")
	else:
		src = w.components.get_component(w.player, "light_source")
		if not src is Dictionary:
			push_error("LIGHT: firing put the weapon light out -- the flash deleted the component instead of falling back to it")
			return false
		if absf(float((src as Dictionary)["magnitude"]) - float(want)) > 0.001:
			push_error("LIGHT: after the flash the holder is lit at %s, want the light's own %s" % [float((src as Dictionary)["magnitude"]), float(want)])
			return false

	# And taking it off puts it out, or the component is simply never cleaned up.
	SimAttachments.detach(w, lamp)
	w.events.drain()
	if w.components.has_component(w.player, "light_source"):
		push_error("LIGHT: the light came off and the holder is still lit")
		return false

	# And the plain case the fitted one is built on: a lamp in a hand lights the hand that holds
	# it. Asserted here rather than assumed, because until 2026-09-10 it did not -- this module's
	# private content accessor could not resolve an item at all, so the candle, the lamp and the
	# oil lantern each declared a `light` block that nothing carried had ever read. A lane that
	# only checked the fitted part would have passed over the same broken resolver.
	var w2: Variant = _world()
	var lamp2: int = _spawn(w2, "item.lamp.electric")
	var lamp_mag: Variant = SimLightModule.light_reach_of(w2, lamp2)
	if lamp_mag == null or float(lamp_mag) <= 0.0:
		push_error("LIGHT: the electric lamp resolves no light at all -- the content accessor is broken again")
		return false
	if not SimInventory.equip(w2, w2.player, lamp2):
		push_error("LIGHT: the lamp would not equip")
		return false
	w2.events.drain()
	var lit: Variant = w2.components.get_component(w2.player, "light_source")
	if not lit is Dictionary or absf(float((lit as Dictionary)["magnitude"]) - float(lamp_mag)) > 0.001:
		push_error("LIGHT: a carried lamp left its holder at %s, want %s" % [str(lit), str(lamp_mag)])
		return false

	print("LIGHT OK a fitted light lights its holder at %.1f, survives its own muzzle flash, and goes out when removed; a carried lamp lights at %.1f" % [float(want), float(lamp_mag)])
	return true


# --- ARMOR ------------------------------------------------------------------------------------
# docs/10's body-armour slots -- plate, lining, pocket -- and headgear's face. `SimAttachments`
# gained a third SCALABLE table with this slice, and it is the odd one out: its "profile" is a
# coverage map keyed by body part, not a list of field names, so `fold` folds it without knowing
# that is what it is doing.
#
# Four claims, each with the negative that can refuse it:
#
#   1. A plate raises the coverage its host is worth -- measured through `armor_coverage_of`,
#      which is what the rest of the sim actually asks, never through the multiplier the content
#      declares. A dictionary that says a plate is good is a dictionary comparing itself.
#   2. "Multipliers, never adders" has teeth: a part scales coverage the base already declares and
#      **cannot conjure coverage it does not**. A visor on a helmet lifts the head; the same visor
#      cannot give a welding apron a head to protect.
#   3. A garment blocked for want of a required part covers **nothing at all** -- the plate
#      carrier is a nylon bib until something is in the pouch -- and says so in prose, with no
#      digit in the sentence.
#   4. A pouch fitted to a rig is somewhere a survivor can really put a tin. A fitted part is not
#      in its host's grid, so without `reachable_containers` reading the slots it would be a grid
#      nothing could ever reach.
func _armour_slots_carry_armour() -> bool:
	var lane: String = "ARMOR"
	var w: Variant = _world()

	# 1. The plate. The carrier spawns assembled (its `defaultParts`), so the comparison is the
	# same garment with and without the part that came in it -- one variable, not two garments.
	var carrier: int = _spawn(w, "item.vest.carrier")
	var plate: int = SimAttachments.in_slot(w, carrier, "plate")
	if plate < 0:
		push_error("%s: the plate carrier spawned with nothing in its plate slot, so this lane has no part to judge" % lane)
		return false
	if not SimInventory.equip(w, w.player, carrier, "vest"):
		push_error("%s: the plate carrier would not go on" % lane)
		return false
	var plated: float = SimInfection.armor_coverage_of(w, w.player, "torso")
	var declared: float = float((SimItems.item_base_of(w, carrier) as Dictionary)["armor"]["torso"])
	if plated <= declared + 0.0001:
		push_error("%s: a plated carrier covers the torso %.4f and the bare base declares %.4f -- the fold is reaching nothing" % [lane, plated, declared])
		return false

	# TN for 1: take the plate out and the number has to move back. It moves further than back --
	# the carrier requires a plate and is worth nothing without one -- which is claim 3, asserted
	# here because this is the moment the part comes off.
	if not SimAttachments.detach(w, plate):
		push_error("%s: the plate would not come out" % lane)
		return false
	var stripped: float = SimInfection.armor_coverage_of(w, w.player, "torso")
	if stripped != 0.0:
		push_error("%s: a carrier with no plate covered the torso %.4f, and a carrier with no plate is webbing" % [lane, stripped])
		return false
	# 3b. And it says so, in words. The sentence goes on the HUD, where check_hud.gd allows no
	# digits at all, so this lane refuses one here rather than letting that gate find it later.
	var said: String = SimAttachments.refusal_clause(w, w.player)
	if said.is_empty():
		push_error("%s: an empty plate carrier is worth nothing and the HUD says nothing about it" % lane)
		return false
	for i in said.length():
		if said[i].is_valid_int():
			push_error("%s: the refusal sentence carries a digit: %s" % [lane, said])
			return false
	# 3c, and the sabotage pass is what found it was missing. `armor_coverage` answers zero by two
	# different routes -- an empty `attachments` component short-circuits before `blocked_reason`
	# is ever asked -- and with only the test above, deleting the `blocked_reason` check entirely
	# left this gate **green**. A branch a gate cannot fail is a branch that is not gated.
	#
	# So: put something in a slot that is *not* the required one. The carrier now has a part
	# fitted and still has no plate, which is the only state in which `blocked_reason` is the
	# thing deciding the answer.
	var spare_pouch: int = _spawn(w, "item.armorpart.pocket.pouch")
	if not SimAttachments.attach(w, carrier, spare_pouch, "pocket"):
		push_error("%s: the pouch would not fit the carrier's pocket slot" % lane)
		return false
	if SimInfection.armor_coverage_of(w, w.player, "torso") != 0.0:
		push_error("%s: a carrier with a pouch on it and no plate in it covered the torso -- a garment blocked for want of a required part is worth nothing, whatever else is bolted to it" % lane)
		return false
	if not SimAttachments.detach(w, spare_pouch):
		push_error("%s: the spare pouch would not come off" % lane)
		return false

	# Put the plate back, and the coverage has to come back with it -- a detach that quietly
	# destroyed the part would leave `stripped` looking exactly the same as a working refusal.
	if not SimAttachments.attach(w, carrier, plate, "plate"):
		push_error("%s: the plate would not go back in" % lane)
		return false
	if absf(SimInfection.armor_coverage_of(w, w.player, "torso") - plated) > 0.0001:
		push_error("%s: refitting the plate did not restore the coverage it took away" % lane)
		return false

	# 2. Each declared multiplier lands on the part it names, and on that part only.
	#
	# This claim started life as "a lining cannot conjure coverage an apron does not have", and
	# the sabotage pass threw that version away: it could not fail. A multiplier applied to
	# coverage that is not there is a multiplier applied to zero, so "multipliers, never adders"
	# makes the conjuring case arithmetically impossible rather than merely forbidden. Removing
	# `fold`'s profile guard *and* changing `armor_coverage` to fold the whole map at once left
	# the old lane green, because the coverage was still zero either way. An assertion no edit
	# can break is what this repo means by a gate that cannot fail.
	#
	# What *can* break is the fold landing a multiplier on the wrong key, or landing one
	# multiplier on every key. So the claim is now stated as exact arithmetic across two keys the
	# same part scales by two different amounts: the aramid lining is 1.35 on an arm and 1.05 on a
	# torso, and both have to come out exactly, against `multiplier_of` rather than against a
	# number written here -- the content owns the figure, the gate owns the relationship.
	var w4: Variant = _world()
	var jacket: int = _spawn(w4, "item.jacket.leather")
	if not SimInventory.equip(w4, w4.player, jacket, "torso"):
		push_error("%s: the jacket would not go on" % lane)
		return false
	# A helmet as well, so the second half of the claim has a second garment to be about.
	var helmet: int = _spawn(w4, "item.helmet.bike")
	if not SimInventory.equip(w4, w4.player, helmet, "head"):
		push_error("%s: the helmet would not go on" % lane)
		return false
	var arm_before: float = SimInfection.armor_coverage_of(w4, w4.player, "arm_left")
	var torso_before: float = SimInfection.armor_coverage_of(w4, w4.player, "torso")
	var head_before: float = SimInfection.armor_coverage_of(w4, w4.player, "head")
	var lining: int = _spawn(w4, "item.armorpart.lining.aramid")
	if not SimAttachments.attach(w4, jacket, lining, "lining"):
		push_error("%s: the lining would not fit the jacket" % lane)
		return false
	var arm_mul: float = SimAttachments.multiplier_of(w4, lining, "armor", "arm_left")
	var torso_mul: float = SimAttachments.multiplier_of(w4, lining, "armor", "torso")
	if is_equal_approx(arm_mul, torso_mul):
		push_error("%s: the lining scales an arm and a torso by the same %.4f, so this lane cannot tell the two keys apart" % [lane, arm_mul])
		return false
	var arm_after: float = SimInfection.armor_coverage_of(w4, w4.player, "arm_left")
	var torso_after: float = SimInfection.armor_coverage_of(w4, w4.player, "torso")
	if not is_equal_approx(arm_after, arm_before * arm_mul):
		push_error("%s: a lining took the arm %.4f -> %.4f, and %.4f x %.4f is %.4f" % [lane, arm_before, arm_after, arm_before, arm_mul, arm_before * arm_mul])
		return false
	if not is_equal_approx(torso_after, torso_before * torso_mul):
		push_error("%s: a lining took the torso %.4f -> %.4f, and %.4f x %.4f is %.4f" % [lane, torso_before, torso_after, torso_before, torso_mul, torso_before * torso_mul])
		return false

	# And the other garment is untouched. `armor_coverage` is asked about one *item* at a time and
	# the max is taken afterwards, which is easy to write the other way round -- fold everything
	# the actor is wearing together -- and that mistake would put a jacket's lining on a helmet.
	if not is_equal_approx(SimInfection.armor_coverage_of(w4, w4.player, "head"), head_before):
		push_error("%s: a lining laced into a jacket moved the head from %.4f to %.4f, and the lining is not in the helmet" % [lane, head_before, SimInfection.armor_coverage_of(w4, w4.player, "head")])
		return false
	# The visor is the same statement from the other end: fitted to the helmet, it moves the head
	# and leaves the jacket's torso where it was.
	var visor: int = _spawn(w4, "item.armorpart.face.visor")
	if not SimAttachments.attach(w4, helmet, visor, "face"):
		push_error("%s: the visor would not fit a helmet's face slot" % lane)
		return false
	var head_after: float = SimInfection.armor_coverage_of(w4, w4.player, "head")
	if not is_equal_approx(head_after, head_before * SimAttachments.multiplier_of(w4, visor, "armor", "head")):
		push_error("%s: a visor took the head %.4f -> %.4f, which is not the multiplier it declares" % [lane, head_before, head_after])
		return false
	if not is_equal_approx(SimInfection.armor_coverage_of(w4, w4.player, "torso"), torso_after):
		push_error("%s: a visor bracketed to a helmet moved the torso, and a visor is not a chest piece" % lane)
		return false
	# TN for the slot rule itself, which the fold never sees: the apron declares a `pocket` and no
	# `lining`, and a lining must not go into a slot that does not exist.
	var w3: Variant = _world()
	var apron: int = _spawn(w3, "item.apron.welding")
	if not SimInventory.equip(w3, w3.player, apron, "torso"):
		push_error("%s: the apron would not go on" % lane)
		return false
	if SimAttachments.attach(w3, apron, _spawn(w3, "item.armorpart.lining.aramid"), "lining"):
		push_error("%s: the apron declares no lining slot and took a lining anyway" % lane)
		return false

	# 4. The pouch. A pouch fitted to a worn rig is a place a survivor can put something, and the
	# only reader that can say so is `reachable_containers` -- `attach` takes the part out of every
	# grid on the way in, so nothing that walks contents can ever find it.
	var w5: Variant = _world()
	var vest: int = _spawn(w5, "item.vest.riot")
	if not SimInventory.equip(w5, w5.player, vest, "vest"):
		push_error("%s: the riot vest would not go on" % lane)
		return false
	var pouch2: int = _spawn(w5, "item.armorpart.pocket.pouch")
	var reach_before: int = SimInventory.reachable_containers(w5, w5.player).size()
	if not SimAttachments.attach(w5, vest, pouch2, "pocket"):
		push_error("%s: the pouch would not fit the riot vest" % lane)
		return false
	var reach_after: Array[int] = SimInventory.reachable_containers(w5, w5.player)
	if not reach_after.has(pouch2):
		push_error("%s: a pouch fitted to a worn vest is in no container a survivor can reach -- %d before, %d after" % [lane, reach_before, reach_after.size()])
		return false
	# And it holds a real thing, not just a slot in a list.
	var mass_before: float = SimInventory.carried_mass_kg(w5, w5.player)
	var tin: int = _spawn(w5, "item.food.canned")
	if not SimInventory.store_anywhere(w5, tin, pouch2):
		push_error("%s: the pouch would not take a tin" % lane)
		return false
	if not SimInventory.contents_of(w5, pouch2).has(tin):
		push_error("%s: the tin went into the pouch and the pouch does not have it" % lane)
		return false
	# And it weighs something. A pocket reachable for storing but invisible to `carried_mass_kg`
	# would be free carry -- the grid without the cost -- and the recursion that prevents it goes
	# equipment -> `item_mass_kg` -> `parts_of` -> the pouch -> its contents, which is three hops
	# and no single place that obviously owns the answer.
	if SimInventory.carried_mass_kg(w5, w5.player) <= mass_before:
		push_error("%s: a tin stowed in a fitted pouch added no weight (%.3f kg before, %.3f after) -- a pocket you can fill for free" % [lane, mass_before, SimInventory.carried_mass_kg(w5, w5.player)])
		return false
	# TN for 4, and it took two goes to write. The obvious negative -- detach the pouch and assert
	# it is gone -- is not a negative at all: `detach` re-homes the part into the wearer's own
	# pack, where the ordinary contents walk finds it and *should*. It is reachable because it is
	# in a pocket now, which is correct and proves nothing about the new branch.
	#
	# So the negative isolates the branch instead: the same pouch on the same vest, with the vest
	# **not being worn**. `reachable_containers` loops over `equipped_items`, so an unworn rig's
	# slots must be out of reach -- and then putting the rig on has to bring them back, on one
	# variable, in one world.
	var w6: Variant = _world()
	var loose: int = _spawn(w6, "item.vest.riot")
	var pouch3: int = _spawn(w6, "item.armorpart.pocket.pouch")
	if not SimAttachments.attach(w6, loose, pouch3, "pocket"):
		push_error("%s: the pouch would not fit the loose vest" % lane)
		return false
	if SimInventory.reachable_containers(w6, w6.player).has(pouch3):
		push_error("%s: a pouch on a vest nobody is wearing is reachable, so the reader is not reading equipped slots" % lane)
		return false
	if not SimInventory.equip(w6, w6.player, loose, "vest"):
		push_error("%s: the loose vest would not go on" % lane)
		return false
	if not SimInventory.reachable_containers(w6, w6.player).has(pouch3):
		push_error("%s: putting the vest on did not bring its pouch into reach" % lane)
		return false

	print("  ARMOR OK a plate takes a carrier's torso %.2f -> %.2f and an empty one to zero (\"%s\"); a lining lifts an arm %.2f -> %.2f by exactly what it declares and leaves the helmet alone; a pouch on a worn vest holds a tin and is out of reach on a vest nobody is wearing" % [declared, plated, said, arm_before, arm_after])
	return true


# --- AFFIXES THAT NAME A STAT (firearms arc, stage 1) ------------------------------------------
#
# "of the Quiet Hand", "of Ruin", "of Salvage" and "Reinforced" were authored against stats nothing
# resolved, so an item carrying one did exactly what an item without it did. Each lane below is
# the same shape: a true positive (the named stat moves the number it governs), a true negative (a
# suffix that does not name that stat leaves the number exactly where it was), and the attachment
# path proved on a part rather than a host. Affixes are item-scoped, so every reader here reads
# the item it is asked about, never the survivor carrying it.

# A pistol or an axe carrying one affix at a given tier, with the item's own modifiers rebuilt the
# way a bench edit rebuilds them. An empty id is the bare item.
func _carrying(w: Variant, id: String, affix_id: String, tier: int) -> int:
	var item: int = _spawn(w, id)
	if affix_id != "":
		# A prefix goes in the prefixes list, as a roll puts it; a suffix in the suffixes list.
		var rolled: Array = [{"id": affix_id, "tier": tier}]
		var prefix: bool = affix_id.begins_with("affix.prefix.")
		w.components.set_component(item, "affixes", {"prefixes": rolled if prefix else [], "suffixes": [] if prefix else rolled})
		SimItems.reapply_affix_modifiers(w, item)
	return item


# A survivor's swing at a body 0.8 m ahead, as the hands gate stages it, read off the noise the
# connect publishes. The noise is the attention spine's own magnitude, so it is compared as-is.
func _connect_noise(affix_id: String, tier: int) -> float:
	var lane: String = "SWING"
	var w: Variant = _world()
	var axe: int = _carrying(w, AXE, affix_id, tier)
	SimInventory.equip(w, w.player, axe)
	w.events.drain()
	var body: int = int(w.entities.spawn())
	w.components.set_component(body, "position", {"x": 9.3, "y": 12.5})
	w.components.set_component(body, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(body, "body", SimCombat.ZOMBIE_BODY.duplicate())
	var noises: Array = []
	var connected: Array = []
	w.commands.push({"type": "swing"})
	for i in 40:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "noise.emitted" and int(ev.get("source", -1)) == w.player:
				noises.append(float(ev.get("magnitude", 0)))
			if String(ev.get("type", "")) == "attack.connected":
				connected.append(ev)
	if connected.is_empty() or noises.is_empty():
		push_error("%s: an axe swing at 0.8 m did not connect and make a noise (connects %d, noises %s)" % [lane, connected.size(), str(noises)])
		return -1.0
	return float(noises[0])


func _an_affix_reaches_the_swing_it_names() -> bool:
	var lane: String = "SWING"
	var bare: float = _connect_noise("", 0)
	if bare < 0.0:
		return false
	var quiet: float = _connect_noise("affix.suffix.quiet_hand", 0)
	var quieter: float = _connect_noise("affix.suffix.quiet_hand", 2)
	var plain: float = _connect_noise("affix.suffix.salvage", 0)
	# TP: the axe's connect is its own connectNoise (8) scaled by quiet_hand's tier-zero 0.85.
	if quiet < 0.0 or absf(quiet - float(SimCombat.MELEE_CONNECT_NOISE) * 0.85) > 0.0001:
		push_error("%s: a quiet-handed axe connects at %.4f, not %.4f" % [lane, quiet, float(SimCombat.MELEE_CONNECT_NOISE) * 0.85])
		return false
	if not (quieter < quiet and quiet < bare):
		push_error("%s: tiers do not order (bare %.4f, tier 0 %.4f, tier 2 %.4f)" % [lane, bare, quiet, quieter])
		return false
	# TN: salvage names repair_cost, not noise, so the connect must be the bare connect to the digit.
	if absf(plain - bare) > 0.0001:
		push_error("%s: an axe of Salvage connects at %.4f, not the bare %.4f -- salvage moved noise" % [lane, plain, bare])
		return false
	print("  SWING OK a quiet-handed axe connects at %.2f (bare %.2f, tier two %.2f); of Salvage leaves it at %.2f" % [quiet, bare, quieter, plain])
	return true


# The part path. A suppressor-shaped part wears through `wear_parts` (the channel a shot uses on a
# part), and the wear it takes is the part's own `condition_loss` times the declared amount. The
# two worlds differ by one variable, the part's modifier; the ratio is what is asserted, so this
# does not depend on the suppressor's declared wearRate.
func _part_loss_after_one_shot(modifier_value: float) -> float:
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var can: int = _spawn(w, SUPPRESSOR)
	if not SimAttachments.attach(w, pistol, can, "muzzle"):
		return -1.0
	if modifier_value != 1.0:
		w.modifiers.add({"stat": "condition_loss", "op": "mul", "value": modifier_value, "source": "gate.fixture"}, can)
	var before: float = _condition_of(w, can)
	SimAttachments.wear_parts(w, pistol, "shot")
	return before - _condition_of(w, can)


func _an_affix_reaches_the_wear_it_names() -> bool:
	var lane: String = "WEAR"
	var plain: float = _part_loss_after_one_shot(1.0)
	var worn: float = _part_loss_after_one_shot(2.0)
	if plain <= 0.0:
		push_error("%s: one shot took nothing off a fitted part (%.6f), so the ratio measures nothing" % [lane, plain])
		return false
	# TP: condition_loss x2 on the part takes exactly twice what it took plain.
	if absf(worn - 2.0 * plain) > 0.000001:
		push_error("%s: a part with condition_loss x2 lost %.6f in one shot, not %.6f" % [lane, worn, 2.0 * plain])
		return false
	# TN: a part whose condition_loss is untouched is the plain part to the digit, and so is a
	# part carrying a modifier on some other stat (ranged_accuracy moves aim, not wear).
	var other_stat: float = 0.0
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var can: int = _spawn(w, SUPPRESSOR)
	SimAttachments.attach(w, pistol, can, "muzzle")
	w.modifiers.add({"stat": "ranged_accuracy", "op": "mul", "value": 2.0, "source": "gate.fixture"}, can)
	var before: float = _condition_of(w, can)
	SimAttachments.wear_parts(w, pistol, "shot")
	other_stat = before - _condition_of(w, can)
	if absf(other_stat - plain) > 0.000001:
		push_error("%s: a part moved by ranged_accuracy lost %.6f, not the plain %.6f" % [lane, other_stat, plain])
		return false
	# And the host, through the item path: one shot's wear on a pistol carrying ruin is twice the
	# bare pistol's. The ratio is asserted, not the constant, since the constant is items.gd's.
	var host_bare: float = _host_loss_after_one_shot("")
	var host_ruin: float = _host_loss_after_one_shot("affix.suffix.ruin")
	if host_bare <= 0.0 or absf(host_ruin - 2.0 * host_bare) > 0.000001:
		push_error("%s: a ruined pistol lost %.6f from one wear event, not twice the bare %.6f" % [lane, host_ruin, host_bare])
		return false
	# A global entry is the world's, not the item's: it sits inside the scoped resolve and the
	# unscoped one alike, so the item's own share divides it out, as repair_cost_factor does. The
	# positive is that an item carrying its own x2 still reads 2.0 under the same global x3; the
	# negative is that the bare item under that global reads 1.0, not 3.0.
	var wg: Variant = _world()
	var gpistol: int = _armed_pistol(wg)
	wg.modifiers.call("add", {"stat": "condition_loss", "op": "mul", "value": 3.0, "source": "gate.global"}, null)
	wg.modifiers.call("add", {"stat": "noise_emission", "op": "mul", "value": 3.0, "source": "gate.global"}, null)
	if absf(SimItems.condition_loss_of(wg, gpistol) - 1.0) > 0.000001 or absf(SimItems.noise_emission_of(wg, gpistol) - 1.0) > 0.000001:
		push_error("%s: a global x3 on condition_loss and noise_emission read as the item's own (%.3f, %.3f), not 1.0" % [lane, SimItems.condition_loss_of(wg, gpistol), SimItems.noise_emission_of(wg, gpistol)])
		return false
	wg.modifiers.call("add", {"stat": "condition_loss", "op": "mul", "value": 2.0, "source": "gate.own"}, gpistol)
	wg.modifiers.call("add", {"stat": "noise_emission", "op": "mul", "value": 2.0, "source": "gate.own"}, gpistol)
	if absf(SimItems.condition_loss_of(wg, gpistol) - 2.0) > 0.000001 or absf(SimItems.noise_emission_of(wg, gpistol) - 2.0) > 0.000001:
		push_error("%s: an item's own x2 under a global x3 read (%.3f, %.3f), not 2.0" % [lane, SimItems.condition_loss_of(wg, gpistol), SimItems.noise_emission_of(wg, gpistol)])
		return false
	print("  WEAR OK a part with condition_loss x2 loses %.5f a shot, plain %.5f; a ruined pistol loses %.5f, bare %.5f; a global x3 is not the item's own" % [worn, plain, host_ruin, host_bare])
	return true


func _host_loss_after_one_shot(affix_id: String) -> float:
	var w: Variant = _world()
	var pistol: int = _carrying(w, PISTOL, affix_id, 0)
	w.components.set_component(pistol, "condition", {"current": 1.0, "ceiling": 1.0})
	var before: float = _condition_of(w, pistol)
	SimItems.apply_wear(w, pistol, SimItems.WEAR_PER_SHOT)
	return before - _condition_of(w, pistol)


# Repair spends the ceiling, and the item's own repair_cost is what it spends it by. The reader is
# repair_item (docs/23, the wider-web arc's second piece, 2026-09-13), so this lane is the proof
# that a ranged weapon's affix reaches it, not a second reader. Plain hands, no repairer named.
func _repaired_ceiling(affix_id: String, tier: int) -> float:
	var w: Variant = _world()
	var pistol: int = _carrying(w, PISTOL, affix_id, tier)
	w.components.set_component(pistol, "condition", {"current": 0.5, "ceiling": 1.0})
	if not SimItems.repair_item(w, pistol):
		return -1.0
	return float((w.components.get_component(pistol, "condition") as Dictionary)["ceiling"])


func _an_affix_reaches_the_repair_it_names() -> bool:
	var lane: String = "REPAIR"
	var plain: float = _repaired_ceiling("", 0)
	var salvage: float = _repaired_ceiling("affix.suffix.salvage", 0)
	var salvage_deep: float = _repaired_ceiling("affix.suffix.salvage", 2)
	var quiet: float = _repaired_ceiling("affix.suffix.quiet_hand", 0)
	# A ceiling of 1.0 drops by REPAIR_CEILING_DROP (0.05) times the item's repair_cost.
	if absf(plain - 0.95) > 0.000001:
		push_error("%s: a plain pistol repaired to a ceiling of %.6f, not 0.95" % [lane, plain])
		return false
	# TP: of Salvage is 0.8 at tier zero and 0.45 at tier two, so the drop shrinks by that much.
	if absf(salvage - (1.0 - 0.05 * 0.8)) > 0.000001 or absf(salvage_deep - (1.0 - 0.05 * 0.45)) > 0.000001:
		push_error("%s: salvage left the ceiling at %.6f and %.6f, not 0.96 and 0.9775" % [lane, salvage, salvage_deep])
		return false
	# TN: quiet_hand names noise, not repair_cost, so the repair is the plain repair to the digit.
	if absf(quiet - plain) > 0.000001:
		push_error("%s: a quiet-handed pistol repaired to %.6f, not the plain %.6f" % [lane, quiet, plain])
		return false
	print("  REPAIR OK a plain pistol's ceiling goes to %.4f; of Salvage to %.4f and %.4f; quiet hand leaves it at %.4f" % [plain, salvage, salvage_deep, quiet])
	return true
# --- RANGED AFFIXES ---------------------------------------------------------------------------
# docs/10's ranged prefixes that a stat can carry: Trued (accuracy) and Blued (condition loss).
# Ported (recoil), Chambered (reload time) and Heavy-barrelled (weight, steady time) name effects
# no stat carries yet, so they are not authored; docs/23's ranged affixes entry names them. Every
# lane here is a true positive on the number its affix governs, and a true negative on one it does
# not, read through the same readers the shot and the wear use.

# The felt cone a gun gives its holder at rest, from the reader the shot itself calls
# (`_refresh_cone`), so the lane proves what the sim reads and not a copy of it.
func _resting_cone(w: Variant, affix_id: String, tier: int) -> float:
	var barrel: int = _carrying(w, PISTOL, affix_id, tier)
	var rw: Dictionary = {"state": SimRanged.FireState.Idle, "source": barrel, "cone": 1.0}
	SimRanged._refresh_cone(w, w.player, rw)
	return float(rw["coneHalf"])


func _the_ranged_prefixes_reach_what_they_name() -> bool:
	var lane: String = "RANGED"
	var w: Variant = _world()
	var pool: Array = SimItems.affix_pool(w, "weapon.ranged", "prefix")
	var ids: Array[String] = []
	for affix in pool:
		ids.append(String((affix as Dictionary)["id"]))
	# The pool a ranged roll draws from holds the two new prefixes, so a rolled gun can carry them.
	if not ids.has("affix.prefix.trued") or not ids.has("affix.prefix.blued"):
		push_error("%s: the ranged prefix pool is %s, without trued and blued" % [lane, str(ids)])
		return false
	# Every ranged prefix the pool can roll reads through the item. A stat outside the list is the
	# dead socket docs/23 names, so the lane refuses it by name.
	for affix in pool:
		for tier_v in (affix as Dictionary)["tiers"] as Array:
			for mod_v in (tier_v as Dictionary)["modifiers"] as Array:
				var stat: String = String((mod_v as Dictionary)["stat"])
				if not SimItems.reads_through_item(stat):
					push_error("%s: %s moves %s, which no reader resolves through the item" % [lane, String((affix as Dictionary)["id"]), stat])
					return false
	# A stat that is declared and that no reader resolves through the item (mood) is refused.
	if SimItems.reads_through_item("mood") or not SimItems.reads_through_item("ranged_accuracy"):
		push_error("%s: the item-scoped list admits mood, which nothing reads through an item, or refuses ranged_accuracy" % lane)
		return false

	# Trued, TP: the barrel's own accuracy is 1.1 at tier zero and 1.3 at tier two, and the cone the
	# shot fires from is the bare cone divided by it.
	var bare: float = _resting_cone(w, "", 0)
	var trued_low: float = _resting_cone(w, "affix.prefix.trued", 0)
	var trued_high: float = _resting_cone(w, "affix.prefix.trued", 2)
	if absf(trued_low - bare / 1.1) > 0.000001 or absf(trued_high - bare / 1.3) > 0.000001:
		push_error("%s: a trued barrel's cone is %.6f and %.6f, not the bare %.6f over 1.1 and 1.3" % [lane, trued_low, trued_high, bare])
		return false
	var trued_gun: int = _carrying(w, PISTOL, "affix.prefix.trued", 2)
	if absf(SimItems.accuracy_of(w, trued_gun) - 1.3) > 0.000001:
		push_error("%s: a tier-two trued barrel reads accuracy %.6f, not 1.3" % [lane, SimItems.accuracy_of(w, trued_gun)])
		return false
	# Trued, TN: it names accuracy and nothing else, so the same barrel is as loud as a bare one.
	if absf(SimItems.noise_emission_of(w, trued_gun) - 1.0) > 0.000001 or absf(SimItems.condition_loss_of(w, trued_gun) - 1.0) > 0.000001:
		push_error("%s: a trued barrel moved noise or condition loss" % lane)
		return false

	# Blued, TP: condition loss is 0.75 at tier zero and 0.4 at tier two, and one shot wears the gun
	# by that share of a bare gun's wear.
	var blued_gun: int = _carrying(w, PISTOL, "affix.prefix.blued", 2)
	if absf(SimItems.condition_loss_of(w, blued_gun) - 0.4) > 0.000001:
		push_error("%s: a tier-two blued barrel reads condition loss %.6f, not 0.4" % [lane, SimItems.condition_loss_of(w, blued_gun)])
		return false
	var plain_loss: float = _host_loss_after_one_shot("")
	var blued_loss: float = _host_loss_after_one_shot("affix.prefix.blued")
	if absf(blued_loss - plain_loss * 0.75) > 0.000001:
		push_error("%s: one shot wears a blued pistol by %.6f, not the plain %.6f times 0.75" % [lane, blued_loss, plain_loss])
		return false
	# Blued, TN: it names condition loss and nothing else, so its cone is the bare cone.
	if absf(_resting_cone(w, "affix.prefix.blued", 0) - bare) > 0.000001:
		push_error("%s: a blued barrel moved the cone" % lane)
		return false

	print("  RANGED OK trued cone %.4f at tier zero and %.4f at tier two over bare %.4f; blued wear %.6f against plain %.6f; the pool refuses no stat it rolls" % [trued_low, trued_high, bare, blued_loss, plain_loss])
	return true


# Ported (the recovery clock and the noise), Chambered (the reload clock) and Heavy-barrelled (the
# accuracy and the settle clock). The clocks are F4's item-scoped readers (`steady_share_of`,
# `recover_share_of`, `reload_share_of`), read live by ranged.gd, so each lane reads the clock the
# shot itself reads. Plain numbers are the rung's own: a bare gun's clock is the base's, and an
# affixed one is that clock times the tier's share, rounded the way `_scaled` rounds it.
func _the_ranged_clocks_and_accuracy_reach_the_gun_they_name() -> bool:
	var lane: String = "RANGED"
	var w: Variant = _world()
	var bare_gun: int = _carrying(w, PISTOL, "", 0)
	var ported: int = _carrying(w, PISTOL, "affix.prefix.ported", 0)
	var ported_top: int = _carrying(w, PISTOL, "affix.prefix.ported", 2)
	var chambered: int = _carrying(w, PISTOL, "affix.prefix.chambered", 0)
	var chambered_top: int = _carrying(w, PISTOL, "affix.prefix.chambered", 2)
	var heavy: int = _carrying(w, PISTOL, "affix.prefix.heavy_barrelled", 0)
	var heavy_top: int = _carrying(w, PISTOL, "affix.prefix.heavy_barrelled", 2)

	# A rung's clock from the same reader the shot uses: a plain record of the pistol's heft, with its
	# own item as the source. -1 is the bare clock.
	var recover_base: int = SimCombat.shot_recover_ticks(1.0, 1.0)
	var steady_base: int = SimCombat.steady_ticks(1.0, 1.0)
	var reload_base: int = 24

	# Ported, TP: recovery is 0.85 at tier zero and 0.55 at tier two, and the noise is 1.15 and 1.5.
	var recover_low: int = SimRanged._recover_of(w, {"weight": 1.0, "handling": 1.0, "source": ported})
	var recover_high: int = SimRanged._recover_of(w, {"weight": 1.0, "handling": 1.0, "source": ported_top})
	if recover_low != maxi(1, int(round(float(recover_base) * 0.85))) or recover_high != maxi(1, int(round(float(recover_base) * 0.55))):
		push_error("%s: a ported gun recovers in %d and %d ticks, not the bare %d times 0.85 and 0.55" % [lane, recover_low, recover_high, recover_base])
		return false
	if absf(SimItems.noise_emission_of(w, ported) - 1.15) > 0.000001 or absf(SimItems.noise_emission_of(w, ported_top) - 1.5) > 0.000001:
		push_error("%s: a ported barrel reads noise %.6f and %.6f, not 1.15 and 1.5" % [lane, SimItems.noise_emission_of(w, ported), SimItems.noise_emission_of(w, ported_top)])
		return false
	# Ported, TN: it names recovery and noise, not the settle or the reload, so those clocks are the base's.
	if SimRanged._steady_of(w, {"weight": 1.0, "handling": 1.0, "source": ported}) != steady_base:
		push_error("%s: a ported gun moved its settle clock" % lane)
		return false

	# Chambered, TP: the reload is 0.8 at tier zero and 0.5 at tier two of the base's 24 ticks.
	var reload_low: int = _reload_ticks(w, chambered)
	var reload_high: int = _reload_ticks(w, chambered_top)
	if reload_low != maxi(1, int(round(float(reload_base) * 0.8))) or reload_high != maxi(1, int(round(float(reload_base) * 0.5))):
		push_error("%s: a chambered gun reloads in %d and %d ticks, not 24 times 0.8 and 0.5" % [lane, reload_low, reload_high])
		return false
	# Chambered, TN: it names reload only, so the bare gun reloads on the base clock.
	if _reload_ticks(w, bare_gun) != reload_base:
		push_error("%s: a bare gun reloads in %d ticks, not the base %d" % [lane, _reload_ticks(w, bare_gun), reload_base])
		return false

	# Heavy-barrelled, TP: accuracy 1.08 and 1.22 over bare, and the settle clock 1.15 and 1.45 times the base.
	var settle_low: int = SimRanged._steady_of(w, {"weight": 1.0, "handling": 1.0, "source": heavy})
	var settle_high: int = SimRanged._steady_of(w, {"weight": 1.0, "handling": 1.0, "source": heavy_top})
	if settle_low != maxi(1, int(round(float(steady_base) * 1.15))) or settle_high != maxi(1, int(round(float(steady_base) * 1.45))):
		push_error("%s: a heavy-barrelled gun settles in %d and %d ticks, not the base %d times 1.15 and 1.45" % [lane, settle_low, settle_high, steady_base])
		return false
	if absf(SimItems.accuracy_of(w, heavy) - 1.08) > 0.000001 or absf(SimItems.accuracy_of(w, heavy_top) - 1.22) > 0.000001:
		push_error("%s: a heavy-barrelled barrel reads accuracy %.6f and %.6f, not 1.08 and 1.22" % [lane, SimItems.accuracy_of(w, heavy), SimItems.accuracy_of(w, heavy_top)])
		return false
	# Heavy-barrelled, TN: it names accuracy and the settle, not the recovery, so the recovery is the base's.
	if SimRanged._recover_of(w, {"weight": 1.0, "handling": 1.0, "source": heavy}) != recover_base:
		push_error("%s: a heavy-barrelled gun moved its recovery clock" % lane)
		return false

	print("  RANGED OK ported recovers in %d ticks at tier zero (bare %d) and reads noise 1.15; chambered reloads in %d (bare %d); heavy-barrelled settles in %d (base %d) at accuracy 1.08" % [recover_low, recover_base, reload_low, reload_base, settle_low, steady_base])
	return true


# The reload a rung starts with, from the reader `_begin_reload` calls on a magazine-less record, so
# no ammunition is needed to read the clock.
func _reload_ticks(w: Variant, gun: int) -> int:
	var rw: Dictionary = {"reloadTicks": 24, "magSize": 0, "source": gun}
	SimRanged._begin_reload(w, w.player, rw)
	return int(rw["ticksLeft"])


# --- MELEE FRAMES -----------------------------------------------------------------------------
#
# docs/23's melee arc, stage 1. Every melee base is in one of four families; the slots widen to
# stud, guard and weight; and about two dozen improvised parts go on by what their `fits` and their
# `appliesTo` say. Each lane has a true positive and a true negative, and the negative is picked so
# that the rule under test is the thing refusing: a part that has the right slot and the wrong
# family, not merely a slot that is not there.

func _family_ok(family: String) -> bool:
	return MELEE_FAMILIES.has(family)


func _melee_bases() -> Array:
	var out: Array = []
	for entry_v in SimItems.content_entries(_world(), "item"):
		if (entry_v as Dictionary).get("melee") is Dictionary:
			out.append(entry_v)
	return out


func _every_melee_base_has_a_family_and_the_new_slots_have_hosts() -> bool:
	var counts: Dictionary = {}
	var melee: Array = _melee_bases()
	if melee.is_empty():
		push_error("FAMILY: no melee base was read, so this lane is asserting nothing")
		return false
	for e in melee:
		var id: String = String((e as Dictionary).get("id", "?"))
		var family: String = String((e as Dictionary).get("family", ""))
		if not _family_ok(family):
			push_error("FAMILY: %s declares family '%s', which is none of %s" % [id, family, str(MELEE_FAMILIES)])
			return false
		for s in (e as Dictionary).get("slots", []) as Array:
			counts[String(s)] = int(counts.get(String(s), 0)) + 1
	for slot in NEW_SLOTS:
		if int(counts.get(slot, 0)) == 0:
			push_error("FAMILY: no melee base declares the %s slot, so a part for it is a dead socket" % slot)
			return false
	# TN: the predicate has to be able to say no, and a base with no family says it.
	if _family_ok("") or _family_ok("gate.family") or not _family_ok("club"):
		push_error("FAMILY: the family predicate cannot tell a family from a fabricated name")
		return false
	print("  FAMILY OK %d melee bases, each in one of four families; stud on %d, guard on %d, weight on %d" % [melee.size(), counts.get("stud", 0), counts.get("guard", 0), counts.get("weight", 0)])
	return true


func _every_applies_to_names_a_real_family_or_base_and_every_recipe_has_a_host() -> bool:
	var ids: Dictionary = {}
	var melee: Array = _melee_bases()
	for e in melee:
		ids[String((e as Dictionary).get("id", "?"))] = true
	var recipes: int = 0
	var named: int = 0
	for entry_v in SimItems.content_entries(_world(), "item"):
		var e: Dictionary = entry_v as Dictionary
		if not (e.get("attachment") is Dictionary):
			continue
		var id: String = String(e.get("id", "?"))
		var spec: Dictionary = e["attachment"] as Dictionary
		if spec.get("appliesTo") is Array:
			named += 1
			for n in spec["appliesTo"] as Array:
				if not _family_ok(String(n)) and not ids.has(String(n)):
					push_error("APPLIES: %s applies to '%s', which is neither a melee family nor a shipped base" % [id, String(n)])
					return false
		if not (spec.get("recipe") is Dictionary):
			continue
		recipes += 1
		# An improvised part is made from materials, so every kind it names has to be one the
		# material vocabulary ranks, and its description has to keep the digit ban.
		for kind in (spec["recipe"] as Dictionary).get("kinds", []) as Array:
			if not SimFortify.MATERIAL_KINDS.has(String(kind)):
				push_error("APPLIES: %s recipe names '%s', which is not a material kind" % [id, String(kind)])
				return false
		var desc: String = String(e.get("description", ""))
		for digit in "0123456789":
			if desc.contains(digit):
				push_error("APPLIES: %s has a digit in its description, which the HUD digit ban forbids" % id)
				return false
		# Installable on at least one shipped base: some melee base declares a slot the part fits
		# and takes it by family or by id. The dead-socket rule, one level out from HOSTS.
		var hosted: bool = false
		for b in melee:
			for slot in spec.get("fits", []) as Array:
				if (b as Dictionary).get("slots", []).has(String(slot)) and SimAttachments.takes(b as Dictionary, spec):
					hosted = true
		if not hosted:
			push_error("APPLIES: %s fits and applies to no shipped melee base -- a dead socket" % id)
			return false
	if recipes == 0 or named == 0:
		push_error("APPLIES: no recipe or no appliesTo was read, so this lane is asserting nothing")
		return false
	# TN: a fabricated family or id is refused by the predicate, and a kind the vocabulary lacks is.
	var probe: Dictionary = {"fits": ["stud"], "appliesTo": ["gate.family"]}
	if SimAttachments.takes(melee[0] as Dictionary, probe):
		push_error("APPLIES: the applies predicate admits a fabricated family")
		return false
	if SimFortify.MATERIAL_KINDS.has("gate.kind"):
		push_error("APPLIES: the material vocabulary admits a fabricated kind")
		return false
	print("  APPLIES OK %d appliesTo names, %d improvised parts, each a real family or base, each hosted, each in material kinds" % [named, recipes])
	return true


func _a_part_goes_on_where_its_slot_and_its_family_say_and_nowhere_else() -> bool:
	var w: Variant = _world()
	# True positive: nails are driven into a wooden bat's stud, and the damage they declare arrives.
	var bat: int = _spawn(w, WOOD_BAT)
	var before: Dictionary = SimItems.melee_profile_of(w, bat) as Dictionary
	if not SimAttachments.attach(w, bat, _spawn(w, NAILS), "stud"):
		push_error("PLAUSIBLE: nails were refused a wooden bat's stud, which is the one place they go")
		return false
	var after: Dictionary = SimItems.melee_profile_of(w, bat) as Dictionary
	if float(after["damage"]) <= float(before["damage"]):
		push_error("PLAUSIBLE: nails went in and the damage did not move (%.2f vs %.2f)" % [float(after["damage"]), float(before["damage"])])
		return false
	# True negative, the one the piece names: nails in an aluminium bat. There is no stud on it.
	var alu: int = _spawn(w, ALU_BAT)
	if SimAttachments.attach(w, alu, _spawn(w, NAILS), "stud"):
		push_error("PLAUSIBLE: nails went into an aluminium bat")
		return false
	# The negative that has to refuse by host and not by slot: screws, bolts and glass fit a stud and
	# a steel pipe and a police baton both have one, so only the part's own `appliesTo` (wooden hosts)
	# can keep them off. The wooden bat and the claw hammer are the positives on the same slot.
	var steel_pipe: int = _spawn(w, PIPE)
	var baton: int = _spawn(w, BATON)
	if not SimAttachments.slots_of(w, steel_pipe).has("stud") or not SimAttachments.slots_of(w, baton).has("stud"):
		push_error("PLAUSIBLE: the pipe or the baton lost its stud slot, so the refusals below prove nothing about the host")
		return false
	for studs in [SCREWS, BOLTS, GLASS]:
		if not SimAttachments.fits(w, _spawn(w, String(studs)), "stud"):
			push_error("PLAUSIBLE: %s no longer fits a stud slot, so the refusal below proves nothing" % String(studs))
			return false
		for steel_host in [steel_pipe, baton]:
			if SimAttachments.attach(w, int(steel_host), _spawn(w, String(studs)), "stud"):
				push_error("PLAUSIBLE: %s went into a steel host's stud slot" % String(studs))
				return false
		for wooden in [_spawn(w, WOOD_BAT), _spawn(w, CLAW_HAMMER)]:
			if not SimAttachments.attach(w, int(wooden), _spawn(w, String(studs)), "stud"):
				push_error("PLAUSIBLE: %s was refused a wooden host's stud slot" % String(studs))
				return false
	# True negative, the one the piece names: a guard on a pipe. A pipe has no guard.
	var pipe: int = _spawn(w, PIPE)
	if SimAttachments.attach(w, pipe, _spawn(w, KNUCKLE), "guard"):
		push_error("PLAUSIBLE: a knuckle guard went onto a steel pipe")
		return false
	# The negative that has to refuse by family and not by slot: a scythe fits a head, and a pipe
	# has one, so only the polearm family can keep it off the pipe.
	var scythe: int = _spawn(w, SCYTHE)
	if not SimAttachments.fits(w, scythe, "head"):
		push_error("PLAUSIBLE: the scythe no longer fits a head, so the refusal below proves nothing")
		return false
	if SimAttachments.attach(w, pipe, scythe, "head"):
		push_error("PLAUSIBLE: a polearm head went onto a club's pipe")
		return false
	# And the positive on the same pipe: a pitchfork head is the one head that names it.
	if not SimAttachments.attach(w, pipe, _spawn(w, PITCHFORK_HEAD), "head"):
		push_error("PLAUSIBLE: a pitchfork head was refused the pipe it names")
		return false
	if not SimAttachments.attach(w, _spawn(w, SABRE), _spawn(w, KNUCKLE), "guard"):
		push_error("PLAUSIBLE: a knuckle guard was refused a sabre's guard slot")
		return false
	# Weight is a real reader: a pipe cap changes the swing weight the recovery is computed from.
	var heavy: int = _spawn(w, PIPE)
	var w0: float = float((SimItems.melee_profile_of(w, heavy) as Dictionary)["weight"])
	if not SimAttachments.attach(w, heavy, _spawn(w, PIPE_CAP), "weight"):
		push_error("PLAUSIBLE: a pipe cap was refused a pipe's weight slot")
		return false
	var w1: float = float((SimItems.melee_profile_of(w, heavy) as Dictionary)["weight"])
	if w1 <= w0:
		push_error("PLAUSIBLE: a pipe cap went on and the swing weight did not move (%.2f vs %.2f)" % [w1, w0])
		return false
	print("  PLAUSIBLE OK nails on a wooden bat move damage %.2f -> %.2f; nails in an aluminium bat, screws, bolts and glass in a steel pipe or a baton, a guard on a pipe and a polearm head on a pipe all refused; a pipe cap moves weight %.2f -> %.2f" % [float(before["damage"]), float(after["damage"]), w0, w1])
	return true


func _an_improvised_part_is_made_from_what_is_carried_and_fitted() -> bool:
	var w: Variant = _world()
	# A survivor carrying one unit of fixings, the nails' material.
	var fixings: int = SimItems.spawn_item(w, "item.fixings.nails", {"tier": "scavenged"})
	if not SimInventory.stow(w, w.player, fixings):
		w.components.set_component(fixings, "stored", {"container": w.player})
	SimRanged.load_held(w, w.player)
	var bat: int = _spawn(w, WOOD_BAT)
	var before: int = int(SimFortify.material_count(w, w.player, "fixings"))
	if before != 1:
		push_error("RECIPE: the survivor carries %d fixings, not the one this lane put in the pack" % before)
		return false
	# True positive, through the command the screen sends: field work, so no bench is needed.
	w.commands.push({"type": "item.improvise", "host": bat, "slot": "stud", "recipe": NAILS})
	w.step()
	var made: int = int(SimAttachments.in_slot(w, bat, "stud"))
	if made < 0 or String((SimItems.item_base_of(w, made) as Dictionary).get("id", "")) != NAILS:
		push_error("RECIPE: item.improvise did not fit nails into the wooden bat's stud")
		return false
	if int(SimFortify.material_count(w, w.player, "fixings")) != before - 1:
		push_error("RECIPE: the nails were fitted and the fixings were not spent")
		return false
	var made_events: Array = []
	for e in w.events.drained:
		if String((e as Dictionary).get("type", "")) == "attachment.improvised":
			made_events.append(e)
	if made_events.size() != 1:
		push_error("RECIPE: a successful improvise published %d attachment.improvised events, not one" % made_events.size())
		return false
	# True negative, the bench rule: glass is bench work and there is no bench in this world. The
	# check order puts the bench before the materials, so the reason is the bench, and nothing is spent.
	var glassed: int = _spawn(w, WOOD_BAT)
	var reason: String = SimAttachments.improvise(w, w.player, glassed, "stud", GLASS)
	if reason != "no-bench":
		push_error("RECIPE: glass was made with no bench in reach (reason '%s')" % reason)
		return false
	# True negative, the materials rule: no fixings left, so nails cannot be made.
	var short: String = SimAttachments.improvise(w, w.player, _spawn(w, WOOD_BAT), "stud", NAILS)
	if short != "no-material:fixings":
		push_error("RECIPE: nails were made with no fixings (reason '%s')" % short)
		return false
	# True negative, the plausibility rule: a survivor with fixings in the pack still cannot nail
	# them into an aluminium bat, and the fixings are not spent on the refusal.
	var stock: int = SimItems.spawn_item(w, "item.fixings.nails", {"tier": "scavenged"})
	if not SimInventory.stow(w, w.player, stock):
		w.components.set_component(stock, "stored", {"container": w.player})
	SimRanged.load_held(w, w.player)
	var misfit: String = SimAttachments.improvise(w, w.player, _spawn(w, ALU_BAT), "stud", NAILS)
	if misfit != "not-plausible" or int(SimFortify.material_count(w, w.player, "fixings")) != 1:
		push_error("RECIPE: nails went into an aluminium bat, or the refusal spent the fixings (reason '%s')" % misfit)
		return false
	# True positive, the bench path: a workbench in reach makes the glass, and it spends the cord.
	var wb: Variant = _world()
	SimGunsmith.make_bench(wb, 8.5, 12.5)
	var cord: int = SimItems.spawn_item(wb, "item.cordage.twine", {"tier": "scavenged"})
	if not SimInventory.stow(wb, wb.player, cord):
		wb.components.set_component(cord, "stored", {"container": wb.player})
	SimRanged.load_held(wb, wb.player)
	var glass_bat: int = _spawn(wb, WOOD_BAT)
	if SimAttachments.improvise(wb, wb.player, glass_bat, "stud", GLASS) != "":
		push_error("RECIPE: glass was refused at a bench with cord in the pack")
		return false
	if int(SimAttachments.in_slot(wb, glass_bat, "stud")) < 0 or int(SimFortify.material_count(wb, wb.player, "cordage")) != 0:
		push_error("RECIPE: the glass did not go in, or the cord was not spent")
		return false
	print("  RECIPE OK nails made from one fixings and fitted by command in the field; glass refused with no bench (no-bench), nails refused with no fixings, a misfit refused and not spent; glass made at a bench and the cord spent")
	return true


func _cuts_of_the_hand(w: Variant) -> int:
	var inj: Variant = w.components.get_component(w.player, "injuries")
	if not inj is Dictionary:
		return 0
	var n: int = 0
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		var d: Dictionary = wound as Dictionary
		if String(d.get("kind", "")) == "cut" and String(d.get("bodyPart", "")) == "hand_right":
			n += 1
	return n


func _swing_once(w: Variant, weapon: int) -> void:
	var candidates: Array[int] = []
	SimMelee._resolve_strike(w, w.player, SimItems.melee_profile_of(w, weapon) as Dictionary, w.rng.stream("melee"), candidates)


# A body a metre in front of the player, who stands at (8.5, 12.5) facing east: a swing connects.
func _victim(w: Variant) -> int:
	var v: int = int(w.entities.spawn())
	w.components.set_component(v, "position", {"x": 9.5, "y": 12.5})
	SimHealth.make_survivor_body(w, v)
	return v


func _scratches_of_the_hand(w: Variant) -> int:
	var inj: Variant = w.components.get_component(w.player, "injuries")
	if not inj is Dictionary:
		return 0
	var n: int = 0
	for wound in (inj as Dictionary).get("wounds", []) as Array:
		var d: Dictionary = wound as Dictionary
		if String(d.get("bodyPart", "")) == "hand_right" and int(d.get("severity", -1)) == SimWounds.Severity.Scratch and int(d.get("clotsAtTick", -1)) >= 0:
			n += 1
	return n


func _a_glass_blade_cuts_the_hand_that_holds_it_until_it_is_wrapped() -> bool:
	var w: Variant = _world()
	var bat: int = _spawn(w, WOOD_BAT)
	if not SimAttachments.attach(w, bat, _spawn(w, GLASS), "stud"):
		push_error("CUT: glass was refused a wooden bat's stud")
		return false
	# True negative: a swing that finds nobody costs the hand nothing.
	_swing_once(w, bat)
	if _cuts_of_the_hand(w) != 0:
		push_error("CUT: a swing that missed cut the hand (%d cuts)" % _cuts_of_the_hand(w))
		return false
	# True positive: a swing that connects with the grip bare scratches the hand once, and the
	# scratch is the kind that clots on its own (a Laceration never does).
	_victim(w)
	_swing_once(w, bat)
	if _cuts_of_the_hand(w) != 1 or _scratches_of_the_hand(w) != 1:
		push_error("CUT: glass with a bare grip left %d cuts and %d clotting scratches on one connecting swing, not one of each" % [_cuts_of_the_hand(w), _scratches_of_the_hand(w)])
		return false
	# True negative: wrap the grip and the same connecting swing keeps the hand.
	if not SimAttachments.attach(w, bat, _spawn(w, CORD_WRAP), "wrap"):
		push_error("CUT: a cord wrap was refused the grip")
		return false
	_swing_once(w, bat)
	if _cuts_of_the_hand(w) != 1:
		push_error("CUT: a wrapped grip was cut (%d cuts)" % _cuts_of_the_hand(w))
		return false
	# True negative, a hand that is gone: nothing is left to cut, and nothing is added.
	var w3: Variant = _world()
	var gone_bat: int = _spawn(w3, WOOD_BAT)
	if not SimAttachments.attach(w3, gone_bat, _spawn(w3, GLASS), "stud"):
		push_error("CUT: glass was refused a wooden bat's stud (destroyed-hand world)")
		return false
	_victim(w3)
	(w3.components.get_component(w3.player, "body") as Dictionary)["hand_right"] = SimWounds.DESTROYED
	_swing_once(w3, gone_bat)
	if _cuts_of_the_hand(w3) != 0:
		push_error("CUT: a destroyed hand was cut (%d cuts)" % _cuts_of_the_hand(w3))
		return false
	# True negative, the other way: nails declare no handCut, so a bare grip with nails is not cut.
	var w2: Variant = _world()
	var nailed: int = _spawn(w2, WOOD_BAT)
	if not SimAttachments.attach(w2, nailed, _spawn(w2, NAILS), "stud"):
		push_error("CUT: nails were refused a wooden bat's stud")
		return false
	_victim(w2)
	_swing_once(w2, nailed)
	if _cuts_of_the_hand(w2) != 0:
		push_error("CUT: nails cut the hand, which only glass declares")
		return false
	print("  CUT OK glass on a bare grip scratches the right hand once per connecting swing (a clotting scratch); a miss, a cord wrap and a destroyed hand cost nothing; nails never cut")
	return true


# --- MELEE WEAR -------------------------------------------------------------------------------
# Studs come out, a blade's edge dulls and a whetstone brings it back, a lashed head flies off at
# the swinger's feet. Every roll is on the `meleeWear` stream, and a weapon with nothing that
# declares a roll draws nothing. The first-cut numbers are docs/30's "Melee wear, 2026-10-27".

const SPEAR: String = "item.spear.improvised"
const LASHED_SPIKE: String = "item.attach.head.lashed_spike"
const WHETSTONE: String = "item.whetstone"
const WEAR_TRIALS: int = 2000
const STUD_BAND: Array[int] = [40, 80]
const LASH_BAND: Array[int] = [30, 72]


# A nail that comes out is gone, and the next roll is a fresh nail's. Over WEAR_TRIALS rolls at 0.03
# a nailed bat should lose about 60 nails, and the band holds the seed inside it. The first nail
# out is also where the swing after it is judged: the bat must hit for exactly what a bare bat hits
# for.
func _studs_come_out_at_their_rate_and_the_swing_after_is_bare() -> bool:
	var lane: String = "STUD"
	var w: Variant = _world()
	var bat: int = _spawn(w, WOOD_BAT)
	var bare_damage: float = float((SimItems.melee_profile_of(w, bat) as Dictionary)["damage"])
	var sheds: int = 0
	var checked_first: bool = false
	for i in WEAR_TRIALS:
		if SimAttachments.in_slot(w, bat, "stud") < 0 and not SimAttachments.attach(w, bat, _spawn(w, NAILS), "stud"):
			push_error("%s: a nail was refused the bat's stud slot on roll %d" % [lane, i])
			return false
		SimAttachments.shed_on_connect(w, bat, w.player)
		if SimAttachments.in_slot(w, bat, "stud") >= 0:
			continue
		sheds += 1
		if not checked_first:
			checked_first = true
			var after: float = float((SimItems.melee_profile_of(w, bat) as Dictionary)["damage"])
			if absf(after - bare_damage) > 0.0001:
				push_error("%s: the swing after a nail came out hits for %.4f, not a bare bat's %.4f" % [lane, after, bare_damage])
				return false
	if sheds < STUD_BAND[0] or sheds > STUD_BAND[1]:
		push_error("%s: %d nails came out of %d rolls at 0.03, outside the band %s" % [lane, sheds, WEAR_TRIALS, str(STUD_BAND)])
		return false
	# True negative: a bat with no stud has no roll to make, so it never sheds and never grows a part.
	var bare: int = _spawn(w, WOOD_BAT)
	for i in WEAR_TRIALS:
		SimAttachments.shed_on_connect(w, bare, w.player)
	if SimAttachments.parts_of(w, bare).size() != 0:
		push_error("%s: a bare bat grew a part" % lane)
		return false
	print("  STUD OK %d of %d nail rolls came out (band %s); the swing after one hits for a bare bat's %.2f; a bare bat rolls for nothing" % [sheds, WEAR_TRIALS, str(STUD_BAND), bare_damage])
	return true


# A lashed head comes off at the swinger's feet as its own item, and is no longer attached. Same
# story as the nail at 0.025 over the same trials. A head fitted without a lashing never flies,
# however many blows land on it.
func _a_lashed_head_flies_off_at_the_swingers_feet() -> bool:
	var lane: String = "LASH"
	var w: Variant = _world()
	var spear: int = _spawn(w, SPEAR)
	if not _swap(w, spear, "head", _spawn(w, LASHED_SPIKE)):
		push_error("%s: a lashed spike was refused the spear's head slot" % lane)
		return false
	var feet: Dictionary = (w.components.get_component(w.player, "position") as Dictionary).duplicate()
	var flown: int = 0
	for i in WEAR_TRIALS:
		if SimAttachments.in_slot(w, spear, "head") < 0 and not SimAttachments.attach(w, spear, _spawn(w, LASHED_SPIKE), "head"):
			push_error("%s: a lashed spike was refused the spear's head slot on blow %d" % [lane, i])
			return false
		var head: int = SimAttachments.in_slot(w, spear, "head")
		SimAttachments.shed_on_connect(w, spear, w.player)
		if SimAttachments.in_slot(w, spear, "head") >= 0:
			continue
		flown += 1
		var landed: Variant = w.components.get_component(head, "position")
		if not landed is Dictionary or absf(float((landed as Dictionary)["x"]) - float(feet["x"])) > 0.0001 or absf(float((landed as Dictionary)["y"]) - float(feet["y"])) > 0.0001:
			push_error("%s: a head that flew off did not land at the swinger's feet" % lane)
			return false
		if w.components.has_component(head, "attachedTo"):
			push_error("%s: a head that flew off still says it is attached" % lane)
			return false
	if flown < LASH_BAND[0] or flown > LASH_BAND[1]:
		push_error("%s: %d heads flew off in %d blows at 0.025, outside the band %s" % [lane, flown, WEAR_TRIALS, str(LASH_BAND)])
		return false
	# True negative: a standard head carries no lashing, so the same blows never move it.
	var plain: int = _spawn(w, SPEAR)
	for i in WEAR_TRIALS:
		SimAttachments.shed_on_connect(w, plain, w.player)
	if SimAttachments.in_slot(w, plain, "head") < 0:
		push_error("%s: a standard head flew off a spear" % lane)
		return false
	# FOOTLESS: a swinger with no position has no feet to land the head at, and the spear here is
	# carried by nobody, lies nowhere and sits in no container, so the ladder refuses too. The head
	# must stay fitted rather than be unlinked and homed nowhere. Two thousand rolls at 0.025 miss
	# every one with odds under 1e-20, so a head still on is the ladder's refusal, not the seed's.
	var footless: int = _spawn(w, SPEAR)
	if not _swap(w, footless, "head", _spawn(w, LASHED_SPIKE)):
		push_error("%s: a lashed spike was refused the footless spear's head slot" % lane)
		return false
	var lashed_head: int = SimAttachments.in_slot(w, footless, "head")
	# `_swap` lent the spear a tile so the standard head could detach onto it; take it back, or the
	# ladder's second rung lands the head beside the spear and the refusal is never reached.
	w.components.remove(footless, "position")
	var nobody: int = int(w.entities.spawn())
	for i in WEAR_TRIALS:
		SimAttachments.shed_on_connect(w, footless, nobody)
	if SimAttachments.in_slot(w, footless, "head") != lashed_head:
		push_error("%s: a head flew off for a swinger with no feet; the ladder should have refused and left it on" % lane)
		return false
	if w.components.has_component(lashed_head, "position"):
		push_error("%s: a head with nowhere to land was given a position anyway" % lane)
		return false
	if not w.components.has_component(lashed_head, "attachedTo"):
		push_error("%s: a head that stayed in its slot lost its attachedTo link" % lane)
		return false
	print("  LASH OK %d of %d blows threw a lashed head to the feet (band %s); a standard head never flew; a footless swinger's head stayed on through %d rolls" % [flown, WEAR_TRIALS, str(LASH_BAND), WEAR_TRIALS])
	return true


# A blade's edge dulls on every connect and its damage follows; a club has no edge and takes none.
# Driven through the connect path, so each blow is the one a swing makes.
func _a_blade_dulls_on_each_connect_and_a_club_takes_no_edge() -> bool:
	var lane: String = "EDGE"
	var w: Variant = _world()
	var axe: int = _spawn(w, AXE)
	var keen: float = float((SimItems.melee_profile_of(w, axe) as Dictionary)["damage"])
	_dull_by_connects(w, axe, 20)
	var dull: float = float((SimItems.melee_profile_of(w, axe) as Dictionary)["damage"])
	var edge: Dictionary = SimItems.edge_of(w, axe)
	if float(edge["current"]) >= 1.0:
		push_error("%s: an axe that connected twenty times is still keen (edge %.3f)" % [lane, float(edge["current"])])
		return false
	if dull >= keen:
		push_error("%s: a dull axe hits for %.4f, no less than a keen one's %.4f" % [lane, dull, keen])
		return false
	var club: int = _spawn(w, WOOD_BAT)
	_dull_by_connects(w, club, 20)
	var club_condition: Dictionary = w.components.get_component(club, "condition") as Dictionary
	if float(club_condition["current"]) >= 1.0:
		push_error("%s: the club never connected, so its missing edge proves nothing" % lane)
		return false
	if w.components.has_component(club, "edge"):
		push_error("%s: a club grew an edge" % lane)
		return false
	print("  EDGE OK an axe's edge fell to %.3f on twenty connects and its damage %.2f -> %.2f; a club connected twenty times and has no edge" % [float(edge["current"]), keen, dull])
	return true


# Hone brings a dull edge back to its ceiling and spends one whetstone. Each refusal -- not a blade,
# already keen, no whetstone -- comes back as a reason and spends nothing. Keen is checked before the
# stone, so a keen blade keeps the stone in the pack.
func _a_whetstone_hones_a_blade_and_each_refusal_says_why() -> bool:
	var lane: String = "HONE"
	var w: Variant = _world()
	var axe: int = _spawn(w, AXE)
	var bat: int = _spawn(w, WOOD_BAT)
	_dull_by_connects(w, axe, 20)
	var said: String = _hone_attempt(w, bat)
	if said != "not-a-blade":
		push_error("%s: honing a bat said '%s', not 'not-a-blade'" % [lane, said])
		return false
	said = _hone_attempt(w, axe)
	if said != "no-whetstone":
		push_error("%s: honing with nothing in the pack said '%s', not 'no-whetstone'" % [lane, said])
		return false
	var stone: int = _spawn(w, WHETSTONE)
	SimInventory.stow(w, w.player, stone)
	var dull: float = float((SimItems.melee_profile_of(w, axe) as Dictionary)["damage"])
	said = _hone_attempt(w, axe)
	if said != "honed":
		push_error("%s: honing a dull axe with a whetstone said '%s', not 'honed'" % [lane, said])
		return false
	var edge: Dictionary = SimItems.edge_of(w, axe)
	if float(edge["current"]) != float(edge["ceiling"]) or float(edge["ceiling"]) >= 1.0:
		push_error("%s: honing did not bring the edge to a lowered ceiling (edge %s)" % [lane, str(edge)])
		return false
	if float((SimItems.melee_profile_of(w, axe) as Dictionary)["damage"]) <= dull:
		push_error("%s: honing did not restore any damage" % lane)
		return false
	if SimInventory.carried_items(w, w.player).has(stone):
		push_error("%s: the whetstone was not spent" % lane)
		return false
	# True negative: a keen blade refuses, and the stone it would have cost stays in the pack.
	var stone2: int = _spawn(w, WHETSTONE)
	SimInventory.stow(w, w.player, stone2)
	said = _hone_attempt(w, axe)
	if said != "keen":
		push_error("%s: honing a keen axe said '%s', not 'keen'" % [lane, said])
		return false
	if not SimInventory.carried_items(w, w.player).has(stone2):
		push_error("%s: a keen axe spent a whetstone" % lane)
		return false
	print("  HONE OK a dull axe honed on one whetstone to a ceiling of %.2f; not-a-blade, no-whetstone and keen each refuse in words and spend nothing" % float(edge["ceiling"]))
	return true


# Dead socket: the real swing command, stepped through the tick loop, reaches the stud roll. A nailed
# bat swings at a fresh body in front of the player until a nail comes out, up to 600 swings. Not
# every swing connects (the recovery eats some of the commands), and the seed is fixed, so a red
# lane means the shipped path stopped reading the stud, not that the seed was unlucky. Broken on
# purpose once -- the connect subscriber replaced by a pass -- and the lane went red with
# "no nail came out".
func _a_real_connect_sheds_a_stud_through_the_swing_command() -> bool:
	var lane: String = "CONNECT"
	var w: Variant = _world()
	var bat: int = _spawn(w, WOOD_BAT)
	SimInventory.equip(w, w.player, bat)
	if not SimAttachments.attach(w, bat, _spawn(w, NAILS), "stud"):
		push_error("%s: a nail was refused the bat's stud slot" % lane)
		return false
	var connects: int = 0
	var shed: bool = false
	var body: int = -1
	for i in 600:
		if body >= 0:
			w.despawn(body)
		body = int(w.entities.spawn())
		w.components.set_component(body, "position", {"x": 9.3, "y": 12.5})
		w.components.set_component(body, "velocity", {"dx": 0.0, "dy": 0.0})
		w.components.set_component(body, "body", SimCombat.ZOMBIE_BODY.duplicate())
		w.commands.push({"type": "swing"})
		for t in 60:
			w.step()
			for e in w.events.drained:
				var ev: Dictionary = e as Dictionary
				if String(ev.get("type", "")) == "attack.connected" and int(ev.get("item", -1)) == bat:
					connects += 1
				if String(ev.get("type", "")) == "attachment.shed" and int(ev.get("host", -1)) == bat:
					shed = true
			if shed:
				break
		if shed:
			break
	if connects < 1:
		push_error("%s: no swing connected in 600 tries, so the stud roll was never reached" % lane)
		return false
	if not shed:
		push_error("%s: %d connects through the swing command and no nail came out" % [lane, connects])
		return false
	print("  CONNECT OK a nail came out on connect %d through the real swing command" % connects)
	return true


# The stud and the lashing roll on their own stream. Two identically seeded worlds: one rolls a few
# hundred times, the other does not. Every other stream reads the same next draw in both, and the
# wear stream does not, which is what shows the rolls happened on it.
func _wear_rolls_draw_only_the_melee_wear_stream() -> bool:
	var lane: String = "STREAM"
	var rolled: Variant = _world()
	var quiet: Variant = _world()
	var bat: int = _spawn(rolled, WOOD_BAT)
	for i in 300:
		if SimAttachments.in_slot(rolled, bat, "stud") < 0:
			SimAttachments.attach(rolled, bat, _spawn(rolled, NAILS), "stud")
		SimAttachments.shed_on_connect(rolled, bat, rolled.player)
	for stream in ["melee", "swipe", "ranged", "test"]:
		var a: float = float(rolled.rng.stream(stream).call("next"))
		var b: float = float(quiet.rng.stream(stream).call("next"))
		if a != b:
			push_error("%s: the '%s' stream moved under a run of wear rolls (%f vs %f)" % [lane, stream, a, b])
			return false
	var moved: float = float(rolled.rng.stream("meleeWear").call("next"))
	var untouched: float = float(quiet.rng.stream("meleeWear").call("next"))
	if moved == untouched:
		push_error("%s: the meleeWear stream did not move under 300 rolls" % lane)
		return false
	print("  STREAM OK 300 wear rolls moved meleeWear and left melee, swipe, ranged and test where they were")
	return true


# Dulls an edge the way a connect does: a fresh body in front, then a swing through the same resolver
# every lane in this file uses. The drain is what dispatches `attack.connected` to the wear handlers;
# `_swing_once` only queues it.
func _dull_by_connects(w: Variant, weapon: int, blows: int) -> void:
	for i in blows:
		_victim(w)
		_swing_once(w, weapon)
		w.events.drain()


# Pushes one hone command, steps the tick, and reads what came back: "honed", a refusal's reason, or
# "none" when nothing answered.
func _hone_attempt(w: Variant, item: int) -> String:
	w.commands.push({"type": "item.hone", "actor": w.player, "item": item})
	w.step()
	for e in w.events.drained:
		var ev: Dictionary = e as Dictionary
		if int(ev.get("item", -1)) != item:
			continue
		if String(ev.get("type", "")) == "item.honed":
			return "honed"
		if String(ev.get("type", "")) == "item.hone_refused":
			return String(ev.get("reason", ""))
	return "none"



# --- BARREL -----------------------------------------------------------------------------------
#
# A barrel declares three words (sim/barrel.gd) and the shot reads their product. Six lanes, each
# with a true negative: the vocabulary refuses a typo out loud, the six shipped barrels keep the
# numbers they were authored with, length and quality move the shot they name, material and
# quality move the wear they name, and a slow round loses damage at range where a plain one does
# not.

const BARREL_STD: String = "item.part.barrel.standard"
const BARREL_RIMFIRE: String = "item.part.barrel.rimfire"
const BARREL_45: String = "item.part.barrel.45"
const BARREL_MATCH: String = "item.attach.barrel.match"
const BARREL_SHORT: String = "item.attach.barrel.short"
const BARREL_LONG: String = "item.attach.barrel.long"

# The six barrels as authored before sim/barrel.gd (content at e14a8088). Each number is the total
# a barrel contributed on that axis. The words must land within 5% of it, and `muzzle` is the one
# axis that is new: no shipped barrel had it, so it is absent here and only checked to be 1.0 on
# the barrels that have no reason to slow a round.
const SHIPPED_BEFORE: Dictionary = {
	"item.part.barrel.standard": {"ranged": {}, "wearRate": 1.0},
	"item.part.barrel.rimfire": {"ranged": {"damage": 0.6, "noise": 0.7}, "wearRate": 1.1},
	"item.part.barrel.45": {"ranged": {"damage": 1.2, "rangeMetres": 0.85, "noise": 1.05}, "wearRate": 1.0},
	"item.attach.barrel.match": {"ranged": {"cone": 0.82, "rangeMetres": 1.18, "damage": 1.06, "handling": 0.85}, "wearRate": 1.4},
	"item.attach.barrel.short": {"ranged": {"rangeMetres": 0.72, "noise": 1.22, "handling": 1.25, "cone": 1.1}, "wearRate": 1.0},
	"item.attach.barrel.long": {"ranged": {"rangeMetres": 1.3, "noise": 1.12, "cone": 0.9}, "wearRate": 1.0},
}


func _within_five(got: float, want: float) -> bool:
	return absf(got - want) <= 0.05 * absf(want)


func _the_vocabulary_refuses_a_typo_out_loud() -> bool:
	var lane: String = "BARREL VOCAB"
	var good: Dictionary = {"length": "full", "quality": "service", "material": "steel"}
	if SimBarrel.error_of(good) != "":
		push_error("%s: a barrel of known words was refused as '%s'" % [lane, SimBarrel.error_of(good)])
		return false
	var cases: Dictionary = {
		"length:lenght": {"length": "lenght", "quality": "service", "material": "steel"},
		"quality:matchy": {"length": "full", "quality": "matchy", "material": "steel"},
		"material:brass": {"length": "full", "quality": "service", "material": "brass"},
		"missing:material": {"length": "full", "quality": "service"},
		"unknown-key:colour": {"length": "full", "quality": "service", "material": "steel", "colour": "red"},
		"not-a-barrel": "steel",
	}
	for want in cases.keys():
		var got: String = SimBarrel.error_of(cases[want])
		if got != String(want):
			push_error("%s: %s came back as '%s', not '%s'" % [lane, str(cases[want]), got, String(want)])
			return false
	# TN: a typo'd declaration resolves marked with its reason and with no derived numbers, so no
	# caller can read it as a plain barrel. The `ranged` it carries is left exactly as it was.
	var bad: Dictionary = SimBarrel.resolve({"barrel": cases["length:lenght"], "ranged": {"noise": 0.5}})
	if String(bad.get("barrelError", "")) != "length:lenght" or float((bad["ranged"] as Dictionary)["noise"]) != 0.5:
		push_error("%s: a typo'd barrel resolved as %s" % [lane, str(bad)])
		return false
	# Refused at the weapon too: a pistol whose barrel carries a typo is blocked, and the sentence
	# says so. The base is patched in memory and restored, so no other lane sees the typo.
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var barrel_base: Dictionary = SimItems.base_by_id(w, BARREL_SHORT) as Dictionary
	var words: Dictionary = (barrel_base["attachment"] as Dictionary)["barrel"] as Dictionary
	var keep: String = String(words["length"])
	words["length"] = "lenght"
	var part: int = _spawn(w, BARREL_SHORT)
	var blocked: String = ""
	if _swap(w, pistol, "barrel", part):
		blocked = SimAttachments.blocked_reason(w, pistol)
	words["length"] = keep
	if blocked != "barrel:length:lenght":
		push_error("%s: a pistol with a typo'd barrel reads blocked '%s', not 'barrel:length:lenght'" % [lane, blocked])
		return false
	# refusal_clause asks the actor, whose `rangedWeapon` carries the reason, not the pistol.
	if SimAttachments.refusal_clause(w, w.player) != "The barrel in it is not a barrel the bench knows how to bore.":
		push_error("%s: the refusal sentence is '%s'" % [lane, SimAttachments.refusal_clause(w, w.player)])
		return false
	print("  BARREL VOCAB OK typos refused as length:, quality:, material:, missing:, unknown-key:, not-a-barrel; the pistol says so and fires nothing")
	return true


func _the_shipped_six_keep_their_numbers() -> bool:
	var lane: String = "BARREL SHIPPED"
	var w: Variant = _world()
	var checked: int = 0
	for id_v in SHIPPED_BEFORE.keys():
		var id: String = String(id_v)
		var base: Variant = SimItems.base_by_id(w, id)
		if not base is Dictionary or not ((base as Dictionary).get("attachment") is Dictionary):
			push_error("%s: %s is not a shipped attachment" % [lane, id])
			return false
		var spec: Dictionary = SimBarrel.resolve((base as Dictionary)["attachment"] as Dictionary)
		var before: Dictionary = SHIPPED_BEFORE[id] as Dictionary
		var before_ranged: Dictionary = before["ranged"] as Dictionary
		var ranged: Dictionary = spec.get("ranged", {}) as Dictionary
		for field in before_ranged.keys():
			var got: float = float(ranged.get(field, 1.0))
			if not _within_five(got, float(before_ranged[field])):
				push_error("%s: %s %s is %.4f, was %.4f" % [lane, id, String(field), got, float(before_ranged[field])])
				return false
		for field in ranged.keys():
			if String(field) == "muzzle" or before_ranged.has(field):
				continue
			if not _within_five(float(ranged[field]), 1.0):
				push_error("%s: %s moved %s, an axis it never had" % [lane, id, String(field)])
				return false
		if not _within_five(float(spec.get("wearRate", 1.0)), float(before["wearRate"])):
			push_error("%s: %s wears at %.4f, was %.4f" % [lane, id, float(spec.get("wearRate", 1.0)), float(before["wearRate"])])
			return false
		checked += 1
	if checked != 6:
		push_error("%s: %d shipped barrels checked, expected 6" % [lane, checked])
		return false
	# TN: a number six percent out is refused, so the 5% band is a band and not a shrug.
	if _within_five(1.06, 1.0) or not _within_five(1.04, 1.0):
		push_error("%s: the 5%% band does not separate 1.06 from 1.04" % lane)
		return false
	print("  BARREL SHIPPED OK six barrels, every pre-existing axis within 5% of its authored total; no axis moved that it did not have")
	return true


func _length_moves_the_shot_it_names() -> bool:
	var lane: String = "BARREL LENGTH"
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	var std_noise: float = _noise_of(w, w.player)
	var std_reach: float = float((SimItems.ranged_profile_of(w, pistol) as Dictionary)["rangeMetres"])
	_swap(w, pistol, "barrel", _spawn(w, BARREL_LONG))
	w.events.drain()
	var long_noise: float = _noise_of(w, w.player)
	var long_reach: float = float((SimItems.ranged_profile_of(w, pistol) as Dictionary)["rangeMetres"])
	_swap(w, pistol, "barrel", _spawn(w, BARREL_SHORT))
	w.events.drain()
	var short_noise: float = _noise_of(w, w.player)
	var short_reach: float = float((SimItems.ranged_profile_of(w, pistol) as Dictionary)["rangeMetres"])
	if not (short_noise > long_noise and long_noise > std_noise):
		push_error("%s: noise short %.2f, long %.2f, standard %.2f -- the shorter barrel is not the louder one" % [lane, short_noise, long_noise, std_noise])
		return false
	if not (long_reach > std_reach and std_reach > short_reach):
		push_error("%s: reach long %.2f, standard %.2f, short %.2f -- length is not reaching the shot" % [lane, long_reach, std_reach, short_reach])
		return false
	# TN: the same length on the same receiver gives the same shot.
	_swap(w, pistol, "barrel", _spawn(w, BARREL_STD))
	w.events.drain()
	var again: float = _noise_of(w, w.player)
	if absf(again - std_noise) > 0.001:
		push_error("%s: the same barrel fired twice reads %.4f then %.4f" % [lane, std_noise, again])
		return false
	print("  BARREL LENGTH OK noise short %.1f > long %.1f > standard %.1f; reach long %.1f > standard %.1f > short %.1f; the same length twice reads the same" % [short_noise, long_noise, std_noise, long_reach, std_reach, short_reach])
	return true


func _quality_moves_the_cone_it_names() -> bool:
	var lane: String = "BARREL QUALITY"
	var std_world: Variant = _world()
	var std_pistol: int = _armed_pistol(std_world)
	var std_cone: float = _cone_while_aiming(std_world)
	var match_world: Variant = _world()
	var match_pistol: int = _armed_pistol(match_world)
	_swap(match_world, match_pistol, "barrel", _spawn(match_world, BARREL_MATCH))
	match_world.events.drain()
	var match_cone: float = _cone_while_aiming(match_world)
	if not (match_cone < std_cone * 0.9):
		push_error("%s: match cone %.4f against standard %.4f -- a true bore is not tighter" % [lane, match_cone, std_cone])
		return false
	# TN: a rough bore is wider than service, and a service bore changes nothing at all.
	var rough: Dictionary = SimBarrel.resolve({"barrel": {"length": "full", "quality": "rough", "material": "steel"}})
	var service: Dictionary = SimBarrel.resolve({"barrel": {"length": "full", "quality": "service", "material": "steel"}})
	if not (float((rough["ranged"] as Dictionary)["cone"]) > 1.1) or (service["ranged"] as Dictionary).has("cone"):
		push_error("%s: rough resolves to %s and service to %s" % [lane, str(rough["ranged"]), str(service["ranged"])])
		return false
	# A true bore is also the one that goes off true soonest: `match` wears 1.4 times `service` on
	# the same steel, so the shipped match barrel's wear is its quality's and not a softer metal's.
	# TN: service on steel is the identity.
	var match_steel: Dictionary = SimBarrel.resolve({"barrel": {"length": "full", "quality": "match", "material": "steel"}})
	if not _within_five(float(match_steel["wearRate"]), 1.4) or float(service["wearRate"]) != 1.0:
		push_error("%s: match on steel wears at %.3f and service at %.3f, not 1.4 and 1.0" % [lane, float(match_steel["wearRate"]), float(service["wearRate"])])
		return false
	print("  BARREL QUALITY OK match cone %.4f against standard %.4f; rough widens, service is the identity; match wears %.1f on the same steel" % [match_cone, std_cone, float(match_steel["wearRate"])])
	return true


func _material_moves_the_wear_it_names() -> bool:
	var lane: String = "BARREL MATERIAL"
	# The same short barrel in two worlds, one of them re-declared `mild` in memory for the length
	# of its twenty shots and restored before the steel world fires, so no other lane and not the
	# steel world sees the patch. No shipped barrel is mild: the one that wears 1.4 is match on
	# steel, and that is QUALITY's to hold.
	var mild_world: Variant = _world()
	var mild_pistol: int = _armed_pistol(mild_world)
	var short_base: Dictionary = SimItems.base_by_id(mild_world, BARREL_SHORT) as Dictionary
	var short_words: Dictionary = (short_base["attachment"] as Dictionary)["barrel"] as Dictionary
	var keep_material: String = String(short_words["material"])
	if keep_material != "steel":
		push_error("%s: the shipped short barrel is %s, this lane assumes steel" % [lane, keep_material])
		return false
	short_words["material"] = "mild"
	_swap(mild_world, mild_pistol, "barrel", _spawn(mild_world, BARREL_SHORT))
	for i in 20:
		SimAttachments.wear_parts(mild_world, mild_pistol, "shot")
	var mild_loss: float = 1.0 - _condition_of(mild_world, SimAttachments.in_slot(mild_world, mild_pistol, "barrel"))
	short_words["material"] = keep_material
	var steel_world: Variant = _world()
	var steel_pistol: int = _armed_pistol(steel_world)
	_swap(steel_world, steel_pistol, "barrel", _spawn(steel_world, BARREL_SHORT))
	for i in 20:
		SimAttachments.wear_parts(steel_world, steel_pistol, "shot")
	var steel_loss: float = 1.0 - _condition_of(steel_world, SimAttachments.in_slot(steel_world, steel_pistol, "barrel"))
	if not (mild_loss > 0.0 and steel_loss > 0.0):
		push_error("%s: a shot wore nothing (mild %.5f, steel %.5f)" % [lane, mild_loss, steel_loss])
		return false
	if not _within_five(mild_loss / steel_loss, 1.4):
		push_error("%s: mild loses %.5f a shot against steel %.5f, ratio %.3f, not 1.4" % [lane, mild_loss, steel_loss, mild_loss / steel_loss])
		return false
	# TN: chromed lasts longer than steel, and a material the bench does not know is refused.
	var chromed: Dictionary = SimBarrel.resolve({"barrel": {"length": "full", "quality": "service", "material": "chromed"}})
	if not (float(chromed["wearRate"]) < 1.0):
		push_error("%s: chromed wears at %.3f, not less than steel" % [lane, float(chromed["wearRate"])])
		return false
	print("  BARREL MATERIAL OK mild loses %.5f a shot, steel %.5f (ratio %.2f); chromed wears at %.1f" % [mild_loss, steel_loss, mild_loss / steel_loss, float(chromed["wearRate"])])
	return true


# A target a fraction of the standard reach out, in front of a pistol with the named barrel. Fires
# once and returns the damage the round carried, or -1.0 when nothing was hit. Each world is built
# from the same seed, so the head-or-torso roll is the same in every run and the ratio is the barrel's.
func _damage_at(barrel_id: String, distance: float) -> float:
	var w: Variant = _world()
	var pistol: int = _armed_pistol(w)
	if barrel_id != BARREL_STD:
		_swap(w, pistol, "barrel", _spawn(w, barrel_id))
	w.events.drain()
	var target: int = int(w.entities.spawn())
	w.components.set_component(target, "position", {"x": 8.5 + distance, "y": 12.5})
	w.components.set_component(target, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(target, "body", SimCombat.ZOMBIE_BODY.duplicate())
	w.commands.push({"type": "fire"})
	for i in 80:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "attack.connected" and int(ev.get("target", -1)) == target:
				return float(ev.get("damage", -1.0))
	return -1.0


func _a_slow_round_loses_damage_past_its_falloff() -> bool:
	var lane: String = "BARREL FALLOFF"
	if SimBarrel.falloff(1.0, 1.0) != 1.0 or SimBarrel.falloff(0.6, 0.6) != 1.0:
		push_error("%s: a full-speed round or one inside the start lost damage" % lane)
		return false
	if not _within_five(SimBarrel.falloff(0.6, 1.0), 0.6) or not _within_five(SimBarrel.falloff(0.8, 0.9), 0.85):
		push_error("%s: falloff(0.6, 1.0) %.4f, falloff(0.8, 0.9) %.4f" % [lane, SimBarrel.falloff(0.6, 1.0), SimBarrel.falloff(0.8, 0.9)])
		return false
	if not (SimBarrel.falloff(0.6, 0.8) > SimBarrel.falloff(0.6, 0.95)):
		push_error("%s: a slow round does not lose more the further it goes" % lane)
		return false
	var probe: Variant = _world()
	var reach0: float = float((SimItems.ranged_profile_of(probe, _armed_pistol(probe)) as Dictionary)["rangeMetres"])
	# 0.65 of the standard reach: inside the short barrel's reach (0.72), past its falloff start.
	var distance: float = 0.65 * reach0
	var std_damage: float = _damage_at(BARREL_STD, distance)
	var short_damage: float = _damage_at(BARREL_SHORT, distance)
	if std_damage <= 0.0 or short_damage <= 0.0:
		push_error("%s: a shot at %.2f m did not connect (standard %.3f, short %.3f)" % [lane, distance, std_damage, short_damage])
		return false
	# Short: fraction 0.65 / 0.72 of its own reach, which keeps 1 - 0.2 * ((0.903 - 0.6) / 0.4) = 0.849.
	if not _within_five(short_damage / std_damage, 0.849):
		push_error("%s: short carries %.3f of standard's damage at %.2f m, not 0.849" % [lane, short_damage / std_damage, distance])
		return false
	print("  BARREL FALLOFF OK at %.2f m a cut-down round carries %.3f of the standard round's damage; full speed loses nothing at any range" % [distance, short_damage / std_damage])
	return true


# --- BARREL WORDS ----------------------------------------------------------------------------

# A barrel's three words as the screen says them (sim/barrel.gd `words_of`, drawn by the bench and
# by the inspect pane). The tables are held both ways: every key of LENGTH, QUALITY and MATERIAL_WEAR
# has a screen word, and no screen word is for a key the shot does not read. The words are then
# checked against the six shipped barrels, which say what they are with no digit; a declaration the
# bench refuses, or a part with no barrel, says nothing; a barrel of other words says other words.
# Last, the bench carries the words where the player chooses: a fitted barrel's row and each barrel
# in the pack, and a magazine offer carries none. The dead-socket reader is the bench, which asks
# `words_of` rather than keeping its own copy.
func _barrel_words_are_said_in_words() -> bool:
	var lane: String = "BARREL WORDS"
	var tables: Dictionary = {"length": SimBarrel.LENGTH, "quality": SimBarrel.QUALITY, "material": SimBarrel.MATERIAL_WEAR}
	for key in tables.keys():
		var table: Dictionary = tables[key] as Dictionary
		var words: Dictionary = SimBarrel.WORD_OF[key] as Dictionary
		for k in table.keys():
			if not words.has(k):
				push_error("%s: the %s '%s' has no word on the screen" % [lane, key, k])
				return false
		for k in words.keys():
			if not table.has(k):
				push_error("%s: the screen word for %s '%s' names no key the shot reads" % [lane, key, k])
				return false
	for key in SimBarrel.WORD_OF.keys():
		for word in (SimBarrel.WORD_OF[key] as Dictionary).values():
			if String(word).is_empty() or _has_digit(String(word)):
				push_error("%s: the %s word '%s' is empty or carries a digit" % [lane, key, String(word)])
				return false

	var w: Variant = _world()
	var want: Dictionary = {
		BARREL_STD: "plain",
		BARREL_RIMFIRE: "plain",
		BARREL_45: "plain",
		BARREL_MATCH: "match",
		BARREL_SHORT: "short",
		BARREL_LONG: "long",
	}
	for id in want.keys():
		var spec: Variant = SimAttachments.spec_of(w, _spawn(w, id))
		if not spec is Dictionary:
			push_error("%s: %s has no attachment spec" % [lane, id])
			return false
		var got: String = SimBarrel.words_of(spec as Dictionary)
		if got != String(want[id]):
			push_error("%s: %s says '%s', not '%s'" % [lane, id, got, String(want[id])])
			return false
	# TP: each departure said, in length, quality, material order. A barrel that departs nowhere says
	# "plain" rather than nothing, so a plain barrel and a refused one never read alike.
	if SimBarrel.words_of({"barrel": {"length": "stub", "quality": "rough", "material": "mild"}}) != "stub, rough, mild":
		push_error("%s: a stub, rough, mild barrel did not say its three departures in order" % lane)
		return false
	if SimBarrel.words_of({"barrel": {"length": "full", "quality": "service", "material": "steel"}}) != "plain":
		push_error("%s: the identity barrel did not say plain" % lane)
		return false
	# TN: a barrel the bench refuses says nothing, a typo never reads as a plain barrel, a part with
	# no barrel says nothing, and a barrel that is not a dictionary says nothing.
	for bad in [
		{"barrel": {"length": "lenght", "quality": "service", "material": "steel"}},
		{"barrel": {"length": "full", "quality": "service", "material": "brass"}},
		{"barrel": "steel"},
		{"fits": ["muzzle"]},
	]:
		if SimBarrel.words_of(bad) != "":
			push_error("%s: %s said '%s', not nothing" % [lane, str(bad), SimBarrel.words_of(bad)])
			return false

	# The bench: a fitted barrel's row carries its words, a barrel in the pack is offered with its
	# words, and a magazine offer carries none.
	var bw: Variant = _world()
	var pistol: int = _armed_pistol(bw)
	var fitted: int = SimAttachments.in_slot(bw, pistol, "barrel")
	var match_item: int = _spawn(bw, BARREL_MATCH)
	var spare: int = _spawn(bw, EXT_MAG)
	SimInventory.stow(bw, bw.player, match_item)
	SimInventory.stow(bw, bw.player, spare)
	# Offers are only made where the person can work, so a bench stands on the player.
	var here: Dictionary = bw.components.get_component(bw.player, "position") as Dictionary
	SimGunsmith.make_bench(bw, float(here["x"]), float(here["y"]))
	var view: Dictionary = SimGunsmith.bench_view(bw, bw.player, pistol)
	var fitted_words: String = SimBarrel.words_of(SimAttachments.spec_of(bw, fitted) as Dictionary)
	var barrel_row: Dictionary = {}
	for row_v in view.get("slots", []) as Array:
		if String((row_v as Dictionary).get("slot", "")) == "barrel":
			barrel_row = row_v as Dictionary
	if fitted_words.is_empty() or String(barrel_row.get("barrel", "")) != fitted_words:
		push_error("%s: the fitted barrel's row says '%s', not its words '%s'" % [lane, String(barrel_row.get("barrel", "")), fitted_words])
		return false
	var offered_match: bool = false
	var offered_spare: bool = false
	for offer_v in view.get("offers", []) as Array:
		var offer: Dictionary = offer_v as Dictionary
		if int(offer.get("item", -1)) == match_item:
			offered_match = true
			if String(offer.get("barrel", "")) != "match":
				push_error("%s: the match barrel in the pack is offered as '%s'" % [lane, String(offer.get("barrel", ""))])
				return false
		if int(offer.get("item", -1)) == spare:
			offered_spare = true
			if String(offer.get("barrel", "")) != "":
				push_error("%s: a magazine offer carries barrel words '%s'" % [lane, String(offer.get("barrel", ""))])
				return false
	if not offered_match or not offered_spare:
		push_error("%s: the match barrel (%s) or the spare magazine (%s) is not offered at the bench" % [lane, offered_match, offered_spare])
		return false
	print("  BARREL WORDS OK the six shipped barrels say plain, match, short or long as words with no digit; a typo or a non-barrel says nothing; the bench carries a fitted barrel's words and the one in the pack, and a magazine carries none")
	return true


func _has_digit(text: String) -> bool:
	for i in text.length():
		if "0123456789".find(text[i]) >= 0:
			return true
	return false


# --- INTERNALS --------------------------------------------------------------------------------
#
# A firearm's spring, sear and extractor are parts, so every base that defaults an action is also
# defaulted these three, and each one is structural and stays fitted when it is worn through. The
# last half is what the JAM lane in check_m2_ammo.gd relies on: a part that fell off would take
# itself out of the assembly. A base with no default action (the named break-action) carries none of
# the three, and is left out on purpose: it has never had an action to wear.
func _every_firearm_is_built_with_its_internals() -> bool:
	var lane: String = "INTERNALS"
	var w: Variant = _world()
	var tree: Dictionary = ContentLoader.load_tree()
	var guns: int = 0
	for path in tree.keys():
		if not String(path).begins_with("items/"):
			continue
		var value: Variant = tree[path]
		if not value is Array:
			continue
		for e_v in value as Array:
			var e: Dictionary = e_v as Dictionary
			var defaults: Variant = e.get("defaultParts")
			if not (defaults is Dictionary and (defaults as Dictionary).has("internal")):
				continue
			var id: String = String(e.get("id", "?"))
			var host: int = _spawn(w, id)
			for slot in ["spring", "sear", "extractor"]:
				var part: int = SimAttachments.in_slot(w, host, slot)
				if part < 0:
					push_error("%s: %s spawns with no %s fitted" % [lane, id, slot])
					return false
				var spec: Variant = SimAttachments.spec_of(w, part)
				if not (spec is Dictionary and bool((spec as Dictionary).get("structural", false)) and bool((spec as Dictionary).get("staysWhenWornOut", false))):
					push_error("%s: the %s in %s is not a structural part that stays when worn out" % [lane, slot, id])
					return false
			guns += 1
	if guns == 0:
		push_error("%s: no firearm defaults an internal, so the lane asserts nothing" % lane)
		return false
	print("  INTERNALS OK %d firearms spawn with a spring, a sear and an extractor fitted, each structural and each staying fitted when worn out" % guns)
	return true
