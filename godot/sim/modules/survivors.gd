class_name SimSurvivors
extends RefCounted

# Unique survivor pipeline per .scratch/simplyzombies/issues/05-unique-npc.md.
# Drop another JSON in godot/content/survivors/uniques/ — no code change. Generator is later.

const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
const SimStancesRes = preload("res://sim/stances.gd")
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimItemsRes = preload("res://sim/modules/items.gd")
const SimInventoryRes = preload("res://sim/modules/inventory.gd")
const SimAttentionRes = preload("res://sim/modules/attention_emitter.gd")
const SimNeedsRes = preload("res://sim/modules/needs.gd")
const SimJobsRes = preload("res://sim/modules/jobs.gd")
const SimSkillsRes = preload("res://sim/modules/skills.gd")
const SimSightingsRes = preload("res://sim/modules/sightings.gd")
const SimVisibilityRes = preload("res://sim/vision/visibility.gd")
const SimAllegianceRes = preload("res://sim/modules/allegiance.gd")


static func entry_of(world: Variant, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Dictionary:
		if (c as Dictionary).has("survivor"):
			var by_id: Variant = (c as Dictionary)["survivor"]
			if by_id is Dictionary:
				var hit: Variant = (by_id as Dictionary).get(id)
				if hit != null:
					return hit
		for v in (c as Dictionary).values():
			if v is Dictionary and String((v as Dictionary).get("id", "")) == id:
				return v
			if v is Array:
				for entry in v as Array:
					if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
						return entry
	return null


static func list_uniques(world: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null or world.content == null:
		return out
	var c: Variant = world.content
	if not (c is Dictionary):
		return out
	for path in (c as Dictionary).keys():
		if not String(path).begins_with("survivors/"):
			continue
		var raw: Variant = (c as Dictionary)[path]
		var entries: Array = raw as Array if raw is Array else [raw]
		for entry_v in entries:
			if entry_v is Dictionary and String((entry_v as Dictionary).get("id", "")).begins_with("survivor.unique."):
				out.append(entry_v as Dictionary)
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


# Eyes, and somewhere to keep what they saw.
#
# Until now the *only* observer in a booted district was the player: `boot.playable` set one pair
# of eyes and nothing else got any, so `world.vision` answered for one entity and every
# per-observer question -- an alarm_on_sight zombie noticing a colonist, a colonist noticing
# anything -- was being asked about a view that did not exist. A survivor has eyes. Giving every
# survivor the same daylight eyes the player has is what makes "you cannot aim at what you cannot
# see" mean the same thing for the colony as it does for the player, which docs/09 requires and
# npc_combat.gd's own comment asked for by name.
#
# The cost is one shadowcast per survivor per tick at worst, and in practice far less: visibility
# caches per observer by tile, range, eye and map generation, and a colonist working a post
# stands on the same tile for minutes at a time.
static func give_eyes(world: Variant, ent: int) -> void:
	if not world.components.has_component(ent, "observer"):
		world.components.set_component(ent, "observer", SimVisibilityRes.daylight_eyes())
	SimSightingsRes.attach(world, ent)


static func spawn_unique(world: Variant, id: String, x: float, y: float) -> int:
	var entry: Variant = entry_of(world, id)
	if entry == null:
		for u in list_uniques(world):
			if String(u.get("id", "")) == id:
				entry = u
				break
	assert(entry is Dictionary, "Unknown unique survivor: " + id)
	var e: Dictionary = entry as Dictionary
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "velocity", {"dx": 0.0, "dy": 0.0})
	world.components.set_component(ent, "posture", SimStancesRes.make_posture(SimStancesRes.Stance.Walk))
	world.components.set_component(ent, "facing", {"radians": 0.0})
	# `age` and `appearance.features` are both already authored on the unique's own content
	# entry (mara.json has carried an age since before this slice) -- reading them here is what
	# gives `person_clause` something to say about a hand-authored survivor, the same as it does
	# for a generated one. Neither was read by anything before this slice.
	var app: Variant = e.get("appearance", {})
	var feats: Array = (app as Dictionary).get("features", []) as Array if app is Dictionary else []
	world.components.set_component(ent, "identity", {
		"id": String(e.get("id", id)),
		"name": String(e.get("name", id)),
		"unique": true,
		"traits": (e.get("traits", []) as Array).duplicate() if e.get("traits", []) is Array else [],
		"age": int(e.get("age", 0)),
		"features": feats.duplicate(),
	})
	# Whose side they are on, said out loud. `SimAllegiance.faction_of` reads COLONY for anything
	# with no component at all, so this changes nothing about who fights whom today -- it is what
	# lets a *raider* find them: `enemies_of` scans bodies carrying an allegiance, and a colony
	# that never declared one would be a colony no band could see.
	SimAllegianceRes.attach(world, ent, SimAllegianceRes.COLONY)
	SimHealthRes.make_survivor_body(world, ent)
	SimHealthRes.make_stamina(world, ent)
	SimInventoryRes.make_inventory(world, ent)
	SimAttentionRes.make_emitter(world, ent)
	SimAptitudesRes.apply(world, ent, e.get("aptitudes", {}))
	SimNeedsRes.attach(world, ent)
	var focus: String = String(e.get("focus", "Auto"))
	var row: Dictionary = {}
	if e.get("jobPriorities", {}) is Dictionary:
		var raw: Dictionary = e["jobPriorities"] as Dictionary
		row = SimJobsRes.empty_row()
		for k in raw.keys():
			row[String(k)] = int(raw[k])
	SimJobsRes.attach(world, ent, focus, row)
	SimSkillsRes.attach(world, ent)
	give_eyes(world, ent)
	var kit: Variant = e.get("kit", [])
	equip_kit(world, ent, kit as Array if kit is Array else [], x, y)
	world.events.publish({"type": "survivor.joined", "entity": ent, "id": id})
	return ent


# Spawns and places one kit, for either spawn path. Anything the kit lists that can be *held*
# is held, rather than packed: a weapon in a satchel is not a weapon -- `melee.gd` and
# `ranged.gd` both build their weapon profile off `item.equipped`, so a stowed knife or bat
# left a colonist with nothing to swing and npc_combat.gd with nothing to reach with, which is
# exactly how the second colonist once came to boot unarmed while carrying her own kit.
# Bandages, food and anything else with no equipSlot fall through to the pack; a pack with no
# room, or no pack at all, drops the item at the spawn point rather than losing it.
static func equip_kit(world: Variant, ent: int, kit: Array, x: float, y: float) -> void:
	for item_id in kit:
		var item: int = SimItemsRes.spawn_item(world, String(item_id), {"tier": "scavenged"})
		if String(item_id).begins_with("item.food."):
			SimNeedsRes.mark_spoilage(world, item, String(item_id))
		if _hold_it(world, ent, item):
			continue
		if not SimInventoryRes.stow(world, ent, item):
			world.components.set_component(item, "position", {"x": x, "y": y})


# Puts a kit item in the hand or on the body it belongs to, if that place is still empty.
# Returns false for anything with no equipSlot at all, and for a second item competing for a slot
# already filled -- `equip` would displace the first, and a kit is a list, not a priority order.
static func _hold_it(world: Variant, ent: int, item: int) -> bool:
	var slot: Variant = SimInventoryRes.equip_slot_for(world, item)
	if slot == null:
		return false
	var eq: Variant = world.components.get_component(ent, "equipment")
	if eq is Dictionary and ((eq as Dictionary).get("slots", {}) as Dictionary).has(String(slot)):
		return false
	return SimInventoryRes.equip(world, ent, item)


# One prose sentence naming who somebody is: name, what they did before, roughly how old they
# read, and what a look at them shows. No digits ever appear in it -- age is stored as an
# integer on `identity.age` for the aptitude nudge above, and this is the only other reader,
# translating it through the same age-band prose the nudge came from rather than printing it.
# `work_panel.gd` is the one screen that shows it today; nothing stops a second one calling the
# same function later, which is the point of a read model over a hand-authored line per screen.
static func person_clause(world: Variant, ent: int) -> String:
	var ident: Variant = world.components.get_component(ent, "identity")
	if not ident is Dictionary:
		return ""
	var id: Dictionary = ident as Dictionary
	var name: String = String(id.get("name", "Someone"))
	var parts: Array[String] = [name]
	var line: String = _backstory_line(world, String(id.get("backstoryId", "")), String(id.get("id", "")))
	if line != "":
		parts.append(line)
	var prose: String = _age_prose(world, int(id.get("age", 0)))
	if prose != "":
		parts.append(prose)
	var clause: String = ", ".join(parts)
	var feats: Array = id.get("features", []) as Array
	if not feats.is_empty():
		var words: Array[String] = []
		for f in feats:
			words.append(String(f))
		clause += "; " + ", ".join(words)
	return clause


# The generator's own content block, found the same way `SimRecruits._pool` finds it. Kept as
# its own small scan rather than a shared helper, because `survivors.gd` and `recruits.gd`
# already `preload` each other one way (recruits -> survivors) and a preload back the other way
# is a cycle; `_content_entry`-style duplication is the accepted shape for this codebase (see
# `presentation/appearance.gd`'s own comment on the same triplication).
static func _generator_pool(world: Variant) -> Dictionary:
	if world == null or world.content == null:
		return {}
	var c: Variant = world.content
	if c is Dictionary:
		for v in (c as Dictionary).values():
			if v is Dictionary and String((v as Dictionary).get("id", "")) == "colony.generator.survivors":
				return v as Dictionary
	return {}


# The authored line for a generated backstory, or a hand-authored unique's own `backstory`
# prose (mara.json's full sentence) when there is no backstory id to look up. Looked up at
# read time rather than copied onto `identity` at spawn, so editing a line in content changes
# what every existing save says without a migration.
static func _backstory_line(world: Variant, backstory_id: String, content_id: String) -> String:
	if backstory_id != "":
		var pool: Dictionary = _generator_pool(world)
		for story in pool.get("backstories", []) as Array:
			if story is Dictionary and String((story as Dictionary).get("id", "")) == backstory_id:
				return String((story as Dictionary).get("line", ""))
		return ""
	var entry: Variant = entry_of(world, content_id)
	if entry is Dictionary:
		return String((entry as Dictionary).get("backstory", ""))
	return ""


# The word for an age, off the same bands the aptitude nudge reads -- an age with no band
# covering it (no age known at all reads as 0) says nothing rather than guessing.
static func _age_prose(world: Variant, age: int) -> String:
	if age <= 0:
		return ""
	var pool: Dictionary = _generator_pool(world)
	for band in pool.get("ageBands", []) as Array:
		if not band is Dictionary:
			continue
		if age >= int((band as Dictionary).get("min", 0)) and age <= int((band as Dictionary).get("max", 999)):
			return String((band as Dictionary).get("prose", ""))
	return ""


# Where the boot's unique survivors stand relative to the player, one entry per index in id
# order. 1.6 m -- inside RESCUE_METRES, an arm's reach apart -- because the colony-shape
# measurement behind the GRABS_ENABLED flip found a colony that never stands together cannot
# rescue anybody (docs/23's flag record).
const BOOT_SPAWN_OFFSETS: Array[Vector2] = [
	Vector2(1.6, 0.0), Vector2(0.0, 1.6), Vector2(-1.6, 0.0), Vector2(0.0, -1.6),
	Vector2(1.6, 1.6), Vector2(-1.6, 1.6),
]


static func boot_playable(world: Variant) -> int:
	# Player: midpoint stats so a fixture boot without this stays parity-neutral.
	SimAllegianceRes.attach(world, world.player, SimAllegianceRes.COLONY)
	SimHealthRes.make_survivor_body(world, world.player)
	SimHealthRes.make_stamina(world, world.player)
	SimInventoryRes.make_inventory(world, world.player)
	SimAttentionRes.make_emitter(world, world.player)
	if not world.components.has_component(world.player, "facing"):
		world.components.set_component(world.player, "facing", {"radians": 0.0})
	SimAptitudesRes.apply(world, world.player, {"str": SimAptitudesRes.DEFAULT, "dex": SimAptitudesRes.DEFAULT, "con": SimAptitudesRes.DEFAULT})
	SimNeedsRes.attach(world, world.player)
	SimSkillsRes.attach(world, world.player)
	give_eyes(world, world.player)
	var pos: Variant = world.components.get_component(world.player, "position")
	var px: float = float((pos as Dictionary)["x"]) if pos is Dictionary else 5.0
	var py: float = float((pos as Dictionary)["y"]) if pos is Dictionary else 5.0
	# One fixed offset per unique, by index -- before this every unique computed the same +1.6 m
	# offset and a second boot colonist stacked on the first's point. A table rather than an RNG
	# draw so a boot stays deterministic and parity-neutral; the blocked-tile fallback (mirror the
	# offset) is kept per spawn, same discipline as before.
	var last: int = -1
	var index: int = 0
	for u in list_uniques(world):
		var id: String = String(u.get("id", ""))
		var offset: Vector2 = BOOT_SPAWN_OFFSETS[index % BOOT_SPAWN_OFFSETS.size()]
		index += 1
		if world.is_blocked_tile(floori(px + offset.x), floori(py + offset.y)):
			offset = -offset
		last = spawn_unique(world, id, px + offset.x, py + offset.y)
	# The last unique in id order -- Mara today, and check_m2_stats._mara_spawns pins that; a
	# unique whose id sorts after "mara" changes what this returns and that gate says so.
	return last
