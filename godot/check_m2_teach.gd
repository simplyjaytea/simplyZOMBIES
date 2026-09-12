extends SceneTree
# Books that teach -- docs/08-skill-web.md, and the socket it had been sitting in since Milestone 1.
#
# What this slice fixed. `sim/modules/skills.gd` is a complete, content-driven six-region XP ladder
# with a focus path, a surplus pass, a drift and a read model, and **nothing in the game taught
# anything**. Every point any survivor had ever earned came from a kill or from finishing a job.
# There was no item content for it at all: no `teaches` key, no reader, nothing on any loot table.
# A whole verb of the fiction -- finding somebody's first aid manual in a bathroom cabinet and
# actually being better at bleeding afterwards -- was a mechanism with no content, which is the
# dead-socket pattern seen from the other side.
#
# The two lanes that are the whole point of the slice, and everything else here exists to stop
# them being gamed:
#
#   TWICE  -- a book teaches once. Read it, read it again, and the second reading pays nothing.
#             Asserted on the *exact* earned total, not on a direction of travel, because "it did
#             not go up much" is not an assertion. The second copy is real: the lane puts two
#             copies of one title in the pack, so the refusal comes from the reader's ledger and
#             not from the shelf being empty.
#   BOUND  -- a book never out-teaches practice. The ceiling is SimSkills.PRACTICE_POINTS, which
#             is what one kill or one completed job actually pays, and the lane measures that
#             payment as behaviour before it uses it as a ceiling. A book worth more than doing
#             the thing once would make doing the thing pointless, and docs/08's web is a record
#             of what somebody has done.
#
# PINNED is the additive claim: the XP the game already paid out is exactly the XP it pays out
# now. Every region, every job kind, and the kill path, measured rather than asserted about -- so
# this slice cannot have been a silent rebalance wearing a content edit's clothes.
#
# Every lane carries a true negative.

const World = preload("res://sim/world.gd")
const SimBoot = preload("res://sim/boot.gd")
const SimSave = preload("res://sim/save.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimSkills = preload("res://sim/modules/skills.gd")
const Clock = preload("res://sim/time/clock.gd")

# The ten bases this slice ships: a field manual for each of the six regions, and four rarer
# volumes. Fixtures, not welds -- every predicate below is "declares a teaches block", and the
# CONTENT lane walks the whole registry rather than this list -- but a gate has to hold something
# concrete or nothing in it is falsifiable.
const MANUAL_MEDICINE: String = "item.book.firstaid"
const MANUAL_CRAFT: String = "item.book.repairs"
const MANUAL_SURVIVAL: String = "item.book.bushcraft"
# The field manual for each region, by region. The CONTENT lane walks the whole registry rather
# than this table, and then asks this table the one question a registry walk cannot: that the six
# manuals are the six they are meant to be, so a rename or a region swapped between two of them is
# a red build rather than a silent reshuffle that still satisfies "every region has something".
const MANUALS: Dictionary = {
	"Melee": "item.book.closequarters",
	"Ranged": "item.book.marksmanship",
	"Medicine": MANUAL_MEDICINE,
	"Craft": MANUAL_CRAFT,
	"Survival": MANUAL_SURVIVAL,
	"Endurance": "item.book.conditioning",
}

# The small one, for the lanes that need two copies in one pack.
const SLIM: String = "item.book.longwalk"

# Things that emphatically teach nothing, for the negatives: a meal, a bandage, a bottle.
const FOOD: String = "item.food.canned"
const BANDAGE: String = "item.bandage.cloth"
const BOTTLE: String = "item.water.bottle"

# Which job kind pays into which region, as docs/08 and skills.gd's own match have it. Written here
# rather than read out of skills.gd, because a table read from the thing it judges judges nothing.
const JOB_REGIONS: Dictionary = {
	"Haul": "Survival",
	"Scavenge": "Survival",
	"Cook": "Survival",
	"Construct": "Craft",
	"Doctor": "Medicine",
	"Rest": "Endurance",
	"Guard": "Endurance",
}
# A job kind nobody maps. The true negative for the PINNED lane: if this earns anything, the
# measurement is picking up something other than the thing it thinks it is measuring.
const UNMAPPED_JOB: String = "Loiter"

const MAP: int = 48


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _the_xp_that_already_shipped_is_unchanged() and ok
	ok = _every_teaches_block_is_whole_and_names_a_region_the_code_has() and ok
	ok = _every_book_is_findable_and_the_key_is_read() and ok
	ok = _a_book_teaches_once_and_a_second_copy_teaches_nothing() and ok
	ok = _a_book_never_out_teaches_doing_the_work() and ok
	ok = _what_has_been_read_survives_a_save() and ok
	if ok:
		print("M2_TEACH_OK pinned content reach twice bound save")
		quit(0)
	else:
		push_error("M2_TEACH_FAIL")
		quit(1)


# --- fixtures ---------------------------------------------------------------------------------

# A survivor on open ground with a web and a pack. The kernel is attached because `_autospend`
# reaches `world.modifiers` on every buy, and the skills module is registered because the PINNED
# lane earns through the real event handlers rather than through `teach` directly.
func _world(seed_val: int = 8811) -> Variant:
	var fixture: Dictionary = {
		"seed": seed_val,
		"tick_hz": 20,
		"map": {"width": MAP, "height": MAP, "walls": []},
		"player": {"id": 0, "x": 24.5, "y": 24.5, "stance": 2},
		"rng_probe": {"stream": "test", "samples": 0},
	}
	var w: Variant = World.new(fixture)
	var map: Variant = SimTileMap.blank_map(MAP, MAP)
	SimBoot.attach_kernel(w, map)
	SimHealth.register_module(w)
	SimInventory.register_module(w)
	SimItems.register_module(w)
	SimNeeds.register_module(w)
	SimSkills.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player)
	SimInventory.make_inventory(w, w.player)
	w.tick = Clock.tick_at_time_of_day(Clock.DAY_BEGINS)
	var bag: int = SimItems.spawn_item(w, "item.pack.hiking", {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, bag):
		push_error("the fixture pack would not go on")
	SimSkills.attach(w, w.player)
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


# Everything earned in every region, banked and spent alike. `SimSkills.earned` is the only honest
# reading here: `attach` and every `_earn` run `_autospend`, so a point can be a node by the time
# anything looks, and a lane watching `points` alone would report a payment of zero for a payment
# that was made and immediately spent.
func _earned_all(w: Variant, ent: int) -> Dictionary:
	var out: Dictionary = {}
	for r in SimSkills.REGIONS:
		out[String(r)] = SimSkills.earned(w, ent, String(r))
	return out


# What moved between two readings, as {region: delta}, dropping the regions that did not move.
func _delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for r in SimSkills.REGIONS:
		var d: int = int(after.get(String(r), 0)) - int(before.get(String(r), 0))
		if d != 0:
			out[String(r)] = d
	return out


func _code_of(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


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


func _carries_a_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


# --- PINNED -----------------------------------------------------------------------------------
#
# Additive, or it is a rebalance. This slice added a new way of earning points and touched the
# arithmetic of the existing ways only to give the literal `1` a name, so the thing worth pinning
# is the payout itself: every job kind into its own region, a melee kill into Melee, one point
# each, nothing anywhere else, and a kind the match does not name earning nothing at all.
#
# The last of those is the true negative, and it is what makes the rest of the lane mean anything:
# a measurement that reported "+1 Survival" for a job kind skills.gd has never heard of would be
# measuring the fixture rather than the handler.
func _the_xp_that_already_shipped_is_unchanged() -> bool:
	var lane: String = "PINNED"
	if int(SimSkills.PRACTICE_POINTS) != 1:
		push_error("%s: one piece of work pays %d and it paid 1 -- either the ladder was rebalanced or a book is being laundered past the BOUND lane" % [lane, int(SimSkills.PRACTICE_POINTS)])
		return false
	for kind_v in JOB_REGIONS.keys():
		var kind: String = String(kind_v)
		var region: String = String(JOB_REGIONS[kind])
		var w: Variant = _world()
		var before: Dictionary = _earned_all(w, w.player)
		w.events.publish({"type": "job.completed", "entity": w.player, "kind": kind})
		w.events.drain()
		var moved: Dictionary = _delta(before, _earned_all(w, w.player))
		if moved != {region: 1}:
			push_error("%s: one completed '%s' moved %s and it moved {\"%s\": 1}" % [lane, kind, str(moved), region])
			return false
	# The kind nobody maps.
	var quiet: Variant = _world()
	var quiet_before: Dictionary = _earned_all(quiet, quiet.player)
	quiet.events.publish({"type": "job.completed", "entity": quiet.player, "kind": UNMAPPED_JOB})
	quiet.events.drain()
	var quiet_moved: Dictionary = _delta(quiet_before, _earned_all(quiet, quiet.player))
	if not quiet_moved.is_empty():
		push_error("%s: a '%s' -- a job kind skills.gd does not name -- earned %s, so the measurement is reading something other than the handler" % [lane, UNMAPPED_JOB, str(quiet_moved)])
		return false
	# The kill path, which is the other half of what already shipped.
	var kw: Variant = _world()
	var kill_before: Dictionary = _earned_all(kw, kw.player)
	var zed: int = int(kw.entities.spawn())
	kw.components.set_component(zed, "zombieType", {"id": "zombie.shambler"})
	kw.components.set_component(zed, "position", {"x": 25.0, "y": 24.5})
	kw.components.set_component(kw.player, "meleeWeapon", {"damage": 10})
	kw.events.publish({"type": "entity.killed", "entity": zed, "killer": kw.player, "x": 25.0, "y": 24.5, "zombieType": "zombie.shambler"})
	kw.events.drain()
	var kill_moved: Dictionary = _delta(kill_before, _earned_all(kw, kw.player))
	if kill_moved != {"Melee": 1}:
		push_error("%s: a shambler put down with a melee weapon moved %s and it moved {\"Melee\": 1}" % [lane, str(kill_moved)])
		return false
	print("%s OK one piece of work is %d point, in %d job kinds and a kill" % [lane, int(SimSkills.PRACTICE_POINTS), JOB_REGIONS.size()])
	return true


# --- CONTENT ----------------------------------------------------------------------------------
#
# The content validator is shallow: it checks top-level types and refuses unexpected top-level
# keys, and it does not look inside `teaches` at all. The warmth slice proved that deliberately on
# a brand-new block. So this is the purpose-built gate for this nested shape -- region really one
# of SimSkills.REGIONS, points a positive integer, no third key, the class something the gear
# gate's own tool rule will not later refuse, and the description prose without a digit in it.
#
# The six manuals are asserted by region rather than by id: the claim worth holding is that every
# region of the web has something that teaches it, not that a particular book exists.
func _every_teaches_block_is_whole_and_names_a_region_the_code_has() -> bool:
	var lane: String = "CONTENT"
	var w: Variant = _world()
	var seen_regions: Dictionary = {}
	var judged: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		var id: String = String(e.get("id", ""))
		if not e.has(SimNeeds.TEACH_KEY):
			continue
		judged += 1
		var block_v: Variant = e[SimNeeds.TEACH_KEY]
		if not (block_v is Dictionary):
			push_error("%s: %s's teaches is not a block" % [lane, id])
			return false
		var block: Dictionary = block_v as Dictionary
		for key in block.keys():
			if not ["region", "points"].has(String(key)):
				push_error("%s: %s's teaches carries '%s', which nothing reads" % [lane, id, String(key)])
				return false
		var region: String = String(block.get("region", ""))
		if not SimSkills.REGIONS.has(region):
			push_error("%s: %s teaches '%s', which is not one of %s -- a region the code does not have is a book nobody can learn from" % [lane, id, region, str(SimSkills.REGIONS)])
			return false
		if not (block.get("points") is float or block.get("points") is int) or int(block.get("points", 0)) < 1:
			push_error("%s: %s teaches %s points" % [lane, id, str(block.get("points"))])
			return false
		seen_regions[region] = true
		if not id.begins_with("item.book."):
			push_error("%s: %s teaches something and is not namespaced item.book.*" % [lane, id])
			return false
		var cls: String = String(e.get("class", ""))
		if not ["consumable", "material"].has(cls):
			push_error("%s: %s is class '%s'; a book is a consumable or a material, and a 'tool' with no light, modification or noise is what check_m2_gear.gd's CATALOGUE lane refuses outright" % [lane, id, cls])
			return false
		var desc: String = String(e.get("description", ""))
		if desc.is_empty():
			push_error("%s: %s has no description" % [lane, id])
			return false
		if _carries_a_digit(desc):
			push_error("%s: %s's description carries a digit: \"%s\"" % [lane, id, desc])
			return false
	if judged < 1:
		push_error("%s: no base in the registry declares a teaches block, so this lane judged nothing" % lane)
		return false
	for r in SimSkills.REGIONS:
		if not seen_regions.has(String(r)):
			push_error("%s: nothing in the game teaches %s -- a region of the web with no book is half the slice" % [lane, String(r)])
			return false
		var manual: String = String(MANUALS.get(String(r), ""))
		var spec: Variant = SimNeeds.teaches_spec(w, manual)
		if not (spec is Dictionary) or String((spec as Dictionary)["region"]) != String(r):
			push_error("%s: %s is meant to be the field manual for %s and teaches %s" % [lane, manual, String(r), str(spec)])
			return false
	# The true negatives, on the same predicates the loop above runs: a fabricated block naming a
	# region the code does not have, and one with a third key, both have to be refusable.
	if SimSkills.REGIONS.has("Shooting"):
		push_error("%s: the region list has grown a 'Shooting', so this negative proves nothing" % lane)
		return false
	var fake: Dictionary = {"region": "Medicine", "points": 1, "charges": 3}
	var extra_found: bool = false
	for key in fake.keys():
		if not ["region", "points"].has(String(key)):
			extra_found = true
	if not extra_found:
		push_error("%s: a fabricated teaches block with a third key was not spotted by the key scan" % lane)
		return false
	# Something that teaches nothing is not accidentally swept in.
	for id in [FOOD, BANDAGE, BOTTLE]:
		if _entry(w, String(id)).has(SimNeeds.TEACH_KEY):
			push_error("%s: %s declares a teaches block" % [lane, String(id)])
			return false
	print("%s OK %d books, every region of the web taught" % [lane, judged])
	return true


# --- REACH ------------------------------------------------------------------------------------
#
# The dead-socket rule, asked three ways, because a mechanism nothing reaches is what this
# milestone keeps paying for.
#
# Findable: every base declaring `teaches` is on a shipped loot table. Books are also covered by
# check_m2_gear.gd's CATALOGUE lane now that `teaches` is in its READ_KEYS, and this lane asserts
# that membership textually -- that list is what makes the rule automatic for every book anybody
# adds later, and a slice that shipped the key without adding it there would have left the
# catalogue blind to a whole category.
#
# Read: the reader is proved by *behaviour*, not by a grep for a function name. `can_use` answers
# yes for a book in a pocket, `verbs_for` offers the verb, and a body with no web is refused. A
# textual assertion would go red the next time somebody moves the call one link down, which is
# exactly how check_respond and check_weather went red for code that was correct.
func _every_book_is_findable_and_the_key_is_read() -> bool:
	var lane: String = "REACH"
	var w: Variant = _world()
	var findable: Dictionary = _findable(w)
	if findable.is_empty():
		push_error("%s: no loot table in the tree has entries, so the findability scan has nothing to judge" % lane)
		return false
	if findable.has("item.book.doesnotexist"):
		push_error("%s: the loot scan found an id that does not exist" % lane)
		return false
	var unreachable: Array[String] = []
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if e.has(SimNeeds.TEACH_KEY) and not findable.has(String(e.get("id", ""))):
			unreachable.append(String(e.get("id", "")))
	if not unreachable.is_empty():
		push_error("%s: %s teach something and are on no loot table -- complete, correct, and unfindable" % [lane, str(unreachable)])
		return false
	# The gear gate's catalogue has to know the key exists.
	var gear: String = _code_of("res://check_m2_gear.gd")
	var read_keys: String = ""
	for line in gear.split("\n"):
		if String(line).begins_with("const READ_KEYS"):
			read_keys = String(line)
	if read_keys.is_empty():
		push_error("%s: check_m2_gear.gd has no READ_KEYS line, so this assertion is reading the wrong file" % lane)
		return false
	if read_keys.contains("\"notakey\""):
		push_error("%s: the READ_KEYS scan matched a key that is not in the list" % lane)
		return false
	if not read_keys.contains("\"%s\"" % SimNeeds.TEACH_KEY):
		push_error("%s: check_m2_gear.gd's READ_KEYS does not list '%s', so its catalogue cannot see a book at all" % [lane, SimNeeds.TEACH_KEY])
		return false
	# The reader, behaviourally: a book in a pocket is usable and the word menu offers the verb.
	var book: int = _give(w, MANUAL_MEDICINE)
	if book < 0:
		return false
	if not SimNeeds.can_use(w, w.player, book):
		push_error("%s: a survivor with a web and a first aid manual in their pocket cannot use it" % lane)
		return false
	if not SimInventory.verbs_for(w, w.player, book).has("use"):
		push_error("%s: the word menu offers %s for a book, with no 'use' -- the menu and the intake disagree" % [lane, str(SimInventory.verbs_for(w, w.player, book))])
		return false
	# The negatives: a meal is not a book, and a body with no web has nothing to learn into.
	var meal: int = _give(w, FOOD)
	if meal >= 0 and SimNeeds.teaches_spec(w, FOOD) != null:
		push_error("%s: %s reads as a book" % [lane, FOOD])
		return false
	var stranger: int = int(w.entities.spawn())
	SimInventory.make_inventory(w, stranger)
	var their_book: int = SimItems.spawn_item(w, SLIM, {"tier": "scavenged"})
	if not SimInventory.stow(w, stranger, their_book):
		push_error("%s: the webless fixture would not hold a book" % lane)
		return false
	if SimNeeds.can_use(w, stranger, their_book):
		push_error("%s: a body with no skill web was offered a book to read" % lane)
		return false
	if SimNeeds.read_book(w, stranger, their_book):
		push_error("%s: a body with no skill web read a book anyway -- can_use and the intake disagree" % lane)
		return false
	print("%s OK every book on a table, the key in READ_KEYS, the verb offered" % lane)
	return true


# --- TWICE ------------------------------------------------------------------------------------
#
# The lane the slice exists for. Two copies of one title go in the pack; the first is read and the
# second is not, and the assertion is on the **exact** earned total in every region either side of
# the second attempt rather than on a direction of travel.
#
# Two copies matter. With one, the second attempt would be refused because the pack is empty and
# the lane would prove nothing about the ledger at all -- it would pass just as green with the
# memory ripped out. The spare copy is also the realistic case: the tables this slice edited can
# hand the same field manual out of two different houses.
func _a_book_teaches_once_and_a_second_copy_teaches_nothing() -> bool:
	var lane: String = "TWICE"
	var w: Variant = _world()
	var first: int = _give(w, SLIM)
	var second: int = _give(w, SLIM)
	if first < 0 or second < 0 or first == second:
		push_error("%s: the fixture could not hold two separate copies (%d, %d)" % [lane, first, second])
		return false
	var before: Dictionary = _earned_all(w, w.player)
	if not SimNeeds.can_use(w, w.player, first):
		push_error("%s: the first copy could not be read at all, so this lane has nothing to judge" % lane)
		return false
	if not SimNeeds.use_item(w, w.player, first):
		push_error("%s: the first reading was refused" % lane)
		return false
	var after_first: Dictionary = _earned_all(w, w.player)
	var taught: Dictionary = _delta(before, after_first)
	if taught.is_empty():
		push_error("%s: the first reading taught nothing, so the second one cannot be shown to teach less" % lane)
		return false
	# Consumed: one copy, one lesson.
	if SimInventory.owns(w, w.player, first):
		push_error("%s: the copy that was read is still in the pack -- a book is spent on reading" % lane)
		return false
	if not SimInventory.owns(w, w.player, second):
		push_error("%s: reading one copy took the other with it" % lane)
		return false
	# And now the point of the lane.
	if SimNeeds.can_use(w, w.player, second):
		push_error("%s: a second copy of a title already read is still offered -- the menu will offer a use that pays nothing" % lane)
		return false
	if SimNeeds.use_item(w, w.player, second):
		push_error("%s: the second copy was read anyway -- can_use and the intake disagree" % lane)
		return false
	var after_second: Dictionary = _earned_all(w, w.player)
	for r in SimSkills.REGIONS:
		if int(after_second.get(String(r), 0)) != int(after_first.get(String(r), 0)):
			push_error("%s: %s reads %d after the second attempt and read %d after the first -- the same book paid twice" % [lane, String(r), int(after_second.get(String(r), 0)), int(after_first.get(String(r), 0))])
			return false
	if not SimInventory.owns(w, w.player, second):
		push_error("%s: the refused second copy was spent anyway" % lane)
		return false
	if not SimNeeds.has_read(w, w.player, SLIM):
		push_error("%s: the ledger does not remember the title that was read" % lane)
		return false
	# The true negative: the ledger is not simply saying yes to everything, and it belongs to the
	# reader rather than to the colony -- somebody else can still learn from the spare copy.
	if SimNeeds.has_read(w, w.player, MANUAL_CRAFT):
		push_error("%s: the ledger claims a title that was never read" % lane)
		return false
	var mate: int = int(w.entities.spawn())
	SimInventory.make_inventory(w, mate)
	SimSkills.attach(w, mate)
	var handed: int = SimItems.spawn_item(w, SLIM, {"tier": "scavenged"})
	if not SimInventory.stow(w, mate, handed):
		push_error("%s: the second survivor would not hold the book" % lane)
		return false
	if not SimNeeds.can_use(w, mate, handed):
		push_error("%s: a second survivor cannot read a title somebody else has read -- the ledger is the colony's and it should be the reader's" % lane)
		return false
	print("%s OK read once (%s), second copy refused and unspent" % [lane, str(taught)])
	return true


# --- BOUND ------------------------------------------------------------------------------------
#
# A book that out-teaches practice makes practice pointless, and docs/08's web is a record of what
# somebody has actually done. So the ceiling is what doing it once pays.
#
# The ceiling is *measured* first and only then applied: a completed Doctor job is published into a
# real world through the real handler and the payment is counted, and that measured number is what
# every shipped book is held against. Reading the constant alone would let a slice raise
# PRACTICE_POINTS and a book together and call it bounded; the PINNED lane pins the constant to the
# behaviour from the other side.
func _a_book_never_out_teaches_doing_the_work() -> bool:
	var lane: String = "BOUND"
	var w: Variant = _world()
	var before: Dictionary = _earned_all(w, w.player)
	w.events.publish({"type": "job.completed", "entity": w.player, "kind": "Doctor"})
	w.events.drain()
	var by_doing: int = int(_delta(before, _earned_all(w, w.player)).get("Medicine", 0))
	if by_doing < 1:
		push_error("%s: a completed Doctor job paid %d, so there is no measured ceiling to hold a book against" % [lane, by_doing])
		return false
	if by_doing != int(SimSkills.PRACTICE_POINTS):
		push_error("%s: doing the work pays %d and SimSkills.PRACTICE_POINTS says %d -- the constant and the behaviour disagree" % [lane, by_doing, int(SimSkills.PRACTICE_POINTS)])
		return false
	var judged: int = 0
	for entry_v in SimItems.content_entries(w, "item"):
		var e: Dictionary = entry_v as Dictionary
		if not e.has(SimNeeds.TEACH_KEY):
			continue
		var block: Dictionary = e[SimNeeds.TEACH_KEY] as Dictionary
		judged += 1
		if int(block.get("points", 0)) > by_doing:
			push_error("%s: %s teaches %d and doing the work once pays %d -- a book that out-teaches practice makes practice pointless" % [lane, String(e.get("id", "")), int(block.get("points", 0)), by_doing])
			return false
	if judged < 1:
		push_error("%s: no book was judged" % lane)
		return false
	# And the same bound, measured through the reader rather than read off content: what a real
	# reading actually pays into the purse is not more than what a real afternoon pays.
	var rw: Variant = _world()
	var book: int = _give(rw, MANUAL_MEDICINE)
	if book < 0:
		return false
	var rb: Dictionary = _earned_all(rw, rw.player)
	if not SimNeeds.use_item(rw, rw.player, book):
		push_error("%s: the first aid manual could not be read" % lane)
		return false
	var by_reading: Dictionary = _delta(rb, _earned_all(rw, rw.player))
	if by_reading != {"Medicine": by_doing}:
		push_error("%s: reading the first aid manual paid %s and one completed Doctor job pays {\"Medicine\": %d}" % [lane, str(by_reading), by_doing])
		return false
	# The true negative: the predicate the loop above runs has to be able to say no. A fabricated
	# block one point over the measured ceiling is refused by the identical comparison.
	var over: Dictionary = {"region": "Medicine", "points": by_doing + 1}
	if not (int(over.get("points", 0)) > by_doing):
		push_error("%s: a fabricated book worth one point more than the work was not refused by the bound" % lane)
		return false
	print("%s OK %d books, none over %d, a reading pays exactly what an afternoon pays" % [lane, judged, by_doing])
	return true


# --- SAVE -------------------------------------------------------------------------------------
#
# CLAUDE.md's trap, asked of the new component: a per-entity memory that does not survive a load
# comes back empty with nothing reported, and here that would mean every book in the colony
# becoming readable again the moment somebody pressed F9. The ledger is an Array of base ids for
# exactly that reason, and this is the lane that proves the shape rather than trusting it.
#
# The round trip is through real JSON text -- encode, parse, restore -- and not through the
# in-memory snapshot dictionary, because the trap is about what JSON does to keys and an
# in-memory hand-off would never touch one.
func _what_has_been_read_survives_a_save() -> bool:
	var lane: String = "SAVE"
	var w: Variant = _world()
	var book: int = _give(w, MANUAL_SURVIVAL)
	if book < 0:
		return false
	if not SimNeeds.use_item(w, w.player, book):
		push_error("%s: the fixture reading was refused, so there is nothing to save" % lane)
		return false
	var before: Dictionary = _earned_all(w, w.player)
	if not SimNeeds.has_read(w, w.player, MANUAL_SURVIVAL):
		push_error("%s: the title was not in the ledger even before the save" % lane)
		return false
	var text: String = SimSave.encode_save(SimSave.create_save(w))
	# In the save *text*, before anything is restored. A ledger kept anywhere but on the reader --
	# a static, a module-level dictionary, anything the process happens to still be holding -- would
	# survive a restore inside one gate process and be gone the moment the game was actually
	# reopened, which is the `static var` trap docs/30 records twice. This is the assertion that
	# cannot be fooled by the two worlds sharing a process.
	if not text.contains(SimNeeds.READ_COMPONENT):
		push_error("%s: the save text carries no '%s' component -- the ledger is being kept somewhere a save cannot see" % [lane, SimNeeds.READ_COMPONENT])
		return false
	if not text.contains(MANUAL_SURVIVAL):
		push_error("%s: the save text does not name the title that was read" % lane)
		return false
	if text.contains(MANUAL_CRAFT):
		push_error("%s: the save text names a title nothing in this fixture ever touched, so the two assertions above prove nothing" % lane)
		return false
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not ((parsed as Dictionary)["snapshot"] is Dictionary):
		push_error("%s: the save did not come back as an object" % lane)
		return false
	var w2: Variant = _world()
	w2.restore((parsed as Dictionary)["snapshot"] as Dictionary)
	if not SimNeeds.has_read(w2, w2.player, MANUAL_SURVIVAL):
		push_error("%s: after a save and a load the reader had forgotten what they read, with nothing reported" % lane)
		return false
	var after: Dictionary = _earned_all(w2, w2.player)
	for r in SimSkills.REGIONS:
		if int(after.get(String(r), 0)) != int(before.get(String(r), 0)):
			push_error("%s: %s reads %d after the load and read %d before it" % [lane, String(r), int(after.get(String(r), 0)), int(before.get(String(r), 0))])
			return false
	# And the memory is load-bearing after the load, not merely present: another copy of the same
	# title is still refused, and a title never read is still offered.
	var spare: int = SimItems.spawn_item(w2, MANUAL_SURVIVAL, {"tier": "scavenged"})
	if not SimInventory.stow(w2, w2.player, spare):
		push_error("%s: the restored survivor would not hold a spare copy" % lane)
		return false
	if SimNeeds.can_use(w2, w2.player, spare):
		push_error("%s: after a load the same title was offered again" % lane)
		return false
	var fresh: int = SimItems.spawn_item(w2, MANUAL_CRAFT, {"tier": "scavenged"})
	if not SimInventory.stow(w2, w2.player, fresh):
		push_error("%s: the restored survivor would not hold a second title" % lane)
		return false
	if not SimNeeds.can_use(w2, w2.player, fresh):
		push_error("%s: after a load a title nobody has read was refused, so the restored ledger refuses everything" % lane)
		return false
	print("%s OK the ledger came back through JSON and still refuses what it should" % lane)
	return true
