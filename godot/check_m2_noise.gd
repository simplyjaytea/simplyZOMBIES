extends SceneTree
# Noise that is an item -- docs/03-attention.md#playing-the-field, and the owner's decision of
# 2026-09-12.
#
# What this slice fixed. The attention field is the kernel mechanic, it has been finished and gated
# since Milestone 1, and **the only thing in the game that spent an item to make a noise was firing
# a gun**. Everything else that published `noise.emitted` was a system: melee on a connect, fortify
# on a construct and on its alarm, the screamer, footsteps, infection, the weather, the jobs, the
# cars, world.gd's shout. docs/03 has listed bait -- "a wind-up noisemaker, a lit lamp on a timer, a
# hung carcass" -- as the whole skill expression of the field since the field was specified, and the
# two distraction devices that existed were world-entity singletons conjured out of nothing.
#
# What it deliberately did **not** do. The alarm line and the noisemaker stay free and unchanged.
# The build-materials slice left five verbs free on purpose and `check_m2_materials.gd`'s PINNED
# lane asserts by name that none of them has since grown a price; this gate's own PINNED lane
# asserts the same thing from the other side -- that those two still do exactly what they did, at
# the numbers they did it at.
#
# The lane that matters most is HORDE, and it is the reason the rest of this file exists. A helper
# that returns 180.0 is not a noise; a component that says `ambient: 180` is not a noise either.
# HORDE measures **where twelve shamblers are standing**, before and after the fuse burns down, and
# it anchors that to the field (`noise_at`) and to the clock (`state_of`) rather than to a second
# run of the same code -- comparing two runs of one code path catches non-determinism and nothing
# else.
#
# Every lane carries a true negative.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimFortify = preload("res://sim/modules/fortify.gd")
const SimNoise = preload("res://sim/modules/noise_device.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimShambler = preload("res://sim/modules/shambler.gd")
const SimCombat = preload("res://sim/combat.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const Clock = preload("res://sim/time/clock.gd")

# The eight bases this slice ships. Fixtures, not welds -- the sim names none of them, and the
# predicates are all "declares a noise block and cannot be worn" -- but a gate has to hold something
# concrete or none of this is falsifiable.
const FIRECRACKER: String = "item.firecracker.string"
const AIRHORN: String = "item.airhorn.canister"
const CLOCKWORK: String = "item.alarmclock.windup"
const RADIO: String = "item.radio.transistor"
const CARALARM: String = "item.caralarm.salvaged"
const SIREN: String = "item.siren.handcrank"
const BELL: String = "item.bell.wind"
const BLASTCAP: String = "item.blastcap.quarry"

# Things that are emphatically not bait, for the negatives: a bottle you drink, a lamp you stand up
# (plantable, and by the *other* module's verb), and a torch you hold.
const BOTTLE: String = "item.water.bottle"
const FLOODLIGHT: String = "item.floodlight.rigged"
const TORCH: String = "item.torch.handheld"

# docs/03's noise table, in the units the "scale and calibration" section calibrated. Every shipped
# magnitude has to be one of these rungs: the table was authored as ratios and the ratios are the
# whole design, so a device at 137 is a number somebody invented rather than a thing that sounds
# like something. Written here rather than read out of content, because a table read from the thing
# it is judging judges nothing.
const DOCS_03_NOISE_TABLE: Array[float] = [
	1.0, 2.0, 4.0, 6.0, 8.0, 25.0, 30.0, 40.0, 45.0, 120.0, 180.0, 220.0, 300.0, 350.0, 400.0,
]

const MAP: int = 64
# Where the bait goes in the HORDE lane, and how far out the ring of dead starts.
const BAIT_X: int = 32
const BAIT_Y: int = 32
const RING_METRES: float = 18.0
const RING_BODIES: int = 12


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_free_bait_is_still_free_and_still_works() and ok
	ok = _every_noise_block_is_whole_and_every_device_can_be_found() and ok
	ok = _every_magnitude_is_a_rung_of_the_table() and ok
	ok = _a_device_is_placed_by_the_verb_that_is_offered_for_it() and ok
	ok = _the_fuse_burns_down_and_the_racket_runs_out() and ok
	ok = _the_horde_walks_to_the_thing_that_is_sounding() and ok
	ok = _a_device_comes_back_up_and_goes_down_again() and ok
	ok = _the_screen_is_told_in_one_word() and ok
	if ok:
		print("M2_NOISE_OK pinned content table place clock horde lift hud")
		quit(0)
	else:
		push_error("M2_NOISE_FAIL")
		quit(1)


# --- fixtures ---------------------------------------------------------------------------------

# A survivor on open ground with the kernel attached, so `w.field` is the real attention field and
# a lane that wants to know what the district can hear has somewhere to ask. The pack is not
# decoration: pockets are 4x2 and a hand-crank siren is 2x3.
func _world(seed_val: int = 5150, pack: String = "item.pack.hiking") -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": MAP, "height": MAP, "walls": []},
		"player": {"id": 0, "x": float(BAIT_X) - 0.5, "y": float(BAIT_Y) + 0.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	var map: Variant = SimTileMap.blank_map(MAP, MAP)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimFortify.register_module(w)
	SimNoise.register_module(w)
	SimAttention.register_module(w, map)
	# Registered in every fixture, not only HORDE's: it acts on entities carrying `shambler` and
	# there are none anywhere else, and a fixture that differed between the lane that measures
	# behaviour and the lanes that measure the mechanism would be two fixtures pretending to be one.
	SimShambler.register_module(w, map)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	# Facing east, at (BAIT_X - 0.5, BAIT_Y + 0.5): the tile in front is (BAIT_X, BAIT_Y).
	w.components.set_component(w.player, "facing", {"radians": 0.0})
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	if not pack.is_empty():
		var bag: int = SimItems.spawn_item(w, pack, {"tier": "scavenged"})
		if not SimInventory.equip(w, w.player, bag):
			push_error("the fixture pack would not go on")
	w.events.drain()
	return w


func _give(w: Variant, id: String) -> int:
	var item: int = SimItems.spawn_item(w, id, {"tier": "scavenged"})
	if not SimInventory.stow(w, w.player, item):
		push_error("the fixture '%s' would not go in a pocket" % id)
		return -1
	return item


func _entry(w: Variant, id: String) -> Dictionary:
	var e: Variant = SimItems.content_entry(w, "item", id)
	return (e as Dictionary) if e is Dictionary else {}


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


func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _ambient_of(w: Variant, device: int) -> float:
	var em: Variant = w.components.get_component(device, "attention_emitter")
	if not (em is Dictionary):
		return -1.0
	return float((em as Dictionary).get("ambient", -1.0))


# --- PINNED -----------------------------------------------------------------------------------
#
# Additive or it is a rebalance, and the owner said so in as many words: the existing alarm line and
# noisemaker stay free and unchanged. `check_m2_materials.gd`'s PINNED lane asserts that from the
# recipe table's side -- no price has appeared for any of the five free verbs. This asserts it from
# the behaviour's side, which is the half a recipe table cannot see: the bait still goes down for
# nothing, still reads 45 at the field, still runs for its twelve thousand ticks, and the alarm line
# still trips at 8.
func _the_free_bait_is_still_free_and_still_works() -> bool:
	var lane: String = "PINNED"
	for verb in SimFortify.RECIPES.keys():
		if ["window", "alarm", "noisemaker", "wind", "camp", "noisedevice", "noiselift"].has(String(verb)):
			push_error("%s: '%s' has acquired a price ('%s') -- the free verbs were free before this slice and the owner kept them free" % [lane, String(verb), String(SimFortify.RECIPES[verb])])
			return false
	if absf(float(SimFortify.NOISEMAKER_MAG) - 45.0) > 1e-9 or int(SimFortify.NOISEMAKER_TICKS) != 12000:
		push_error("%s: the shipped noisemaker is %.1f for %d ticks and it was 45 for 12000" % [lane, float(SimFortify.NOISEMAKER_MAG), int(SimFortify.NOISEMAKER_TICKS)])
		return false
	if absf(float(SimFortify.ALARM_NOISE) - 8.0) > 1e-9:
		push_error("%s: the alarm line trips at %.1f and it tripped at 8" % [lane, float(SimFortify.ALARM_NOISE)])
		return false

	# And it still goes down, out of an empty pack, and the field still hears it. A pack with
	# nothing in it is the point: the free bait costs nothing, and a lane that handed it a
	# firecracker first would not be able to tell.
	var w: Variant = _world(5151)
	if SimInventory.carried_items(w, w.player).size() != 1:
		push_error("%s: the fixture pack is not empty, so 'it cost nothing' is not what this measures" % lane)
		return false
	w.commands.push({"type": "bait.noisemaker.place", "tx": BAIT_X, "ty": BAIT_Y})
	for _i in SimFortify.CHANNEL_TICKS + 2:
		w.step()
	var bait: Array[int] = w.components.query(["noisemaker"])
	if bait.size() != 1:
		push_error("%s: %d noisemakers after a full channel with an empty pack" % [lane, bait.size()])
		return false
	if absf(_ambient_of(w, bait[0]) - 45.0) > 1e-9:
		push_error("%s: the free noisemaker is emitting %.2f, not 45" % [lane, _ambient_of(w, bait[0])])
		return false
	w.step()
	if w.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5) < 20.0:
		push_error("%s: the free noisemaker reads %.2f at the field" % [lane, w.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5)])
		return false
	# The true negative for the free half: the *new* verbs are the ones that cost an item, and this
	# is where a lane of "nothing costs anything" would pass on a slice that shipped nothing. An
	# empty pack cannot place a device.
	if SimFortify.can_place_noise(w, w.player):
		push_error("%s: a body carrying no device at all can still place one -- the new verb costs nothing either, so this slice shipped no item" % lane)
		return false
	print("  %s: the alarm line still trips at %.0f, the free noisemaker still goes down out of an empty pack at %.0f for %d ticks, and the new verb still needs a thing in the pack" % [lane, float(SimFortify.ALARM_NOISE), float(SimFortify.NOISEMAKER_MAG), int(SimFortify.NOISEMAKER_TICKS)])
	return true


# --- CONTENT ----------------------------------------------------------------------------------
#
# The Godot content validator is shallow: it checks that `noise` is an object and stops. Every
# number inside it is judged here instead, in both directions, the way check_m2_light_burn.gd's
# CONTENT lane judges a `light` block -- and with the reachability half `check_m2_attach.gd` set,
# because a device in no loot table is the exact shape `item.floodlight.rigged` was in for the whole
# of this milestone: shipped, correct, and good for nothing.
func _every_noise_block_is_whole_and_every_device_can_be_found() -> bool:
	var lane: String = "CONTENT"
	var w: Variant = _world(5152)
	var findable: Dictionary = _findable(w)
	if findable.is_empty():
		push_error("%s: no loot tables loaded, so the reachability half has nothing to judge" % lane)
		return false

	var devices: int = 0
	var delayed: int = 0
	var instant: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var id: String = String(e.get("id", ""))
		if not (e.get("noise") is Dictionary):
			continue
		devices += 1
		var block: Dictionary = e["noise"] as Dictionary
		var faults: Array[String] = _noise_faults(block)
		if not faults.is_empty():
			push_error("%s: '%s' declares noise %s -- %s" % [lane, id, str(block), ", ".join(faults)])
			return false
		if int(block.get("delayTicks", 0)) > 0:
			delayed += 1
		else:
			instant += 1
		# A device is a thing you stand on a tile. Wearing one would mean `is_placeable` refused it
		# and nothing in the game could ever use it -- the predicate and the content have to agree,
		# and neither can see the other.
		if not String(e.get("equipSlot", "")).is_empty():
			push_error("%s: '%s' declares a noise block and an equipSlot ('%s'), so is_placeable refuses it and nothing can ever put it down" % [lane, id, String(e["equipSlot"])])
			return false
		if String(e.get("class", "")) != "tool":
			push_error("%s: '%s' is class '%s'; a placeable device is a tool" % [lane, id, String(e.get("class", ""))])
			return false
		# Stacking is refused on purpose and it is a correctness rule rather than taste: `plant`
		# moves the whole *entity* onto the tile, so a stack of three firecrackers would put all
		# three down as one device and lose two of them.
		if int(e.get("stack", 1)) > 1:
			push_error("%s: '%s' stacks %d to a cell, and `plant` moves the entity -- placing it would lose the rest of the stack" % [lane, id, int(e["stack"])])
			return false
		if not findable.has(id):
			push_error("%s: '%s' makes a noise and sits in no loot table -- complete, correct and unreachable" % [lane, id])
			return false

	if devices < 8:
		push_error("%s: only %d bases declare a noise block; the slice shipped eight" % [lane, devices])
		return false
	# Both shapes have to exist or the delay is decoration. A roster where every device is instant
	# would pass every other assertion in this file and would have made `delayTicks` a dead key.
	if delayed < 1 or instant < 1:
		push_error("%s: %d devices wind up and %d go off where you stand -- one of the two shapes is missing, so half the block is unread" % [lane, delayed, instant])
		return false

	# The schema is where the shallow validator's blind spot is admitted, so it has to name the keys
	# this lane judges. A key in the code and not in the schema is a key content cannot use.
	var schema: String = _code_of("res://content/schemas/item.schema.json")
	for word in ["\"noise\"", "\"durationTicks\"", "\"delayTicks\""]:
		if not schema.contains(word):
			push_error("%s: item.schema.json does not declare %s" % [lane, word])
			return false

	# The true negatives. Each fabricated block is one a real content edit could plausibly make, and
	# the predicate has to refuse every one of them -- and accept an ordinary device, or it is a
	# predicate that refuses everything and proves nothing.
	for bad in [{}, {"magnitude": 0}, {"magnitude": -3}, {"magnitude": "loud"},
			{"magnitude": 45}, {"magnitude": 45, "durationTicks": 0},
			{"magnitude": 45, "durationTicks": -5}, {"magnitude": 45, "durationTicks": 1.5},
			{"magnitude": 45, "durationTicks": 100, "delayTicks": -1},
			{"magnitude": 45, "durationTicks": 100, "delayTicks": 2.5}]:
		if _noise_faults(bad as Dictionary).is_empty():
			push_error("%s: the noise predicate accepted %s" % [lane, str(bad)])
			return false
	if not _noise_faults({"magnitude": 120, "durationTicks": 600, "delayTicks": 400}).is_empty():
		push_error("%s: the noise predicate refuses an ordinary device, so it refuses everything" % lane)
		return false
	if findable.has("item.firecracker.imaginary"):
		push_error("%s: the table scan found an id that does not exist" % lane)
		return false
	print("  %s: %d devices, each whole, each a tool you cannot wear, none of them stacking, each in a loot table; %d wind up and %d go off where you stand" % [lane, devices, delayed, instant])
	return true


# The one predicate, so the true negatives above go through the same one the shipped bases did.
func _noise_faults(block: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var mag: Variant = block.get("magnitude")
	if not (mag is float or mag is int) or float(mag) <= 0.0:
		return ["magnitude is not a number above zero"]
	if not block.has("durationTicks"):
		out.append("it makes a noise and never stops making it")
	else:
		var d: Variant = block["durationTicks"]
		if not (d is float or d is int):
			out.append("durationTicks is not a number")
		elif float(d) <= 0.0:
			out.append("durationTicks is not above zero")
		elif absf(float(d) - float(int(d))) > 0.0:
			out.append("durationTicks is not a whole number of ticks")
	if block.has("delayTicks"):
		var t: Variant = block["delayTicks"]
		if not (t is float or t is int):
			out.append("delayTicks is not a number")
		elif float(t) < 0.0:
			out.append("delayTicks is below zero")
		elif absf(float(t) - float(int(t))) > 0.0:
			out.append("delayTicks is not a whole number of ticks")
	return out


# --- TABLE ------------------------------------------------------------------------------------
#
# docs/03's emitter table was authored as *ratios* -- a melee connect against a gunshot, an engine
# against everything -- and the ratios are the design. So a device is allowed to sound like
# something in that table and is not allowed to sound like a number somebody picked: a firecracker
# is a gunshot, a car alarm is a horn, a blasting cap is an explosion. The list here is written out
# by hand rather than read from the content it judges.
func _every_magnitude_is_a_rung_of_the_table() -> bool:
	var lane: String = "TABLE"
	var w: Variant = _world(5153)
	var seen: Array[float] = []
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not (e.get("noise") is Dictionary):
			continue
		var mag: float = float((e["noise"] as Dictionary).get("magnitude", -1.0))
		var rung: bool = false
		for value in DOCS_03_NOISE_TABLE:
			if absf(mag - float(value)) <= 1e-9:
				rung = true
		if not rung:
			push_error("%s: '%s' is %.2f, which is no rung of docs/03's table -- it does not sound like anything" % [lane, String(e.get("id", "")), mag])
			return false
		if not seen.has(mag):
			seen.append(mag)

	# The spread is the point of eight devices rather than one. A roster where every device sat on
	# the same rung would pass the loop above and would be one item wearing eight names.
	if seen.size() < 5:
		push_error("%s: the eight devices between them use %d distinct magnitudes" % [lane, seen.size()])
		return false
	var quietest: float = 9999.0
	var loudest: float = -1.0
	for m in seen:
		quietest = minf(quietest, float(m))
		loudest = maxf(loudest, float(m))
	if loudest / quietest < 8.0:
		push_error("%s: the loudest device is %.0f and the quietest %.0f -- less than an order of magnitude apart, so choosing between them is not a decision" % [lane, loudest, quietest])
		return false

	# The magnitude has to reach the *field* as itself, which is the half a content scan cannot see:
	# `magnitude_of` is the one place a content number becomes a magnitude, and the emitter is what
	# the field reads. A fabricated non-rung is refused by the same comparison, so the loop above is
	# not a loop of tautologies.
	var strange: float = 137.0
	for value2 in DOCS_03_NOISE_TABLE:
		if absf(strange - float(value2)) <= 1e-9:
			push_error("%s: the fabricated non-rung is in the table, so the refusal above proves nothing" % lane)
			return false
	var horn: int = _give(w, AIRHORN)
	if horn < 0:
		return false
	if absf(SimNoise.magnitude_of(w, horn) - float(_entry(w, AIRHORN)["noise"]["magnitude"])) > 1e-9:
		push_error("%s: the air horn's content says %s and magnitude_of says %.2f" % [lane, str(_entry(w, AIRHORN)["noise"]["magnitude"]), SimNoise.magnitude_of(w, horn)])
		return false
	if SimNoise.magnitude_of(w, w.player) != 0.0:
		push_error("%s: a survivor reads %.2f on the noise-device channel" % [lane, SimNoise.magnitude_of(w, w.player)])
		return false
	print("  %s: %d distinct magnitudes across %.0f to %.0f, every one a rung of docs/03's table" % [lane, seen.size(), quietest, loudest])
	return true


# --- PLACE ------------------------------------------------------------------------------------
#
# The verb, end to end and through the door the player actually uses: the word menu offers `use`, an
# `item.use` command starts fortify's channel, the channel stands the device up. The floodlight's
# PLANT lane is the precedent and this follows it, including the part that matters most -- the thing
# leaves the pack and stops being loot.
func _a_device_is_placed_by_the_verb_that_is_offered_for_it() -> bool:
	var lane: String = "PLACE"
	var w: Variant = _world(5154)
	var horn: int = _give(w, AIRHORN)
	if horn < 0:
		return false
	if not SimNoise.is_placeable(w, horn):
		push_error("%s: an air horn does not read as placeable" % lane)
		return false
	# Three negatives on the predicate, each a different reason. A bottle of water is not a device;
	# a floodlight is plantable and belongs to the *other* module's verb, so this one must not claim
	# it; a hand torch is a thing you hold.
	for id in [BOTTLE, FLOODLIGHT, TORCH]:
		var other: int = _give(w, String(id))
		if other < 0:
			return false
		if SimNoise.is_placeable(w, other):
			push_error("%s: '%s' reads as a noise device" % [lane, String(id)])
			return false
	# And the other way round: the light module must not claim the air horn, or two verbs would
	# fight over one item. `is_plantable` and `is_placeable` are two predicates with almost the same
	# shape reading two different content keys, which is exactly where they would quietly overlap.
	if SimLightMod.is_plantable(w, horn):
		push_error("%s: the light module reads an air horn as a lamp to plant" % lane)
		return false
	if not SimFortify.can_place_noise(w, w.player):
		push_error("%s: a body carrying an air horn on open ground cannot put it down" % lane)
		return false
	if not SimInventory.verbs_for(w, w.player, horn).has("use"):
		push_error("%s: the word menu will not offer 'use' on a device there is ground for" % lane)
		return false
	# The predicate the menu asks and the predicate the intake runs are the same one, in both
	# directions: the module offers `use` on exactly what it can place and on nothing else.
	for held in SimInventory.carried_items(w, w.player):
		if SimNoise.can_use(w, w.player, int(held)) != SimNoise.is_placeable(w, int(held)):
			push_error("%s: the noise module answers can_use=%s and is_placeable=%s for one item -- the menu and the intake disagree" % [lane, str(SimNoise.can_use(w, w.player, int(held))), str(SimNoise.is_placeable(w, int(held)))])
			return false

	var placed: Array = []
	w.events.subscribe({"id": "gate.placed", "type": "noise.device.placed", "handler": func(e: Dictionary) -> void: placed.append(e)})
	w.commands.push({"type": "item.use", "item": horn})
	w.step()
	if not w.components.has_component(w.player, "construct"):
		push_error("%s: 'use' on a device started no channel -- the verb is not reachable from the menu" % lane)
		return false
	for _i in SimFortify.CHANNEL_TICKS + 2:
		w.step()
	if placed.size() != 1 or int((placed[0] as Dictionary).get("entity", -1)) != horn:
		push_error("%s: the channel finished and published %s" % [lane, str(placed)])
		return false
	if not w.components.has_component(horn, "placedNoise") or not w.components.has_component(horn, "position"):
		push_error("%s: the placed device is not standing anywhere" % lane)
		return false
	if SimInventory.owns(w, w.player, horn):
		push_error("%s: the device is standing on a tile and still in the pack" % lane)
		return false
	# Furniture while it stands, not loot: E must not sweep an armed device off the ground as though
	# it were a tin of beans. Taking it back up is a verb of its own, and LIFT is where that is.
	if SimInventory.ground_items(w).has(horn):
		push_error("%s: the placed device is on the ground-item list, so E picks it up as loot" % lane)
		return false
	if SimNoise.is_placeable(w, horn):
		push_error("%s: a device already standing on a tile still reads as placeable" % lane)
		return false
	# `velocity`, with the names the emitter reads. Writing `x`/`y` here would add a key nothing
	# reads and the device would be silent for ever with nothing raised -- the trap the shambler pin
	# was written around.
	var vel: Variant = w.components.get_component(horn, "velocity")
	if not (vel is Dictionary) or not (vel as Dictionary).has("dx") or not (vel as Dictionary).has("dy"):
		push_error("%s: the placed device's velocity is %s -- the emitter queries for one and reads dx/dy" % [lane, str(vel)])
		return false
	print("  %s: the menu offers 'use', 'use' starts a channel, the channel stands the horn up, the pack is empty and the thing on the tile is not loot" % lane)
	return true


# --- CLOCK ------------------------------------------------------------------------------------
#
# The delay and the duration, measured off `world.tick` rather than quoted. The delay is the whole
# reason a wind-up clock is a different item from an air horn, so it is asserted to the exact tick:
# silent at `startsAtTick - 1`, sounding at `startsAtTick`, silent again at `endsAtTick`. Off by one
# in either direction is a fail, which is why the module arms in `attention-emit` rather than three
# phases later in `structures`.
func _the_fuse_burns_down_and_the_racket_runs_out() -> bool:
	var lane: String = "CLOCK"
	var w: Variant = _world(5155)
	var cracker: int = _give(w, FIRECRACKER)
	if cracker < 0:
		return false
	var delay: int = SimNoise.delay_of(w, cracker)
	var duration: int = SimNoise.duration_of(w, cracker)
	var mag: float = SimNoise.magnitude_of(w, cracker)
	if delay <= 2 or duration <= 2:
		push_error("%s: the firecracker's fuse is %d ticks and it sounds for %d -- too short to measure anything" % [lane, delay, duration])
		return false
	if SimNoise.plant(w, w.player, BAIT_X, BAIT_Y) != cracker:
		push_error("%s: the firecracker would not go down" % lane)
		return false
	var record: Variant = w.components.get_component(cracker, "placedNoise")
	if not (record is Dictionary):
		push_error("%s: the placed firecracker carries no record" % lane)
		return false
	var starts: int = int((record as Dictionary)["startsAtTick"])
	var ends: int = int((record as Dictionary)["endsAtTick"])
	if starts != int(w.tick) + delay or ends != starts + duration:
		push_error("%s: placed at %d with a %d fuse and %d of racket, the record says starts %d ends %d" % [lane, int(w.tick), delay, duration, starts, ends])
		return false

	var triggered: Array = []
	var spent: Array = []
	w.events.subscribe({"id": "gate.trig", "type": "noise.device.triggered", "handler": func(e: Dictionary) -> void: triggered.append(e)})
	w.events.subscribe({"id": "gate.spent", "type": "noise.device.spent", "handler": func(e: Dictionary) -> void: spent.append(e)})

	# The fuse. Stepped to the tick before it goes off, and nothing may be emitting.
	while int(w.tick) < starts - 1:
		w.step()
		if _ambient_of(w, cracker) != 0.0:
			push_error("%s: the firecracker is emitting %.2f at tick %d, before its fuse is out at %d" % [lane, _ambient_of(w, cracker), int(w.tick), starts])
			return false
	if SimNoise.state_of(w, cracker) != SimNoise.WOUND_WORD:
		push_error("%s: a device with its fuse still burning reads '%s'" % [lane, SimNoise.state_of(w, cracker)])
		return false
	if not triggered.is_empty():
		push_error("%s: %d triggers fired during the fuse" % [lane, triggered.size()])
		return false
	# The field's own answer, which is the half an `ambient` assertion cannot reach: nothing is
	# being published, so nothing is in the field.
	if w.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5) > 0.5:
		push_error("%s: the field reads %.3f under a device that has not gone off" % [lane, w.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5)])
		return false

	w.step()
	if int(w.tick) != starts:
		push_error("%s: stepped to tick %d and wanted %d" % [lane, int(w.tick), starts])
		return false
	if absf(_ambient_of(w, cracker) - mag) > 1e-9:
		push_error("%s: on the tick the fuse runs out the firecracker emits %.2f, not %.2f -- the clock is off by one" % [lane, _ambient_of(w, cracker), mag])
		return false
	if triggered.size() != 1:
		push_error("%s: %d triggers on the tick it goes off" % [lane, triggered.size()])
		return false
	if SimNoise.state_of(w, cracker) != SimNoise.SOUNDING_WORD:
		push_error("%s: a sounding device reads '%s'" % [lane, SimNoise.state_of(w, cracker)])
		return false
	# **The field, on that same tick, with no extra step.** This is the assertion that makes the
	# module's phase choice load-bearing, and without it this lane could not fail: `ambient` is a
	# dictionary the clock writes and a gate reads, so it reads the same whether the clock runs at
	# `attention-emit` order -10 or three phases later in `structures`. What differs is whether
	# `attention.emit-movement` -- which runs at `attention-emit` order 0 -- saw it in time to
	# publish. Moving the registration to `structures` was sabotaged in and every `ambient`
	# assertion above still passed; only this line goes red.
	if w.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5) < mag * 0.5:
		push_error("%s: on the tick the fuse ran out the field reads %.2f under a firecracker worth %.2f -- the clock arms after the emitter has already looked, so every fuse in content is a tick longer than it says" % [lane, w.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5), mag])
		return false

	# The duration. It has to stop, and stop on its tick.
	while int(w.tick) < ends - 1:
		w.step()
		if absf(_ambient_of(w, cracker) - mag) > 1e-9:
			push_error("%s: the firecracker fell to %.2f at tick %d, before it runs out at %d" % [lane, _ambient_of(w, cracker), int(w.tick), ends])
			return false
	w.step()
	if _ambient_of(w, cracker) != 0.0:
		push_error("%s: a spent firecracker still emits %.2f" % [lane, _ambient_of(w, cracker)])
		return false
	if spent.size() != 1 or triggered.size() != 1:
		push_error("%s: %d triggers and %d run-outs across one device's life" % [lane, triggered.size(), spent.size()])
		return false
	if SimNoise.state_of(w, cracker) != SimNoise.SPENT_WORD:
		push_error("%s: a run-out device reads '%s'" % [lane, SimNoise.state_of(w, cracker)])
		return false
	# And it stays quiet. A clock that wrapped, or an `ambient` something else re-wrote, would show
	# up here and nowhere above.
	for _i in 40:
		w.step()
		if _ambient_of(w, cracker) != 0.0:
			push_error("%s: a spent firecracker started up again at tick %d" % [lane, int(w.tick)])
			return false
	# The true negative for the whole idea of a delay: an air horn has none, and it must be heard on
	# the tick it is placed rather than on some later one. Without this, a clock that ignored
	# `delayTicks` entirely and always waited the firecracker's 600 would pass everything above.
	var instant: Variant = _world(5156)
	var horn: int = _give(instant, AIRHORN)
	if horn < 0:
		return false
	if SimNoise.delay_of(instant, horn) != 0:
		push_error("%s: the air horn declares a fuse of %d ticks; this lane's negative needs one without" % [lane, SimNoise.delay_of(instant, horn)])
		return false
	if SimNoise.plant(instant, instant.player, BAIT_X, BAIT_Y) != horn:
		push_error("%s: the air horn would not go down" % lane)
		return false
	instant.step()
	if absf(_ambient_of(instant, horn) - SimNoise.magnitude_of(instant, horn)) > 1e-9:
		push_error("%s: an air horn with no fuse is emitting %.2f one tick after it was set down" % [lane, _ambient_of(instant, horn)])
		return false
	print("  %s: a fuse of %d ticks is silent to the tick and loud on it, %d ticks of racket end on theirs, one trigger and one run-out apiece, and a horn with no fuse sounds immediately" % [lane, delay, duration])
	return true


# --- HORDE ------------------------------------------------------------------------------------
#
# **The load-bearing lane.** Everything above measures a number a helper returned or a field a
# component carries. This measures where twelve bodies are standing.
#
# One world, two windows, and the difference between them is the clock rather than the code: a ring
# of shamblers around a hand-crank siren neither closes nor scatters while the fuse burns, and walks
# in once it goes off. The claim is anchored in two places that are not the shambler loop --
# `SimNoise.state_of` for which window we are in and `field.noise_at` for whether the district can
# hear anything -- because an A/B of one code path against itself catches non-determinism and
# nothing else.
#
# The second world is the control that keeps the first honest: an identical siren whose fuse is set
# far enough ahead that it never goes off at all, stepped for the *whole* span. If the ring closes
# there too, the convergence above was wandering rather than bait.
func _the_horde_walks_to_the_thing_that_is_sounding() -> bool:
	var lane: String = "HORDE"
	var loud: Variant = _world(5157, "item.pack.frame")
	var device: int = _give(loud, SIREN)
	if device < 0:
		return false
	var fuse: int = SimNoise.delay_of(loud, device)
	var racket: int = SimNoise.duration_of(loud, device)
	if fuse < 200 or racket < 600:
		push_error("%s: the siren's fuse is %d and its racket %d -- this lane needs both windows to be walkable" % [lane, fuse, racket])
		return false
	if SimNoise.plant(loud, loud.player, BAIT_X, BAIT_Y) != device:
		push_error("%s: the siren would not go down" % lane)
		return false
	# The player goes to the far corner and stays there. A survivor standing beside the bait is a
	# second attractor -- and the thing under test is the bait.
	loud.components.set_component(loud.player, "position", {"x": 4.5, "y": 4.5})
	var ring: Array[int] = _ring_of_dead(loud)
	if ring.size() != RING_BODIES:
		push_error("%s: %d bodies in the ring" % [lane, ring.size()])
		return false

	var start_mean: float = _mean_distance(loud, ring)
	if absf(start_mean - RING_METRES) > 0.5:
		push_error("%s: the ring starts at a mean %.2f m and was laid at %.2f" % [lane, start_mean, RING_METRES])
		return false

	# Window one: the fuse. Nothing is sounding, so nothing should move toward anything.
	for _i in fuse:
		loud.step()
	if SimNoise.state_of(loud, device) != SimNoise.SOUNDING_WORD:
		push_error("%s: after %d ticks the siren reads '%s' rather than sounding -- the two windows are not where this lane thinks they are" % [lane, fuse, SimNoise.state_of(loud, device)])
		return false
	var fuse_mean: float = _mean_distance(loud, ring)
	if start_mean - fuse_mean > 3.0:
		push_error("%s: the ring closed from %.2f m to %.2f m while the fuse was still burning -- something other than the bait is pulling them in" % [lane, start_mean, fuse_mean])
		return false

	# Window two: the racket.
	for _j in racket:
		loud.step()
	var end_mean: float = _mean_distance(loud, ring)
	# The absolute claim, not merely a comparison: they are substantially nearer than they were.
	if fuse_mean - end_mean < 8.0:
		push_error("%s: the siren sounded for %d ticks and the ring went from %.2f m to %.2f m -- the horde did not come" % [lane, racket, fuse_mean, end_mean])
		return false
	if end_mean > RING_METRES * 0.5:
		push_error("%s: the ring ended at a mean %.2f m from a siren it started %.2f m from" % [lane, end_mean, RING_METRES])
		return false

	# The control. An identical siren whose fuse outlasts the whole run, stepped for the same total
	# span: if this ring closes too, the one above proved nothing about bait.
	var quiet: Variant = _world(5157, "item.pack.frame")
	var mute: int = _give(quiet, SIREN)
	if mute < 0:
		return false
	if SimNoise.plant(quiet, quiet.player, BAIT_X, BAIT_Y) != mute:
		push_error("%s: the control siren would not go down" % lane)
		return false
	# A fuse long enough that this device never goes off. A legal state, not a fabricated one -- it
	# is exactly what an alarm clock's record looks like the moment it is set down.
	var far: Dictionary = quiet.components.get_component(mute, "placedNoise") as Dictionary
	far["startsAtTick"] = int(quiet.tick) + (fuse + racket) * 4
	far["endsAtTick"] = int(far["startsAtTick"]) + racket
	quiet.components.set_component(quiet.player, "position", {"x": 4.5, "y": 4.5})
	var quiet_ring: Array[int] = _ring_of_dead(quiet)
	var quiet_start: float = _mean_distance(quiet, quiet_ring)
	for _k in fuse + racket:
		quiet.step()
	if SimNoise.state_of(quiet, mute) != SimNoise.WOUND_WORD:
		push_error("%s: the control siren went off after all" % lane)
		return false
	if quiet.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5) > 0.5:
		push_error("%s: the control district reads %.3f of noise under a siren that never sounded" % [lane, quiet.field.noise_at(float(BAIT_X) + 0.5, float(BAIT_Y) + 0.5)])
		return false
	var quiet_end: float = _mean_distance(quiet, quiet_ring)
	if quiet_start - quiet_end > 3.0:
		push_error("%s: the control ring closed from %.2f m to %.2f m with nothing sounding -- the convergence above is wandering, not bait" % [lane, quiet_start, quiet_end])
		return false
	print("  %s: %d bodies at a mean %.1f m held %.1f m through a %d-tick fuse and closed to %.1f m over %d ticks of siren, while an identical siren that never went off left its ring at %.1f m" % [
		lane, RING_BODIES, start_mean, fuse_mean, fuse, end_mean, racket, quiet_end])
	return true


# Twelve shamblers on a circle of RING_METRES around the bait tile. No `observer`, so nothing here
# can see the survivor in the corner; no `attention_emitter`, so nothing here makes a sound of its
# own that it could then follow.
func _ring_of_dead(w: Variant) -> Array[int]:
	var out: Array[int] = []
	for i in RING_BODIES:
		var angle: float = TAU * float(i) / float(RING_BODIES)
		var ent: int = int(w.entities.spawn())
		w.components.set_component(ent, "position", {
			"x": float(BAIT_X) + 0.5 + cos(angle) * RING_METRES,
			"y": float(BAIT_Y) + 0.5 + sin(angle) * RING_METRES,
		})
		w.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
		w.components.set_component(ent, "facing", {"radians": 0.0})
		w.components.set_component(ent, "body", SimCombat.ZOMBIE_BODY.duplicate())
		SimShambler.make_shambler(w, ent, w.rng.stream("shambler"))
		out.append(ent)
	return out


func _mean_distance(w: Variant, bodies: Array[int]) -> float:
	if bodies.is_empty():
		return -1.0
	var total: float = 0.0
	for body in bodies:
		var pos: Variant = w.components.get_component(int(body), "position")
		if not (pos is Dictionary):
			continue
		var dx: float = float((pos as Dictionary)["x"]) - (float(BAIT_X) + 0.5)
		var dy: float = float((pos as Dictionary)["y"]) - (float(BAIT_Y) + 0.5)
		total += sqrt(dx * dx + dy * dy)
	return total / float(bodies.size())


# --- LIFT -------------------------------------------------------------------------------------
#
# The owner's decision of 2026-09-12, and the one place this slice deliberately parts company with
# the light slice: a floodlight is planted one-way and a noise device is not. So there is a verb
# that takes it back up, it is E, and the device that comes back up is the same device -- placed
# again, its clock starts again.
func _a_device_comes_back_up_and_goes_down_again() -> bool:
	var lane: String = "LIFT"
	var w: Variant = _world(5158)
	var cracker: int = _give(w, FIRECRACKER)
	if cracker < 0:
		return false
	if SimNoise.plant(w, w.player, BAIT_X, BAIT_Y) != cracker:
		push_error("%s: the firecracker would not go down" % lane)
		return false
	if SimNoise.placed_in_reach(w, w.player) != cracker:
		push_error("%s: a device on the tile in front of the survivor is not in reach" % lane)
		return false
	if not SimFortify.can_lift_noise(w, w.player):
		push_error("%s: a device standing at arm's length cannot be picked back up" % lane)
		return false

	var lifted: Array = []
	w.events.subscribe({"id": "gate.lift", "type": "noise.device.lifted", "handler": func(e: Dictionary) -> void: lifted.append(e)})
	w.commands.push({"type": "use.context"})
	w.step()
	# The *verb*, not merely "a channel started". E is a ladder and its lower rungs are still there:
	# with the lift rung deleted, E on an empty tile falls through to laying an alarm line, a
	# channel starts, and an assertion that only asked whether one had would pass. Sabotaged in and
	# confirmed -- this is the line that names what went wrong.
	var chan: Variant = w.components.get_component(w.player, "construct")
	if not (chan is Dictionary) or String((chan as Dictionary).get("verb", "")) != "noiselift":
		push_error("%s: E at a placed device started %s rather than a lift -- the rung is not on the ladder, or something above it got there first" % [lane, str(chan)])
		return false
	for _i in SimFortify.CHANNEL_TICKS + 2:
		w.step()
	if lifted.size() != 1:
		push_error("%s: the channel finished and published %s" % [lane, str(lifted)])
		return false
	if not SimInventory.owns(w, w.player, cracker):
		push_error("%s: the firecracker came up and is in nobody's pack" % lane)
		return false
	for dead_key in ["placedNoise", "position", "velocity", "attention_emitter"]:
		if w.components.has_component(cracker, String(dead_key)):
			push_error("%s: a device back in the pack still carries '%s' -- it is standing in the yard and in your pocket at once" % [lane, String(dead_key)])
			return false
	if not SimNoise.is_placeable(w, cracker):
		push_error("%s: a device that came back up cannot be put down again, so it is not multi-use" % lane)
		return false

	# Down again, and the clock starts again. This is the multi-use claim measured rather than
	# asserted: the same entity, a fresh fuse off the tick it was set down the second time.
	var again_tick: int = int(w.tick)
	if SimNoise.plant(w, w.player, BAIT_X, BAIT_Y) != cracker:
		push_error("%s: the firecracker would not go down a second time" % lane)
		return false
	var record: Dictionary = w.components.get_component(cracker, "placedNoise") as Dictionary
	if int(record["startsAtTick"]) != again_tick + SimNoise.delay_of(w, cracker):
		push_error("%s: re-placed at %d, the fuse says %d rather than %d -- the clock remembered the first placing" % [lane, again_tick, int(record["startsAtTick"]), again_tick + SimNoise.delay_of(w, cracker)])
		return false

	# The negatives. A survivor standing nowhere near a device lifts nothing, and a pack with no
	# room refuses and leaves the device exactly where it stood -- the refusal that must not eat it.
	var away: Variant = _world(5159)
	if SimFortify.can_lift_noise(away, away.player) or SimNoise.take_up(away, away.player):
		push_error("%s: a survivor standing at nothing picked something up" % lane)
		return false
	var full: Variant = _world(5160, "")
	var siren: int = SimItems.spawn_item(full, SIREN, {"tier": "scavenged"})
	if not SimInventory.stow(full, full.player, siren):
		push_error("%s: the bare-pockets fixture would not hold one siren" % lane)
		return false
	if SimNoise.plant(full, full.player, BAIT_X, BAIT_Y) != siren:
		push_error("%s: the siren would not go down" % lane)
		return false
	# Fill the four-by-two pockets until nothing else will go in, so "no room" is measured rather
	# than assumed: a fixed number of bricks is a number that stops being enough the day somebody
	# changes a footprint, and the lane would then quietly pass by testing nothing.
	var packed: int = 0
	while packed < 32:
		var brick: int = SimItems.spawn_item(full, "item.clay.brick", {"tier": "scavenged"})
		if not SimInventory.stow(full, full.player, brick):
			full.despawn(brick)
			break
		packed += 1
	if packed == 0:
		push_error("%s: the pockets were full before this lane filled them, so the refusal below is about the wrong thing" % lane)
		return false
	if SimNoise.take_up(full, full.player):
		push_error("%s: a siren went into pockets that had no room for it" % lane)
		return false
	if not full.components.has_component(siren, "placedNoise") or not full.components.has_component(siren, "position"):
		push_error("%s: a refused lift left the siren neither standing nor carried -- it is gone" % lane)
		return false
	if not full.components.has_component(siren, "stored"):
		push_error("%s: a refused lift left the siren standing and countable as loot" % lane)
		return false
	print("  %s: E takes a placed device back into the pack, the tile is left with nothing on it, the same entity goes down again on a fresh fuse, and a lift with nowhere to put it refuses rather than losing the thing" % lane)
	return true


# --- HUD --------------------------------------------------------------------------------------
#
# The dead-socket rule applied to the screen's half. `state_of` returns a word; a word nothing reads
# is a word that will be wrong the first time somebody looks at it. `SimFortify.look_at` is its one
# reader and `main.gd` is look_at's, and the whole path is under the digit ban.
func _the_screen_is_told_in_one_word() -> bool:
	var lane: String = "HUD"
	var w: Variant = _world(5161)
	if not String(SimFortify.look_at(w, w.player).get("device", "x")).is_empty():
		push_error("%s: a survivor standing at nothing is told about a device" % lane)
		return false
	var siren: int = _give(w, SIREN)
	if siren < 0:
		return false
	if SimNoise.plant(w, w.player, BAIT_X, BAIT_Y) != siren:
		push_error("%s: the siren would not go down" % lane)
		return false
	var starts: int = int((w.components.get_component(siren, "placedNoise") as Dictionary)["startsAtTick"])
	var ends: int = int((w.components.get_component(siren, "placedNoise") as Dictionary)["endsAtTick"])
	var words: Dictionary = {}
	for at in [int(w.tick), starts, ends]:
		w.tick = int(at)
		var word: String = String(SimFortify.look_at(w, w.player).get("device", ""))
		if word.is_empty():
			push_error("%s: a device at arm's length at tick %d says nothing at all" % [lane, int(at)])
			return false
		for ch in word:
			if ch >= "0" and ch <= "9":
				push_error("%s: the device clause reads '%s', which carries a digit" % [lane, word])
				return false
		words[word] = true
	if words.size() != 3:
		push_error("%s: the device clause only ever said %s -- fewer words than states" % [lane, str(words.keys())])
		return false

	# main.gd is look_at's reader and the needle has to be findable there, per the two gates this
	# milestone turned red by looking for a call that had moved. Both lists: the developer sheet's
	# and the player's context line.
	var main: String = _code_of("res://presentation/main.gd")
	if main.is_empty():
		push_error("%s: main.gd would not open" % lane)
		return false
	if not main.contains("look.get(\"device\", \"\")"):
		push_error("%s: main.gd never reads look_at's 'device' -- the word has no reader" % lane)
		return false
	if not main.contains("[\"window\", \"noisemaker\", \"device\"]"):
		push_error("%s: the player's context line does not list 'device', so the word only ever reaches the developer sheet behind M" % lane)
		return false
	if main.contains("look.get(\"deviceword\", \"\")"):
		push_error("%s: the needle matched a key that does not exist, so this lane is not reading what it thinks" % lane)
		return false
	print("  %s: three states, three words (%s), no digit among them, and main.gd reads the key on both the sheet and the player's line" % [lane, ", ".join(PackedStringArray(words.keys()))])
	return true
