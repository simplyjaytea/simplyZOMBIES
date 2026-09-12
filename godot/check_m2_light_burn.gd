extends SceneTree
# Light that burns down, and what feeds it -- docs/03-attention.md#light, docs/12-resources.md's
# fuel line, and the owner's decision of 2026-09-12.
#
# What this slice fixed. Every light in the game burned **for ever**: there was no `burnTicks` and
# no fuel key of any kind, so `item.lamp.electric` at magnitude 35 was strictly, permanently better
# than `item.candle.wax` at 3 from the moment you found one, `item.battery` was an inert `material`
# nothing in the game consumed, and `item.lantern.oil` had nothing that could refill it. Light was
# the only resource in a resource game that could not run out.
#
# And the reader had two dead sockets of its own, both reached here on the owner's instruction.
# `SimLightModule.HAND_SLOTS` was `["primary", "secondary"]` and it was the *only* list the carried
# scan walked, so `head` and `eyes` -- legal `equipSlot` values since inventory shipped -- were
# invisible to the light field: a headlamp validated, equipped, drew on the pawn and lit nothing.
# It is `LIGHT_SLOTS` now and it has four entries. The other socket is the weapon light, whose
# `attachment.fitted` / `.removed` / `.broke` wiring has been live and unfed; it now declares a
# burn and a feed like every other lamp, so the part that was nearly an orphan eats cells.
#
# Three shipped orphans this slice adopts, on the arc's standing rule that an unreachable item is a
# bug in the reader rather than a thing to delete: `item.floodlight.rigged` (magnitude 90, 3x3, no
# equipSlot, in the military cache's table, and **no placement verb existed**) gets one;
# `item.jerrycan.empty` (nothing could fill it, there was no siphon) gets one; and `item.battery`
# becomes what the electric lamp eats.
#
# The lane that matters most is PINNED, for the reason check_m2_medicine.gd's PINNED and
# check_m2_materials.gd's PINNED matter most: the retrofit has to reproduce the old numbers exactly
# or this is not a new mechanism, it is a silent nerf of every light in the game wearing one. Every
# shipped magnitude is pinned and every shipped light is pinned *full* -- what changes is only what
# happens after it runs out.
#
# The lane that is hardest is HEADLAMP, and it measures the **lit radius off the shadowcast**
# rather than the helper's return value. Widening a constant makes a helper answer differently;
# only `SimLight.refresh` walking `light_source` into a real cast proves the widening reached the
# world. NIGHT is the balance claim and it is measured, not authored: the dark stretch is computed
# from SimClock rather than asserted from memory, and every shipped burn time is judged against it.
#
# Every lane carries a true negative.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimVehicles = preload("res://sim/modules/vehicles.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimLightIndex = preload("res://sim/vision/light.gd")
const Clock = preload("res://sim/time/clock.gd")

# The four bases that shipped before this slice. Fixtures, not welds -- the sim names none of them
# -- but PINNED has to hold something concrete or the retrofit is unfalsifiable.
const CANDLE: String = "item.candle.wax"
const LAMP: String = "item.lamp.electric"
const LANTERN: String = "item.lantern.oil"
const FLOODLIGHT: String = "item.floodlight.rigged"
const WEAPON_LIGHT: String = "item.attach.underbarrel.light"
# What they threw before the burn clock existed, straight out of git. A change to any of these is a
# rebalance and this gate is where it is caught.
const SHIPPED_MAGNITUDES: Dictionary = {
	CANDLE: 3.0, LAMP: 35.0, LANTERN: 20.0, FLOODLIGHT: 90.0, WEAPON_LIGHT: 16.0,
}

# New bases the lanes below put on a body. The headlamp is the whole point of the widened scan.
const HEADLAMP: String = "item.headlamp.band"
const CLIPLIGHT: String = "item.cliplight.glasses"
const TORCH: String = "item.torch.handheld"
const GLOWSTICK: String = "item.glowstick"
const BATTERY: String = "item.battery"
const LAMP_OIL: String = "item.oil.lamp"
const PROPANE: String = "item.propane.cylinder"
const HELMET: String = "item.helmet.bike"
const RIFLE: String = "item.rifle.hunting"
const EMPTY_CAN: String = "item.jerrycan.empty"
const FULL_CAN: String = "item.jerrycan.fuel"

const MAP: int = 48
const CAR_X: int = 20
const CAR_Y: int = 24

# Two lamps identical in every number except the slot they declare. Fabricated on purpose: nothing
# in the shipped roster puts a light on a torso, which is exactly why the true negative for "the
# scan is no wider than the decision" has to invent one. `SimInventory.equip` refuses any slot but
# the one content names, so this is a pair rather than one base moved between slots.
const _FIXTURE_LAMPS: Array = [
	{"id": "item.gate.vestlamp", "name": "Vest Lamp", "class": "tool", "size": {"w": 1, "h": 1},
		"massKg": 0.2, "equipSlot": "torso", "light": {"magnitude": 40, "burnTicks": 1000}},
	{"id": "item.gate.headlamp", "name": "Gate Headlamp", "class": "tool", "size": {"w": 1, "h": 1},
		"massKg": 0.2, "equipSlot": "head", "light": {"magnitude": 40, "burnTicks": 1000}},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_shipped_lights_still_throw_what_they_threw() and ok
	ok = _every_light_block_is_whole_and_every_fuel_has_a_mouth() and ok
	ok = _the_head_and_the_eyes_are_finally_looked_in() and ok
	ok = _a_lamp_burns_only_while_it_is_the_one_alight() and ok
	ok = _a_headlamp_lights_the_district_from_the_head() and ok
	ok = _a_cell_refills_the_lamp_and_is_gone() and ok
	ok = _the_floodlight_can_at_last_be_stood_up() and ok
	ok = _an_empty_can_can_at_last_be_filled() and ok
	ok = _the_shipped_burn_times_are_measured_against_the_dark() and ok
	if ok:
		print("M2_LIGHT_BURN_OK pinned content slots burn headlamp feed plant siphon night")
		quit(0)
	else:
		push_error("M2_LIGHT_BURN_FAIL")
		quit(1)


# --- fixtures ---------------------------------------------------------------------------------

# A survivor on an open map with the kernel attached, so `w.light` is the real index and a lane
# that wants the shadowcast has one. The pack is not decoration: pockets are 4x2 and a floodlight
# is 3x3.
func _world(seed_val: int = 9101, tick: int = -1) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": MAP, "height": MAP, "walls": []},
		"player": {"id": 0, "x": 8.5, "y": 12.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	var map: Variant = SimTileMap.blank_map(MAP, MAP)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimLightMod.register_module(w)
	SimFortify.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	w.tick = tick if tick >= 0 else Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var pack: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, pack):
		push_error("the fixture pack would not go on")
	w.events.drain()
	return w


func _give(w: Variant, id: String) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	if not SimInventory.stow(w, w.player, item):
		push_error("the fixture '%s' would not go in a pocket" % id)
		return -1
	return item


func _wear(w: Variant, id: String, slot: String = "") -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, item, slot):
		push_error("the fixture '%s' would not go on" % id)
		return -1
	w.events.drain()
	return item


func _entry(w: Variant, id: String) -> Dictionary:
	var e: Variant = SimItems.content_entry(w, "item", id)
	return (e as Dictionary) if e is Dictionary else {}


func _magnitude_of(w: Variant, id: String) -> float:
	var light: Variant = _entry(w, id).get("light")
	if not (light is Dictionary):
		return -1.0
	return float((light as Dictionary).get("magnitude", -1.0))


func _burn_of(w: Variant, id: String) -> int:
	var light: Variant = _entry(w, id).get("light")
	if not (light is Dictionary):
		return -1
	return int((light as Dictionary).get("burnTicks", -1))


# Every id any shipped loot table can hand out.
func _findable(w: Variant) -> Dictionary:
	var out: Dictionary = {}
	for file_v in (w.content as Dictionary).values():
		if not (file_v is Array):
			continue
		for entry_v in file_v as Array:
			if not (entry_v is Dictionary):
				continue
			var t: Dictionary = entry_v as Dictionary
			if not String(t.get("id", "")).begins_with("loot."):
				continue
			for row_v in t.get("entries", []) as Array:
				out[String((row_v as Dictionary).get("item", ""))] = true
	return out


# --- PINNED -----------------------------------------------------------------------------------
#
# Additive or it is a rebalance. The five shipped lights must throw the number they threw before
# the burn clock existed, and must throw it *from a fresh instance* -- a perfect content table on
# a reader that started every lamp half empty would be the same nerf wearing a different hat.
func _the_shipped_lights_still_throw_what_they_threw() -> bool:
	var w: Variant = _world()
	for id in SHIPPED_MAGNITUDES.keys():
		var want: float = float(SHIPPED_MAGNITUDES[id])
		var got: float = _magnitude_of(w, String(id))
		if absf(got - want) > 1e-9:
			push_error("PINNED: '%s' throws %.2f m against the shipped %.2f -- the burn slice moved a magnitude" % [String(id), got, want])
			return false
		var item: int = SimItems.spawn_item(w, String(id), {"tier": "scavenged"})
		var reach: Variant = SimLightMod.light_reach_of(w, item)
		if reach == null or absf(float(reach) - want) > 1e-9:
			push_error("PINNED: a fresh '%s' reads %s, not %.2f -- a new lamp does not start full" % [String(id), str(reach), want])
			return false
		if SimLightMod.spent(w, item):
			push_error("PINNED: a fresh '%s' is already spent" % String(id))
			return false

	# docs/03's table and the light index's copy of it, which the schema's own description says a
	# test pins. Three of the four rungs are shipped bases; `campfire` is SimNeeds' fire.
	for pair in [[CANDLE, "candle"], [LAMP, "lamp"], [FLOODLIGHT, "floodlight"]]:
		var table: float = float(SimLightIndex.LIGHT_TABLE.get(String(pair[1]), -1.0))
		if absf(_magnitude_of(w, String(pair[0])) - table) > 1e-9:
			push_error("PINNED: '%s' is %.2f and LIGHT_TABLE's '%s' is %.2f" % [String(pair[0]), _magnitude_of(w, String(pair[0])), String(pair[1]), table])
			return false

	# A carried lamp lights its holder at exactly the shipped number, through the whole path the
	# field reads -- the component, not the helper.
	var holder: Variant = _world()
	var lamp: int = _wear(holder, LAMP)
	if lamp < 0:
		return false
	var src: Variant = holder.components.get_component(holder.player, "light_source")
	if not (src is Dictionary) or absf(float((src as Dictionary).get("magnitude", 0.0)) - 35.0) > 1e-9:
		push_error("PINNED: a fresh electric lamp puts %s on its holder, not 35" % str(src))
		return false

	# The true negative for the whole PINNED idea: fabricate a magnitude that is *not* the shipped
	# one and watch the comparison refuse it, so a lane of equalities is not a lane of tautologies.
	if absf(_magnitude_of(w, LAMP) - 34.0) <= 1e-9:
		push_error("PINNED: the comparison cannot tell 35 from 34")
		return false
	print("  PINNED: candle %.0f, lamp %.0f, lantern %.0f, floodlight %.0f and the weapon light %.0f, each unchanged and each starting full" % [
		_magnitude_of(w, CANDLE), _magnitude_of(w, LAMP), _magnitude_of(w, LANTERN), _magnitude_of(w, FLOODLIGHT), _magnitude_of(w, WEAPON_LIGHT)])
	return true


# --- CONTENT ----------------------------------------------------------------------------------
#
# The content validator is shallow: it checks that `light` is an object and stops. So every number
# inside it is judged here instead, and both directions of the feed vocabulary are asserted the way
# check_m2_materials.gd's KINDS lane asserts the material kinds -- every kind the code ranks is
# declared by some shipped base, and every kind some base declares is one the code ranks. Neither
# list can see the other, which is the only reason this needs saying twice.
func _every_light_block_is_whole_and_every_fuel_has_a_mouth() -> bool:
	var w: Variant = _world()
	var findable: Dictionary = _findable(w)
	if findable.is_empty():
		push_error("CONTENT: no loot tables loaded, so the reachability half has nothing to judge")
		return false

	var lights: int = 0
	var burners: int = 0
	var fed: Dictionary = {}
	var plantable: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var id: String = String(e.get("id", ""))
		if not (e.get("light") is Dictionary):
			continue
		lights += 1
		var block: Dictionary = e["light"] as Dictionary
		var faults: Array[String] = _light_faults(block)
		if not faults.is_empty():
			push_error("CONTENT: '%s' declares light %s -- %s" % [id, str(block), ", ".join(faults)])
			return false
		if block.has("burnTicks"):
			burners += 1
		if block.has("feed"):
			fed[String(block["feed"])] = true
		var wearable: bool = SimInventory.EQUIP_SLOTS.has(String(e.get("equipSlot", "")))
		var attaches: bool = e.get("attachment") is Dictionary
		if not wearable and not attaches:
			plantable += 1
		if not findable.has(id):
			push_error("CONTENT: '%s' throws light and sits in no loot table -- complete, correct and unreachable" % id)
			return false

	var fuels: Dictionary = {}
	for entry2_v in SimItems.content_entries(w, "item"):
		var e2: Dictionary = entry2_v as Dictionary
		var kind: String = String(e2.get("lightFuel", ""))
		if kind.is_empty():
			continue
		if not SimLightMod.FUEL_KINDS.has(kind):
			push_error("CONTENT: '%s' is fuel of kind '%s', which SimLightModule.FUEL_KINDS does not rank" % [String(e2.get("id", "")), kind])
			return false
		if not findable.has(String(e2.get("id", ""))):
			push_error("CONTENT: the fuel '%s' sits in no loot table" % String(e2.get("id", "")))
			return false
		fuels[kind] = true

	# Both directions. A lamp that eats a kind nothing in the world is, and a fuel nothing in the
	# world eats, are the same defect written from opposite ends -- and each is exactly the shape
	# `item.battery` was in before this slice: shipped, findable, and food for nothing.
	for kind2 in fed.keys():
		if not fuels.has(String(kind2)):
			push_error("CONTENT: some lamp feeds on '%s' and no shipped item is '%s' -- a lamp nobody can ever refill" % [String(kind2), String(kind2)])
			return false
	for kind3 in fuels.keys():
		if not fed.has(String(kind3)):
			push_error("CONTENT: '%s' is fuel and no shipped lamp eats it -- that is what item.battery was" % String(kind3))
			return false
	for kind4 in SimLightMod.FUEL_KINDS:
		if not fuels.has(String(kind4)) or not fed.has(String(kind4)):
			push_error("CONTENT: FUEL_KINDS ranks '%s' and the roster has no fuel or no mouth for it -- a dead rung" % String(kind4))
			return false

	if lights < 15:
		push_error("CONTENT: only %d bases in the roster throw light; this lane is judging almost nothing" % lights)
		return false
	if burners < lights:
		push_error("CONTENT: %d of %d lights declare no burnTicks -- a light that never runs out is the defect this slice exists to fix" % [lights - burners, lights])
		return false
	if plantable < 2:
		push_error("CONTENT: only %d lights can be stood up rather than held; the floodlight verb has almost nothing to reach" % plantable)
		return false

	# The schema is where the shallow validator's blind spot is admitted, so it has to name the
	# keys this lane judges. A key in the code and not in the schema is a key content cannot use.
	var schema: String = _code_of("res://content/schemas/item.schema.json")
	for word in ["\"burnTicks\"", "\"feed\"", "\"lightFuel\""]:
		if not schema.contains(word):
			push_error("CONTENT: item.schema.json does not declare %s" % word)
			return false

	# The true negatives. Each fabricated block is one a real content edit could plausibly make,
	# and the predicate has to say no to every one of them -- and yes to an ordinary light, or it
	# is a predicate that refuses everything and proves nothing.
	for bad in [{}, {"magnitude": 0}, {"magnitude": -3}, {"magnitude": "bright"},
			{"magnitude": 10, "burnTicks": 0}, {"magnitude": 10, "burnTicks": -5},
			{"magnitude": 10, "burnTicks": 1.5}, {"magnitude": 10, "feed": "plutonium"},
			{"magnitude": 10, "feed": ""}, {"magnitude": 10, "burnTicks": 100, "feed": "petrol"}]:
		if _light_faults(bad as Dictionary).is_empty():
			push_error("CONTENT: the light predicate accepted %s" % str(bad))
			return false
	if not _light_faults({"magnitude": 12, "burnTicks": 6000, "feed": "cell"}).is_empty():
		push_error("CONTENT: the light predicate refuses an ordinary lamp, so it refuses everything")
		return false
	if findable.has("item.lamp.imaginary"):
		push_error("CONTENT: the table scan found an id that does not exist")
		return false
	print("  CONTENT: %d lights, every one with a burn clock and a table to be found in; %d feed kinds, each with fuel and a mouth; %d can be stood up" % [lights, fuels.size(), plantable])
	return true


# The one predicate, so the true negatives above are fed the same one the shipped bases went
# through. A `light` block is a magnitude above zero; `burnTicks` a whole number of ticks above
# zero when present; `feed` a kind the code ranks when present.
func _light_faults(block: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var mag: Variant = block.get("magnitude")
	if not (mag is float or mag is int) or float(mag) <= 0.0:
		return ["magnitude is not a number above zero"]
	if block.has("burnTicks"):
		var t: Variant = block["burnTicks"]
		if not (t is float or t is int):
			out.append("burnTicks is not a number")
		elif float(t) <= 0.0:
			out.append("burnTicks is not above zero")
		elif absf(float(t) - float(int(t))) > 0.0:
			out.append("burnTicks is not a whole number of ticks")
	if block.has("feed"):
		var f: String = String(block["feed"])
		if not SimLightMod.FUEL_KINDS.has(f):
			out.append("feed '%s' is not a kind SimLightModule.FUEL_KINDS ranks" % f)
		elif not block.has("burnTicks"):
			out.append("it declares what refills it and nothing that runs out")
	return out


func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


# --- SLOTS ------------------------------------------------------------------------------------
#
# The widened scan, at the helper's level -- HEADLAMP does it at the world's. A light in each of
# the four slots must reach `carried_magnitude`, and a light in a slot that is *not* in the list
# must not: without that second half, widening the list to all twelve slots would pass, and "every
# slot" is not what the owner decided.
func _the_head_and_the_eyes_are_finally_looked_in() -> bool:
	if not SimLightMod.LIGHT_SLOTS.has("head") or not SimLightMod.LIGHT_SLOTS.has("eyes"):
		push_error("SLOTS: LIGHT_SLOTS is %s -- the head and the eyes are still invisible to light" % str(SimLightMod.LIGHT_SLOTS))
		return false
	for slot in SimLightMod.LIGHT_SLOTS:
		if not SimInventory.EQUIP_SLOTS.has(String(slot)):
			push_error("SLOTS: LIGHT_SLOTS names '%s', which is not an equip slot at all" % String(slot))
			return false

	var by_slot: Dictionary = {}
	for pair in [[HEADLAMP, "head", 18.0], [CLIPLIGHT, "eyes", 7.0], [TORCH, "secondary", 25.0]]:
		var w: Variant = _world()
		if SimLightMod.carried_magnitude(w, w.player) != 0.0:
			push_error("SLOTS: a survivor carrying nothing reads a light")
			return false
		var item: int = _wear(w, String(pair[0]), String(pair[1]))
		if item < 0:
			return false
		var got: float = SimLightMod.carried_magnitude(w, w.player)
		if absf(got - float(pair[2])) > 1e-9:
			push_error("SLOTS: '%s' in the %s slot reads %.2f, not %.2f -- a light in a slot nothing walks" % [String(pair[0]), String(pair[1]), got, float(pair[2])])
			return false
		by_slot[String(pair[1])] = got

	# The true negative, and it needs a light that a slot outside the list will actually accept.
	# Fabricated rather than shipped: nothing in the roster declares a light on a torso piece, and
	# that is exactly why it has to be made up here.
	var neg: Variant = _world()
	(neg.content as Dictionary)["items/_light_burn_gate_fixture.json"] = _FIXTURE_LAMPS
	if _wear(neg, "item.gate.vestlamp", "torso") < 0:
		return false
	if SimLightMod.carried_magnitude(neg, neg.player) != 0.0:
		push_error("SLOTS: a lamp in the torso slot lit its holder -- LIGHT_SLOTS has been widened past what the owner decided")
		return false
	# The twin, identical in every number but the slot it declares, put on a head: that is what
	# proves the refusal above was about the slot rather than about the base being fabricated. A
	# second base rather than the same one moved, because `SimInventory.equip` refuses any slot
	# that is not the one content declares -- there is no moving it.
	if _wear(neg, "item.gate.headlamp", "head") < 0:
		return false
	if absf(SimLightMod.carried_magnitude(neg, neg.player) - 40.0) > 1e-9:
		push_error("SLOTS: the twin fixture lamp reads %.2f on a head, not 40" % SimLightMod.carried_magnitude(neg, neg.player))
		return false

	# A lamp in the pack is not a lamp in your hand -- the separation an implementation built on
	# `carried_items` would fail, and the one `item.battery` in a drawer depends on.
	var pocket: Variant = _world()
	if _give(pocket, LAMP) < 0:
		return false
	if SimLightMod.carried_magnitude(pocket, pocket.player) != 0.0:
		push_error("SLOTS: a lamp stowed in the pack lights the street from inside the pack")
		return false

	# Max, not sum, and the hands win a tie. Two lights in two different slots; the answer is the
	# brighter one, never the total, and never twice the radius.
	var both: Variant = _world()
	if _wear(both, HEADLAMP, "head") < 0 or _wear(both, TORCH, "secondary") < 0:
		return false
	var pair_mag: float = SimLightMod.carried_magnitude(both, both.player)
	if absf(pair_mag - 25.0) > 1e-9:
		push_error("SLOTS: a headlamp and a torch together read %.2f, want the brighter 25 -- max, not sum" % pair_mag)
		return false
	if int(SimLightMod.brightest_carried(both, both.player).get("item", -1)) < 0:
		push_error("SLOTS: the brightest carried light names no item, so the burn clock has nothing to spend")
		return false
	print("  SLOTS: %d slots walked; a headlamp reads %.0f on the head, a clip light %.0f on the eyes, a torch %.0f in a hand, a twin lamp on a torso nothing and the same numbers on a head everything, and two lights read the brighter" % [
		SimLightMod.LIGHT_SLOTS.size(), float(by_slot["head"]), float(by_slot["eyes"]), float(by_slot["secondary"])])
	return true


# --- BURN -------------------------------------------------------------------------------------
#
# The clock itself, and the three things about it that are easy to get wrong: it spends one tick a
# tick, it spends only the lamp that is *actually lighting somebody* (max-not-sum has consequences
# downstream), and when the wick is gone the next-brightest thing in your hands takes over rather
# than the survivor being left in the dark holding two lamps.
func _a_lamp_burns_only_while_it_is_the_one_alight() -> bool:
	var w: Variant = _world()
	var lamp: int = _wear(w, LAMP)
	if lamp < 0:
		return false
	var cap: int = SimLightMod.capacity_of(w, lamp)
	if cap <= 0:
		push_error("BURN: the electric lamp declares no burn clock at all")
		return false
	if SimLightMod.fuel_left(w, lamp) != cap:
		push_error("BURN: a lamp nobody has burned reads %d of %d" % [SimLightMod.fuel_left(w, lamp), cap])
		return false
	for _i in 40:
		w.step()
	if SimLightMod.fuel_left(w, lamp) != cap - 40:
		push_error("BURN: forty ticks cost %d ticks of wick, not forty" % (cap - SimLightMod.fuel_left(w, lamp)))
		return false

	# A lamp in the pack does not burn: the true negative, and the reason the clock reads
	# `light_source` rather than the pack.
	var stowed: int = _give(w, TORCH)
	if stowed < 0:
		return false
	var stowed_cap: int = SimLightMod.capacity_of(w, stowed)
	for _j in 40:
		w.step()
	if SimLightMod.fuel_left(w, stowed) != stowed_cap:
		push_error("BURN: a torch lying in the pack burned %d ticks down" % (stowed_cap - SimLightMod.fuel_left(w, stowed)))
		return false

	# The handover. A headlamp on the head beside the lamp in the hand burns nothing while the lamp
	# is lit, and the moment the lamp is out the headlamp is what the field sees. Written by driving
	# the clock down rather than by stepping a hundred thousand times, which is minutes of wall
	# clock -- and it is a pair across two *different* slots on purpose, so the handover is also the
	# widened scan being exercised by something other than SLOTS.
	var pair: Variant = _world()
	var big: int = _wear(pair, LAMP, "secondary")
	var small: int = _wear(pair, HEADLAMP, "head")
	if big < 0 or small < 0:
		return false
	var small_cap: int = SimLightMod.capacity_of(pair, small)
	pair.components.set_component(big, "lightFuel", {"ticksLeft": 3})
	var seen: Array = []
	pair.events.subscribe({"id": "gate.spent", "type": "light.spent", "handler": func(e: Dictionary) -> void: seen.append(e)})
	for _k in 3:
		pair.step()
	if seen.size() != 1 or int((seen[0] as Dictionary).get("item", -1)) != big:
		push_error("BURN: the lamp running out published %s" % str(seen))
		return false
	if not SimLightMod.spent(pair, big) or SimLightMod.light_reach_of(pair, big) != null:
		push_error("BURN: a lamp with no cell left still throws light")
		return false
	if SimLightMod.fuel_left(pair, small) != small_cap:
		push_error("BURN: the headlamp on the head burned %d ticks while the lamp in the hand was lit -- only the lit one burns" % (small_cap - SimLightMod.fuel_left(pair, small)))
		return false
	var now: Variant = pair.components.get_component(pair.player, "light_source")
	if not (now is Dictionary) or absf(float((now as Dictionary).get("magnitude", 0.0)) - 18.0) > 1e-9:
		push_error("BURN: with the lamp dead the survivor reads %s, not the headlamp's 18" % str(now))
		return false
	pair.step()
	if SimLightMod.fuel_left(pair, small) != small_cap - 1:
		push_error("BURN: the headlamp did not start burning once it became the light")
		return false

	# And the last one out leaves nobody lit rather than leaving a dead component behind.
	pair.components.set_component(small, "lightFuel", {"ticksLeft": 1})
	pair.step()
	if pair.components.has_component(pair.player, "light_source"):
		push_error("BURN: with every wick gone the survivor still carries a light source")
		return false

	# The weapon light: the near-orphan the fitted/removed/broke wiring has been waiting for. It
	# burns while the rifle is in hand, and when its cell goes the rifle throws nothing.
	var gun_world: Variant = _world()
	var rifle: int = _wear(gun_world, RIFLE, "primary")
	var part: int = SimItems.spawn_item(gun_world, WEAPON_LIGHT, {"tier": "scavenged"})
	if rifle < 0 or not SimAttachments.attach(gun_world, rifle, part, "underbarrel"):
		push_error("BURN: the weapon light would not fit the rifle")
		return false
	gun_world.events.drain()
	if absf(SimLightMod.carried_magnitude(gun_world, gun_world.player) - 16.0) > 1e-9:
		push_error("BURN: a rifle with a light on it reads %.2f, not 16" % SimLightMod.carried_magnitude(gun_world, gun_world.player))
		return false
	var part_cap: int = SimLightMod.capacity_of(gun_world, part)
	if part_cap <= 0:
		push_error("BURN: the weapon light declares no burn clock, so the attachment wiring is still being fed nothing")
		return false
	for _m in 20:
		gun_world.step()
	if SimLightMod.fuel_left(gun_world, part) != part_cap - 20:
		push_error("BURN: the fitted light burned %d ticks in twenty" % (part_cap - SimLightMod.fuel_left(gun_world, part)))
		return false
	gun_world.components.set_component(part, "lightFuel", {"ticksLeft": 1})
	gun_world.step()
	if gun_world.components.has_component(gun_world.player, "light_source"):
		push_error("BURN: a rifle whose light is flat still lights the room")
		return false
	print("  BURN: a lit lamp spends a tick a tick and a stowed one none; the lamp out, the headlamp on the head takes over and only then starts burning; the fitted weapon light burns and the rifle goes dark with it")
	return true


# --- HEADLAMP ---------------------------------------------------------------------------------
#
# The lane the owner asked for, and the one that could not be faked. SLOTS proves the *helper*
# answers differently once LIGHT_SLOTS is widened; that is worth nothing on its own, because a
# helper answering is not a district being lit. This measures the **lit radius off the shadowcast**
# -- `SimLight.refresh` walking `light_source` into a real cast, `lit_metres` reading it back --
# at midnight on an open map, with the bare survivor as the control.
func _a_headlamp_lights_the_district_from_the_head() -> bool:
	var midnight: int = Clock.tick_at_time_of_day(0.9)
	if Clock.ambient_light_at(midnight) > Clock.NIGHT_AMBIENT + 1e-9:
		push_error("HEADLAMP: the chosen tick is not dark (ambient %.4f)" % Clock.ambient_light_at(midnight))
		return false

	var bare: Variant = _world(9301, midnight)
	bare.step()
	var bare_radius: float = _lit_radius(bare)
	if bare_radius > 0.0:
		push_error("HEADLAMP: a survivor carrying nothing lights %.0f m of street" % bare_radius)
		return false

	var head: Variant = _world(9301, midnight)
	if _wear(head, HEADLAMP, "head") < 0:
		return false
	head.step()
	var head_radius: float = _lit_radius(head)
	var want: float = _magnitude_of(head, HEADLAMP)
	if head_radius < want - 1.5 or head_radius > want + 1.5:
		push_error("HEADLAMP: a headlamp on the head lights %.1f m of street, want about %.0f -- the widened scan did not reach the shadowcast" % [head_radius, want])
		return false
	if head.light.source_count() != 1:
		push_error("HEADLAMP: the light index holds %d sources with one headlamp on" % head.light.source_count())
		return false

	# Sight, one layer on: the reach a body has at its own feet is the max of ambient and lit, so
	# the headlamp has to move `sight_metres` too or it is light nobody can see by.
	var observer: Dictionary = {"range_metres": 30.0}
	var at: Dictionary = head.components.get_component(head.player, "position") as Dictionary
	var lit_sight: float = SimLightIndex.sight_metres(head, observer, float(at["x"]), float(at["y"]))
	var bare_at: Dictionary = bare.components.get_component(bare.player, "position") as Dictionary
	var dark_sight: float = SimLightIndex.sight_metres(bare, observer, float(bare_at["x"]), float(bare_at["y"]))
	if not (lit_sight > dark_sight + 1.0):
		push_error("HEADLAMP: sight at the survivor's feet is %.2f m with the headlamp and %.2f m without -- the lamp lights nothing anybody can see by" % [lit_sight, dark_sight])
		return false

	# The true negative that matters most, and it is the *whole* claim of the slice: the identical
	# lamp on a torso -- a slot LIGHT_SLOTS does not walk -- must leave the street exactly as dark
	# as carrying nothing. Without this, a scan widened to all twelve slots passes above.
	var torso: Variant = _world(9301, midnight)
	(torso.content as Dictionary)["items/_light_burn_gate_fixture.json"] = [
		{"id": "item.gate.vestlamp", "name": "Vest Lamp", "class": "tool", "size": {"w": 1, "h": 1},
			"massKg": 0.2, "equipSlot": "torso", "light": {"magnitude": 18, "burnTicks": 96000}},
	]
	if _wear(torso, "item.gate.vestlamp", "torso") < 0:
		return false
	torso.step()
	if _lit_radius(torso) > 0.0:
		push_error("HEADLAMP: the same lamp on a torso lit %.1f m -- the scan is wider than the decision" % _lit_radius(torso))
		return false

	# And a dead cell is a dark district: the burn clock reaching the shadowcast, not just the
	# helper. Same world, same lamp, one component driven flat.
	var flat: Variant = _world(9301, midnight)
	var worn: int = _wear(flat, HEADLAMP, "head")
	if worn < 0:
		return false
	flat.step()
	if _lit_radius(flat) <= 0.0:
		push_error("HEADLAMP: the control for the flat-cell case was dark to begin with")
		return false
	flat.components.set_component(worn, "lightFuel", {"ticksLeft": 1})
	flat.step()
	flat.step()
	if _lit_radius(flat) > 0.0:
		push_error("HEADLAMP: a headlamp with a flat cell still lights %.1f m of street" % _lit_radius(flat))
		return false
	print("  HEADLAMP: at midnight a bare survivor lights nothing and one on the head lights %.1f m of real shadowcast (sight at the feet %.1f m against %.1f); the same lamp on a torso lights nothing, and a flat cell puts the street back in the dark" % [
		head_radius, lit_sight, dark_sight])
	return true


# How far the light index actually reaches from the player, measured by walking east one metre at
# a time until `lit_metres` gives up. The index's own number, not the component's.
func _lit_radius(w: Variant) -> float:
	var at: Variant = w.components.get_component(w.player, "position")
	if not (at is Dictionary) or w.light == null:
		return -1.0
	var x: float = float((at as Dictionary)["x"])
	var y: float = float((at as Dictionary)["y"])
	var best: float = 0.0
	for step_m in range(1, 120):
		if float(w.light.lit_metres(x + float(step_m), y)) > 0.0:
			best = float(step_m)
		else:
			break
	return best


# --- FEED -------------------------------------------------------------------------------------
#
# `item.battery` shipped as an inert `material` in three loot tables with the description "A
# battery. Something here needs one." and nothing did. This is the something.
func _a_cell_refills_the_lamp_and_is_gone() -> bool:
	var w: Variant = _world()
	var lamp: int = _wear(w, LAMP)
	if lamp < 0:
		return false
	var cap: int = SimLightMod.capacity_of(w, lamp)
	var cell: int = _give(w, BATTERY)
	if cell < 0:
		return false
	if SimLightMod.fuel_kind_of(w, cell) != "cell":
		push_error("FEED: the battery reads fuel kind '%s'" % SimLightMod.fuel_kind_of(w, cell))
		return false

	# A full lamp refuses the cell, so a cell is never wasted on a lamp that did not need it --
	# and the word menu must not offer `use` either, because the menu and the intake are one
	# predicate.
	if SimLightMod.feed_target(w, w.player, cell) >= 0 or SimLightMod.can_use(w, w.player, cell):
		push_error("FEED: a full lamp took a cell it did not need")
		return false
	if SimInventory.verbs_for(w, w.player, cell).has("use"):
		push_error("FEED: the word menu offered 'use' on a cell with nowhere to go")
		return false

	w.components.set_component(lamp, "lightFuel", {"ticksLeft": 10})
	if SimLightMod.feed_target(w, w.player, cell) != lamp:
		push_error("FEED: a nearly flat lamp is not what the cell wants")
		return false
	if not SimInventory.verbs_for(w, w.player, cell).has("use"):
		push_error("FEED: the word menu will not offer 'use' on a cell that has somewhere to go")
		return false
	var stack_before: int = _count(w, BATTERY)
	if not SimLightMod.feed(w, w.player, cell):
		push_error("FEED: the cell would not go in")
		return false
	if SimLightMod.fuel_left(w, lamp) != cap:
		push_error("FEED: the fed lamp reads %d of %d" % [SimLightMod.fuel_left(w, lamp), cap])
		return false
	if _count(w, BATTERY) != stack_before - 1:
		push_error("FEED: the pack holds %d cells after feeding one, was %d -- the unit was not spent" % [_count(w, BATTERY), stack_before])
		return false

	# The lamp lights again, which is the half a "fuel went up" assertion cannot reach.
	var src: Variant = w.components.get_component(w.player, "light_source")
	if not (src is Dictionary) or absf(float((src as Dictionary).get("magnitude", 0.0)) - 35.0) > 1e-9:
		push_error("FEED: a refilled lamp puts %s on its holder" % str(src))
		return false

	# The wrong kind is refused, exactly the way a caliber is: an oil flask does not go in a
	# battery lamp and a cell does not go in an oil lantern.
	var mixed: Variant = _world()
	var lantern: int = _wear(mixed, LANTERN)
	if lantern < 0:
		return false
	mixed.components.set_component(lantern, "lightFuel", {"ticksLeft": 10})
	var wrong: int = _give(mixed, BATTERY)
	if wrong < 0:
		return false
	if SimLightMod.feed_target(mixed, mixed.player, wrong) >= 0 or SimLightMod.feed(mixed, mixed.player, wrong):
		push_error("FEED: a battery went into an oil lantern")
		return false
	var oil: int = _give(mixed, LAMP_OIL)
	if oil < 0:
		return false
	if SimLightMod.feed_target(mixed, mixed.player, oil) != lantern or not SimLightMod.feed(mixed, mixed.player, oil):
		push_error("FEED: lamp oil would not go into an oil lantern")
		return false
	if SimLightMod.fuel_left(mixed, lantern) != SimLightMod.capacity_of(mixed, lantern):
		push_error("FEED: the filled lantern is not full")
		return false

	# A candle takes nothing at all: single-use is a real state and not an oversight, and it is
	# the trade a candle makes against a lamp.
	var wax: Variant = _world()
	var stub: int = _wear(wax, CANDLE)
	if stub < 0:
		return false
	wax.components.set_component(stub, "lightFuel", {"ticksLeft": 1})
	for id in [BATTERY, LAMP_OIL, PROPANE]:
		var unit: int = _give(wax, String(id))
		if unit < 0:
			return false
		if SimLightMod.feed_target(wax, wax.player, unit) >= 0:
			push_error("FEED: a wax candle accepted %s" % String(id))
			return false

	# And a thing that is not fuel at all feeds nothing, so `use` on a helmet is still nothing.
	var helm: Variant = _world()
	if _wear(helm, LAMP) < 0:
		return false
	helm.components.set_component(int(SimLightMod.brightest_carried(helm, helm.player).get("item", -1)), "lightFuel", {"ticksLeft": 5})
	var lid: int = _give(helm, HELMET)
	if lid < 0:
		return false
	if SimLightMod.feed_target(helm, helm.player, lid) >= 0 or SimLightMod.can_use(helm, helm.player, lid):
		push_error("FEED: a bike helmet reads as fuel")
		return false
	# The screen's half, and the dead-socket rule applied to it: a read model nothing reads is a
	# read model that will be wrong the first time anybody looks. `fuel_clause` has exactly one
	# reader -- the inspect pane -- and it has to walk all four words and stay a word throughout,
	# because the pane is under the full digit ban (check_inventory.gd's INSPECT lane).
	var pane_world: Variant = _world()
	var seen_words: Dictionary = {}
	var pane_lamp: int = _give(pane_world, LAMP)
	if pane_lamp < 0:
		return false
	var pane_cap: int = SimLightMod.capacity_of(pane_world, pane_lamp)
	for left in [pane_cap, pane_cap / 4, pane_cap / 16, 0]:
		pane_world.components.set_component(pane_lamp, "lightFuel", {"ticksLeft": int(left)})
		var view: Dictionary = SimInventory.inspect_view(pane_world, pane_world.player, pane_lamp)
		if not view.has("fuel"):
			push_error("FEED: the inspect pane says nothing about a lamp's fuel -- fuel_clause has no reader")
			return false
		var word: String = String(view["fuel"])
		if word.is_empty():
			push_error("FEED: a lamp with %d ticks of wick reads no fuel word at all" % int(left))
			return false
		for ch in word:
			if ch >= "0" and ch <= "9":
				push_error("FEED: the fuel clause reads '%s', which carries a digit" % word)
				return false
		seen_words[word] = true
	if seen_words.size() < 4:
		push_error("FEED: the fuel clause only ever said %s -- fewer words than states" % str(seen_words.keys()))
		return false
	# And a thing that is not a lamp says nothing rather than saying "dark", which is the true
	# negative that keeps the word off every other item in the game.
	var rag: int = _give(pane_world, HELMET)
	if rag < 0:
		return false
	if String(SimInventory.inspect_view(pane_world, pane_world.player, rag).get("fuel", "x")) != "":
		push_error("FEED: a bike helmet's inspect pane has a fuel word on it")
		return false
	print("  FEED: a flat lamp takes a cell and lights again, the stack loses exactly one, a full lamp and a candle both refuse, a cell will not go in an oil lantern nor oil in a torch, the word menu offers 'use' on exactly the cells that have somewhere to go, and the pane says %s and nothing at all about a helmet" % str(seen_words.keys()))
	return true


func _count(w: Variant, base_id: String) -> int:
	var total: int = 0
	for item in SimInventory.carried_items(w, w.player):
		var base: Variant = w.components.get_component(int(item), "itemBase")
		if not (base is Dictionary) or String((base as Dictionary).get("baseId", "")) != base_id:
			continue
		var st: Variant = w.components.get_component(int(item), "stack")
		total += int((st as Dictionary).get("count", 1)) if st is Dictionary else 1
	return total


# --- PLANT ------------------------------------------------------------------------------------
#
# `item.floodlight.rigged` has sat in the military cache's loot table with no equipSlot and no verb
# since lights shipped: findable, carriable, and good for absolutely nothing. It now stands up.
func _the_floodlight_can_at_last_be_stood_up() -> bool:
	var w: Variant = _world()
	var flood: int = _give(w, FLOODLIGHT)
	if flood < 0:
		return false
	if not SimLightMod.is_plantable(w, flood):
		push_error("PLANT: the floodlight does not read as plantable")
		return false
	# A thing you *can* wear is not a thing you stand up, or every torch would be furniture.
	var torch: int = _give(w, TORCH)
	if torch < 0 or SimLightMod.is_plantable(w, torch):
		push_error("PLANT: a hand torch reads as plantable")
		return false
	if not SimFortify.can_place_light(w, w.player):
		push_error("PLANT: a body carrying a floodlight on open ground cannot stand it up")
		return false
	if not SimInventory.verbs_for(w, w.player, flood).has("use"):
		push_error("PLANT: the word menu will not offer 'use' on a floodlight there is room for")
		return false

	var planted: Array = []
	w.events.subscribe({"id": "gate.planted", "type": "light.planted", "handler": func(e: Dictionary) -> void: planted.append(e)})
	w.commands.push({"type": "item.use", "item": flood})
	w.step()
	if not w.components.has_component(w.player, "construct"):
		push_error("PLANT: 'use' on a floodlight started no channel -- the verb is not reachable from the menu")
		return false
	for _i in SimFortify.CHANNEL_TICKS + 2:
		w.step()
	if planted.size() != 1 or int((planted[0] as Dictionary).get("entity", -1)) != flood:
		push_error("PLANT: the channel finished and published %s" % str(planted))
		return false
	if not w.components.has_component(flood, "placedLight") or not w.components.has_component(flood, "position"):
		push_error("PLANT: the planted floodlight is not standing anywhere")
		return false
	if SimInventory.owns(w, w.player, flood):
		push_error("PLANT: the floodlight is standing in the yard and still in the pack")
		return false
	var src: Variant = w.components.get_component(flood, "light_source")
	if not (src is Dictionary) or absf(float((src as Dictionary).get("magnitude", 0.0)) - 90.0) > 1e-9:
		push_error("PLANT: the standing floodlight throws %s, not 90" % str(src))
		return false
	# Furniture, not loot: E must not pick the thing back up off its own stand.
	if SimInventory.ground_items(w).has(flood):
		push_error("PLANT: the standing floodlight is on the ground-item list, so E picks it up")
		return false
	# It burns where it stands, and gas puts it back on.
	var cap: int = SimLightMod.capacity_of(w, flood)
	if cap <= 0:
		push_error("PLANT: a planted floodlight has no burn clock")
		return false
	# Read from where it is rather than from the capacity: it has been alight since the tick the
	# channel finished, which was partway through the loop above, so `cap` is no longer the
	# baseline and an assertion that thinks it is goes red blaming code that is correct.
	var before: int = SimLightMod.fuel_left(w, flood)
	if before >= cap:
		push_error("PLANT: a floodlight that has been standing lit has burned nothing")
		return false
	for _j in 10:
		w.step()
	if SimLightMod.fuel_left(w, flood) != before - 10:
		push_error("PLANT: ten ticks standing lit cost %d of the floodlight's gas" % (before - SimLightMod.fuel_left(w, flood)))
		return false
	w.components.set_component(flood, "lightFuel", {"ticksLeft": 1})
	w.step()
	if w.components.has_component(flood, "light_source"):
		push_error("PLANT: a floodlight out of gas is still lit")
		return false
	var bottle: int = _give(w, PROPANE)
	if bottle < 0:
		return false
	if SimLightMod.feed_target(w, w.player, bottle) != flood:
		push_error("PLANT: a propane bottle beside a dead floodlight has nowhere to go")
		return false
	if not SimLightMod.feed(w, w.player, bottle):
		push_error("PLANT: the bottle would not go into the floodlight")
		return false
	if not w.components.has_component(flood, "light_source") or SimLightMod.fuel_left(w, flood) != cap:
		push_error("PLANT: the refilled floodlight is not lit and full")
		return false

	# The true negatives. Nothing plantable in the pack, and a tile that is not open ground.
	var empty_handed: Variant = _world()
	if SimFortify.can_place_light(empty_handed, empty_handed.player) or SimFortify.place_light(empty_handed, empty_handed.player):
		push_error("PLANT: a body carrying no floodlight stood one up")
		return false
	var blocked: Variant = _world()
	if _give(blocked, FLOODLIGHT) < 0:
		return false
	var face: Vector2i = Vector2i(9, 12)
	blocked.tilemap.tiles[face.y * int(blocked.tilemap.w) + face.x] = SimTileMap.Tile.Wall
	if SimFortify.can_place_light(blocked, blocked.player) or SimFortify.place_light(blocked, blocked.player):
		push_error("PLANT: a floodlight was stood up inside a wall")
		return false
	# And a bottle of gas is not offered anywhere near a floodlight that is still full.
	var full: Variant = _world()
	if _give(full, PROPANE) < 0:
		return false
	print("  PLANT: 'use' stands a floodlight on the tile in front over %d ticks, it leaves the pack, lights at 90, is not loot, burns where it stands, goes dark and takes a bottle of gas; an empty hand and a walled tile both refuse" % SimFortify.CHANNEL_TICKS)
	return true


# --- SIPHON -----------------------------------------------------------------------------------
#
# `item.jerrycan.empty` is what a poured can leaves and it sits in the industrial table in its own
# right, and until this slice **nothing in the game could fill one**. The refuel path read
# backwards: a body at the nose of a parked engine with an empty can draws a canful out.
func _an_empty_can_can_at_last_be_filled() -> bool:
	var w: Variant = _car_world()
	var car: int = _car_of(w)
	if car < 0:
		return false
	var v: Dictionary = w.components.get_component(car, "vehicle") as Dictionary
	var tank: float = float(SimVehicles.drive_of(SimVehicles.class_of(w, "vehicle.sedan"))["tank"])

	# The reverse lookup, with its own true negatives: the pair is found through `empties` rather
	# than through a second content key, and an id that is nobody's empties finds nothing.
	if SimVehicles.siphon_fill_of(w, EMPTY_CAN) != FULL_CAN:
		push_error("SIPHON: the empty can fills back into '%s'" % SimVehicles.siphon_fill_of(w, EMPTY_CAN))
		return false
	for not_empty in ["item.water.bottle.empty", "item.scrap.metal", "item.not.a.real.base", ""]:
		if not SimVehicles.siphon_fill_of(w, String(not_empty)) .is_empty():
			push_error("SIPHON: '%s' reads as a can that fills with fuel" % String(not_empty))
			return false

	_stand_at_nose(w)
	v["fuel"] = tank
	# Nothing to put it in: the refusal that has to come before any of the rest.
	if SimVehicles.siphon_problem(w, w.player, car) != "no empty can":
		push_error("SIPHON: with nothing to fill the problem reads '%s'" % SimVehicles.siphon_problem(w, w.player, car))
		return false
	var can: int = _give(w, EMPTY_CAN)
	if can < 0:
		return false
	if not SimVehicles.siphon_problem(w, w.player, car).is_empty():
		push_error("SIPHON: at the nose of a full tank with an empty can, the draw is refused: %s" % SimVehicles.siphon_problem(w, w.player, car))
		return false

	var drawn: Array = []
	w.events.subscribe({"id": "gate.siphoned", "type": "vehicle.siphoned", "handler": func(e: Dictionary) -> void: drawn.append(e)})
	# Through the E ladder, not through the function: a verb only a gate can reach is not a verb.
	w.commands.push({"type": "use.context"})
	w.step()
	if not w.components.has_component(w.player, "siphon"):
		push_error("SIPHON: E at the nose with an empty can started no draw -- the verb is unreachable")
		return false
	var steps: int = 0
	while w.components.has_component(w.player, "siphon") and steps < SimVehicles.SIPHON_TICKS + 10:
		w.step()
		steps += 1
	if drawn.size() != 1:
		push_error("SIPHON: %d draws finished in %d steps" % [drawn.size(), steps])
		return false
	if absf(float(v["fuel"]) - (tank - 10.0)) > 1e-9:
		push_error("SIPHON: the tank reads %.4f, want %.0f" % [float(v["fuel"]), tank - 10.0])
		return false
	if w.components.has_component(can, "itemBase"):
		push_error("SIPHON: the empty can is still an item after being filled")
		return false
	if _count(w, FULL_CAN) != 1 or _count(w, EMPTY_CAN) != 0:
		push_error("SIPHON: the pack holds %d full cans and %d empty ones" % [_count(w, FULL_CAN), _count(w, EMPTY_CAN)])
		return false
	# The can that came out is a can that goes back in: the round trip, which is what makes the
	# siphon part of the fuel economy rather than a one-way trick.
	if SimVehicles.fuel_spec(w, FULL_CAN) == null:
		push_error("SIPHON: what came out is not a can anything can pour")
		return false

	# Refusals, each keeping the tank and the can. A tank too shallow to fill a can is the one
	# that matters: whole can or nothing, the pour's rule read backwards.
	var shallow: Variant = _car_world()
	var car2: int = _car_of(shallow)
	var v2: Dictionary = shallow.components.get_component(car2, "vehicle") as Dictionary
	_stand_at_nose(shallow)
	if _give(shallow, EMPTY_CAN) < 0:
		return false
	v2["fuel"] = 9.5
	if SimVehicles.siphon_problem(shallow, shallow.player, car2) != "not enough in the tank to fill it":
		push_error("SIPHON: a tank with nine and a half litres reads '%s'" % SimVehicles.siphon_problem(shallow, shallow.player, car2))
		return false
	shallow.commands.push({"type": "use.context"})
	shallow.step()
	if shallow.components.has_component(shallow.player, "siphon") or absf(float(v2["fuel"]) - 9.5) > 1e-9:
		push_error("SIPHON: a shallow tank was siphoned anyway")
		return false
	v2["fuel"] = 10.0
	if not SimVehicles.siphon_problem(shallow, shallow.player, car2).is_empty():
		push_error("SIPHON: exactly a canful is refused: '%s'" % SimVehicles.siphon_problem(shallow, shallow.player, car2))
		return false

	# A body holding a full can came to fill the car, so E pours rather than drawing. The ladder's
	# decision, not the siphon's -- asked directly, the draw is still legal.
	var both: Variant = _car_world()
	var car3: int = _car_of(both)
	var v3: Dictionary = both.components.get_component(car3, "vehicle") as Dictionary
	_stand_at_nose(both)
	v3["fuel"] = float(SimVehicles.drive_of(SimVehicles.class_of(both, "vehicle.sedan"))["tank"])
	if _give(both, EMPTY_CAN) < 0 or _give(both, FULL_CAN) < 0:
		return false
	both.commands.push({"type": "use.context"})
	both.step()
	if both.components.has_component(both.player, "siphon"):
		push_error("SIPHON: a body carrying fuel to a full tank emptied it instead of looking")
		return false
	if SimVehicles.siphon_problem(both, both.player, car3) != "":
		push_error("SIPHON: asked directly, the draw is refused for carrying a full can: '%s'" % SimVehicles.siphon_problem(both, both.player, car3))
		return false

	# A grab stops the draw the way it stops a pour.
	var grabbed: Variant = _car_world()
	var car4: int = _car_of(grabbed)
	(grabbed.components.get_component(car4, "vehicle") as Dictionary)["fuel"] = 40.0
	_stand_at_nose(grabbed)
	if _give(grabbed, EMPTY_CAN) < 0:
		return false
	if not SimVehicles.begin_siphon(grabbed, grabbed.player, car4):
		push_error("SIPHON: the interrupt fixture could not start a draw")
		return false
	grabbed.events.publish({"type": "grab.started", "victim": grabbed.player})
	grabbed.step()
	if grabbed.components.has_component(grabbed.player, "siphon"):
		push_error("SIPHON: a grab did not stop the draw")
		return false
	print("  SIPHON: E at the nose fills an empty can from a sedan in %d steps, ten litres off the tank and a pourable can in the pack; a tank under a canful, a hand already holding fuel and a grab each refuse, and the reverse lookup finds one full base and no bottle" % steps)
	return true


# A world with a sedan parked nose-north, borrowed wholesale from check_vehicles.gd's fixture so
# the two gates are looking at the same car.
func _car_world() -> Variant:
	var fixture: Dictionary = {
		"seed": 9401, "tick_hz": 20,
		"map": {"width": MAP, "height": MAP, "walls": []},
		"player": {"id": 0, "x": 5.0, "y": 5.0, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	var map: Variant = SimTileMap.blank_map(MAP, MAP)
	SimBoot.attach_kernel(w, map)
	SimVehicles.register_module(w)
	SimAttention.register_module(w, map)
	var rec: Dictionary = {"x": CAR_X, "y": CAR_Y, "w": 2, "h": 5, "axis": "ns", "class": "vehicle.sedan", "facing": "n"}
	for ty in range(int(rec["y"]), int(rec["y"]) + int(rec["h"])):
		for tx in range(int(rec["x"]), int(rec["x"]) + int(rec["w"])):
			map.tiles[ty * int(map.w) + tx] = SimTileMap.Tile.Low
	(map.vehicles as Array).append(rec)
	SimVehicles.spawn_from_manifest(w, map)
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimLightMod.register_module(w)
	SimFortify.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	for c in w.components.query(["vehicle"]):
		var hv: Dictionary = w.components.get_component(int(c), "vehicle") as Dictionary
		hv["integrity"] = SimVehicles.INTEGRITY_MAX
	var pack: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, pack):
		push_error("SIPHON: could not equip the pack")
	w.events.drain()
	return w


func _car_of(w: Variant) -> int:
	for c in w.components.query(["vehicle"]):
		return int(c)
	push_error("SIPHON: the fixture parked no car")
	return -1


func _stand_at_nose(w: Variant) -> void:
	var p: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	p["x"] = float(CAR_X) + 1.0
	p["y"] = float(CAR_Y) - 0.5


# --- NIGHT ------------------------------------------------------------------------------------
#
# The balance claim, and it is **measured rather than authored**: the length of the dark stretch is
# computed off SimClock here rather than remembered, so a change to dawn or dusk moves this lane's
# yardstick with it instead of leaving a stale number in a comment. Then every shipped burn time is
# judged against it.
#
# What the numbers say. A wax candle is a third of a night and single-use, so a stack of four is a
# night and a bit of very little light. The electric lamp is exactly one night on one cell: brightest
# in the game to carry, and it costs a battery every night you use it -- which is the whole point,
# because before this slice it was strictly better than everything for ever. The oil lantern is a
# third longer than a night at two thirds the reach, which is the trade that makes it worth finding
# lamp oil for. The floodlight is one night of the yard lit per bottle of gas.
func _the_shipped_burn_times_are_measured_against_the_dark() -> bool:
	# Counted, not spanned. The dark stretch runs from dusk through midnight into dawn, so it wraps
	# the day's own zero -- a first-and-last scan reports the whole day, which is what the first cut
	# of this lane did and what the gate then said out loud. One sample a second, summed.
	const SAMPLE: int = Clock.TICK_HZ
	var dark_samples: int = 0
	var dim_samples: int = 0
	for t in range(0, Clock.DAY_TICKS, SAMPLE):
		var ambient: float = Clock.ambient_light_at(t)
		if ambient <= Clock.NIGHT_AMBIENT + 1e-9:
			dark_samples += 1
		if ambient < 0.5:
			dim_samples += 1
	var night: int = dark_samples * SAMPLE
	var gloom: int = dim_samples * SAMPLE
	if night <= 0:
		push_error("NIGHT: no part of the day reads as dark, so this lane has nothing to measure against")
		return false
	if night < Clock.DAY_TICKS / 8 or night > Clock.DAY_TICKS / 2:
		push_error("NIGHT: the measured dark stretch is %d of %d ticks, which is not a night" % [night, Clock.DAY_TICKS])
		return false
	if gloom <= night:
		push_error("NIGHT: the dim stretch (%d) is no longer than the dark one (%d), so dusk and dawn are measuring nothing" % [gloom, night])
		return false

	var w: Variant = _world()
	# A light that is meant to see you through a night has to. A light that is not -- the candle,
	# the flare, the lighter -- has to be honestly short rather than almost enough.
	var through: Array[String] = [LAMP, LANTERN, FLOODLIGHT]
	for id in through:
		var burn: int = _burn_of(w, String(id))
		if burn < night:
			push_error("NIGHT: '%s' burns %d ticks against a %d-tick night -- a light sold as lasting does not last one" % [String(id), burn, night])
			return false
	if _burn_of(w, CANDLE) >= night:
		push_error("NIGHT: the wax candle outlasts a whole night, so nothing about it is a trade against the lamp")
		return false
	if _burn_of(w, LANTERN) <= _burn_of(w, LAMP):
		push_error("NIGHT: the oil lantern burns %d against the brighter lamp's %d -- the dimmer light has to last longer or there is no reason to carry it" % [_burn_of(w, LANTERN), _burn_of(w, LAMP)])
		return false
	if _magnitude_of(w, LANTERN) >= _magnitude_of(w, LAMP):
		push_error("NIGHT: the lantern is no dimmer than the lamp, so the longer burn is a free upgrade")
		return false

	# Every shipped light, measured: nothing may burn so long that it is the old for-ever wearing a
	# number. Four nights is the ceiling, which the storm lantern sits just under.
	var longest: int = 0
	var longest_id: String = ""
	var shortest: int = 1 << 30
	var shortest_id: String = ""
	var judged: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not (e.get("light") is Dictionary):
			continue
		var ticks: int = int((e["light"] as Dictionary).get("burnTicks", 0))
		if ticks <= 0:
			continue
		judged += 1
		if ticks > longest:
			longest = ticks
			longest_id = String(e.get("id", ""))
		if ticks < shortest:
			shortest = ticks
			shortest_id = String(e.get("id", ""))
	if judged == 0:
		push_error("NIGHT: nothing in the roster declares a burn time, so this lane is judging nothing")
		return false
	if longest > night * 4:
		push_error("NIGHT: '%s' burns %d ticks, more than four nights -- that is the old for-ever with a number on it" % [longest_id, longest])
		return false
	if shortest >= night:
		push_error("NIGHT: the shortest light in the game ('%s') still outlasts a night, so nothing is a short light" % shortest_id)
		return false
	print("  NIGHT: the dark measures %d ticks off SimClock (%.1f in-game hours, %.1f counting dusk and dawn); the lamp burns %.1f nights on a cell, the lantern %.1f at two thirds the reach, the candle %.2f, and across %d lights the range is '%s' to '%s'" % [
		night, float(night) * 24.0 / float(Clock.DAY_TICKS), float(gloom) * 24.0 / float(Clock.DAY_TICKS),
		float(_burn_of(w, LAMP)) / float(night),
		float(_burn_of(w, LANTERN)) / float(night), float(_burn_of(w, CANDLE)) / float(night),
		judged, shortest_id, longest_id])
	return true
