extends SceneTree
# The words the inventory sheet reads, and the rule that decides which verbs it may draw.
#
# The inventory has been mechanically complete since Milestone 1 and the screen has reached four
# of its commands. The 2026-09-08 overhaul (docs/30's "The inventory sheet") gives the screen
# three read models instead of letting it compute anything itself, and this gate holds down the
# three things about them that are easy to get wrong:
#
#  1. **A description is prose, never a measurement.** docs/01 clause 4 bans a UI that collapses
#     uncertainty into a number, and "eighteen damage, twenty-five metres" with a full stop after
#     it is exactly that. DESCRIPTION scans every authored line and INSPECT scans the whole view;
#     both scanners are proved able to fail before either is trusted, because a textual assertion
#     needs to be shown it is reading what it thinks it is (CLAUDE.md's traps, the `_low_arms`
#     lesson).
#
#  2. **A verb is offered iff the sim would accept it.** `work_panel.gd`'s rule and
#     `SimTreatment.response_view`'s contract: a thing you cannot do is absent, not greyed. So
#     every VERBS assertion is a pair -- the loadout where the verb belongs and the loadout where
#     it does not -- and then the dead-socket half: the command each offered verb maps to is
#     actually pushed, and the sim state actually moves. A verb list nothing acts on is the
#     eleventh dead socket of this milestone waiting to happen.
#
#  3. **The strip spends what you pressed.** `_complete` has always picked the best dressing in
#     the pack. A number key naming one has to beat that, or the strip is a decoration: press the
#     dirty rag and the sterile bandage in the same pocket must survive. That is one lane with its
#     true positive and true negative in the same world.
#
# Every lane carries its true negative. A gate that cannot fail is worse than no gate.

const World = preload("res://sim/world.gd")
const ContentLoader = preload("res://platform/content_loader.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWounds = preload("res://sim/modules/wounds.gd")
const SimTreatment = preload("res://sim/modules/treatment.gd")
const SimNeeds = preload("res://sim/modules/needs.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimAttachments = preload("res://sim/modules/attachments.gd")
const SimContainers = preload("res://sim/modules/containers.gd")

# The pane's whole vocabulary. Adding a key here is a decision about what the player is told, so
# it is made in this file as well as in the read model -- the `check_ban_health_bar` arrangement,
# and the reason a numeric field cannot be added to either by accident.
const INSPECT_KEYS: Array[String] = ["item", "name", "condition", "description", "slot", "worn", "attachments", "fits"]
# `item` is an entity handle the screen routes a click with, never drawn. Every other value is a
# word, a boolean, or a list of words.
const INSPECT_HANDLE: String = "item"

const PART: String = "torso"
const DEEP_DAMAGE: float = 20.0

const INSPECT_PANE_GD: String = "res://ui/inspect_pane.gd"
const PANEL_GD: String = "res://ui/inventory_panel.gd"

var _tree_cache: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok: bool = true
	ok = _every_base_says_what_it_is() and ok
	ok = _a_base_with_nothing_authored_still_says_something() and ok
	ok = _the_pane_carries_only_words() and ok
	ok = _a_verb_is_offered_only_when_it_would_work() and ok
	ok = _every_offered_verb_reaches_a_command() and ok
	ok = _the_strip_is_the_belt_and_the_pockets() and ok
	ok = _the_strip_spends_what_you_pressed() and ok
	ok = await _the_column_is_in_a_fixed_order() and ok
	ok = _the_windows_are_gone_and_the_keys_moved() and ok
	ok = await _a_cupboard_is_a_column_and_a_window() and ok
	if ok:
		print("INVENTORY_OK descriptions are prose, the pane carries only words, a verb is offered iff it works and reaches its command, the strip is belt and pockets and spends what you pressed, the column is fixed, the windows are gone, and a cupboard is a column and a window")
		quit(0)
	else:
		push_error("INVENTORY_FAIL")
		quit(1)


# --- helpers ------------------------------------------------------------------------------

func _tree() -> Dictionary:
	if _tree_cache.is_empty():
		_tree_cache = ContentLoader.load_tree()
	return _tree_cache


# Every shipped item base, as {id: entry}.
func _bases() -> Dictionary:
	var out: Dictionary = {}
	for path in _tree().keys():
		if not String(path).begins_with("items/"):
			continue
		var value: Variant = _tree()[path]
		if value is Array:
			for entry in value as Array:
				if entry is Dictionary:
					out[String((entry as Dictionary).get("id", "?"))] = entry as Dictionary
	return out


# A key's name is not a measurement: "F1" and the strip's "1 . 6" are what you press, and the ban
# is on a number that stands for a quantity. So the key line is scanned with the key names taken
# out first -- exactly the way `check_hud` strips the day token before scanning a HUD line rather
# than widening the scanner to tolerate it. "speed: 1x, 3x, 10x", the line this replaced, still
# fails: an x after a digit is not a key.
static func _without_key_names(text: String) -> String:
	var out: String = text
	for key in ["F1", "F2", "F5", "F8", "F9"]:
		out = out.replace(key, "")
	# A bare digit surrounded by spaces or punctuation is a key; one glued to a letter is not.
	var stripped: String = ""
	for i in out.length():
		var ch: String = out[i]
		if ch >= "0" and ch <= "9":
			var before: String = out[i - 1] if i > 0 else " "
			var after: String = out[i + 1] if i + 1 < out.length() else " "
			var alone: bool = not _is_letter(before) and not _is_letter(after) and not (after >= "0" and after <= "9")
			if alone:
				continue
		stripped += ch
	return stripped


static func _is_letter(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")


# The one scanner, so DESCRIPTION and INSPECT cannot disagree about what a digit is. Proved able
# to fail in `_the_pane_carries_only_words` before either lane trusts it.
static func _carries_a_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


func _world(seed_val: int) -> Variant:
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
	SimNeeds.register_module(w)
	SimItems.register_module(w)
	SimInventory.register_module(w)
	SimAttachments.register_module(w)
	SimHealth.make_survivor_body(w, w.player)
	SimHealth.make_stamina(w, w.player, 100)
	SimNeeds.attach(w, w.player)
	SimInventory.make_inventory(w, w.player)
	return w


func _give(w: Variant, base_id: String, count: int = 1) -> int:
	var item: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged", "count": count})
	if not SimInventory.stow(w, w.player, item):
		return -1
	return item


# Worn straight onto the body rather than stowed first. Pockets are eight cells and a medic pouch
# is nine of them, so a belt pouch can never reach a belt through `stow`.
func _wear(w: Variant, base_id: String, slot: String) -> int:
	var item: int = SimItems.spawn_item(w, base_id, {"tier": "scavenged"})
	if not SimInventory.equip(w, w.player, item, slot):
		return -1
	return item


# Room to carry a fixture. Pockets hold eight cells and a leather jacket is six of them, so any
# lane with more than one bulky thing in it needs a pack on the back first.
func _room(w: Variant) -> bool:
	return _wear(w, "item.pack.frame", "back") >= 0


# The most a base will stack to. Read rather than assumed: canned food stops at three, and a
# fixture asking for four gets three, which silently turns "split a stack" into "split the last
# one" and despawns the item the next assertion is about.
func _stack_limit(w: Variant, base_id: String) -> int:
	var entry: Variant = SimItems.content_entry(w, "item", base_id)
	return SimItems.base_stack_limit(entry as Dictionary) if entry is Dictionary else 1


# A real bleeding wound through the real path, so `bandage` has something to answer.
func _wound(w: Variant) -> bool:
	w.events.publish({"type": "attack.connected", "attacker": -1, "target": w.player, "bodyPart": PART, "damage": DEEP_DAMAGE})
	w.step()
	var inj: Variant = w.components.get_component(w.player, "injuries")
	if not (inj is Dictionary):
		return false
	return not ((inj as Dictionary).get("wounds", []) as Array).is_empty()


# --- DESCRIPTION ----------------------------------------------------------------------------

# Every shipped base says what it is, in prose. Authored rather than generated for all of them:
# the fallback exists so a base added tomorrow is never blank on the screen, not so the catalogue
# can stay silent -- "A tool." on the whetstone and on the sewing kit alike is a screen that has
# stopped telling you anything.
func _every_base_says_what_it_is() -> bool:
	var bases: Dictionary = _bases()
	if bases.size() < 40:
		push_error("only %d item bases found -- the content walk is not reading items/" % bases.size())
		return false
	var blank: Array[String] = []
	var numeric: Array[String] = []
	for id in bases.keys():
		var text: String = String((bases[id] as Dictionary).get("description", ""))
		if text.strip_edges().is_empty():
			blank.append(String(id))
			continue
		if _carries_a_digit(text):
			numeric.append("%s: \"%s\"" % [String(id), text])
	if not blank.is_empty():
		push_error("%d shipped bases carry no description: %s" % [blank.size(), ", ".join(blank)])
		return false
	if not numeric.is_empty():
		push_error("a description carries a digit, which is docs/01 clause 4 with a full stop after it: %s" % ", ".join(numeric))
		return false
	print("DESCRIPTION OK %d shipped bases, every one authored and digit-free" % bases.size())
	return true


# The fallback, and the true negative for the lane above: a base with nothing authored still gets
# a sentence, and two *different* kinds of base get two *different* sentences. One sentence for
# everything would satisfy "non-empty" and tell the player nothing, which is the failure this
# assertion exists to catch.
func _a_base_with_nothing_authored_still_says_something() -> bool:
	var axe: String = SimItems.generated_description({"class": "weapon.melee", "equipSlot": "primary"})
	var boot: String = SimItems.generated_description({"class": "armor", "equipSlot": "feet"})
	var scrap: String = SimItems.generated_description({"class": "material"})
	var odd: String = SimItems.generated_description({"class": "not_a_class_anybody_wrote"})
	for pair in [["primary", axe], ["feet", boot], ["material", scrap], ["unknown", odd]]:
		if String((pair as Array)[1]).strip_edges().is_empty():
			push_error("the %s fallback is blank" % String((pair as Array)[0]))
			return false
		if _carries_a_digit(String((pair as Array)[1])):
			push_error("the %s fallback carries a digit: \"%s\"" % [String((pair as Array)[0]), String((pair as Array)[1])])
			return false
	if axe == boot or boot == scrap:
		push_error("the fallback says the same thing about a weapon, a boot and a scrap: \"%s\" / \"%s\" / \"%s\"" % [axe, boot, scrap])
		return false
	# The slot outranks the class, because "worn on the feet" says more than "something to wear".
	if boot == SimItems.generated_description({"class": "armor"}):
		push_error("the equip slot changed nothing: a boot and a bare armour base both read \"%s\"" % boot)
		return false
	# And an authored line wins over both, which is the only reason the content is worth writing.
	var w: Variant = _world(3101)
	var authored: String = SimItems.description_of(w, "item.axe.fire")
	if authored == axe:
		push_error("item.axe.fire fell back to the generated sentence rather than reading its own")
		return false
	print("FALLBACK OK a base with nothing authored reads \"%s\"; the slot outranks the class; an authored line outranks both" % scrap)
	return true


# --- INSPECT --------------------------------------------------------------------------------

# What the pane is handed, held to the same shape `check_ban_health_bar` holds the condition view
# to: exactly these keys, every value a word or a boolean or a list of words, and not one digit in
# any of them. The `item` handle is the single exception and is named as one -- the screen routes
# a click with it and never draws it.
func _the_pane_carries_only_words() -> bool:
	# First: prove the scanners can fail, on a fabricated view, before trusting them on a real one.
	var sabotage: Dictionary = {
		"item": 7, "name": "Service Pistol", "condition": "worn",
		"description": "A service pistol. 18 damage at 25 metres.", "slot": "secondary",
		"worn": true, "attachments": [], "fits": [],
	}
	if _inspect_faults(sabotage).is_empty():
		push_error("the pane scanner passed a description reading \"%s\"" % String(sabotage["description"]))
		return false
	var extra: Dictionary = sabotage.duplicate()
	extra["description"] = "A service pistol."
	extra["damage"] = 18
	if _inspect_faults(extra).is_empty():
		push_error("the key allowlist passed a view carrying a numeric \"damage\" field")
		return false
	var missing: Dictionary = sabotage.duplicate()
	missing["description"] = "A service pistol."
	missing.erase("condition")
	if _inspect_faults(missing).is_empty():
		push_error("the key allowlist passed a view with no condition word")
		return false

	# Now the real thing, on a loadout that fills every branch: a worn coat, a held weapon with an
	# attachment fitted and an empty slot beside it, a loose attachment, and a plain stack.
	var w: Variant = _world(3102)
	if not _room(w):
		push_error("the pack would not go on")
		return false
	var coat: int = _give(w, "item.jacket.leather")
	var pistol: int = _give(w, "item.pistol.service")
	var can: int = _give(w, "item.attach.suppressor")
	var dot: int = _give(w, "item.attach.optic.red_dot")
	var tins: int = _give(w, "item.food.canned", _stack_limit(w, "item.food.canned"))
	if coat < 0 or pistol < 0 or can < 0 or dot < 0 or tins < 0:
		push_error("the fixture could not be carried")
		return false
	if not SimInventory.equip(w, w.player, coat, "torso"):
		push_error("the coat would not go on")
		return false
	if not SimAttachments.attach(w, pistol, can, "barrel"):
		push_error("the suppressor would not fit the pistol")
		return false

	var checked: int = 0
	for item in [coat, pistol, can, dot, tins]:
		var view: Dictionary = SimInventory.inspect_view(w, w.player, int(item))
		if view.is_empty():
			push_error("inspect_view said nothing about item %d" % int(item))
			return false
		var faults: Array = _inspect_faults(view)
		if not faults.is_empty():
			push_error("inspect_view of %s: %s" % [String(view.get("name", "?")), ", ".join(PackedStringArray(faults))])
			return false
		checked += 1

	# The fields that would otherwise be present and empty for everybody, which is how a read model
	# quietly becomes a dead socket.
	var gun: Dictionary = SimInventory.inspect_view(w, w.player, pistol)
	var slots: Array = gun.get("attachments", []) as Array
	if slots.size() < 2:
		push_error("the pistol reported %d attachment slots" % slots.size())
		return false
	var filled: int = 0
	var empty: int = 0
	for row in slots:
		if String((row as Dictionary).get("name", "")).is_empty():
			empty += 1
		else:
			filled += 1
	if filled < 1 or empty < 1:
		push_error("the pistol's slots read %d filled and %d empty; the lane needs one of each to prove both" % [filled, empty])
		return false
	var scope: Dictionary = SimInventory.inspect_view(w, w.player, dot)
	if (scope.get("fits", []) as Array).is_empty():
		push_error("a loose red dot listed nothing it fits")
		return false
	if not (SimInventory.inspect_view(w, w.player, coat).get("worn", false)):
		push_error("the worn coat did not read as worn")
		return false
	if bool(SimInventory.inspect_view(w, w.player, tins).get("worn", true)):
		push_error("a tin in a pocket read as worn")
		return false
	# And nothing at all for something that is not an item, which is the shape the screen relies
	# on to draw an empty pane rather than a pane full of defaults.
	if not SimInventory.inspect_view(w, w.player, w.player).is_empty():
		push_error("inspect_view described the survivor holding the inventory")
		return false

	# The reader half. Until the sheet exists there is nothing to assert, and this says so rather
	# than passing quietly -- an assertion with no data to judge is the thing CLAUDE.md's
	# conventions section forbids.
	if ResourceLoader.exists(INSPECT_PANE_GD):
		var src: String = FileAccess.get_file_as_string(INSPECT_PANE_GD)
		if src.find("description") < 0:
			push_error("%s exists and never reads `description` -- the sentence is a dead socket" % INSPECT_PANE_GD)
			return false
		print("INSPECT OK %d views, every value a word or a boolean; %s draws the sentence" % [checked, INSPECT_PANE_GD])
		return true
	print("INSPECT OK %d views, every value a word or a boolean; the reader half SKIPPED -- %s does not exist yet" % [checked, INSPECT_PANE_GD])
	return true


# Everything wrong with one inspect view, as a list of sentences. Empty means clean.
func _inspect_faults(view: Dictionary) -> Array:
	var out: Array = []
	for key in view.keys():
		if not INSPECT_KEYS.has(String(key)):
			out.append("unexpected key \"%s\"" % String(key))
	for key in INSPECT_KEYS:
		if not view.has(key):
			out.append("missing key \"%s\"" % key)
	for key in view.keys():
		var name: String = String(key)
		if name == INSPECT_HANDLE:
			continue
		var value: Variant = view[key]
		if value is String:
			if _carries_a_digit(value as String):
				out.append("\"%s\" carries a digit: \"%s\"" % [name, String(value)])
		elif value is bool:
			pass
		elif value is Array:
			for row in value as Array:
				if row is String:
					if _carries_a_digit(row as String):
						out.append("\"%s\" carries a digit: \"%s\"" % [name, String(row)])
				elif row is Dictionary:
					for sub in (row as Dictionary).values():
						if not (sub is String):
							out.append("\"%s\" carries a %s where a word belongs" % [name, type_string(typeof(sub))])
						elif _carries_a_digit(sub as String):
							out.append("\"%s\" carries a digit: \"%s\"" % [name, String(sub)])
				else:
					out.append("\"%s\" carries a %s where a word belongs" % [name, type_string(typeof(row))])
		else:
			out.append("\"%s\" is a %s; only the entity handle may be one" % [name, type_string(typeof(value))])
	return out


# --- VERBS ----------------------------------------------------------------------------------

# Each verb asserted present where it belongs and absent where it does not, in one world, with
# everything else held fixed. Absent is half the contract: the screen draws what comes back, so a
# verb that is always offered is a menu entry the sim silently drops.
func _a_verb_is_offered_only_when_it_would_work() -> bool:
	var w: Variant = _world(3103)
	if not _room(w):
		push_error("the pack would not go on")
		return false
	var coat: int = _give(w, "item.jacket.leather")
	var tins: int = _give(w, "item.food.canned", _stack_limit(w, "item.food.canned"))
	var one_tin: int = _give(w, "item.food.jerky")
	var pouch: int = _give(w, "item.pouch.utility")
	var scrap: int = _give(w, "item.scrap.metal")
	var rag: int = _give(w, "item.rag.dirty")
	if coat < 0 or tins < 0 or one_tin < 0 or pouch < 0 or scrap < 0 or rag < 0:
		push_error("the fixture could not be carried")
		return false

	var pairs: Array = [
		# verb, where it belongs, where it does not, why
		["equip", coat, scrap, "a coat can be worn and a twist of scrap cannot"],
		["split", tins, one_tin, "a full stack can be split and a single cannot"],
		["open", pouch, scrap, "a pouch opens and scrap does not"],
		["use", tins, scrap, "a tin can be eaten and scrap cannot"],
	]
	for row in pairs:
		var r: Array = row as Array
		var verb: String = String(r[0])
		if not SimInventory.verbs_for(w, w.player, int(r[1])).has(verb):
			push_error("\"%s\" was not offered where it belongs (%s)" % [verb, String(r[3])])
			return false
		if SimInventory.verbs_for(w, w.player, int(r[2])).has(verb):
			push_error("\"%s\" was offered where it does not belong (%s)" % [verb, String(r[3])])
			return false

	# Worn and unworn are the same item twice, which is the strongest form of this assertion: the
	# menu changes because the world changed, not because the item is a different one.
	if SimInventory.verbs_for(w, w.player, coat).has("unequip"):
		push_error("\"unequip\" was offered on a coat in the pack")
		return false
	if not SimInventory.equip(w, w.player, coat, "torso"):
		push_error("the coat would not go on")
		return false
	var worn: Array[String] = SimInventory.verbs_for(w, w.player, coat)
	if not worn.has("unequip"):
		push_error("\"unequip\" was not offered on a worn coat")
		return false
	for gone in ["equip", "drop", "split", "use", "open"]:
		if worn.has(gone):
			push_error("\"%s\" was offered on a coat that is being worn" % gone)
			return false

	# The medical half, which is the one that routes outside this module: a dressing is usable
	# only when there is something to dress, and the predicate asked is the sim's own.
	if SimInventory.verbs_for(w, w.player, rag).has("use"):
		push_error("\"use\" was offered on a dressing with nothing bleeding")
		return false
	if not _wound(w):
		push_error("the fixture would not bleed")
		return false
	if not SimInventory.verbs_for(w, w.player, rag).has("use"):
		push_error("\"use\" was not offered on a dressing with an open wound in front of it")
		return false

	# And nothing at all for somebody else's property, which is what stops the loot window from
	# offering "equip" on the contents of a cupboard.
	var stranger: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	if not SimInventory.verbs_for(w, w.player, stranger).is_empty():
		push_error("verbs were offered on an item nobody is carrying")
		return false
	print("VERBS OK equip, unequip, split, open, use and drop each offered where they belong and absent where they do not")
	return true


# The dead-socket half, and the reason the lane above is not enough: a list of words is worth
# nothing until something acts on it. Every verb the menu offers is pushed as the command the
# screen pushes, and the world has to move.
func _every_offered_verb_reaches_a_command() -> bool:
	var w: Variant = _world(3104)
	if not _room(w):
		push_error("the pack would not go on")
		return false
	var coat: int = _give(w, "item.jacket.leather")
	# A full stack, and split by one rather than in half: this lane spends the same stack four
	# times over, and a stack of three split down the middle leaves one tin to eat and nothing to
	# drop. (Canned food stops at three, which is exactly how this lane first went red.)
	var limit: int = _stack_limit(w, "item.food.canned")
	var tins: int = _give(w, "item.food.canned", limit)
	if coat < 0 or tins < 0 or limit < 3:
		push_error("the fixture could not be carried (stack limit %d)" % limit)
		return false

	# equip
	if not SimInventory.verbs_for(w, w.player, coat).has("equip"):
		push_error("\"equip\" was not on offer")
		return false
	w.commands.push({"type": "item.equip", "item": coat, "slot": "torso"})
	w.step()
	if not bool(SimInventory.inspect_view(w, w.player, coat).get("worn", false)):
		push_error("the offered \"equip\" pushed a command that did nothing")
		return false

	# unequip
	if not SimInventory.verbs_for(w, w.player, coat).has("unequip"):
		push_error("\"unequip\" was not on offer for a worn coat")
		return false
	w.commands.push({"type": "item.unequip", "slot": "torso", "item": coat})
	w.step()
	if bool(SimInventory.inspect_view(w, w.player, coat).get("worn", true)):
		push_error("the offered \"unequip\" pushed a command that did nothing")
		return false

	# split
	if not SimInventory.verbs_for(w, w.player, tins).has("split"):
		push_error("\"split\" was not on offer for a full stack")
		return false
	var before: int = SimInventory.carried_items(w, w.player).size()
	w.commands.push({"type": "item.split", "item": tins, "count": 1})
	w.step()
	if SimInventory.carried_items(w, w.player).size() != before + 1:
		push_error("the offered \"split\" pushed a command that did nothing: %d carried before and after" % before)
		return false

	# use
	if not SimInventory.verbs_for(w, w.player, tins).has("use"):
		push_error("\"use\" was not on offer for a tin")
		return false
	var stack_before: int = _count_of(w, tins)
	w.commands.push({"type": "item.use", "item": tins})
	w.step()
	if _count_of(w, tins) >= stack_before:
		push_error("the offered \"use\" pushed a command that ate nothing: %d before, %d after" % [stack_before, _count_of(w, tins)])
		return false

	# drop
	if not SimInventory.verbs_for(w, w.player, tins).has("drop"):
		push_error("\"drop\" was not on offer")
		return false
	w.commands.push({"type": "item.drop", "item": tins})
	w.step()
	if SimInventory.owns(w, w.player, tins):
		push_error("the offered \"drop\" pushed a command that dropped nothing")
		return false
	if not (w.components.get_component(tins, "position") is Dictionary):
		push_error("the dropped tin is nowhere")
		return false
	print("COMMANDS OK every offered verb pushed its command and the world moved")
	return true


func _count_of(w: Variant, item: int) -> int:
	var st: Variant = w.components.get_component(item, "stack")
	if st is Dictionary:
		return int((st as Dictionary).get("count", 1))
	return 1 if w.components.has_component(item, "itemBase") else 0


# --- STRIP ----------------------------------------------------------------------------------

# What the number keys reach: the pockets and the belt, and neither the back nor the vest. The
# rule is the pinnable windows' old one -- a pouch on your front is reachable mid-fight and a
# backpack is not -- and the true negative is the item in the pack that must not appear.
func _the_strip_is_the_belt_and_the_pockets() -> bool:
	var w: Variant = _world(3105)
	var pouch: int = _wear(w, "item.pouch.medic", "belt")
	var pack: int = _wear(w, "item.pack.frame", "back")
	if pouch < 0 or pack < 0:
		push_error("the pouch and the pack would not go on")
		return false

	var in_pocket: int = SimItems.spawn_item(w, "item.bandage.cloth", {"tier": "scavenged"})
	if not SimInventory.store_anywhere(w, in_pocket, w.player):
		push_error("nothing would go in a pocket")
		return false
	var on_belt: int = SimItems.spawn_item(w, "item.painkillers.blister", {"tier": "scavenged"})
	if not SimInventory.store_anywhere(w, on_belt, pouch):
		push_error("nothing would go in the belt pouch")
		return false
	var in_pack: int = SimItems.spawn_item(w, "item.food.canned", {"tier": "scavenged"})
	if not SimInventory.store_anywhere(w, in_pack, pack):
		push_error("nothing would go in the pack")
		return false

	var strip: Array = SimInventory.quick_strip_view(w, w.player)
	var ids: Array = []
	for row in strip:
		ids.append(int((row as Dictionary)["item"]))
	if not ids.has(in_pocket):
		push_error("what is in a pocket is not on the strip")
		return false
	if not ids.has(on_belt):
		push_error("what is on the belt is not on the strip")
		return false
	if ids.has(in_pack):
		push_error("what is in the pack reached the strip; a backpack is not a thing you open mid-fight")
		return false

	# Six at most, because six is how many keys there are. Filled past the cap on purpose.
	for _i in range(12):
		var filler: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged"})
		SimInventory.store_anywhere(w, filler, w.player)
	var full: Array = SimInventory.quick_strip_view(w, w.player)
	if full.size() > SimInventory.STRIP_SLOTS:
		push_error("the strip offered %d entries for %d keys" % [full.size(), SimInventory.STRIP_SLOTS])
		return false
	for row in full:
		var d: Dictionary = row as Dictionary
		if String(d.get("name", "")).is_empty():
			push_error("a strip entry has no name")
			return false
		if _carries_a_digit(String(d.get("name", ""))):
			push_error("a strip entry's name carries a digit: \"%s\"" % String(d.get("name", "")))
			return false
	print("STRIP OK the pocket and the belt are on it, the pack is not, and %d entries fill %d keys" % [full.size(), SimInventory.STRIP_SLOTS])
	return true


# The strip key spends the item under it, not the best one in the pack. Both halves in one world:
# press the dirty rag with a sterile dressing in the same pocket, and the sterile dressing must
# still be there afterwards -- which is exactly what `_complete` did NOT do before the channel
# could be told which supply it was reaching for.
func _the_strip_spends_what_you_pressed() -> bool:
	var w: Variant = _world(3106)
	if not _room(w):
		push_error("the pack would not go on")
		return false
	var rag: int = _give(w, "item.rag.dirty")
	var sterile: int = _give(w, "item.medkit.field")
	if rag < 0 or sterile < 0:
		push_error("the fixture could not be carried")
		return false
	if not _wound(w):
		push_error("the fixture would not bleed")
		return false

	# The strip's own row is what the key reaches, and the item under it is the one pressed.
	var strip: Array = SimInventory.quick_strip_view(w, w.player)
	var pressed: int = -1
	for row in strip:
		if int((row as Dictionary)["item"]) == rag:
			pressed = rag
	if pressed < 0:
		push_error("the dirty rag is not on the strip, so no key reaches it")
		return false

	w.commands.push({"type": "item.use", "item": pressed})
	w.step()
	var channel: Variant = w.components.get_component(w.player, "treatment")
	if not (channel is Dictionary):
		push_error("pressing a dressing's key began no channel")
		return false
	var state: Dictionary = channel as Dictionary
	if String(state.get("verb", "")) != "bandage":
		push_error("pressing a dressing's key began a \"%s\" channel" % String(state.get("verb", "")))
		return false
	if int(state.get("supply", -1)) != pressed:
		push_error("the channel remembered supply %d rather than the rag the key named (%d)" % [int(state.get("supply", -1)), pressed])
		return false

	# Run it out.
	for _t in range(4000):
		if not w.components.has_component(w.player, "treatment"):
			break
		w.step()
	if w.components.has_component(w.player, "treatment"):
		push_error("the channel never finished")
		return false

	if SimInventory.owns(w, w.player, rag):
		push_error("the channel finished and the rag it named is still in the pack")
		return false
	if not SimInventory.owns(w, w.player, sterile):
		push_error("the channel spent the sterile medkit rather than the rag the key named -- the strip is a decoration")
		return false
	# And the dressing that was actually applied is the one pressed, which is the tier the wound
	# records: a dirty rag leaves a dirty dressing, and getting this wrong would make the strip
	# quietly better than the pack.
	var inj: Dictionary = w.components.get_component(w.player, "injuries") as Dictionary
	var tier: String = ""
	for wd in (inj.get("wounds", []) as Array):
		var d: Dictionary = wd as Dictionary
		if String(d.get("bandage", "")) != "":
			tier = String(d.get("bandage", ""))
	if tier != "dirty":
		push_error("the wound records a \"%s\" dressing after a dirty rag was pressed" % tier)
		return false
	print("SUPPLY OK the key spent the rag it named, the sterile medkit in the same pack survived, and the wound records a dirty dressing")
	return true


# --- SHEET ------------------------------------------------------------------------------

# The column, in the order the owner picked: pockets first because they are always there, then the
# belt, the vest and the back, then whatever nested bag the player chose to open. It is asserted
# rather than assumed because it is a *decision* about what you reach for first, and
# `reachable_containers` hands them over in its own order (pockets, then everything nested inside
# them, then what is worn) which is not this one.
func _the_column_is_in_a_fixed_order() -> bool:
	var w: Variant = _world(3107)
	var pouch: int = _wear(w, "item.pouch.medic", "belt")
	var rig: int = _wear(w, "item.rig.chest", "vest")
	var pack: int = _wear(w, "item.pack.frame", "back")
	if pouch < 0 or rig < 0 or pack < 0:
		push_error("the loadout would not go on")
		return false
	# A nested bag, inside the pack: reachable, and deliberately not a column until it is opened.
	var box: int = SimItems.spawn_item(w, "item.toolbox.steel", {"tier": "scavenged"})
	if not SimInventory.store_anywhere(w, box, pack):
		push_error("the toolbox would not go in the pack")
		return false

	var panel: Control = (load(PANEL_GD) as GDScript).new() as Control
	root.add_child(panel)
	await process_frame
	panel.call("set_world", w, w.player)
	panel.call("set_open", true)

	var labels: Array = panel.call("column_labels")
	var want: Array = ["pockets", SimItems.item_name(w, pouch), SimItems.item_name(w, rig), SimItems.item_name(w, pack)]
	if labels != want:
		push_error("the column read %s rather than %s" % [str(labels), str(want)])
		panel.queue_free()
		return false

	# Opened, and then closed again: the nested bag is a column only while the player has asked
	# for it, which is what the `open` verb means and the difference between a fixed sheet and a
	# sheet that grows a grid every time somebody picks up a pouch.
	panel.call("_act", "open", box)
	panel.call("set_world", w, w.player)
	var opened: Array = panel.call("column_labels")
	if opened.size() != want.size() + 1 or String(opened[opened.size() - 1]) != SimItems.item_name(w, box):
		push_error("opening the toolbox gave the column %s" % str(opened))
		panel.queue_free()
		return false
	panel.call("_act", "open", box)
	panel.call("set_world", w, w.player)
	if panel.call("column_labels") != want:
		push_error("closing the toolbox left it in the column")
		panel.queue_free()
		return false

	# And a bag that is no longer carried leaves no column behind. Dropped through the queue, the
	# way the screen drops one.
	panel.call("_act", "open", box)
	w.commands.push({"type": "item.drop", "item": box})
	w.step()
	panel.call("set_world", w, w.player)
	var after: Array = panel.call("column_labels")
	if after != want:
		push_error("dropping the opened toolbox left the column reading %s" % str(after))
		panel.queue_free()
		return false
	print("SHEET OK the column is pockets, belt, vest, back; a nested bag joins it only when opened and leaves when dropped")
	panel.queue_free()
	return true


# The screen's own text, and the pieces of main.gd that reach it. Textual, because what is being
# asserted is that the *old* arrangement is gone -- a deleted file that something still preloads
# is a parse error, but a stale key binding or a remembered window position is silent.
func _the_windows_are_gone_and_the_keys_moved() -> bool:
	var faults: Array[String] = []
	if ResourceLoader.exists("res://ui/container_window.gd"):
		faults.append("ui/container_window.gd still exists")
	var prefs: String = FileAccess.get_file_as_string("res://ui/prefs.gd")
	if prefs.find("\"windows\"") >= 0 or prefs.find("pinned_opacity") >= 0:
		faults.append("ui/prefs.gd still remembers window positions or the pinned-bag opacity")
	var main: String = FileAccess.get_file_as_string("res://presentation/main.gd")
	if main.find("KEY_1: speed") >= 0 or main.find("KEY_2: speed") >= 0:
		faults.append("main.gd still binds the number row to speed")
	for needed in ["KEY_MINUS", "KEY_EQUAL", "_strip_use", "strip_use"]:
		if main.find(needed) < 0:
			faults.append("main.gd never mentions %s" % needed)
	var legend: String = FileAccess.get_file_as_string("res://ui/legend.gd")
	if legend.find("- / =") < 0:
		faults.append("the legend does not name the speed keys")
	if legend.find("pin it to keep it on screen") >= 0:
		faults.append("the legend still tells the player to pin a bag")
	# The HUD's key line is on the player's HUD, so it is under the digit ban like everything else
	# there -- and it is the line most likely to grow one back, because it names keys.
	var hud: String = FileAccess.get_file_as_string("res://ui/hud.gd")
	var line: String = ""
	for row in hud.split("\n"):
		if String(row).find("var keys: String") >= 0:
			line = String(row)
	if line.is_empty():
		faults.append("ui/hud.gd has no key line")
	elif _carries_a_digit(_without_key_names(line.substr(line.find("\"") + 1))):
		faults.append("the HUD's key line carries a digit that is not a key's name: %s" % line.strip_edges())
	# The strip has to be on screen during play, not only on the open sheet: it is what the
	# pinnable pouches were deleted in favour of, and a strip you can only see with the screen
	# open is a pouch you can only reach with the screen open -- the exact thing the windows were
	# kept for. `_draw` returns early when closed, so the strip has to be drawn *before* it does.
	var panel_src: String = FileAccess.get_file_as_string(PANEL_GD)
	var draw_body: String = ""
	var inside: bool = false
	for row in panel_src.split("\n"):
		if String(row).begins_with("func _draw()"):
			inside = true
			continue
		if inside and String(row).begins_with("func "):
			break
		if inside:
			draw_body += String(row) + "\n"
	if draw_body.is_empty():
		faults.append("could not read _draw out of the sheet, so the strip assertion has nothing to judge")
	else:
		var early: int = draw_body.find("if not _open:")
		var strip: int = draw_body.find("QuickStrip.draw_strip")
		if early < 0 or strip < 0:
			faults.append("_draw has no closed-sheet branch or never draws the strip")
		elif strip > draw_body.find("return", early) and draw_body.find("QuickStrip.draw_strip", early) > draw_body.find("return", early):
			faults.append("the strip is drawn only after the closed-sheet return, so it is invisible during play")

	# And the narrowed scanner still catches what it is for. The line this one replaced said
	# "speed: 1x, 3x, 10x", and an x after a digit is a quantity however it is punctuated.
	if not _carries_a_digit(_without_key_names("F1 keys - speed: 1x, 3x, 10x")):
		faults.append("the key-line scanner would pass \"speed: 1x, 3x, 10x\", so it is judging nothing")
	if _carries_a_digit(_without_key_names("F1 keys - 1 . 6 use - Esc settings")):
		faults.append("the key-line scanner rejects a bare key name, so it would fail any legal line")
	if not faults.is_empty():
		push_error("; ".join(faults))
		return false
	print("KEYS OK the windows and their prefs are gone, the strip draws during play, the number row spends it, speed is - and =, and the HUD's key line is digit-free")
	return true


# --- LOOT -------------------------------------------------------------------------------

# A container you are standing at reaches the screen twice, and the two must not both be up at
# once: as the **first column** of the sheet (above what you are carrying -- it is the thing you
# opened the screen for, and the only column that is not yours), and as a small **transfer
# window** beside your pockets while the sheet is closed, so a loot stop never leaves the
# district.
func _a_cupboard_is_a_column_and_a_window() -> bool:
	var w: Variant = _world(3108)
	SimContainers.register_module(w)
	var actor: int = w.player
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary
	# A table this bare world can roll. `_world` builds no district, so the loot content is
	# reached the same way the game reaches it and the box is stood by hand.
	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	if not bool(SimContainers.open(w, actor, box).get("ok", false)):
		push_error("the fixture cupboard would not open")
		return false

	var panel: Control = (load(PANEL_GD) as GDScript).new() as Control
	root.add_child(panel)
	await process_frame
	panel.call("set_world", w, actor)

	# Closed sheet: the window is up, and it is the only thing stopping the mouse -- a Control
	# that ate clicks over the whole screen would eat the one that swings your axe.
	panel.call("set_open", false)
	panel.call("set_loot", SimContainers.open_view(w, actor))
	if not bool(panel.call("loot_open")):
		push_error("standing at an open cupboard with the sheet closed showed no transfer window")
		return false
	var layer: Variant = panel.get("_loot_layer")
	if not (layer is Control):
		push_error("the transfer window has no control of its own")
		return false
	var win: Control = layer as Control
	if win.mouse_filter != Control.MOUSE_FILTER_STOP:
		push_error("the transfer window does not stop the mouse, so nothing in it can be clicked")
		return false
	if int(panel.get("mouse_filter")) != Control.MOUSE_FILTER_IGNORE:
		push_error("the closed sheet stops the mouse, so a click anywhere would never reach the world")
		return false
	# Small enough to leave the street visible behind it, which is the entire reason it exists
	# rather than the full sheet. Judged against the size the game runs at (1920x1080) rather than
	# against `get_viewport_rect()`, because headless the viewport is a fraction of that and the
	# window would "pass" by being bigger than the screen it is measured against.
	if win.size.x > 1000.0 or win.size.y > 700.0:
		push_error("the transfer window is %s; at that size it may as well be the full sheet" % str(win.size))
		return false

	# Open sheet: the window goes away and the cupboard is the first column instead, because two
	# pictures of one box on one screen is the confusion the fixed layout exists to end.
	panel.call("set_open", true)
	panel.call("set_loot", SimContainers.open_view(w, actor))
	if bool(panel.call("loot_open")):
		push_error("the transfer window stayed up under the open sheet")
		return false
	var labels: Array = panel.call("column_labels")
	if labels.is_empty() or String(labels[0]) != "cupboard":
		push_error("the open cupboard is not the first column: %s" % str(labels))
		return false
	if labels.size() < 2 or String(labels[1]) != "pockets":
		push_error("what you are carrying does not follow what you are standing at: %s" % str(labels))
		return false

	# Walk away, and both go: `opened_by` closes a box out of reach, so the screen has nothing to
	# draw without needing to be told.
	var pos: Dictionary = w.components.get_component(actor, "position") as Dictionary
	pos["x"] = float(pos["x"]) + 6.0
	panel.call("set_world", w, actor)
	panel.call("set_loot", SimContainers.open_view(w, actor))
	if String((panel.call("column_labels") as Array)[0]) == "cupboard":
		push_error("walking away from a cupboard left it as a column")
		panel.queue_free()
		return false
	panel.call("set_open", false)
	panel.call("set_loot", SimContainers.open_view(w, actor))
	if bool(panel.call("loot_open")):
		push_error("walking away from a cupboard left the transfer window up")
		panel.queue_free()
		return false

	# And the reader half, textually: main.gd feeds the window and Escape closes the box.
	var main_src: String = FileAccess.get_file_as_string("res://presentation/main.gd")
	for needed in ["set_loot", "SimContainers.open_view", "container.close", "loot_open"]:
		if main_src.find(needed) < 0:
			push_error("main.gd never mentions %s, so the window is drawn by nothing or closed by nothing" % needed)
			panel.queue_free()
			return false
	# The key sheet has to say the verb changed: E opened a container by tipping it onto the floor
	# before this, and a player told to "search" a cupboard will not know a window is coming.
	var legend_src: String = FileAccess.get_file_as_string("res://ui/legend.gd")
	if legend_src.find("open a cupboard") < 0:
		push_error("the legend's E row does not say E opens a container")
		panel.queue_free()
		return false
	print("LOOT OK a cupboard is the first column with the sheet open and a small window beside the pockets with it closed, only the window stops the mouse, and walking away ends both")
	panel.queue_free()
	return true
