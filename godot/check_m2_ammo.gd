extends SceneTree
# Ammunition types -- docs/10-items.md, docs/09-combat.md, and the owner's decision of 2026-09-12.
#
# A weapon's `ranged.ammo` is the round it prefers and its `ranged.caliber` is the set it will take
# at all; a round declares that caliber and, optionally, multipliers folded over the host weapon's
# profile for the one shot that spends it. The same grammar `attachment.ranged` uses, so nothing in
# the sim has to know what a slug is.
#
# The content validator is shallow -- it checks `ammo` is an object and stops -- so every claim
# about what is inside one is this gate's job, exactly as `check_m2_attach.gd` is for `attachment`.
# The two ways a round can be quietly inert are a caliber no weapon chambers and a multiplier keyed
# to a field nothing reads after the round is picked, and REACH and SCALED are those two checks.
#
# Every behavioural lane measures the *shot*, never the profile. A dictionary that says a round is
# different is a dictionary comparing itself; `check_m2_attach.gd`'s OVERRIDE lane says so in its
# own header and this file inherits the rule.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimLightModule = preload("res://sim/modules/light.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const Clock = preload("res://sim/time/clock.gd")

const PISTOL: String = "item.pistol.service"
const SHOTGUN: String = "item.shotgun.pump"
const BOW: String = "item.bow.hunting"
const NINE: String = "item.ammo.9mm"
const NINE_SUB: String = "item.ammo.9mm.sub"
const BUCK: String = "item.ammo.12g"
const SLUG: String = "item.ammo.12g.slug"
const BIRD: String = "item.ammo.12g.bird"
const RIFLE_ROUND: String = "item.ammo.rifle"
const ARROW: String = "item.ammo.arrow"
const BROADHEAD: String = "item.ammo.arrow.broadhead"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _every_round_and_every_gun_is_well_formed() and ok
	ok = _every_caliber_reaches_both_ways() and ok
	ok = _every_scalable_field_is_scaled_by_something() and ok
	ok = _the_default_round_changes_nothing() and ok
	ok = _a_non_default_round_of_the_same_caliber_fires() and ok
	ok = _a_round_of_the_wrong_caliber_is_refused() and ok
	ok = _the_multipliers_reach_the_shot() and ok
	ok = _an_unknown_multiplier_is_dropped() and ok
	ok = _a_weapon_with_no_caliber_still_fires_its_own_round() and ok
	ok = _a_conversion_moves_the_round_and_the_set_together() and ok
	ok = _what_is_recovered_is_what_was_fired() and ok
	ok = _a_worn_internal_jams_the_gun() and ok
	ok = _the_debug_spawned_round_holds_the_count_asked_for() and ok
	ok = _the_round_you_choose_is_the_round_you_fire() and ok
	ok = _the_magazine_remembers_what_you_loaded() and ok
	ok = _every_load_reads_in_words() and ok
	ok = _a_round_comes_back_as_it_went_in() and ok
	if ok:
		print("M2_AMMO_OK content reach scaled default pick refuse fold drops legacy convert recover jam debug-stack round mag word tier")
		quit(0)
	else:
		push_error("M2_AMMO_FAIL")
		quit(1)


func _world(seed_val: int = 31) -> Variant:
	var f: Dictionary = {"seed": seed_val, "tick_hz": 20, "map": {"width": 24, "height": 24, "walls": []}, "player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2}, "rng_probe": {"stream": "test", "samples": 0}}
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


# Arm the player with `weapon` and put `rounds` in their pockets. Returns the weapon entity, or -1.
#
# The weapon is equipped straight off the spawn and never stored first: `SimInventory.equip`
# refuses an item that is already inside the actor (`is_within`), and a pump shotgun is one cell by
# five where a pocket grid is four by two, so storing it would fail for a second, unrelated reason.
# Rounds do go in pockets -- they are one cell each, which is the whole point of a round.
func _armed(w: Variant, weapon_id: String, rounds: Array) -> int:
	var gun: int = _spawn(w, weapon_id)
	if not SimInventory.equip(w, w.player, gun):
		push_error("the weapon would go in neither hand")
		return -1
	for row in rounds:
		var pair: Array = row as Array
		var stack: int = SimItems.spawn_item(w, String(pair[0]), {"tier": "scavenged", "count": int(pair[1])})
		if not SimInventory.store_anywhere(w, stack, w.player):
			push_error("the rounds would not go in a pocket: %s" % String(pair[0]))
			return -1
	# Loaded the way a raider arrives, at once and from the pack: a reload would wear the weapon
	# (`WEAR_PER_RELOAD`), and DEFAULT pins a fresh gun's numbers to the decimal.
	SimRanged.load_held(w, w.player)
	return gun


# How many units of `base_id` this actor has: in the pack, and in the magazine of anything they
# hold. Since the magazine remembers its load (2026-10-28) a reload moves rounds from the first to
# the second and only a shot spends one, so "spent" is the sum going down, never the pack alone.
# Counted through `carried_items`, never through `components.query`: `_consume_ammo` despawns a
# spent stack without removing its components, and docs/23's defect list records that a query
# still returns those ids.
func _rounds_left(w: Variant, actor: int, base_id: String) -> int:
	var total: int = _in_magazines(w, actor, base_id)
	for item in SimInventory.carried_items(w, actor) as Array:
		var base: Variant = SimItems.item_base_of(w, int(item))
		if not (base is Dictionary and String((base as Dictionary).get("id", "")) == base_id):
			continue
		var stk: Variant = w.components.get_component(int(item), "stack")
		total += int((stk as Dictionary).get("count", 1)) if stk is Dictionary else 1
	return total


func _in_magazines(w: Variant, actor: int, base_id: String) -> int:
	var n: int = 0
	for held in SimInventory.equipped_items(w, actor):
		for id in SimRanged.rounds_in(w, int(held)):
			if String(id) == base_id:
				n += 1
	return n


func _in_pack(w: Variant, actor: int, base_id: String) -> int:
	return _rounds_left(w, actor, base_id) - _in_magazines(w, actor, base_id)


# Wait for the weapon to be idle, and if it is a magazine with nothing in it, pull the trigger once
# and wait out the reload that pull becomes. A gun arrives empty since the magazine remembers its
# load, so every lane below that means "fire this gun" has to load it first, the way a player would.
func _load_first(w: Variant, shooter: int) -> void:
	for i in 200:
		var rw0: Variant = w.components.get_component(shooter, "rangedWeapon")
		if rw0 is Dictionary and int((rw0 as Dictionary)["state"]) == SimRanged.FireState.Idle:
			break
		w.step()
	var rw: Variant = w.components.get_component(shooter, "rangedWeapon")
	if not (rw is Dictionary and SimRanged.is_fed(rw as Dictionary) and int((rw as Dictionary).get("mag", 0)) <= 0):
		return
	w.commands.push({"type": "fire"})
	for i in 200:
		w.step()
		var r2: Variant = w.components.get_component(shooter, "rangedWeapon")
		if r2 is Dictionary and int((r2 as Dictionary)["state"]) == SimRanged.FireState.Idle:
			break


# Fire once and report the loudest noise this shooter made, or 0.0 if nothing fired. Lifted from
# `check_m2_attach._noise_of`, comment and all: `try_begin_fire` refuses anything mid-sequence and
# the command is consumed on the tick it is pushed, so pushing at a Recover tick asks for a shot
# that never happens -- which read as "a suppressed pistol makes no noise" the first time.
func _fire_once(w: Variant, shooter: int) -> float:
	_load_first(w, shooter)
	var loudest: float = 0.0
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


# Fire once at a body standing `metres` away and report the damage that landed, or 0.0.
func _damage_at(w: Variant, shooter: int, metres: float) -> float:
	var target: int = w.entities.spawn()
	w.components.set_component(target, "position", {"x": 8.5 + metres, "y": 12.5})
	SimHealth.make_survivor_body(w, target)
	_load_first(w, shooter)
	var worst: float = 0.0
	for i in 40:
		var rw0: Variant = w.components.get_component(shooter, "rangedWeapon")
		if rw0 is Dictionary and int((rw0 as Dictionary)["state"]) == SimRanged.FireState.Idle:
			break
		w.step()
	w.commands.push({"type": "fire"})
	for i in 60:
		w.step()
		for e in w.events.drained:
			var d: Dictionary = e as Dictionary
			if String(d.get("type", "")) == "attack.connected" and int(d.get("attacker", -1)) == shooter and int(d.get("target", -1)) == target:
				worst = maxf(worst, float(d.get("damage", 0)))
		if worst > 0.0:
			break
	return worst


func _all_items() -> Array:
	var out: Array = []
	var tree: Dictionary = ContentLoader.load_tree()
	for path in tree.keys():
		if not String(path).begins_with("items/"):
			continue
		var value: Variant = tree[path]
		if not value is Array:
			continue
		for entry in value as Array:
			if entry is Dictionary:
				out.append(entry as Dictionary)
	return out


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


# --- CONTENT ------------------------------------------------------------------------------------
#
# The shallow-validator half: every shape claim about `ammo` and about `ranged.caliber` that the
# schema states and cannot enforce one level down.
func _every_round_and_every_gun_is_well_formed() -> bool:
	var lane: String = "CONTENT"
	var items: Array = _all_items()
	if items.size() < 100:
		push_error("%s: only %d item bases read -- the content walk is not reading items/" % [lane, items.size()])
		return false
	var droppable: Dictionary = _loot_ids()
	if droppable.is_empty():
		push_error("%s: no loot tables loaded, so the findability half has nothing to judge" % lane)
		return false
	var guns: int = 0
	var rounds: int = 0
	for entry in items:
		var e: Dictionary = entry as Dictionary
		var id: String = String(e.get("id", ""))
		var ranged: Variant = e.get("ranged")
		if ranged is Dictionary:
			guns += 1
			if String((ranged as Dictionary).get("caliber", "")) == "":
				push_error("%s: %s is a ranged weapon with no caliber -- nothing can say what it takes" % [lane, id])
				return false
		var spec: Variant = e.get("ammo")
		if not spec is Dictionary:
			continue
		rounds += 1
		if String((spec as Dictionary).get("caliber", "")) == "":
			push_error("%s: %s declares an ammo block with no caliber" % [lane, id])
			return false
		for fault in _table_faults((spec as Dictionary).get("ranged")):
			push_error("%s: %s %s" % [lane, id, fault])
			return false
		if not droppable.has(id):
			push_error("%s: %s is in no loot table -- a round nobody can find" % [lane, id])
			return false
	if guns == 0 or rounds == 0:
		push_error("%s: %d guns and %d rounds -- the scan has nothing to judge" % [lane, guns, rounds])
		return false

	# Prove the multiplier predicate can fail before the walk above is trusted, on a fabricated
	# table rather than on shipped content -- the shape check_m2_attach's SCALES lane uses.
	if _table_faults({"damage": 1.5}).size() != 0:
		push_error("%s: the multiplier check refused a legitimate damage multiplier" % lane)
		return false
	if _table_faults({"magSize": 2.0}).size() == 0:
		push_error("%s: the multiplier check passed `magSize`, which is read before a round is picked" % lane)
		return false
	if _table_faults({"dammage": 1.5}).size() == 0:
		push_error("%s: the multiplier check passed a misspelt field, which is a round that does nothing" % lane)
		return false
	if _table_faults({"damage": 0.0}).size() == 0:
		push_error("%s: the multiplier check passed a zero multiplier" % lane)
		return false

	print("  CONTENT OK %d guns all chambered, %d rounds all well formed and all findable" % [guns, rounds])
	return true


# Everything wrong with one round's multiplier table, as sentences. Empty is fine -- a round that
# names only a caliber is the plain load, and its fold is the identity.
func _table_faults(table: Variant) -> Array:
	var out: Array = []
	if table == null:
		return out
	if not table is Dictionary:
		out.append("declares an ammo.ranged that is not a table")
		return out
	for field_v in (table as Dictionary).keys():
		var field: String = String(field_v)
		if not SimRanged.AMMO_SCALABLE.has(field):
			out.append("scales ammo.ranged.%s, which AMMO_SCALABLE does not name -- nothing would read it" % field)
			continue
		if float((table as Dictionary)[field_v]) <= 0.0:
			out.append("scales %s by a number at or below zero" % field)
	return out


# --- REACH --------------------------------------------------------------------------------------
#
# The dead-socket question, in both directions, which is what `check_m2_attach`'s CONTENT and HOSTS
# lanes are to each other. A gun chambered for a caliber no round declares cannot be loaded; a
# round of a caliber no gun chambers cannot be fired.
#
# The gun side is deliberately the union of two declarations. `45` is declared by **no weapon** --
# it exists only as the target of `item.part.barrel.45` and `item.part.magazine.45` -- so a lane
# reading `ranged.caliber` alone goes red on shipped content the day it lands. That is the same
# defect `SimDirector._ammo_ids` records having paid for twice, one level down.
func _every_caliber_reaches_both_ways() -> bool:
	var lane: String = "REACH"
	var items: Array = _all_items()
	var chambered: Dictionary = _chambered_calibers(items)
	var loaded: Dictionary = _round_calibers(items)
	if chambered.is_empty() or loaded.is_empty():
		push_error("%s: %d chambered and %d loaded calibers -- nothing to judge" % [lane, chambered.size(), loaded.size()])
		return false
	for cal_v in chambered.keys():
		if not loaded.has(String(cal_v)):
			push_error("%s: %s is chambered by %s and declared by no shipped round -- a gun nobody can load" % [lane, String(cal_v), String(chambered[cal_v])])
			return false
	for cal_v in loaded.keys():
		if not chambered.has(String(cal_v)):
			push_error("%s: %s is declared by %s and chambered by nothing -- a round nobody can fire" % [lane, String(cal_v), String(loaded[cal_v])])
			return false

	# The conversion half, named rather than assumed: at least one caliber must be reachable only
	# through an override, or the union above is doing nothing and the lane would stay green if it
	# were quietly narrowed back to weapons.
	var weapons_only: Dictionary = {}
	for entry in items:
		var r: Variant = (entry as Dictionary).get("ranged")
		if r is Dictionary and String((r as Dictionary).get("caliber", "")) != "":
			weapons_only[String((r as Dictionary)["caliber"])] = true
	var conversion_only: Array = []
	for cal_v in chambered.keys():
		if not weapons_only.has(String(cal_v)):
			conversion_only.append(String(cal_v))
	if conversion_only.is_empty():
		push_error("%s: no caliber is reachable only through a conversion, so the override half of this lane is judged by nothing" % lane)
		return false

	# Both predicates proved able to fail, on fabricated content, before either is trusted.
	var fake_gun: Array = items.duplicate()
	fake_gun.append({"id": "item.gate.gun", "ranged": {"caliber": "gate", "weight": 1.0}})
	if _chambered_calibers(fake_gun).has("gate") == false:
		push_error("%s: the gun-side scan did not see a fabricated caliber" % lane)
		return false
	if _round_calibers(fake_gun).has("gate"):
		push_error("%s: the round-side scan claimed a caliber no round declares" % lane)
		return false
	var fake_round: Array = items.duplicate()
	fake_round.append({"id": "item.gate.round", "ammo": {"caliber": "gate"}})
	if _round_calibers(fake_round).has("gate") == false:
		push_error("%s: the round-side scan did not see a fabricated round" % lane)
		return false

	print("  REACH OK %d calibers, every one chambered and loaded, %d of them reachable only through a conversion (%s)" % [chambered.size(), conversion_only.size(), ", ".join(PackedStringArray(conversion_only))])
	return true


# Calibers something can be made to fire: declared by a weapon, or produced by a conversion part.
# A plain Array through a local, never a PackedStringArray reached through a Dictionary -- that is
# the value-copy trap, and this is the shape that keeps it impossible.
func _chambered_calibers(items: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry in items:
		var e: Dictionary = entry as Dictionary
		var id: String = String(e.get("id", ""))
		var r: Variant = e.get("ranged")
		if r is Dictionary and String((r as Dictionary).get("caliber", "")) != "":
			out[String((r as Dictionary)["caliber"])] = id
		var spec: Variant = e.get("attachment")
		if not spec is Dictionary:
			continue
		var over: Variant = (spec as Dictionary).get("overrides")
		if not over is Dictionary:
			continue
		var ranged: Variant = (over as Dictionary).get("ranged")
		if ranged is Dictionary and String((ranged as Dictionary).get("caliber", "")) != "":
			out[String((ranged as Dictionary)["caliber"])] = id
	return out


func _round_calibers(items: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry in items:
		var spec: Variant = (entry as Dictionary).get("ammo")
		if spec is Dictionary and String((spec as Dictionary).get("caliber", "")) != "":
			out[String((spec as Dictionary)["caliber"])] = String((entry as Dictionary).get("id", ""))
	return out


# --- SCALED -------------------------------------------------------------------------------------
#
# The mirror of check_m2_attach's SCALES: a whitelist entry nothing names is the fold standing
# ready and nothing ever asking, which is the dead-socket shape one level out.
func _every_scalable_field_is_scaled_by_something() -> bool:
	var lane: String = "SCALED"
	var items: Array = _all_items()
	var seen: Dictionary = _scaled_fields(items)
	if seen.is_empty():
		push_error("%s: no shipped round scales anything, so AMMO_SCALABLE is read by no content" % lane)
		return false
	for field_v in SimRanged.AMMO_SCALABLE:
		if not seen.has(String(field_v)):
			push_error("%s: AMMO_SCALABLE names %s and no shipped round scales it" % [lane, String(field_v)])
			return false

	# The true negative, in the shape SCALES uses: a fabricated field must come back unscaled while
	# a real one does not, or this lane passes by always answering yes.
	if _scaled_fields(items).has("gateField"):
		push_error("%s: the scan reported a field no round declares" % lane)
		return false

	print("  SCALED OK all %d fields in SimRanged.AMMO_SCALABLE are scaled by shipped content (%d rounds read)" % [SimRanged.AMMO_SCALABLE.size(), _round_calibers(items).size()])
	return true


func _scaled_fields(items: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry in items:
		var spec: Variant = (entry as Dictionary).get("ammo")
		if not spec is Dictionary:
			continue
		var table: Variant = (spec as Dictionary).get("ranged")
		if not table is Dictionary:
			continue
		for field_v in (table as Dictionary).keys():
			out[String(field_v)] = true
	return out


# --- DEFAULT ------------------------------------------------------------------------------------
#
# The parity claim the whole slice rests on: a survivor carrying only the round their weapon
# prefers gets exactly the shot they got before calibers existed. Pinned numbers rather than "it
# fired", because "unchanged" is only a claim if the number is written down.
func _the_default_round_changes_nothing() -> bool:
	var lane: String = "DEFAULT"
	var w: Variant = _world()
	if _armed(w, PISTOL, [[NINE, 20]]) < 0:
		return false
	var noise: float = _fire_once(w, w.player)
	if not is_equal_approx(noise, 180.0):
		push_error("%s: a service pistol on its own round made %.4f, not the 180 it has always made" % [lane, noise])
		return false
	var w2: Variant = _world()
	if _armed(w2, PISTOL, [[NINE, 20]]) < 0:
		return false
	var dmg: float = _damage_at(w2, w2.player, 4.0)
	if not is_equal_approx(dmg, 18.0):
		push_error("%s: a service pistol on its own round did %.4f, not the 18 it has always done" % [lane, dmg])
		return false

	# The negative: the same fixture with a round that scales must not come back 180, or this lane
	# is measuring something that cannot move and would pass for a fold that never ran.
	var w3: Variant = _world()
	if _armed(w3, PISTOL, [[NINE_SUB, 20]]) < 0:
		return false
	var quiet: float = _fire_once(w3, w3.player)
	if is_equal_approx(quiet, 180.0) or quiet <= 0.0:
		push_error("%s: a subsonic round came back at %.4f -- the fold did not run" % [lane, quiet])
		return false

	print("  DEFAULT OK the preferred round is the old numbers exactly: noise 180.0, damage 18.0; a subsonic round is %.1f" % quiet)
	return true


# --- PICK ---------------------------------------------------------------------------------------
#
# The assertion that something *reads* the caliber, which is the difference between this slice and
# eleven dead sockets. A shotgun with no buckshot at all fires the slugs in the same pocket.
func _a_non_default_round_of_the_same_caliber_fires() -> bool:
	var lane: String = "PICK"
	var w: Variant = _world()
	if _armed(w, SHOTGUN, [[SLUG, 8]]) < 0:
		return false
	var noise: float = _fire_once(w, w.player)
	if noise <= 0.0:
		push_error("%s: a pump shotgun carrying only slugs did not fire" % lane)
		return false
	if _rounds_left(w, w.player, SLUG) != 7:
		push_error("%s: it fired, and the slug stack still stands at %d of eight" % [lane, _rounds_left(w, w.player, SLUG)])
		return false

	# Preference, which is the half that keeps every shipped weapon byte-identical: carrying both,
	# the round the weapon names goes first and the slug is untouched.
	var w2: Variant = _world()
	if _armed(w2, SHOTGUN, [[BUCK, 5], [SLUG, 5]]) < 0:
		return false
	if _fire_once(w2, w2.player) <= 0.0:
		push_error("%s: a shotgun carrying both rounds did not fire" % lane)
		return false
	if _rounds_left(w2, w2.player, BUCK) != 4 or _rounds_left(w2, w2.player, SLUG) != 5:
		push_error("%s: with both carried it spent %d buckshot and %d slugs -- the preferred round did not go first" % [lane, 5 - _rounds_left(w2, w2.player, BUCK), 5 - _rounds_left(w2, w2.player, SLUG)])
		return false

	# And it fires the compatible one rather than merely firing: a wrong-caliber round in the same
	# pocket must still be there afterwards, or "it fired" does not mean "it fired the right thing".
	var w3: Variant = _world()
	if _armed(w3, SHOTGUN, [[SLUG, 4], [RIFLE_ROUND, 4]]) < 0:
		return false
	if _fire_once(w3, w3.player) <= 0.0:
		push_error("%s: a shotgun carrying slugs and rifle rounds did not fire" % lane)
		return false
	if _rounds_left(w3, w3.player, SLUG) != 3 or _rounds_left(w3, w3.player, RIFLE_ROUND) != 4:
		push_error("%s: it reached past the slugs for a rifle round" % lane)
		return false

	print("  PICK OK a shotgun with only slugs fires one; with both it spends the buckshot first; and it never touches a rifle round")
	return true


# --- REFUSE -------------------------------------------------------------------------------------
#
# The other half of PICK, and the true negative that makes it mean something. `check_m2_attach`'s
# OVERRIDE lane is the model: a gun that refuses is only a claim if the same fixture with the right
# round fires, or "it did not fire" is proving the fixture was broken.
func _a_round_of_the_wrong_caliber_is_refused() -> bool:
	var lane: String = "REFUSE"
	var w: Variant = _world()
	if _armed(w, SHOTGUN, [[RIFLE_ROUND, 8]]) < 0:
		return false
	var noise: float = _fire_once(w, w.player)
	if noise > 0.0:
		push_error("%s: a pump shotgun fired a rifle round at %.4f" % [lane, noise])
		return false
	if _rounds_left(w, w.player, RIFLE_ROUND) != 8:
		push_error("%s: it did not fire and the rifle rounds went somewhere anyway" % lane)
		return false
	var w2: Variant = _world()
	if _armed(w2, SHOTGUN, [[RIFLE_ROUND, 8], [BIRD, 2]]) < 0:
		return false
	if _fire_once(w2, w2.player) <= 0.0:
		push_error("%s: the same shotgun with one shell it can take still did not fire, so the refusal above proves nothing" % lane)
		return false

	print("  REFUSE OK a shotgun holding only rifle rounds never fires and spends none; one birdshot shell in the same pocket and it does")
	return true


# --- FOLD ---------------------------------------------------------------------------------------
#
# One assertion per field, each measuring the shot rather than the profile. The two fields behind
# an RNG draw -- `flash` and `recoverable` -- are asserted through the fold itself, which is the
# honest form: a counted comparison over a hundred shots would be a slower way of saying the same
# thing with a seed dependency attached.
func _the_multipliers_reach_the_shot() -> bool:
	var lane: String = "FOLD"

	# damage, at point blank, against the same weapon on its plain round.
	#
	# The two worlds are the same seed and the same fixture, and choosing a round draws no
	# randomness, so both take the identical RNG sequence and both resolve the same body part --
	# which is why an exact ratio is safe here rather than lucky. `_damage_at` fires once and the
	# head multiplier is x3, so a lane that let the two worlds diverge would be comparing a torso
	# with a head and reporting a multiplier of four and a half.
	var plain: Variant = _world()
	if _armed(plain, SHOTGUN, [[BUCK, 4]]) < 0:
		return false
	var buck_dmg: float = _damage_at(plain, plain.player, 3.0)
	var slugged: Variant = _world()
	if _armed(slugged, SHOTGUN, [[SLUG, 4]]) < 0:
		return false
	var slug_dmg: float = _damage_at(slugged, slugged.player, 3.0)
	if buck_dmg <= 0.0 or slug_dmg <= 0.0:
		push_error("%s: nothing connected (buckshot %.4f, slug %.4f)" % [lane, buck_dmg, slug_dmg])
		return false
	if not is_equal_approx(slug_dmg, buck_dmg * 1.5):
		push_error("%s: a slug did %.4f against buckshot's %.4f -- expected exactly the declared 1.5x, unsoftened by condition" % [lane, slug_dmg, buck_dmg])
		return false

	# noise, on the quiet round.
	var loud: Variant = _world()
	if _armed(loud, PISTOL, [[NINE, 4]]) < 0:
		return false
	var loud_n: float = _fire_once(loud, loud.player)
	var quiet: Variant = _world()
	if _armed(quiet, PISTOL, [[NINE_SUB, 4]]) < 0:
		return false
	var quiet_n: float = _fire_once(quiet, quiet.player)
	if not is_equal_approx(quiet_n, loud_n * 0.45):
		push_error("%s: a subsonic round made %.4f against %.4f -- expected the declared 0.45x" % [lane, quiet_n, loud_n])
		return false

	# rangeMetres, which is legible only past the weapon's own reach: a sawn-off shotgun reaches
	# eight metres and a slug carries it to fourteen, so a body at eleven is hit by one and not
	# by the other. The clearest possible form of "the round changed the shot".
	var short: Variant = _world()
	if _armed(short, "item.shotgun.sawnoff", [[BUCK, 4]]) < 0:
		return false
	var near_miss: float = _damage_at(short, short.player, 11.0)
	var long: Variant = _world()
	if _armed(long, "item.shotgun.sawnoff", [[SLUG, 4]]) < 0:
		return false
	var carried: float = _damage_at(long, long.player, 11.0)
	if near_miss > 0.0:
		push_error("%s: buckshot reached a body at eleven metres out of an eight-metre barrel" % lane)
		return false
	if carried <= 0.0:
		push_error("%s: a slug did not reach a body at eleven metres, so rangeMetres was not folded" % lane)
		return false

	# cone, flash and recoverable, through the fold. `ammo_scale` is the one place a round's table
	# becomes numbers, so asserting it is asserting what every read site is handed.
	var probe: Variant = _world()
	var bird_scale: Dictionary = SimRanged.ammo_scale(probe, BIRD)
	if not is_equal_approx(float(bird_scale.get("cone", 1.0)), 1.7):
		push_error("%s: birdshot's cone multiplier came back %.4f" % [lane, float(bird_scale.get("cone", 1.0))])
		return false
	var sub_scale: Dictionary = SimRanged.ammo_scale(probe, NINE_SUB)
	if not is_equal_approx(float(sub_scale.get("flash", 1.0)), 0.5):
		push_error("%s: the subsonic round's flash multiplier came back %.4f" % [lane, float(sub_scale.get("flash", 1.0))])
		return false
	var head_scale: Dictionary = SimRanged.ammo_scale(probe, BROADHEAD)
	if not is_equal_approx(float(head_scale.get("recoverable", 1.0)), 0.5):
		push_error("%s: the broadhead's recoverable multiplier came back %.4f" % [lane, float(head_scale.get("recoverable", 1.0))])
		return false
	# A plain round folds to nothing at all, which is what makes DEFAULT's parity structural.
	if not SimRanged.ammo_scale(probe, BUCK).is_empty():
		push_error("%s: buckshot, which declares no table, folded something" % lane)
		return false

	print("  FOLD OK slug %.1f vs buckshot %.1f damage, subsonic %.1f vs %.1f noise, a slug carries to eleven metres where buckshot does not, and cone/flash/recoverable fold as declared" % [slug_dmg, buck_dmg, quiet_n, loud_n])
	return true


# --- DROPS --------------------------------------------------------------------------------------
#
# The whitelist doing its job. A misspelt field must behave like a round that says nothing, and
# `magSize`, `reloadTicks` and `handling` are read *before* a round is chosen, so a round scaling
# one of them would be a multiplier authored in content that nothing could ever read.
func _an_unknown_multiplier_is_dropped() -> bool:
	var lane: String = "DROPS"
	for field in ["magSize", "reloadTicks", "handling", "weight", "jams", "gateField", "dammage"]:
		if SimRanged.AMMO_SCALABLE.has(field):
			push_error("%s: AMMO_SCALABLE names %s, which is read before the round is picked or is not a number" % [lane, field])
			return false
	for field in ["damage", "noise", "flash", "rangeMetres", "cone", "recoverable"]:
		if not SimRanged.AMMO_SCALABLE.has(field):
			push_error("%s: AMMO_SCALABLE does not name %s, which _fire_shot reads after the round is spent" % [lane, field])
			return false
	print("  DROPS OK %d fields whitelisted, every one read after the round is spent; magSize, reloadTicks and handling refused because they are read before it" % SimRanged.AMMO_SCALABLE.size())
	return true


# --- LEGACY -------------------------------------------------------------------------------------
#
# The save-compatibility path, gated rather than assumed. `rangedWeapon` is an ordinary component
# saved wholesale and never rebuilt on load, so a save written before this slice restores a weapon
# with no `caliber` at all. That weapon must behave exactly as it did when it was saved: it fires
# the round it named and refuses everything else. No SAVE_VERSION bump is honest only because this
# holds, and a branch nothing asserts is the twelfth dead socket by another name.
func _a_weapon_with_no_caliber_still_fires_its_own_round() -> bool:
	var lane: String = "LEGACY"
	var w: Variant = _world()
	if _armed(w, SHOTGUN, [[BUCK, 4]]) < 0:
		return false
	# One step before reading it: `make_ranged_armed` runs off `item.equipped`, and `events.publish`
	# only queues -- handlers run at `drain()`, at the *end* of `world.step()`. Reading the
	# component in the same breath as equipping the weapon finds nothing there.
	w.step()
	var rw: Variant = w.components.get_component(w.player, "rangedWeapon")
	if not rw is Dictionary:
		push_error("%s: the weapon was equipped and no rangedWeapon arrived" % lane)
		return false
	(rw as Dictionary).erase("caliber")
	if _fire_once(w, w.player) <= 0.0:
		push_error("%s: a weapon restored with no caliber would not fire the round it names" % lane)
		return false
	if _rounds_left(w, w.player, BUCK) != 3:
		push_error("%s: it fired and spent no buckshot" % lane)
		return false

	var w2: Variant = _world()
	if _armed(w2, SHOTGUN, [[SLUG, 4]]) < 0:
		return false
	w2.step()
	var rw2: Variant = w2.components.get_component(w2.player, "rangedWeapon")
	if not rw2 is Dictionary:
		push_error("%s: the second fixture's weapon was equipped and no rangedWeapon arrived" % lane)
		return false
	(rw2 as Dictionary).erase("caliber")
	if _fire_once(w2, w2.player) > 0.0:
		push_error("%s: with no caliber it accepted a slug, so it has not fallen back to matching by id" % lane)
		return false

	print("  LEGACY OK a weapon with its caliber erased fires the round it names and refuses a same-caliber one, which is what it did before this slice")
	return true


# --- CONVERT ------------------------------------------------------------------------------------
#
# `ammo` and `caliber` are two overridable fields and a conversion part must move both. A part that
# moved only the round would build a gun that prefers something it cannot chamber -- the pick would
# fall through to the old caliber every time, so the conversion would appear to work and quietly
# fire the wrong ammunition. Nothing in `attachments.gd` can see the sibling key, which is why the
# claim lives here.
func _a_conversion_moves_the_round_and_the_set_together() -> bool:
	var lane: String = "CONVERT"
	var pairs: int = 0
	for entry in _all_items():
		var spec: Variant = (entry as Dictionary).get("attachment")
		if not spec is Dictionary:
			continue
		var over: Variant = (spec as Dictionary).get("overrides")
		if not over is Dictionary:
			continue
		var ranged: Variant = (over as Dictionary).get("ranged")
		if not ranged is Dictionary:
			continue
		var has_ammo: bool = String((ranged as Dictionary).get("ammo", "")) != ""
		var has_cal: bool = String((ranged as Dictionary).get("caliber", "")) != ""
		if has_ammo != has_cal:
			push_error("%s: %s overrides %s and not the other -- a gun that prefers a round it cannot chamber" % [lane, String((entry as Dictionary).get("id", "")), "the round" if has_ammo else "the caliber"])
			return false
		if not has_ammo:
			continue
		pairs += 1
		# And the two must agree: the round it now prefers must be of the caliber it now takes.
		var round_id: String = String((ranged as Dictionary)["ammo"])
		var cal: String = String((ranged as Dictionary)["caliber"])
		var found: String = ""
		for other in _all_items():
			if String((other as Dictionary).get("id", "")) != round_id:
				continue
			var ablock: Variant = (other as Dictionary).get("ammo")
			found = String((ablock as Dictionary).get("caliber", "")) if ablock is Dictionary else ""
		if found != cal:
			push_error("%s: %s converts to %s in caliber %s, but that round is caliber \"%s\"" % [lane, String((entry as Dictionary).get("id", "")), round_id, cal, found])
			return false
	if pairs == 0:
		push_error("%s: no shipped part converts a caliber, so this lane has nothing to judge" % lane)
		return false

	# And behaviourally: a converted pistol takes the converted caliber's rounds, including ones
	# the part never named. This is the reader test -- the paragraph above is a dictionary check.
	var w: Variant = _world()
	var gun: int = _armed(w, PISTOL, [["item.ammo.22", 8]])
	if gun < 0:
		return false
	if _fire_once(w, w.player) > 0.0:
		push_error("%s: an unconverted service pistol fired a rimfire round" % lane)
		return false
	# A pistol arrives assembled and a slot holds one thing, so the standard kit comes out before
	# the conversion goes in -- which is also what a person at a bench would have to do.
	for slot in ["barrel", "magazine"]:
		var fitted: int = SimAttachments.in_slot(w, gun, slot)
		if fitted >= 0:
			SimAttachments.detach(w, fitted)
	var barrel: int = _spawn(w, "item.part.barrel.rimfire")
	var magazine: int = _spawn(w, "item.part.magazine.rimfire")
	if not SimAttachments.attach(w, gun, barrel, "barrel") or not SimAttachments.attach(w, gun, magazine, "magazine"):
		push_error("%s: the rimfire kit would not fit" % lane)
		return false
	SimItems.refresh_armed(w, w.player)
	if _fire_once(w, w.player) <= 0.0:
		push_error("%s: a converted pistol would not fire the caliber it was converted to" % lane)
		return false

	print("  CONVERT OK %d conversion parts each move the round and the set together and agree about the caliber, and a converted pistol fires what it was converted to" % pairs)
	return true


# --- RECOVER ------------------------------------------------------------------------------------
#
# What lands in the grass is what was fired. This read the weapon's *preferred* round until the
# caliber landed -- the same answer while a bow had exactly one arrow, and the wrong one the moment
# a broadhead and a target arrow share one: firing your last broadhead would have grown a target
# arrow, with no error and no wrong number.
func _what_is_recovered_is_what_was_fired() -> bool:
	var lane: String = "RECOVER"
	var w: Variant = _world(7717)
	if _armed(w, BOW, [[BROADHEAD, 20]]) < 0:
		return false
	var dropped: Dictionary = {}
	for shot in 20:
		_fire_once(w, w.player)
		for e in w.components.query(["position", "itemBase"]):
			var base: Variant = SimItems.item_base_of(w, int(e))
			if not base is Dictionary:
				continue
			var id: String = String((base as Dictionary).get("id", ""))
			if id.begins_with("item.ammo."):
				dropped[id] = true
		if not dropped.is_empty():
			break
	# The wrong arrow is checked *first*, and deliberately. Under the defect this lane exists to
	# catch, a plain arrow is what lands and no broadhead ever does -- so asking "was a broadhead
	# recovered" first reports "nothing was recovered, the lane has nothing to judge" and blames
	# the fixture for a bug in the code under test, which is the worst thing a gate can do.
	if dropped.has(ARROW):
		push_error("%s: a bow firing broadheads dropped a plain arrow -- recovery is naming the round the bow prefers, not the one it fired" % lane)
		return false
	if not dropped.has(BROADHEAD):
		push_error("%s: twenty broadheads fired and nothing at all was recovered -- the lane has nothing to judge" % lane)
		return false

	print("  RECOVER OK a bow shooting broadheads recovers broadheads and never grows a plain arrow")
	return true


# --- DEBUG-STACK ------------------------------------------------------------------------------
#
# The F8 panel and a hand-pushed `debug.spawn` hand a round over as a stack. Before the item arm
# read a count, every dev round arrived as a stack of one, and a stack of one is despawned on the
# shot that spends it: a tester with one round on hand fired once and had nothing left to reload
# with. The lane asks what the spawned stack actually holds. Asking for five must give five, and
# asking for nothing must still give one, so the default is pinned rather than assumed.

const DEBUG_SEED: int = 20260805
const DEBUG_TILES: int = 64


func _the_debug_spawned_round_holds_the_count_asked_for() -> bool:
	var round_id: String = "item.ammo.9mm"
	var asked: int = _debug_spawned_stack(round_id, {"count": 5})
	var default_stack: int = _debug_spawned_stack(round_id, {})
	if asked < 0 or default_stack < 0:
		push_error("DEBUG-STACK: the dev spawn of '%s' made no item at all" % round_id)
		return false
	if asked != 5:
		push_error("DEBUG-STACK: a dev spawn asking for 5 rounds arrived with %d -- the count on the command is not reaching spawn_item" % asked)
		return false
	if default_stack != 1:
		push_error("DEBUG-STACK: a dev spawn with no count arrived with %d, not the default of 1" % default_stack)
		return false
	print("DEBUG-STACK OK a dev spawn of 5 rounds holds %d, and with no count holds %d" % [asked, default_stack])
	return true


## Pushes one `debug.spawn` item command carrying `extra` and returns the stack the new item holds,
## or -1 when the command made no item of `round_id`.
func _debug_spawned_stack(round_id: String, extra: Dictionary) -> int:
	var w: Variant = SimBoot.playable(DEBUG_SEED, DEBUG_TILES)["world"]
	var before: Array[int] = []
	for e in w.components.query(["itemBase"]):
		before.append(int(e))
	var pos: Variant = w.components.get_component(int(w.player), "position")
	var cmd: Dictionary = {"type": "debug.spawn", "kind": "item", "id": round_id, "x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"])}
	cmd.merge(extra)
	w.commands.push(cmd)
	w.step()
	for e in w.components.query(["itemBase"]):
		if before.has(int(e)):
			continue
		var base: Variant = w.components.get_component(int(e), "itemBase")
		if not base is Dictionary or String((base as Dictionary).get("baseId", "")) != round_id:
			continue
		var stack: Variant = w.components.get_component(int(e), "stack")
		if stack is Dictionary:
			return int((stack as Dictionary).get("count", 1))
		return 1
	return -1


# JAM. A jam is read off the worst internal, so a worn sear jams a pistol that its own receiver
# does not explain. Three things to prove, each against the same pistol: a sound gun never jams
# and draws nothing; a worn sear jams at its band's rate and the inspect view says the band in
# words; a sear worn through stays fitted (a part that fell off would take itself out of the
# assembly and leave the gun jamming less for losing it), reads "broken", and blocks the weapon
# as `broken:sear` -- refused before a pull, named on the HUD, and no envelope for npc_combat,
# the way a gun with no action is. Then the same on the revolver, the one base whose content says
# it never jams: a worn-through extractor stops it all the same, so `jams: false` is not a way
# round a broken part.
#
# The roll is SimRanged._jammed, the function a trigger pull calls, fed a seeded stand-in for the
# stream. A real trigger pull is one draw of this function, and four thousand draws are what makes
# a one-in-eight chance measurable without firing four thousand rounds.
class SeededRoll:
	extends RefCounted
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	func _init(seed_val: int) -> void:
		rng.seed = seed_val

	func float_range(lo: float, hi: float) -> float:
		return rng.randf_range(lo, hi)


func _jams_in(w: Variant, gun: int, draws: int) -> int:
	var profile: Dictionary = SimItems.ranged_profile_of(w, gun) as Dictionary
	var roll: SeededRoll = SeededRoll.new(7)
	var jams: int = 0
	for i in draws:
		if SimRanged._jammed(w, profile, roll):
			jams += 1
	return jams


func _a_worn_internal_jams_the_gun() -> bool:
	var lane: String = "JAM"
	var w: Variant = _world()
	var gun: int = _armed(w, "item.pistol.service", [])
	if gun < 0:
		return false
	# One step so `make_ranged_armed` has run and the player holds a live `rangedWeapon` for the
	# refusal below to land on (the LEGACY lane's note on `item.equipped`).
	w.step()
	var sear: int = SimAttachments.in_slot(w, gun, "sear")
	if sear < 0:
		push_error("%s: a shipped pistol spawned with no sear fitted, so there is nothing to wear" % lane)
		return false
	var sear_cond: Dictionary = w.components.get_component(sear, "condition") as Dictionary

	# Sound: the table's 0.0, and not one draw of the stand-in is a jam.
	SimItems.refresh_armed(w, gun)
	var sound_chance: float = SimItems.jam_chance(w, gun)
	if sound_chance != 0.0 or _jams_in(w, gun, 4000) != 0:
		push_error("%s: a sound pistol has jam chance %.3f and jammed on a 4000-pull sample" % [lane, sound_chance])
		return false

	# Worn to "failing" (0.2 up to 0.5): the table's 0.12, and the inspect view says "failing" for
	# the pistol, which reads its own condition as "sound" unless the internals count.
	sear_cond["current"] = 0.35
	SimItems.refresh_armed(w, gun)
	var worn_chance: float = SimItems.jam_chance(w, gun)
	var band: String = String(SimInventory.inspect_view(w, w.player, gun).get("condition", ""))
	if not is_equal_approx(worn_chance, float(SimItems.JAM_CHANCE_BY_BAND["failing"])):
		push_error("%s: a sear at 0.35 gives jam chance %.3f, not the failing band's %.2f" % [lane, worn_chance, float(SimItems.JAM_CHANCE_BY_BAND["failing"])])
		return false
	if band != "failing":
		push_error("%s: the inspect view says the pistol is '%s' with a failing sear in it -- the screen would call a jamming gun sound" % [lane, band])
		return false
	var jams: int = _jams_in(w, gun, 4000)
	var rate: float = float(jams) / 4000.0
	if rate < 0.10 or rate > 0.14:
		push_error("%s: a failing sear jammed %d of 4000 pulls (%.3f), not near 0.12" % [lane, jams, rate])
		return false

	# TN for the block below: a failing sear is a gun that still fires. It has an envelope and no
	# refusal, or the refusal that follows proves nothing.
	if not SimRanged.can_fire(w, w.player) or SimNpcCombat._ranged_range(w, w.player) <= 0.0:
		push_error("%s: a pistol with a failing sear is refused ('%s') or has no envelope, so the broken case below would not be the sear's doing" % [lane, SimRanged.refusal_of(w, w.player)])
		return false

	# Worn through: the sear stays where it is, reads "broken", the table reads 1.0 so it stays
	# total, and the weapon is refused as broken:sear -- before a pull, in a sentence that names the
	# sear, and with no envelope for an NPC to walk into.
	sear_cond["current"] = 0.001
	SimAttachments.wear_parts(w, gun, "shot")
	SimItems.refresh_armed(w, gun)
	var dead_chance: float = SimItems.jam_chance(w, gun)
	if SimAttachments.in_slot(w, gun, "sear") != sear:
		push_error("%s: a sear worn through came off the gun -- a part that falls off makes the gun jam less" % lane)
		return false
	if dead_chance != 1.0 or String(SimInventory.inspect_view(w, w.player, gun).get("condition", "")) != "broken":
		push_error("%s: a worn-through sear gives jam chance %.3f, not 1.0" % [lane, dead_chance])
		return false
	if not _refused_as(w, gun, "broken:sear", "sear", lane):
		return false

	# The revolver never jams by its content (`jams: false`), and a worn-through extractor stops it
	# anyway: a stoppage is not the only way a dead part shows, and a gun firing for nothing would
	# be the silent dud this lane exists to refuse.
	var w2: Variant = _world()
	var revolver: int = _armed(w2, "item.revolver.snub", [])
	if revolver < 0:
		return false
	w2.step()
	var extractor: int = SimAttachments.in_slot(w2, revolver, "extractor")
	if extractor < 0:
		push_error("%s: the revolver spawned with no extractor fitted" % lane)
		return false
	SimItems.refresh_armed(w2, revolver)
	if not SimRanged.can_fire(w2, w2.player) or SimItems.jam_chance(w2, revolver) != 0.0:
		push_error("%s: a sound revolver is refused ('%s') or has a jam chance" % [lane, SimRanged.refusal_of(w2, w2.player)])
		return false
	(w2.components.get_component(extractor, "condition") as Dictionary)["current"] = 0.001
	SimAttachments.wear_parts(w2, revolver, "shot")
	SimItems.refresh_armed(w2, revolver)
	if SimAttachments.in_slot(w2, revolver, "extractor") != extractor:
		push_error("%s: the revolver's extractor came off when worn through" % lane)
		return false
	if not _refused_as(w2, revolver, "broken:extractor", "extractor", lane):
		return false

	print("  JAM OK a sound pistol never jams; a sear at 0.35 jams %.3f of pulls (table 0.12) and reads 'failing'; a sear worn through stays fitted, reads 'broken' and refuses as broken:sear with no NPC envelope; the never-jamming revolver refuses the same on a worn-through extractor" % rate)
	return true


# The three faces of one refusal, for the weapon in the player's hands: `can_fire` false and the
# reason id on it; a trigger pull that publishes `weapon.refused` with that id and fires nothing;
# the HUD's sentence naming the part; and npc_combat's envelope at zero, which is what keeps an NPC
# from walking into range of a gun that cannot shoot.
func _refused_as(w: Variant, gun: int, reason: String, noun: String, lane: String) -> bool:
	if SimRanged.can_fire(w, w.player) or SimRanged.refusal_of(w, w.player) != reason:
		push_error("%s: the weapon is refused as '%s', not %s" % [lane, SimRanged.refusal_of(w, w.player), reason])
		return false
	var mag_before: int = int((w.components.get_component(w.player, "rangedWeapon") as Dictionary).get("mag", -1))
	w.events.drain()
	if SimRanged.try_begin_fire(w, w.player):
		push_error("%s: a trigger pull on a weapon refused as %s began a fire" % [lane, reason])
		return false
	w.events.drain()
	var refused: String = ""
	for e in w.events.drained:
		if String((e as Dictionary).get("type", "")) == "weapon.refused" and int((e as Dictionary).get("entity", -1)) == w.player:
			refused = String((e as Dictionary).get("reason", ""))
	if refused != reason:
		push_error("%s: the trigger pull published '%s', not weapon.refused %s" % [lane, refused, reason])
		return false
	if int((w.components.get_component(w.player, "rangedWeapon") as Dictionary).get("mag", -1)) != mag_before:
		push_error("%s: a refused pull spent a round" % lane)
		return false
	var said: String = SimAttachments.refusal_clause(w, w.player)
	if said.is_empty() or not said.contains(noun) or not said.contains("worn through"):
		push_error("%s: the HUD's sentence for %s reads '%s'" % [lane, reason, said])
		return false
	if SimNpcCombat._ranged_range(w, w.player) != 0.0:
		push_error("%s: npc_combat gives a weapon refused as %s an envelope of %.1f m" % [lane, reason, SimNpcCombat._ranged_range(w, w.player)])
		return false
	if SimItems.jam_chance(w, gun) != 1.0:
		push_error("%s: the table reads %.3f for a broken assembly, not 1.0" % [lane, SimItems.jam_chance(w, gun)])
		return false
	return true


# --- ROUND --------------------------------------------------------------------------------------
#
# docs/23's "Choosing which round to fire". With buckshot and slugs both in the pack the pick order
# used to decide, and the only way to fire a slug was to carry nothing else. The sheet's `load` verb
# sends `item.load` on the round; the weapon in hand remembers the choice and a magazine reloads
# with it. The true negative is the same fixture with no verb, which still spends buckshot first.
func _the_round_you_choose_is_the_round_you_fire() -> bool:
	var lane: String = "ROUND"
	var w: Variant = _world()
	var gun: int = _armed(w, SHOTGUN, [[BUCK, 5], [SLUG, 5]])
	if gun < 0:
		return false
	w.step()
	var slugs: int = _stack_of(w, w.player, SLUG)
	var rifle_round: int = SimItems.spawn_item(w, RIFLE_ROUND, {"tier": "scavenged", "count": 2})
	SimInventory.store_anywhere(w, rifle_round, w.player)
	if SimRanged.load_refusal(w, w.player, rifle_round) != "wont-chamber":
		push_error("%s: a rifle round was offered to a shotgun (%s)" % [lane, SimRanged.load_refusal(w, w.player, rifle_round)])
		return false
	if SimRanged.load_refusal(w, w.player, slugs) != "":
		push_error("%s: slugs were refused to a shotgun loaded with buckshot (%s)" % [lane, SimRanged.load_refusal(w, w.player, slugs)])
		return false
	w.commands.push({"type": "item.load", "actor": w.player, "item": slugs})
	w.step()
	var rw: Dictionary = w.components.get_component(w.player, "rangedWeapon") as Dictionary
	if int(rw.get("state", -1)) != SimRanged.FireState.Reload:
		push_error("%s: choosing slugs did not start a reload" % lane)
		return false
	_load_first(w, w.player)
	if SimRanged.rounds_in(w, gun) != [SLUG, SLUG, SLUG, SLUG, SLUG]:
		push_error("%s: after choosing slugs the magazine holds %s" % [lane, str(SimRanged.rounds_in(w, gun))])
		return false
	if _rounds_left(w, w.player, BUCK) != 5 or _in_pack(w, w.player, BUCK) != 5:
		push_error("%s: the buckshot that came out did not go back in the pack (%d in pack of %d)" % [lane, _in_pack(w, w.player, BUCK), _rounds_left(w, w.player, BUCK)])
		return false
	if _fire_once(w, w.player) <= 0.0 or _rounds_left(w, w.player, SLUG) != 4 or _rounds_left(w, w.player, BUCK) != 5:
		push_error("%s: the chosen slug was not the round fired (slugs %d, buckshot %d)" % [lane, _rounds_left(w, w.player, SLUG), _rounds_left(w, w.player, BUCK)])
		return false
	if SimRanged.load_refusal(w, w.player, _stack_of(w, w.player, BUCK)) != "":
		push_error("%s: switching back to buckshot was refused" % lane)
		return false

	# The choice is the weapon's, not the hand's: slung and drawn again, it still holds four slugs
	# and still wants slugs -- and is not refilled to five, which the old counter did on every equip.
	SimInventory.unequip(w, w.player, _slot_of(w, w.player, gun))
	w.step()
	if w.components.has_component(w.player, "rangedWeapon"):
		push_error("%s: the shotgun was slung and the hand still holds a weapon" % lane)
		return false
	SimInventory.equip(w, w.player, gun)
	w.step()
	var again: Variant = w.components.get_component(w.player, "rangedWeapon")
	if not (again is Dictionary and int((again as Dictionary).get("mag", -1)) == 4 and SimRanged.choice_in(w, again as Dictionary) == SLUG):
		push_error("%s: drawn again the shotgun holds %s and wants '%s'" % [lane, str((again as Dictionary).get("mag", -1)) if again is Dictionary else "nothing", SimRanged.choice_in(w, again as Dictionary) if again is Dictionary else ""])
		return false

	# The true negative: the same pack, no verb, and buckshot goes first as it always has.
	var w2: Variant = _world()
	var gun2: int = _armed(w2, SHOTGUN, [[BUCK, 5], [SLUG, 5]])
	if gun2 < 0:
		return false
	if _fire_once(w2, w2.player) <= 0.0 or _rounds_left(w2, w2.player, BUCK) != 4 or _rounds_left(w2, w2.player, SLUG) != 5:
		push_error("%s: with nothing chosen the shotgun did not spend buckshot first" % lane)
		return false

	# A bow has no magazine and only remembers: the next nock takes the broadhead.
	var w3: Variant = _world()
	if _armed(w3, BOW, [[ARROW, 5], [BROADHEAD, 5]]) < 0:
		return false
	w3.step()
	w3.commands.push({"type": "item.load", "actor": w3.player, "item": _stack_of(w3, w3.player, BROADHEAD)})
	w3.step()
	if _fire_once(w3, w3.player) <= 0.0 or _rounds_left(w3, w3.player, BROADHEAD) != 4 or _rounds_left(w3, w3.player, ARROW) != 5:
		push_error("%s: a bow told to nock broadheads spent %d broadheads and %d arrows" % [lane, 5 - _rounds_left(w3, w3.player, BROADHEAD), 5 - _rounds_left(w3, w3.player, ARROW)])
		return false
	if SimRanged.load_refusal(w3, w3.player, _stack_of(w3, w3.player, BROADHEAD)) != "already-loaded":
		push_error("%s: a bow already set to broadheads was offered them again" % lane)
		return false
	print("  ROUND OK slugs chosen over buckshot reload into the magazine and fire, the buckshot goes back in the pack, the choice survives a holster; unchosen, buckshot goes first; a bow nocks the chosen broadhead")
	return true


# --- MAG ----------------------------------------------------------------------------------------
#
# docs/23's "The magazine remembers what you loaded". A reload takes rounds out of the pack and the
# record keeps them; a shot spends from the record and leaves the pack alone; a reload with a
# different round changes what is in it, and that costs the reload's time.
func _the_magazine_remembers_what_you_loaded() -> bool:
	var lane: String = "MAG"
	var w: Variant = _world()
	var gun: int = _armed(w, PISTOL, [[NINE, 20]])
	if gun < 0:
		return false
	if SimRanged.rounds_in(w, gun).size() != 8 or _in_pack(w, w.player, NINE) != 12:
		push_error("%s: loading took %d from the pack into a magazine of %d" % [lane, 20 - _in_pack(w, w.player, NINE), SimRanged.rounds_in(w, gun).size()])
		return false
	if _fire_once(w, w.player) <= 0.0 or _in_pack(w, w.player, NINE) != 12 or SimRanged.rounds_in(w, gun).size() != 7:
		push_error("%s: a shot left the pack at %d and the magazine at %d (want 12 and 7)" % [lane, _in_pack(w, w.player, NINE), SimRanged.rounds_in(w, gun).size()])
		return false
	_fire_once(w, w.player)
	w.commands.push({"type": "reload"})
	_load_first(w, w.player)
	for i in 80:
		w.step()
	if SimRanged.rounds_in(w, gun).size() != 8 or _in_pack(w, w.player, NINE) != 10:
		push_error("%s: a top-up after two shots left the magazine at %d and the pack at %d (want 8 and 10)" % [lane, SimRanged.rounds_in(w, gun).size(), _in_pack(w, w.player, NINE)])
		return false

	# A loaded gun fires with nothing left in the pack; emptied, it does not, and the pull does not
	# even start a reload with nothing to load.
	var w2: Variant = _world()
	var gun2: int = _armed(w2, PISTOL, [[NINE, 2]])
	if gun2 < 0:
		return false
	if _in_pack(w2, w2.player, NINE) != 0 or _fire_once(w2, w2.player) <= 0.0:
		push_error("%s: a pistol with two rounds loaded and none in the pack did not fire" % lane)
		return false
	_fire_once(w2, w2.player)
	if _fire_once(w2, w2.player) > 0.0:
		push_error("%s: an empty pistol with an empty pack fired" % lane)
		return false
	var rw2: Dictionary = w2.components.get_component(w2.player, "rangedWeapon") as Dictionary
	if int(rw2.get("state", -1)) != SimRanged.FireState.Idle:
		push_error("%s: an empty pistol with an empty pack started a reload with nothing to load" % lane)
		return false

	# Mixed: two slugs chosen into a five-round magazine take the slugs and then buckshot, and fire
	# in that order.
	var w3: Variant = _world()
	var gun3: int = _armed(w3, SHOTGUN, [[SLUG, 2], [BUCK, 8]])
	if gun3 < 0:
		return false
	w3.step()
	if SimRanged.rounds_in(w3, gun3) != [BUCK, BUCK, BUCK, BUCK, BUCK]:
		push_error("%s: the fixture loaded %s, not buckshot" % [lane, str(SimRanged.rounds_in(w3, gun3))])
		return false
	w3.commands.push({"type": "item.load", "actor": w3.player, "item": _stack_of(w3, w3.player, SLUG)})
	w3.commands.push({"type": "fire"})
	w3.step()
	# Switching loads costs the reload: on the tick the verb lands the magazine is still buckshot and
	# the trigger pull beside it did nothing.
	var rw3: Dictionary = w3.components.get_component(w3.player, "rangedWeapon") as Dictionary
	if int(rw3.get("state", -1)) != SimRanged.FireState.Reload or SimRanged.rounds_in(w3, gun3) != [BUCK, BUCK, BUCK, BUCK, BUCK]:
		push_error("%s: switching to slugs was instant (state %d, %s)" % [lane, int(rw3.get("state", -1)), str(SimRanged.rounds_in(w3, gun3))])
		return false
	_load_first(w3, w3.player)
	var mixed: Array = [SLUG, SLUG, BUCK, BUCK, BUCK]
	if SimRanged.rounds_in(w3, gun3) != mixed or _rounds_left(w3, w3.player, BUCK) != 8:
		push_error("%s: two slugs chosen loaded %s with %d buckshot in all" % [lane, str(SimRanged.rounds_in(w3, gun3)), _rounds_left(w3, w3.player, BUCK)])
		return false
	_fire_once(w3, w3.player)
	_fire_once(w3, w3.player)
	if SimRanged.rounds_in(w3, gun3) != [BUCK, BUCK, BUCK] or _rounds_left(w3, w3.player, SLUG) != 0:
		push_error("%s: two shots from a slug-over-buckshot magazine left %s" % [lane, str(SimRanged.rounds_in(w3, gun3))])
		return false
	print("  MAG OK a reload takes eight from the pack and a shot none; a top-up takes only the two fired; a loaded pistol fires with an empty pack and an emptied one does not; a switch waits out the reload, and two slugs load over buckshot and fire first")
	return true


# --- WORD ---------------------------------------------------------------------------------------
#
# The inspect pane's load line, in words. Every round has a word, none carries a digit (its name may,
# under the one amendment; this line may not), and no two rounds of one caliber share one, or two
# different loads would read the same. The line itself: "empty", one round's word, and "mixed"
# when they differ; and "" for anything with no magazine.
func _every_load_reads_in_words() -> bool:
	var lane: String = "WORD"
	var seen: Dictionary = {}
	var rounds: int = 0
	for entry in _all_items():
		var spec: Variant = (entry as Dictionary).get("ammo")
		if not spec is Dictionary:
			continue
		rounds += 1
		var id: String = String((entry as Dictionary).get("id", ""))
		var word: String = String((spec as Dictionary).get("word", ""))
		if word.is_empty():
			push_error("%s: %s has no word for the inspect pane" % [lane, id])
			return false
		for c in word:
			if c >= "0" and c <= "9":
				push_error("%s: %s's word '%s' carries a digit" % [lane, id, word])
				return false
		var key: String = String((spec as Dictionary).get("caliber", "")) + "|" + word
		if seen.has(key):
			push_error("%s: %s and %s are both '%s' in one caliber" % [lane, id, String(seen[key]), word])
			return false
		seen[key] = id
	var w: Variant = _world()
	var gun: int = _armed(w, SHOTGUN, [])
	var bow: int = _spawn(w, BOW)
	if SimRanged.load_words(w, gun) != "empty" or SimRanged.load_words(w, bow) != "":
		push_error("%s: an empty shotgun reads '%s' and a bow '%s'" % [lane, SimRanged.load_words(w, gun), SimRanged.load_words(w, bow)])
		return false
	var w2: Variant = _world()
	var gun2: int = _armed(w2, SHOTGUN, [[SLUG, 2], [BUCK, 8]])
	if SimRanged.load_words(w2, gun2) != "buckshot":
		push_error("%s: a shotgun full of buckshot reads '%s'" % [lane, SimRanged.load_words(w2, gun2)])
		return false
	w2.step()
	w2.commands.push({"type": "item.load", "actor": w2.player, "item": _stack_of(w2, w2.player, SLUG)})
	_load_first(w2, w2.player)
	for i in 80:
		w2.step()
	var view: Dictionary = SimInventory.inspect_view(w2, w2.player, gun2)
	if String(view.get("load", "")) != "mixed":
		push_error("%s: a slug-over-buckshot magazine reads '%s' on the inspect view, not mixed" % [lane, String(view.get("load", ""))])
		return false
	for i in 2:
		_fire_once(w2, w2.player)
	if String(SimInventory.inspect_view(w2, w2.player, gun2).get("load", "")) != "buckshot":
		push_error("%s: with the two slugs fired the magazine reads '%s', not buckshot" % [lane, String(SimInventory.inspect_view(w2, w2.player, gun2).get("load", ""))])
		return false
	print("  WORD OK %d rounds each with a word, none with a digit, none shared in a caliber; empty reads empty, a bow reads nothing, slug over buckshot reads mixed and buckshot once the slugs are fired" % rounds)
	return true


# --- TIER ---------------------------------------------------------------------------------------
#
# A round a reload puts back comes out at the tier it went in at (the review of 2026-10-28: the first
# cut spawned every returned round "scavenged"). Modified buckshot loaded, slugs chosen over it: the
# buckshot back in the pack is still modified, and the slugs in the gun are still scavenged.
func _a_round_comes_back_as_it_went_in() -> bool:
	var lane: String = "TIER"
	var w: Variant = _world()
	var gun: int = _spawn(w, SHOTGUN)
	if not SimInventory.equip(w, w.player, gun):
		push_error("%s: the shotgun would go in neither hand" % lane)
		return false
	var buck: int = SimItems.spawn_item(w, BUCK, {"tier": "modified", "count": 5})
	var slug: int = SimItems.spawn_item(w, SLUG, {"tier": "scavenged", "count": 5})
	if not SimInventory.store_anywhere(w, buck, w.player) or not SimInventory.store_anywhere(w, slug, w.player):
		push_error("%s: the rounds would not go in a pocket" % lane)
		return false
	SimRanged.load_held(w, w.player)
	w.step()
	if _stack_of(w, w.player, BUCK) >= 0:
		push_error("%s: loading five buckshot left a buckshot stack in the pack" % lane)
		return false
	w.commands.push({"type": "item.load", "actor": w.player, "item": _stack_of(w, w.player, SLUG)})
	w.step()
	_load_first(w, w.player)
	var back: int = _stack_of(w, w.player, BUCK)
	if back < 0 or _rounds_left(w, w.player, BUCK) != 5:
		push_error("%s: the buckshot did not come back to the pack" % lane)
		return false
	if SimItems.tier_of(w, back) != "modified":
		push_error("%s: modified buckshot came back out of the magazine %s" % [lane, SimItems.tier_of(w, back)])
		return false
	var rec: Variant = w.components.get_component(gun, SimRanged.LOAD)
	if not (rec is Dictionary and (rec as Dictionary).get("tiers") == ["scavenged", "scavenged", "scavenged", "scavenged", "scavenged"]):
		push_error("%s: the slugs in the gun carry tiers %s" % [lane, str((rec as Dictionary).get("tiers") if rec is Dictionary else null)])
		return false
	print("  TIER OK modified buckshot swapped out for slugs comes back to the pack modified, and the slugs in the gun keep their own tier")
	return true


func _stack_of(w: Variant, actor: int, base_id: String) -> int:
	for item in SimInventory.carried_items(w, actor) as Array:
		var base: Variant = SimItems.item_base_of(w, int(item))
		if base is Dictionary and String((base as Dictionary).get("id", "")) == base_id:
			return int(item)
	return -1


func _slot_of(w: Variant, actor: int, item: int) -> String:
	var eq: Dictionary = (w.components.get_component(actor, "equipment") as Dictionary).get("slots", {}) as Dictionary
	for k in eq.keys():
		if int(eq[k]) == item:
			return String(k)
	return ""
