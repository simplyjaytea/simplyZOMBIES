extends SceneTree
# NPC combat from assigned posts -- docs/09's "NPCs fight autonomously from their post and Focus
# ... they break off when critically injured, per traits".
#
# Every assertion here carries a true positive AND a true negative, the convention
# check_ban_health_bar.gd set after a field that was always false passed a "no leak" test. An
# NPC that never swings would satisfy "does not swing across the district" perfectly.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimMelee = preload("res://sim/modules/melee.gd")
const SimRanged = preload("res://sim/modules/ranged.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")
const SimRoster = preload("res://sim/modules/roster.gd")
const SimNpcCombat = preload("res://sim/modules/npc_combat.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const Clock = preload("res://sim/time/clock.gd")

const ARENA_SEED: int = 4242
const ARENA_TICKS: int = 900

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok: bool = true
	ok = _armed_npc_kills_what_walks_into_reach() and ok
	ok = _ranged_npc_spends_its_ammunition() and ok
	ok = _critically_injured_breaks_off() and ok
	ok = _distance_and_silence_are_both_negative_controls() and ok
	ok = _a_guard_engages_without_leaving_its_post() and ok
	if ok:
		print("M2_NPC_COMBAT_OK melee ranged breakoff quiet post")
		quit(0)
	else:
		push_error("M2_NPC_COMBAT_FAIL")
		quit(1)


# A bare arena with the combat modules and no shambler AI: the target stands still so the thing
# under test is the intake deciding to act, not a chase. The post test below uses the real
# district, where everything moves.
func _arena() -> Variant:
	var fixture: Dictionary = {
		"seed": ARENA_SEED,
		"tick_hz": 20,
		"map": {"width": 32, "height": 32, "walls": []},
		"player": {"id": 0, "x": 2.0, "y": 2.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var map: Variant = SimTileMap.blank_map(32, 32)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimMelee.register_module(w)
	SimRanged.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimNpcCombat.register_module(w)
	return w


# A survivor who is not the one the player is driving: needs, a body, a facing, and no
# `controlled` component. That absence is the whole point of the module.
func _npc(w: Variant, x: float, y: float, traits: Array = []) -> int:
	var ent: int = int(w.entities.spawn())
	w.components.set_component(ent, "position", {"x": x, "y": y})
	w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	w.components.set_component(ent, "facing", {"radians": 0.0})
	w.components.set_component(ent, "identity", {"id": "survivor.test", "name": "Test", "traits": traits})
	SimHealth.make_survivor_body(w, ent)
	SimHealth.make_stamina(w, ent)
	SimInventory.make_inventory(w, ent)
	SimNeeds.attach(w, ent)
	return ent


func _zombie(w: Variant, x: float, y: float) -> int:
	return SimRoster.spawn_zombie(w, x, y, SimRoster.TYPE_SHAMBLER, w.rng.stream("shambler"))


func _alive(w: Variant, ent: int) -> bool:
	var body: Variant = w.components.get_component(ent, "body")
	return body is Dictionary and SimHealth.is_alive(body as Dictionary)


func _swings(w: Variant, ent: int, ticks: int) -> int:
	var connected: int = 0
	for _t in ticks:
		w.step()
		for e in w.events.drained:
			var ev: Dictionary = e as Dictionary
			if String(ev.get("type", "")) == "attack.connected" and int(ev.get("attacker", -1)) == ent:
				connected += 1
	return connected


func _arrows(w: Variant, ent: int) -> int:
	var n: int = 0
	for item in SimInventory.carried_items(w, ent) as Array:
		var base: Variant = SimItems.item_base_of(w, int(item))
		if not (base is Dictionary and String((base as Dictionary).get("id", "")) == "item.ammo.arrow"):
			continue
		var stack: Variant = w.components.get_component(int(item), "stack")
		n += int((stack as Dictionary).get("count", 1)) if stack is Dictionary else 1
	return n


func _armed_npc_kills_what_walks_into_reach() -> bool:
	var w: Variant = _arena()
	var npc: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, npc, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	var z: int = _zombie(w, 10.9, 10.0)
	var connected: int = _swings(w, npc, ARENA_TICKS)
	if connected < 1:
		push_error("armed NPC never connected in %d ticks" % ARENA_TICKS)
		return false
	if _alive(w, z):
		push_error("armed NPC connected %d times and the shambler lived" % connected)
		return false

	# Negative: the same NPC with empty hands. Not "swung less" -- did not swing.
	var w2: Variant = _arena()
	var bare: int = _npc(w2, 10.0, 10.0)
	var z2: int = _zombie(w2, 10.9, 10.0)
	var idle: int = _swings(w2, bare, ARENA_TICKS)
	if idle != 0:
		push_error("unarmed NPC connected %d times" % idle)
		return false
	if not _alive(w2, z2):
		push_error("unarmed NPC killed a shambler")
		return false
	print("MELEE OK connected=%d unarmed=%d" % [connected, idle])
	return true


func _ranged_npc_spends_its_ammunition() -> bool:
	var w: Variant = _arena()
	var archer: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, archer, SimItems.spawn_item(w, "item.bow.hunting", {"tier": "scavenged"}))
	SimInventory.stow(w, archer, SimItems.spawn_item(w, "item.ammo.arrow", {"tier": "scavenged", "count": 12}))
	var before: int = _arrows(w, archer)
	_zombie(w, 18.0, 10.0)
	for _t in ARENA_TICKS:
		w.step()
	var after: int = _arrows(w, archer)
	if after >= before:
		push_error("bow NPC fired nothing: arrows %d -> %d" % [before, after])
		return false

	# Negative: the same archer with no arrows never leaves Idle. An empty quiver is a refusal,
	# not a silent dry fire.
	var w2: Variant = _arena()
	var dry: int = _npc(w2, 10.0, 10.0)
	SimInventory.equip(w2, dry, SimItems.spawn_item(w2, "item.bow.hunting", {"tier": "scavenged"}))
	_zombie(w2, 18.0, 10.0)
	var raised: int = 0
	for _t in 200:
		w2.step()
		var rw: Variant = w2.components.get_component(dry, "rangedWeapon")
		if rw is Dictionary and int((rw as Dictionary)["state"]) != SimRanged.FireState.Idle:
			raised += 1
	if raised != 0:
		push_error("bow NPC with no arrows left Idle on %d ticks" % raised)
		return false

	# A pistol runs its magazine down and reloads itself -- the reload-when-empty branch is
	# inherited from try_begin_fire rather than restated here.
	var w3: Variant = _arena()
	var shooter: int = _npc(w3, 10.0, 10.0)
	SimInventory.equip(w3, shooter, SimItems.spawn_item(w3, "item.pistol.service", {"tier": "scavenged"}))
	SimInventory.stow(w3, shooter, SimItems.spawn_item(w3, "item.ammo.9mm", {"tier": "scavenged", "count": 20}))
	_zombie(w3, 18.0, 10.0)
	var reloads: int = 0
	var was: int = -1
	for _t in ARENA_TICKS:
		w3.step()
		var rw: Variant = w3.components.get_component(shooter, "rangedWeapon")
		if rw is Dictionary:
			var state: int = int((rw as Dictionary)["state"])
			if state == SimRanged.FireState.Reload and was != SimRanged.FireState.Reload:
				reloads += 1
			was = state
	if reloads < 1:
		push_error("pistol NPC never reloaded in %d ticks" % ARENA_TICKS)
		return false
	print("RANGED OK arrows %d->%d dry=%d reloads=%d" % [before, after, raised, reloads])
	return true


func _critically_injured_breaks_off() -> bool:
	# Positive control first: this exact body, this exact placement, does fight. Without it the
	# negative below would pass on a module that never fired at all.
	var w: Variant = _arena()
	var whole: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, whole, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	_zombie(w, 10.9, 10.0)
	var fought: int = _swings(w, whole, 300)
	if fought < 1:
		push_error("whole NPC did not fight, so the break-off test proves nothing")
		return false

	var w2: Variant = _arena()
	var hurt: int = _npc(w2, 10.0, 10.0)
	SimInventory.equip(w2, hurt, SimItems.spawn_item(w2, "item.knife.kitchen", {"tier": "scavenged"}))
	_wound_to(w2, hurt, "arm_right", SimNpcCombat.BREAK_OFF_STATE)
	_zombie(w2, 10.9, 10.0)
	var broken: int = _swings(w2, hurt, 300)
	if broken != 0:
		push_error("critically injured NPC connected %d times" % broken)
		return false

	# And traits move the threshold by a rung rather than changing the decision: at a merely
	# Hurt arm the squeamish survivor is done and the ordinary one is not.
	var squeamish_swings: int = _fights_at(["squeamish"], SimHealth.PartState.Hurt)
	var ordinary_swings: int = _fights_at([], SimHealth.PartState.Hurt)
	if squeamish_swings != 0 or ordinary_swings < 1:
		push_error("trait threshold wrong: squeamish=%d ordinary=%d at Hurt" % [squeamish_swings, ordinary_swings])
		return false
	print("BREAKOFF OK whole=%d broken=%d squeamish=%d ordinary=%d" % [fought, broken, squeamish_swings, ordinary_swings])
	return true


# Damage one part down to exactly the state named, using part_state's own scale rather than a
# second guess at what each part's maximum is.
func _wound_to(w: Variant, ent: int, part: String, state: int) -> void:
	var body: Dictionary = w.components.get_component(ent, "body") as Dictionary
	var maxv: Variant = SimHealth.max_of(body, part)
	var top: float = float(int(maxv)) if maxv != null else 40.0
	for step in range(int(top), -1, -1):
		body[part] = float(step)
		if int(SimHealth.part_state(body, part)) >= state:
			return


func _fights_at(traits: Array, state: int) -> int:
	var w: Variant = _arena()
	var ent: int = _npc(w, 10.0, 10.0, traits)
	SimInventory.equip(w, ent, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	_wound_to(w, ent, "arm_right", state)
	_zombie(w, 10.9, 10.0)
	return _swings(w, ent, 300)


func _distance_and_silence_are_both_negative_controls() -> bool:
	# Nothing to fight: an armed NPC alone in a district stays Idle. Milestone 1's exit criterion
	# reads "a quiet district has nobody pursuing"; NPC combat must not make one loud.
	var w: Variant = _arena()
	var alone: int = _npc(w, 10.0, 10.0)
	SimInventory.equip(w, alone, SimItems.spawn_item(w, "item.knife.kitchen", {"tier": "scavenged"}))
	var noise: int = 0
	for _t in 400:
		w.step()
		for e in w.events.drained:
			if String((e as Dictionary).get("type", "")) == "noise.emitted":
				noise += 1
		var swing: Variant = w.components.get_component(alone, "swing")
		if swing is Dictionary and int((swing as Dictionary)["state"]) != SimMelee.SwingState.Idle:
			push_error("NPC swung at nothing")
			return false
	if noise != 0:
		push_error("empty district emitted %d noise events" % noise)
		return false

	# And a threat further off than ENGAGE_METRES is not a threat yet -- a bow reaches 40 m and a
	# guard does not spend an arrow on everything inside it.
	var w2: Variant = _arena()
	var archer: int = _npc(w2, 4.0, 10.0)
	SimInventory.equip(w2, archer, SimItems.spawn_item(w2, "item.bow.hunting", {"tier": "scavenged"}))
	SimInventory.stow(w2, archer, SimItems.spawn_item(w2, "item.ammo.arrow", {"tier": "scavenged", "count": 12}))
	var quiver: int = _arrows(w2, archer)
	_zombie(w2, 4.0 + SimNpcCombat.ENGAGE_METRES + 4.0, 10.0)
	for _t in 400:
		w2.step()
	if _arrows(w2, archer) != quiver:
		push_error("NPC fired at a threat beyond ENGAGE_METRES")
		return false
	print("QUIET OK noise=%d quiver held at %d beyond %.0fm" % [noise, quiver, SimNpcCombat.ENGAGE_METRES])
	return true


func _a_guard_engages_without_leaving_its_post() -> bool:
	# The real district this time, with every module the playable boot registers.
	var w: Variant = SimBoot.playable(20260805, 64)["world"]
	var guard: int = -1
	for ent in w.components.query(["needs", "jobPriorities", "position"]):
		if w.components.has_component(int(ent), "controlled") or int(ent) == int(w.player):
			continue
		guard = int(ent)
		break
	if guard < 0:
		push_error("no NPC survivor in the playable boot")
		return false
	SimJobs.set_focus(w, guard, "Manual")
	SimJobs.set_priority(w, guard, "Guard", 1)
	SimInventory.unequip(w, guard, "primary")
	if not SimInventory.equip(w, guard, SimItems.spawn_item(w, "item.bat.aluminium", {"tier": "scavenged"})):
		push_error("could not arm the guard")
		return false

	# Stand them on the post rather than waiting for the job router to walk them there --
	# routing is `M2_JOBS_OK`'s claim, and a need seek can legitimately hold a survivor for
	# hours. What is under test here is what they do once they are standing on it.
	var post_x: float = float(SimFortify.GATE_A.x) + 0.5
	var post_y: float = float(SimFortify.GATE_A.y) + 1.5
	w.components.set_component(guard, "position", {"x": post_x, "y": post_y})
	w.components.set_component(guard, "job", SimJobs._work_for(w, guard, "Guard"))
	_zombie(w, post_x + 0.9, post_y)
	var connected: int = _swings(w, guard, 600)
	if connected < 1:
		push_error("guard at its post never connected")
		return false
	var after: Dictionary = w.components.get_component(guard, "position") as Dictionary
	var drift: float = sqrt((float(after["x"]) - post_x) ** 2.0 + (float(after["y"]) - post_y) ** 2.0)
	# Engaging is something you do *from* a post. Some drift is the job system's own business;
	# a chase is not, and 6 m is well inside the gate's own footprint.
	if drift > 6.0:
		push_error("guard chased %.1f m off its post" % drift)
		return false
	print("POST OK connected=%d drift=%.2fm" % [connected, drift])
	return true
