extends RefCounted
# The first-day hints: one sentence, the first time the player meets each of four things, once per save.
#
# What it says is presentation's to choose, and what makes it due is read from sim read models the
# action bar already trusts: `SimContainers.hud_clause` (the E clause), the injuries component, the
# player's sightings and the clock. So a hint never names a key that does nothing where the player
# stands, and the sim never learns that a hint exists.
#
# The seen set is the one piece of state here, and it travels with the save: `session.gd` writes it
# beside the snapshot and reads it back on load, so a run that was loaded does not hear again what
# its player was already told. A new run starts with nothing seen.
#
# A hint is marked seen the moment it is offered, not the moment it is read. A player who walks away
# from it has still been told, and a hint that came back every time it was ignored would be a nag.

const SimContainers = preload("res://sim/modules/containers.gd")
const SimSightings = preload("res://sim/modules/sightings.gd")
const Clock = preload("res://sim/time/clock.gd")

# How long a hint stays up on the wall clock before it lets go by itself. A click lets it go sooner.
const HOLD_MS: int = 20000

# The order they come due in when more than one holds on the same frame. The first thing a player
# meets is the one they need told first.
const ORDER: Array[String] = ["container", "wound", "zombie", "night"]

# Plain sentences, no digits: check_hud judges every line the HUD draws, and these are drawn.
const PROSE: Dictionary = {
	"container": "Containers can hold supplies. Press E beside one to go through it.",
	"wound": "A wound bleeds until it is dressed. Press T to treat it.",
	"zombie": "That is a zombie. Keep your distance, and keep quiet: noise draws them.",
	"night": "Night has come. You see only as far as your light reaches.",
}

# Every id seen in this save, as a set. Dictionary, not Array, so a membership test is one lookup.
var seen: Dictionary = {}
# The id on screen right now, or "" for none, and the wall-clock millisecond it was offered at.
var current: String = ""
var _offered_at_ms: int = 0


static func prose_of(id: String) -> String:
	return String(PROSE.get(id, ""))


# The first hint in ORDER whose situation holds for `player` and that `seen_ids` does not name, or
# "" for none. Pure over the world and the set, so the gate can ask it about a fabricated world.
static func due(world: Variant, player: int, seen_ids: Dictionary) -> String:
	if world == null:
		return ""
	for id in ORDER:
		if seen_ids.has(id):
			continue
		if _holds(id, world, player):
			return id
	return ""


static func _holds(id: String, world: Variant, player: int) -> bool:
	match id:
		"container":
			return not SimContainers.hud_clause(world, player).is_empty()
		"wound":
			return _is_wounded(world, player)
		"zombie":
			return not SimSightings.remembered(world, player, ["zombie"]).is_empty()
		"night":
			return Clock.phase_at(Clock.time_of_day(int(world.tick))) == Clock.Phase.Night
	return false


# Any open wound at all. The injuries component holds only the wounds still standing.
static func _is_wounded(world: Variant, player: int) -> bool:
	var inj: Variant = world.components.get_component(player, "injuries")
	return inj is Dictionary and not ((inj as Dictionary).get("wounds", []) as Array).is_empty()


# The prose the HUD should speak this frame, or "" for none. Offers the next due hint when none is up,
# marking it seen as it goes, and lets the current one go once HOLD_MS has passed.
func offer(world: Variant, player: int, now_ms: int) -> String:
	if not current.is_empty() and now_ms - _offered_at_ms > HOLD_MS:
		current = ""
	if current.is_empty():
		var id: String = due(world, player, seen)
		if id.is_empty():
			return ""
		current = id
		_offered_at_ms = now_ms
		seen[id] = true
	return prose_of(current)


# The player clicked the hint away. It stays seen: dismissing is not un-telling.
func dismiss() -> void:
	current = ""


# A fresh run, or a loaded one, starts from its own seen set and nothing on screen.
func reset() -> void:
	seen = {}
	current = ""


# The seen ids as an Array, in ORDER, so the same set always writes the same bytes.
func to_save() -> Array:
	var out: Array = []
	for id in ORDER:
		if seen.has(id):
			out.append(id)
	return out


# Reads what `to_save` wrote. Anything unknown is dropped rather than kept as a hint that never shows.
func from_save(ids: Variant) -> void:
	reset()
	if not ids is Array:
		return
	for id in ids as Array:
		if ORDER.has(String(id)):
			seen[String(id)] = true
