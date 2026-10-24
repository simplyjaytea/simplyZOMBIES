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
#  4. **A picked body part offers only the care the sim would take** (CARE, the UI overhaul's first
#     slice). The figure is clicked where a player clicks it; the pane's buttons are exactly the
#     verbs `SimTreatment.options_for` allows, a refusal is said in words only when the survivor can
#     act on it, and the button pushes the `treat.begin` that starts the channel on that part.
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
const SimGunsmith = preload("res://sim/modules/gunsmith.gd")
const SimContainers = preload("res://sim/modules/containers.gd")
const InspectPane = preload("res://ui/inspect_pane.gd")
const CarePane = preload("res://ui/care_pane.gd")

# The pane's whole vocabulary. Adding a key here is a decision about what the player is told, so
# it is made in this file as well as in the read model -- the `check_ban_health_bar` arrangement,
# and the reason a numeric field cannot be added to either by accident.
const INSPECT_KEYS: Array[String] = ["item", "name", "condition", "description", "slot", "worn", "attachments", "fits", "fuel"]
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
	ok = await _the_sheet_fits_and_scrolls() and ok
	ok = _the_windows_are_gone_and_the_keys_moved() and ok
	ok = await _a_cupboard_is_a_column_and_a_window() and ok
	ok = _a_stack_that_cannot_merge_is_not_reported_as_stored() and ok
	ok = await _the_list_and_the_buttons_reach_the_world() and ok
	ok = await _a_picked_part_offers_only_legal_care() and ok
	ok = await _a_part_dropped_on_a_weapon_fits_it_or_lands_in_the_grid() and ok
	if ok:
		print("INVENTORY_OK a picked body part offers the care the sim would take and nothing else, descriptions are prose, the pane carries only words, a verb is offered iff it works and reaches its command, the strip is belt and pockets and spends what you pressed, the column is fixed, the windows are gone, a cupboard is a column and a window, a stack that cannot merge is not reported as stored, the list, a ctrl-click and the pane's buttons each move the world, and a part dropped on a weapon fits an empty slot and lands in the grid otherwise")
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


# An item's **name** is the one string on these screens allowed to carry a digit, by the owner's
# decision of 2026-09-12 (docs/30, "The cartridge on the label"). A cartridge is called what it is
# called -- `.308 Winchester`, `12 Gauge Buckshot`, `9x19mm Parabellum` -- and a roster of twenty
# rounds named around the ban would have been twenty rounds a player cannot tell apart, which is a
# worse failure of clause 4 than the digit was.
#
# **One predicate, two lanes.** STRIP and INSPECT both scan a name, and the file already keeps one
# `_carries_a_digit` so DESCRIPTION and INSPECT cannot disagree about what a digit is; two copies
# of this exemption written separately is the same mistake with the answer inverted, and is the
# shape of every dead socket in this milestone.
#
# **What is still refused, and this is the whole of the clause.** A name that is *nothing but* a
# quantity -- "12", "3 " -- is a count with no noun, which no cartridge designation is and no item
# on the roster is. That is the true negative `_a_bare_quantity_is_still_refused` fabricates. And
# the exemption is scoped to this one field: `description`, `condition`, every other value in the
# inspect pane, and every line `check_hud.gd` scans are all untouched, which the lanes below prove
# by refusing the identical string in those positions.
static func _name_is_allowed(text: String) -> bool:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return false
	for ch in trimmed:
		if not (ch >= "0" and ch <= "9"):
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
	SimGunsmith.register_module(w)
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
		"worn": true, "attachments": [], "fits": [], "fuel": "",
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

	# The name exemption, both ways round, because an exemption with only a positive is a hole.
	# A cartridge is allowed to be called what it is called; a name that is *nothing but* a
	# quantity is still a count with no noun and is still refused. And the exemption reaches
	# exactly one field: the identical string is refused the moment it is a description instead,
	# which is what "narrow" means here and is the half that would rot silently if unasserted.
	var cartridge: Dictionary = sabotage.duplicate()
	cartridge["description"] = "A service pistol."
	cartridge["name"] = ".308 Winchester Match"
	if not _inspect_faults(cartridge).is_empty():
		push_error("the pane refused a cartridge name: %s" % ", ".join(PackedStringArray(_inspect_faults(cartridge))))
		return false
	var counted: Dictionary = cartridge.duplicate()
	counted["name"] = "12"
	if _inspect_faults(counted).is_empty():
		push_error("the pane passed a name that is nothing but a quantity: \"12\"")
		return false
	var leaked: Dictionary = cartridge.duplicate()
	leaked["description"] = ".308 Winchester Match"
	if _inspect_faults(leaked).is_empty():
		push_error("the name exemption leaked into `description` -- it is scoped to one field")
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
	# The muzzle, not the barrel: a pistol spawns with a barrel already in it and a can screws onto
	# the end of one. That is what the `muzzle` slot is for.
	if not SimAttachments.attach(w, pistol, can, "muzzle"):
		push_error("the suppressor would not fit the pistol's muzzle")
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
			# The one exempted field, and only in this one position. `description` and every other
			# string below stay under the full ban -- see `_name_is_allowed`.
			if name == "name":
				if not _name_is_allowed(value as String):
					out.append("\"%s\" is a bare quantity: \"%s\"" % [name, String(value)])
			elif _carries_a_digit(value as String):
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

	# modify -- absent away from a bench, present at one, and the command it pushes opens the
	# weapon on it. The absence is the half that matters: a verb offered everywhere is a menu
	# entry the sim silently drops when the player picks it.
	var rifle: int = _give(w, "item.rifle.hunting")
	if rifle < 0:
		push_error("the fixture rifle could not be carried")
		return false
	if SimInventory.verbs_for(w, w.player, rifle).has("modify"):
		push_error("\"modify\" was on offer with no bench anywhere")
		return false
	var here: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	SimGunsmith.make_bench(w, float(here["x"]), float(here["y"]))
	if not SimInventory.verbs_for(w, w.player, rifle).has("modify"):
		push_error("\"modify\" was not on offer for a rifle at a bench")
		return false
	# The negative used to be the coat, and the armour-slot slice of 2026-09-12 made the coat the
	# wrong subject rather than making the assertion wrong: a leather jacket declares `lining` and
	# `pocket` now, so it does come apart, and `modify` is correctly on offer for it. The claim
	# this lane makes is unchanged -- a garment with no slots at all must not be offered a bench
	# verb -- so it moved to a garment that still has none. A cloth wrap is strips of cloth.
	var wrap: int = _give(w, "item.wrap.cloth")
	if wrap < 0:
		push_error("the fixture wrap could not be carried")
		return false
	if not SimAttachments.slots_of(w, wrap).is_empty():
		push_error("the cloth wrap declares slots now, so it is no longer the thing that comes apart into nothing")
		return false
	if SimInventory.verbs_for(w, w.player, wrap).has("modify"):
		push_error("\"modify\" was on offer for a cloth wrap, which comes apart into nothing")
		return false
	if not SimInventory.verbs_for(w, w.player, coat).has("modify"):
		push_error("\"modify\" was not on offer for a leather jacket at a bench, and a jacket has a lining slot")
		return false
	w.commands.push({"type": "bench.open", "item": rifle})
	w.step()
	if SimGunsmith.focus_of(w, w.player) != rifle:
		push_error("the offered \"modify\" pushed a command that did nothing")
		return false
	w.commands.push({"type": "bench.close"})
	w.step()

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
		if not _name_is_allowed(String(d.get("name", ""))):
			push_error("a strip entry's name is a bare quantity: \"%s\"" % String(d.get("name", "")))
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
	# The keys and the hand-off are two files since the alpha shell's input split (docs/30, "The
	# alpha shell, 2026-09-16"): `presentation/input_map.gd` binds them and main.gd still owns
	# `_strip_use`, which is what the panel's `strip_use` is called through. Asking each file for
	# its own half is the point -- a needle that scanned both together would pass with the
	# binding in the wrong file.
	var keys: String = FileAccess.get_file_as_string("res://presentation/input_map.gd")
	if keys.is_empty():
		faults.append("presentation/input_map.gd would not open, so nothing here judges the keys")
	if keys.find("KEY_1: speed") >= 0 or keys.find("KEY_2: speed") >= 0:
		faults.append("the key router still binds the number row to speed")
	for needed in ["KEY_MINUS", "KEY_EQUAL", "_strip_use"]:
		if keys.find(needed) < 0:
			faults.append("presentation/input_map.gd never mentions %s" % needed)
	var main: String = FileAccess.get_file_as_string("res://presentation/main.gd")
	if main.find("KEY_1: speed") >= 0 or main.find("KEY_2: speed") >= 0:
		faults.append("main.gd still binds the number row to speed")
	for needed in ["_strip_use", "strip_use"]:
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

	# And the reader half, textually, in the two files that hold it since the alpha shell's input
	# split (docs/30, "The alpha shell, 2026-09-16"): main.gd's `_update_hud` feeds the window,
	# and the Escape that closes the box is in the key router with the rest of the peel order.
	# Each needle asks the file that should hold it, so a half-done move is red rather than
	# quietly satisfied by the other half.
	var readers: Array = [
		["res://presentation/main.gd", ["set_loot", "SimContainers.open_view"], "the window is drawn by nothing"],
		["res://presentation/input_map.gd", ["container.close", "loot_open"], "the box is closed by nothing"],
	]
	for reader in readers:
		var src: String = FileAccess.get_file_as_string(String((reader as Array)[0]))
		if src.is_empty():
			push_error("%s would not open, so the reader half judges nothing" % String((reader as Array)[0]))
			panel.queue_free()
			return false
		for needed in (reader as Array)[1] as Array:
			if src.find(String(needed)) < 0:
				push_error("%s never mentions %s, so %s" % [String((reader as Array)[0]), String(needed), String((reader as Array)[2])])
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


# --- STACK -------------------------------------------------------------------------------------
#
# `merge_stacks` used to answer 0 both for "merged entirely" and for every one of its refusals, so
# `merge_into_stack` read a same-base item that could not take the stack as having taken it, and
# `stow` reported an item put away that had gone nowhere -- no `stored`, no `position`, alive and
# unreachable. Three outcomes, each judged: a refusal is not stored (and the item comes back to the
# ground through `pick_up_nearest`); a merge that fits is stored and the source is gone; a merge
# that does not fit leaves the remainder and `stow` finds it a cell.
func _a_stack_that_cannot_merge_is_not_reported_as_stored() -> bool:
	var w: Variant = _world(3107)
	var limit: int = _stack_limit(w, "item.scrap.metal")
	if limit < 4:
		push_error("STACK: scrap stacks to %d, so no partial merge could be judged" % limit)
		return false
	# Pockets full of same-base items that carry no `stack` component -- the shape `merge_stacks`
	# refuses -- so a loose stack of three has nothing to pour into and nowhere else to go.
	var cells: int = int(SimInventory.POCKET_GRID["w"]) * int(SimInventory.POCKET_GRID["h"])
	for i in cells:
		var bare: int = w.entities.spawn()
		w.components.set_component(bare, "itemBase", {"baseId": "item.scrap.metal"})
		var placed: Dictionary = SimInventory.place_at(w, bare, w.player, i % int(SimInventory.POCKET_GRID["w"]), i / int(SimInventory.POCKET_GRID["w"]), false)
		if not bool(placed.get("ok", false)):
			push_error("STACK: could not fill pocket cell %d: %s" % [i, str(placed)])
			return false
	var loose: int = SimItems.spawn_item(w, "item.scrap.metal", {"tier": "scavenged", "count": 3})
	w.components.remove(loose, "position")
	if SimInventory.stow(w, w.player, loose):
		push_error("STACK: stow reported three scrap stored into pockets that could not take them")
		return false
	var stack: Variant = w.components.get_component(loose, "stack")
	if not w.entities.is_alive(loose) or not stack is Dictionary or int((stack as Dictionary).get("count", 0)) != 3:
		push_error("STACK: the refused stack was consumed anyway")
		return false
	if w.components.get_component(loose, "stored") != null:
		push_error("STACK: the refused stack reads as stored")
		return false
	# Through the real pick-up path: a refusal puts the item back at your feet, not out of the world.
	var here: Dictionary = w.components.get_component(w.player, "position") as Dictionary
	w.components.set_component(loose, "position", {"x": float(here["x"]), "y": float(here["y"])})
	if SimInventory.pick_up_nearest(w, w.player):
		push_error("STACK: pick_up_nearest reported a pick-up that went nowhere")
		return false
	if w.components.get_component(loose, "position") == null:
		push_error("STACK: the scrap that could not be picked up is no longer on the ground")
		return false
	# The control: a proper stack with room takes it, and the source is gone.
	var w2: Variant = _world(3108)
	var held: int = _give(w2, "item.scrap.metal", 4)
	if held < 0:
		push_error("STACK: could not seed the pockets with a stack of four")
		return false
	var three: int = SimItems.spawn_item(w2, "item.scrap.metal", {"tier": "scavenged", "count": 3})
	w2.components.remove(three, "position")
	if not SimInventory.stow(w2, w2.player, three):
		push_error("STACK: a stack of three was refused by a stack of four with room for six")
		return false
	var held_stack: Dictionary = w2.components.get_component(held, "stack") as Dictionary
	if int(held_stack.get("count", 0)) != 7 or w2.entities.is_alive(three):
		push_error("STACK: four and three made %d, and the source %s" % [int(held_stack.get("count", 0)), "survived" if w2.entities.is_alive(three) else "was consumed"])
		return false
	# And a stack with no room leaves the remainder, which stow then finds a cell for.
	var w3: Variant = _world(3109)
	var full: int = _give(w3, "item.scrap.metal", limit)
	var extra: int = SimItems.spawn_item(w3, "item.scrap.metal", {"tier": "scavenged", "count": 3})
	w3.components.remove(extra, "position")
	var remainder: int = SimInventory.merge_stacks(w3, extra, full)
	if remainder != 3:
		push_error("STACK: pouring three into a full stack of %d answered %d, not the three left" % [limit, remainder])
		return false
	if not SimInventory.stow(w3, w3.player, extra):
		push_error("STACK: the three left over found no pocket")
		return false
	var extra_stack: Dictionary = w3.components.get_component(extra, "stack") as Dictionary
	if int(extra_stack.get("count", 0)) != 3 or w3.components.get_component(extra, "stored") == null:
		push_error("STACK: the remainder was stored as %d or not stored at all" % int(extra_stack.get("count", 0)))
		return false
	print("STACK OK a refused stack is not stored and comes back to the ground; four and three make seven and the source is gone; three over a full %d stay three and find a cell" % limit)
	return true


# Window-sized geometry and the matching input boundaries, exercised on the real sheet.
# A seven-cell pack is the widest carried container; shrinking its cells would change the
# footprint picture, so all seven must fit beside the inspect pane at either supported size.
func _the_sheet_fits_and_scrolls() -> bool:
	var panel_script: GDScript = load(PANEL_GD) as GDScript
	var bag: GDScript = load("res://ui/bag_grid.gd") as GDScript
	var w: Variant = _world(3118)
	var pack: int = _wear(w, "item.pack.frame", "back")
	if pack < 0:
		push_error("LAYOUT: no frame pack to measure")
		return false
	var body_state: Dictionary = w.components.get_component(w.player, "body") as Dictionary
	for part in ["head", "torso", "arm_left", "arm_right", "hand_left", "hand_right", "leg_left", "leg_right", "foot_left", "foot_right"]:
		body_state[part] = float(body_state[part]) * 0.5
	var ok: bool = true
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = dims
		root.add_child(viewport)
		var panel: Control = panel_script.new() as Control
		viewport.add_child(panel)
		panel.call("set_world", w, w.player)
		panel.call("set_open", true)
		await process_frame
		var layer: Control = panel.get("_column_layer") as Control
		if not layer.visible:
			push_error("LAYOUT: open sheet does not show its bag layer")
			ok = false
		panel.call("set_open", false)
		if layer.visible:
			push_error("LAYOUT: closed sheet leaves bag grids over the street")
			ok = false
		panel.call("set_open", true)
		var body: Rect2 = panel.call("_body_rect")
		var column: Rect2 = panel.call("_column_rect")
		var inspect: Rect2 = panel.call("_inspect_rect")
		var screen := Rect2(Vector2.ZERO, Vector2(dims))
		if not _separate_sheet_rects(screen, [body, column, inspect]):
			push_error("LAYOUT: sheet columns overlap or leave %s" % str(dims))
			ok = false
		if _separate_sheet_rects(screen, [body, Rect2(body.position + Vector2(10, 0), column.size), inspect]):
			push_error("LAYOUT: an overlapping bag column passed the same judge")
			ok = false
		if column.size.x < (bag.call("size_of", 7, 9) as Vector2).x:
			push_error("LAYOUT: the frame pack loses a native-width cell at %s" % str(dims))
			ok = false
		var boxes: Array = panel.call("_slot_boxes")
		for box in boxes:
			if not body.encloses(box["rect"] as Rect2):
				push_error("LAYOUT: an equipment slot leaves its panel")
				ok = false
		var condition: Rect2 = panel.call("_condition_rect")
		for box in boxes:
			if condition.intersects(box["rect"] as Rect2):
				push_error("LAYOUT: condition prose overlaps an equipment slot")
				ok = false
		var rows: Array = panel.call("_condition_rows")
		var capacity: int = int(panel.call("_condition_capacity"))
		if rows.size() <= capacity:
			push_error("LAYOUT: injured fixture did not need scrolling; nothing judged")
			ok = false
		var wheel := InputEventMouseButton.new()
		wheel.pressed = true
		wheel.position = condition.get_center()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		for i in rows.size():
			panel.call("_gui_input", wheel)
		if int(panel.get("_condition_scroll")) != maxi(0, rows.size() - capacity) or float(panel.get("_scroll")) != 0.0:
			push_error("LAYOUT: wheel over condition did not reach the final row independently of bags")
			ok = false
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		for i in rows.size():
			panel.call("_gui_input", wheel)
		if int(panel.get("_condition_scroll")) != 0:
			push_error("LAYOUT: condition did not scroll back to the first row")
			ok = false
		# A release below the clip must not put an item in an invisible bag cell.
		panel.set("_placed", panel.call("_column_places"))
		panel.set("_drag_item", pack)
		w.commands.take(int(w.tick))
		panel.call("_release_at", Vector2(column.position.x + 20.0, column.end.y + 20.0))
		if not (w.commands._pending as Array).is_empty():
			push_error("LAYOUT: releasing beneath the clipped bags proposed a move")
			ok = false
		viewport.queue_free()
		await process_frame
	if ok:
		print("LAYOUT OK 1280/1920 columns and equipment fit, seven native bag cells stay visible, condition scroll reaches both ends, clipped cells cannot accept a drop")
	return ok


func _separate_sheet_rects(screen: Rect2, rects: Array) -> bool:
	for i in rects.size():
		if not screen.encloses(rects[i] as Rect2):
			return false
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				return false
	return true


# --- QUICK -------------------------------------------------------------------------------------
#
# The Salvage Locker (docs/23, "The inventory, redone") added three ways to act that are not a drag
# or the word menu: the list beside the grids, a ctrl-click that sends an item across to the box you
# are standing at, and verb buttons along the inspect pane's foot. Each is a mechanism, so each is
# asked whether a real press reaches the world -- not whether a helper returns the right rect. The
# presses go through `_press_at` at the points the panel itself draws, in a 1920x1080 SubViewport.
#
#   LIST     the list carries every item the grids carry under `all`, and only weapons under the
#            arms chip -- reached by pressing the chip, not by setting the filter; a press on a row
#            selects that row's item.
#   SEND     a ctrl-press on a pocket item with a cupboard open moves it into the cupboard after a
#            step; the same press with no box open pushes no command and the item stays put.
#   BUTTONS  a press on the inspect pane's `drop` button drops the selected item after a step; a
#            press in the pane that misses every button pushes nothing.
func _the_list_and_the_buttons_reach_the_world() -> bool:
	var w: Variant = _world(3131)
	SimContainers.register_module(w)
	var actor: int = w.player
	var bottle: int = _give(w, "item.water.bottle")
	var knife: int = _give(w, "item.knife.kitchen")
	if bottle < 0 or knife < 0:
		push_error("QUICK: the fixture could not stow its bottle and knife")
		return false
	var at: Dictionary = w.components.get_component(actor, "position") as Dictionary
	var box: int = SimContainers.make_container(w, float(at["x"]) + 0.5, float(at["y"]), "cupboard", "residential")
	if not bool(SimContainers.open(w, actor, box).get("ok", false)):
		push_error("QUICK: the fixture cupboard would not open")
		return false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var panel: Control = (load(PANEL_GD) as GDScript).new() as Control
	viewport.add_child(panel)
	await process_frame
	panel.call("set_world", w, actor)
	panel.call("set_open", true)
	panel.call("set_loot", SimContainers.open_view(w, actor))
	var ok: bool = true

	# LIST: every item on the sheet, then only the weapons once the arms chip is pressed.
	var carried: int = 0
	for column in panel.call("_columns") as Array:
		carried += ((column as Dictionary).get("items", []) as Array).size()
	var rows: Array = panel.call("_list_rows")
	if carried == 0 or rows.size() != carried:
		push_error("QUICK: LIST has %d rows for the %d items the grids draw" % [rows.size(), carried])
		ok = false
	var arms: int = -1
	var chips: Array = panel.call("_chip_rects")
	for chip in chips:
		if String(((panel.get("FILTERS") as Array)[int((chip as Dictionary)["index"])] as Array)[0]) == "arms":
			arms = int((chip as Dictionary)["index"])
			panel.call("_press_at", ((chip as Dictionary)["rect"] as Rect2).get_center())
	if arms < 0 or int(panel.get("_filter")) != arms:
		push_error("QUICK: LIST pressing the arms chip did not put the arms filter in force")
		ok = false
	var armed: Array = panel.call("_list_rows")
	var knife_row: bool = false
	for row in armed:
		if not String((row as Dictionary)["class"]).begins_with("weapon."):
			push_error("QUICK: LIST the arms chip let a %s through" % String((row as Dictionary)["class"]))
			ok = false
		knife_row = knife_row or int((row as Dictionary)["item"]) == knife
	if not knife_row or armed.size() >= rows.size():
		push_error("QUICK: LIST the arms chip dropped the knife or kept everything (%d of %d)" % [armed.size(), rows.size()])
		ok = false
	var hits: Array = panel.call("_list_hits")
	if hits.is_empty():
		push_error("QUICK: LIST has no rows on screen to press")
		ok = false
	else:
		panel.set("_selected", -1)
		panel.call("_press_at", ((hits[0] as Dictionary)["rect"] as Rect2).get_center())
		panel.call("_cancel_drag")
		if int(panel.get("_selected")) != int(((hits[0] as Dictionary)["row"] as Dictionary)["item"]):
			push_error("QUICK: LIST a press on a row did not select its item")
			ok = false
	panel.set("_filter", 0)

	# SEND: the true negative first, with no box open, then the real one. A frame after each change
	# of layout, because the press is tested against what was last drawn, as it is in play.
	SimContainers.close(w, actor)
	panel.call("set_loot", SimContainers.open_view(w, actor))
	await process_frame
	var p: Variant = _plate_point(panel, bottle)
	if p == null:
		push_error("QUICK: SEND could not find the bottle's plate on screen")
		ok = false
	else:
		panel.call("_press_at", p as Vector2, true)
		if not (w.commands._pending as Array).is_empty():
			push_error("QUICK: SEND a ctrl-press with no box open pushed %s" % str(w.commands._pending))
			ok = false
		if not bool(SimContainers.open(w, actor, box).get("ok", false)):
			push_error("QUICK: SEND the fixture cupboard would not reopen")
			ok = false
		panel.call("set_loot", SimContainers.open_view(w, actor))
		await process_frame
		p = _plate_point(panel, bottle)
		panel.call("_press_at", p as Vector2, true)
		w.step()
		var moved: bool = false
		for entry in SimContainers.open_view(w, actor).get("items", []) as Array:
			moved = moved or int((entry as Dictionary).get("item", -1)) == bottle
		if not moved:
			push_error("QUICK: SEND a ctrl-press on the bottle with the cupboard open did not move it into the cupboard")
			ok = false

	# BUTTONS: close the box so the pane is on screen, select the knife, miss, then press drop.
	SimContainers.close(w, actor)
	panel.call("set_loot", SimContainers.open_view(w, actor))
	panel.call("set_world", w, actor)
	await process_frame
	panel.set("_selected", knife)
	var pane: Rect2 = panel.call("_inspect_rect")
	var buttons: Array = InspectPane.button_rects(pane, panel.call("_pane_verbs"))
	var drop: Variant = null
	for b in buttons:
		if String((b as Dictionary)["verb"]) == "drop":
			drop = (b as Dictionary)["rect"]
	if drop == null:
		push_error("QUICK: BUTTONS the pane offers no drop for a knife in the pockets: %s" % str(panel.call("_pane_verbs")))
		ok = false
	else:
		panel.call("_press_at", pane.position + Vector2(8.0, 8.0))
		if not (w.commands._pending as Array).is_empty():
			push_error("QUICK: BUTTONS a press on the pane's header pushed %s" % str(w.commands._pending))
			ok = false
		panel.set("_selected", knife)
		panel.call("_press_at", (drop as Rect2).get_center())
		w.step()
		if SimInventory.owns(w, actor, knife):
			push_error("QUICK: BUTTONS pressing drop left the knife carried")
			ok = false
	if ok:
		print("QUICK OK the list carries all %d items and the arms chip only weapons, a row press selects; ctrl-click sends the bottle into the cupboard and pushes nothing with no box open; the pane's drop button drops the knife and a miss pushes nothing" % carried)
	viewport.queue_free()
	return ok


# The centre of `item`'s plate on the sheet, from the panel's own placement list, or null.
func _plate_point(panel: Control, item: int) -> Variant:
	var bag: GDScript = load("res://ui/bag_grid.gd") as GDScript
	for placed in panel.call("_column_places") as Array:
		var column: Dictionary = (placed as Dictionary)["column"] as Dictionary
		for entry in column.get("items", []) as Array:
			if int((entry as Dictionary).get("item", -1)) == item:
				var origin: Vector2 = bag.call("origin_of", (placed as Dictionary)["at"] as Vector2)
				return (bag.call("plate_rect", origin, entry) as Rect2).get_center()
	return null


# --- FIT-DROP ---------------------------------------------------------------------------------
#
# A part dropped on a weapon is the fit when the weapon has an empty slot the part goes into and
# the survivor may work on the part here; anywhere else it is the ordinary grid placement. Three
# drops, three answers: an empty magazine slot takes the spare (attached, and the hover says so); a
# bipod the survivor cannot change by hand goes to a free underbarrel and is placed in the grid (the
# negative: the slot is free and the rule is the hands); a second magazine on a rifle whose magazine
# slot is full is placed in the grid (the negative: no empty slot).
func _a_part_dropped_on_a_weapon_fits_it_or_lands_in_the_grid() -> bool:
	var w: Variant = _world(3157)
	var actor: int = w.player
	if not _room(w):
		push_error("FIT-DROP: the pack would not go on")
		return false
	var rifle: int = _give(w, "item.rifle.hunting")
	if rifle < 0:
		push_error("FIT-DROP: the fixture rifle could not be carried")
		return false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var panel: Control = (load(PANEL_GD) as GDScript).new() as Control
	viewport.add_child(panel)
	await process_frame
	panel.call("set_world", w, actor)
	panel.call("set_open", true)
	await process_frame

	# Away from a bench the magazine comes off by hand. It is now a spare in the pack, and the
	# rifle's magazine slot is empty.
	var spare: int = SimAttachments.in_slot(w, rifle, "magazine")
	w.commands.push({"type": "item.detach", "item": spare})
	w.step()
	if SimAttachments.in_slot(w, rifle, "magazine") >= 0:
		push_error("FIT-DROP: the fixture magazine would not come off by hand")
		viewport.queue_free()
		return false
	var ok: bool = true

	# TP: the spare, held over the rifle, is the fit and the release attaches it.
	_refresh_sheet(panel, w, actor)
	var at_rifle: Variant = _plate_point(panel, rifle)
	if at_rifle == null:
		push_error("FIT-DROP: the rifle has no plate on the sheet")
		viewport.queue_free()
		return false
	panel.set("_drag_item", spare)
	var hint: Dictionary = panel.call("drop_hint", at_rifle) as Dictionary
	if not bool(hint.get("fit", false)) or not (hint.get("rect", Rect2()) as Rect2).has_area():
		push_error("FIT-DROP: a magazine held over a rifle with an empty slot shows no fit")
		ok = false
	w.commands.take(int(w.tick))
	panel.call("_release_at", at_rifle)
	if not _pending_has(w, "item.attach", spare):
		push_error("FIT-DROP: a magazine dropped on a rifle with an empty magazine slot was not attached")
		ok = false
	w.step()
	if SimAttachments.in_slot(w, rifle, "magazine") != spare:
		push_error("FIT-DROP: the dropped magazine is not in the rifle")
		ok = false

	# Negative 1: a bipod the survivor cannot change by hand, dropped on a rifle whose underbarrel
	# is empty, is the grid's. The slot is free, so only the hands-or-bench rule can refuse it.
	var bipod: int = _give(w, "item.attach.underbarrel.bipod")
	_refresh_sheet(panel, w, actor)
	at_rifle = _plate_point(panel, rifle)
	if bipod < 0 or at_rifle == null:
		push_error("FIT-DROP: the bipod fixture could not be carried or drawn")
		viewport.queue_free()
		return false
	panel.set("_drag_item", bipod)
	w.commands.take(int(w.tick))
	panel.call("_release_at", at_rifle)
	if _pending_has(w, "item.attach", bipod):
		push_error("FIT-DROP: a bipod was fitted by a drop away from a bench")
		ok = false
	if not _pending_has(w, "item.move", bipod):
		push_error("FIT-DROP: a bipod dropped on a rifle away from a bench was not placed in the grid")
		ok = false
	w.step()

	# Negative 2: a second magazine onto a rifle whose magazine slot is full is the grid's too.
	var extra: int = _give(w, "item.attach.magazine.extended")
	_refresh_sheet(panel, w, actor)
	at_rifle = _plate_point(panel, rifle)
	if extra < 0 or at_rifle == null:
		push_error("FIT-DROP: the second magazine could not be carried or drawn")
		viewport.queue_free()
		return false
	panel.set("_drag_item", extra)
	w.commands.take(int(w.tick))
	panel.call("_release_at", at_rifle)
	if _pending_has(w, "item.attach", extra):
		push_error("FIT-DROP: a magazine was fitted over a full magazine slot")
		ok = false
	if not _pending_has(w, "item.move", extra):
		push_error("FIT-DROP: a magazine dropped on a full rifle was not placed in the grid")
		ok = false
	w.step()

	viewport.queue_free()
	await process_frame
	return ok


func _refresh_sheet(panel: Control, w: Variant, actor: int) -> void:
	panel.call("set_world", w, actor)
	panel.call("_redraw_columns")
	panel.set("_placed", panel.call("_column_places"))


func _pending_has(w: Variant, kind: String, item: int) -> bool:
	for c in w.commands._pending as Array:
		var d: Dictionary = c as Dictionary
		if String(d.get("type", "")) == kind and int(d.get("item", -1)) == item:
			return true
	return false


# --- CARE -------------------------------------------------------------------------------------
#
# The first playable journey's "select an injured region, then available care" (docs/32,
# "Acceptance"), on the real sheet: a bleeding cut on the left arm, the figure clicked where the arm
# is drawn, and the pane read and pressed.
#
#   PICK      a press on the arm picks "arm_left" and hands the inspect slot to the part; a press on
#             the body panel off the figure puts it down again (the negative).
#   OFFER     the buttons are exactly the verbs `options_for` allows, for the cut arm (pressure, no
#             dressing carried) and for an unhurt head (none at all); "dress it" is refused in words
#             because there is no dressing, and "not-bleeding" on the head is absent, not greyed.
#   PRESS     the button pushes treat.begin for that patient, part and verb, and a step starts the
#             channel on the arm; with the channel running the pane offers "stop" and nothing else,
#             and "stop" pushes treat.cancel. A press on the pane's header pushes nothing.
#   SUPPLY    with a cloth bandage in the pockets, "dress it" becomes a button.
#   WORDS     every word the pane draws for the part is digit-free.
#   FIT       a refusal wraps to fit a narrow pane and keeps its whole reason; a wide pane keeps it on one line.
#   ESCAPE    Escape's first press puts the part down and leaves the sheet open.
func _a_picked_part_offers_only_legal_care() -> bool:
	var w: Variant = _world(4242)
	var actor: int = w.player
	SimWounds.append_wound(w, actor, "cut", "arm_left", -1, 0.0, "", SimWounds.Severity.Laceration)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var panel: Control = (load(PANEL_GD) as GDScript).new() as Control
	viewport.add_child(panel)
	await process_frame
	panel.call("set_world", w, actor)
	panel.call("set_open", true)
	await process_frame
	var ok: bool = true
	var doll: Control = panel.get("_paperdoll") as Control
	panel.call("_place_doll")
	var arm_at: Vector2 = doll.position + (doll.call("point_of", "arm_left") as Vector2)
	var head_at: Vector2 = doll.position + (doll.call("point_of", "head") as Vector2)

	# PICK
	panel.call("_press_at", arm_at)
	if String(panel.get("_part")) != "arm_left" or not bool(panel.call("_showing_part")):
		push_error("CARE: PICK a press on the drawn left arm picked %s" % String(panel.get("_part")))
		ok = false
	var body: Rect2 = panel.call("_body_rect")
	panel.call("_press_at", Vector2(body.get_center().x, body.end.y - 12.0))
	if not String(panel.get("_part")).is_empty():
		push_error("CARE: PICK a press on the body panel off the figure kept %s picked" % String(panel.get("_part")))
		ok = false

	# OFFER, on the arm and on the head.
	for case in [["arm_left", arm_at], ["head", head_at]]:
		panel.call("_press_at", case[1] as Vector2)
		var part: String = String(case[0])
		if String(panel.get("_part")) != part:
			push_error("CARE: OFFER a press on the drawn %s picked %s" % [part, String(panel.get("_part"))])
			ok = false
			continue
		var want: Array[String] = []
		for o in SimTreatment.options_for(w, actor, actor, part):
			if bool((o as Dictionary).get("ok", false)):
				want.append(String((o as Dictionary)["verb"]))
		var view: Dictionary = panel.call("_care_view")
		var got: Array[String] = CarePane.verbs_of(view)
		if got != want:
			push_error("CARE: OFFER the %s's buttons are %s; options_for allows %s" % [part, str(got), str(want)])
			ok = false
		if part == "arm_left":
			if not want.has("pressure") or want.has("bandage"):
				push_error("CARE: OFFER the fixture is wrong: a bleeding arm with no dressing should allow pressure and not bandage, got %s" % str(want))
				ok = false
			var said: bool = false
			for r in view.get("refused", []) as Array:
				said = said or (String((r as Dictionary)["verb"]) == "bandage" and String((r as Dictionary)["reason"]) == "no-bandage")
			if not said:
				push_error("CARE: OFFER the arm does not say why it cannot be dressed: %s" % str(view.get("refused", [])))
				ok = false
		else:
			if not got.is_empty():
				push_error("CARE: OFFER an unhurt head offers %s" % str(got))
				ok = false
			for r in view.get("refused", []) as Array:
				if String((r as Dictionary)["reason"]) in ["not-bleeding", "nothing-to-do"]:
					push_error("CARE: OFFER the head greys %s out for having nothing to do instead of leaving it off" % String((r as Dictionary)["verb"]))
					ok = false

	# WORDS: everything the pane writes about the part.
	panel.call("_press_at", arm_at)
	var words: Dictionary = panel.call("_care_view")
	var lines: Array[String] = [String(words.get("label", "")), CarePane.STATE_WORDS[clampi(int(words.get("state", 0)), 0, 3)]]
	for n in words.get("notes", []) as Array:
		lines.append(String(n))
	for v in CarePane.verbs_of(words):
		lines.append(CarePane.word_of(v))
	for r in words.get("refused", []) as Array:
		lines.append(String(CarePane.REASON_WORDS.get(String((r as Dictionary)["reason"]), "")))
	var digit := RegEx.create_from_string("[0-9]")
	for line in lines:
		if digit.search(line) != null:
			push_error("CARE: WORDS the pane writes a digit: %s" % line)
			ok = false
	# FIT: a refusal is never cut. In the compact pane's width each line fits whole and the reason is
	# all there; in a pane wide enough it stays one line (the negative: the wrap is not unconditional).
	var font_c: Font = load("res://ui/chrome.gd").call("font") as Font
	for r in words.get("refused", []) as Array:
		var narrow: Array[String] = CarePane.refusal_lines(r as Dictionary, 300.0)
		var why: String = String(CarePane.REASON_WORDS.get(String((r as Dictionary)["reason"]), ""))
		for line in narrow:
			if font_c.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, CarePane.BODY_TEXT).x > 300.0:
				push_error("CARE: FIT the refusal line '%s' is wider than a 300 px pane" % line)
				ok = false
		if not "".join(narrow).contains(why):
			push_error("CARE: FIT the narrow refusal %s lost its reason '%s'" % [str(narrow), why])
			ok = false
		if CarePane.refusal_lines(r as Dictionary, 2000.0).size() != 1:
			push_error("CARE: FIT a refusal wraps even in a 2000 px pane")
			ok = false
	if digit.search("hold pressure 3") == null:
		push_error("CARE: WORDS the digit scanner cannot fail")
		ok = false

	# PRESS: a miss on the header first, then the button.
	var pane: Rect2 = panel.call("_inspect_rect")
	panel.call("_press_at", pane.position + Vector2(8.0, 8.0))
	if not (w.commands._pending as Array).is_empty():
		push_error("CARE: PRESS a press on the pane's header pushed %s" % str(w.commands._pending))
		ok = false
	panel.call("_press_at", arm_at)
	var buttons: Array = CarePane.button_rects(pane, panel.call("_care_view"))
	if buttons.is_empty():
		push_error("CARE: PRESS the cut arm's pane has no button to press")
		ok = false
	else:
		panel.call("_press_at", ((buttons[0] as Dictionary)["rect"] as Rect2).get_center())
		var pushed: Array = (w.commands._pending as Array).duplicate()
		var want_cmd := {"type": "treat.begin", "patient": actor, "part": "arm_left", "verb": "pressure"}
		if pushed.size() != 1 or (pushed[0] as Dictionary) != want_cmd:
			push_error("CARE: PRESS the button pushed %s, not %s" % [str(pushed), str(want_cmd)])
			ok = false
		w.step()
		var t: Variant = w.components.get_component(actor, "treatment")
		if not (t is Dictionary) or String((t as Dictionary).get("part", "")) != "arm_left":
			push_error("CARE: PRESS the step did not start a channel on the arm: %s" % str(t))
			ok = false
		var running: Dictionary = panel.call("_care_view")
		if CarePane.verbs_of(running) != [CarePane.STOP_VERB]:
			push_error("CARE: PRESS with the channel running the pane offers %s, not only stop" % str(CarePane.verbs_of(running)))
			ok = false
		var stop: Array = CarePane.button_rects(pane, running)
		if not stop.is_empty():
			panel.call("_press_at", ((stop[0] as Dictionary)["rect"] as Rect2).get_center())
			var cancel: Array = (w.commands._pending as Array).duplicate()
			if cancel.size() != 1 or String((cancel[0] as Dictionary).get("type", "")) != "treat.cancel":
				push_error("CARE: PRESS stop pushed %s, not treat.cancel" % str(cancel))
				ok = false
			w.step()
			if w.components.has_component(actor, "treatment"):
				push_error("CARE: PRESS stop left the channel running")
				ok = false

	# SUPPLY: a dressing in the pocket makes "dress it" a button.
	if _give(w, "item.bandage.cloth") < 0:
		push_error("CARE: SUPPLY the fixture could not pocket a cloth bandage")
		ok = false
	panel.call("set_world", w, actor)
	panel.call("_press_at", arm_at)
	if not CarePane.verbs_of(panel.call("_care_view")).has("bandage"):
		push_error("CARE: SUPPLY a cloth bandage in the pocket did not make the arm dressable: %s" % str(CarePane.verbs_of(panel.call("_care_view"))))
		ok = false

	# ESCAPE
	if not bool(panel.call("escape")) or not String(panel.get("_part")).is_empty() or not bool(panel.call("is_open")):
		push_error("CARE: ESCAPE the first press did not put the part down and leave the sheet open")
		ok = false
	if bool(panel.call("escape")):
		push_error("CARE: ESCAPE with nothing picked, held or open the sheet still claimed the press")
		ok = false
	if ok:
		print("CARE OK a press on the drawn arm picks it and one off the figure puts it down; the arm's buttons are options_for's (%s) and the head's are none, dressing is refused in words and nothing-to-do is absent; the button pushes treat.begin and starts the channel, stop cancels it, a header press pushes nothing; a bandage makes it dressable; every word is digit-free; Escape puts the part down first" % ", ".join(CarePane.verbs_of(words)))
	viewport.queue_free()
	return ok
