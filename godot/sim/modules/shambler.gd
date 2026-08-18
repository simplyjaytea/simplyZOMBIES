class_name SimShambler
extends RefCounted

# Port of src/sim/modules/shambler.ts — 5 states, gradient+bias pursuit, plus the
# grab -> struggle -> bite loop ("Make harm real" slice, Part B). Cripple (the CRIPPLED_SOURCE
# move_speed penalty on a destroyed pelvis) and stagger (a swing knocking a shambler out of
# whatever it was doing) remain unwired here -- shambler.gd still subscribes to neither
# injury.sustained nor entity.staggered -- and stay open for whoever picks that up next.

const ShamblerState: Dictionary = {
	"Wander": 0,
	"Seek": 1,
	"Investigate": 2,
	"Staggered": 3,
	"Pursue": 4,
}

const DEFAULT_LOCOMOTION: Dictionary = {"speed": 0.8, "wander": 0.35, "mill": 0.25, "crawl": 0.25}
const DEFAULT_GRAB_STRENGTH: float = 0.5

const SPREAD_RADIANS: float = 0.62
const NOISE_SENSITIVITY: float = 0.2
const SCENT_SENSITIVITY: float = 0.9
const SCENT_BIAS: float = 0.35
const LIGHT_SENSITIVITY: float = 0.1
const LIGHT_BIAS: float = 0.5
const CONTACT_METRES: float = 1.6
const GRAB_METRES: float = 1.0
const RELEASE_METRES: float = 3.2
const MILL_TICKS: int = 90
const COMMIT_TICKS: int = 400

# The grab -> struggle -> bite loop. Originally ported verbatim from src/sim/modules/shambler.ts;
# four of these values have since moved off the oracle's numbers in the bite-lethality re-tune
# docs/23's Milestone 2 status records. The frozen TypeScript reference deliberately keeps the old
# ones -- R1 parity covers movement, so the divergence is expected and is not drift.
#
# 1.5 s to the first bite, four seconds between later ones, a bite costs a wound rather than
# health-bar damage, and the contextual F commits four fifths of a second before the escape roll
# lands.
const FIRST_BITE_TICKS: int = 30
# 80, not the oracle's 40. A held survivor cannot fight back, so this clock *is* the lethality of
# a hold: at 40 the same hold delivered twice as many bites in the window it took the colony to
# come and pull it off.
const REPEAT_BITE_TICKS: int = 80
# The ceiling on a bite, not the value of one -- see BITE_DAMAGE_PART_FRACTION below.
const BITE_DAMAGE: float = 8.0
# A bite takes a fraction of the part's *maximum* rather than a flat number, floored so that no
# bite is ever free. CLAUDE.md's standing trap: parts do not share a scale, so a flat 8 was a
# scratch on a 40-torso and a death sentence on a 15-head. 0.35 puts a head at three bites rather
# than two; a torso still takes the full 8 (0.35 * 40 = 14, clamped by BITE_DAMAGE); hands and
# feet drop to 3.5. The floor matters mechanically as well as tonally: health.gd:141 records no
# wound for a hit that removed no integrity, so a bite that rounded to nothing would leave no
# mark to treat.
const BITE_DAMAGE_PART_FRACTION: float = 0.35
const BITE_DAMAGE_MIN: float = 2.0
# 16 and 15, down from the oracle's 20/20: the contest itself is untouched (SimAptitudes gives one
# shambler 1/1.5 = 0.667, pinned in check_m2_stats.gd), but a survivor gets to have it slightly
# sooner and can afford six attempts on a full tank rather than five. It no longer doubles as the
# re-grab cooldown -- see REGRAB_COOLDOWN_TICKS below.
const STRUGGLE_TICKS: int = 16
const STRUGGLE_STAMINA: float = 15.0
# How long a held body waits for a decision before it fights back on its own. Two seconds: long
# enough that an attentive player's F is always the thing that answers a grab, short enough that
# nobody stands still being eaten because the person at the keyboard is looking elsewhere -- or,
# in a harness, because there is nobody at the keyboard at all. It is a gap between *attempts*
# rather than the age of the hold (every arming site resets `grabbed.heldTicks`), so a survivor
# who has just failed an escape gets the same beat before the next one.
const STRUGGLE_INSTINCT_TICKS: int = 40
# How long a shambler that has just lost its grip must wait before it can take anyone again.
# This was STRUGGLE_TICKS doing double duty, which meant the escape lever silently moved it: a
# cheaper, faster struggle also handed the shambler its hands back sooner, and instrumenting a
# live district showed the same shambler re-taking the same survivor every 24 to 36 ticks. Named
# separately and pinned at its old value, so the two can be tuned apart, and so BREAK_AWAY_TICKS
# keeps outliving it the way its own note says it should.
const REGRAB_COOLDOWN_TICKS: int = 20
# An escape that leaves you standing inside arm's reach is not an escape. Without this the
# balance harness lost a whole colony on 1 seed in 4: a survivor would tear free, stand exactly
# where they were, be re-taken the moment the holder's cooldown lapsed, and pay another tankful
# of stamina for the privilege until there was none left. The player solves this by walking away;
# nothing in the build did it for anyone else. BREAK_AWAY_TICKS is deliberately a shade longer
# than the re-grab cooldown so the separation outlives it.

# Grabs are still off by default, and the reason has changed three times now. The first two were
# guesses; the last two were measured, and the measurement is the point of the note.
#
# Reason one (retired): "the flip waits on a recovery clock" -- a bite rolled over all ten parts
# and nothing raised a part's integrity again, so grabs were cumulative rather than hard.
# Recovery shipped (M2_RECOVERY_OK), the flag was flipped, and the fast balance tier failed
# *worse*.
#
# Reason two (retired, and fixed): a held survivor was being executed. A head is 15, a bite was a
# flat 8, and one bite in five aimed at the head, so two rolls killed. Seed 404 lost both
# colonists on day one with `cause=head-destroyed`. That is what the four levers above answer --
# HELD_HIT_LOCATION_WEIGHTS, REPEAT_BITE_TICKS 40 -> 80, part-scaled damage, a cheaper struggle --
# and it worked: on the same seed the head share falls from a fifth to a twentieth and the first
# death moves off day one.
#
# Reason three (retired as an explanation, and answered): the harness colony had no agency. An
# unattended `controlled` survivor never struggled because F is a key press and a harness presses
# nothing, the second colonist booted unarmed, and `npc.combat` dropped a holder to the back of
# its own threat queue. All three are fixed -- instinct (STRUGGLE_INSTINCT_TICKS above, INSTINCT
# in check_m2_contact.gd), a kit weapon that is actually held (SimSurvivors._hold_it, ARMED in
# check_m2_balance.gd), and holder-first target selection (HOLDER in check_m2_npc_combat.gd) --
# and they moved every number except the one that decides. On seed 404 a campaign with grabs on
# went from 111 bites and 0 struggles to 57 bites and 73 struggles; the shipped default, with
# grabs still off, records the colony's first kills in the fast tier at all (6 on 404, 1 on
# 90210, where every arm previously read zero).
#
# Reason four, which is where it now sits, and which is a design call about a price rather than a
# bug: *an escape costs stamina, and a survivor held over and over cannot afford it.* Measured
# on the same four seeds with the flag forced on -- 20260805 and 31337 end 2/2 (neither boot
# colonist is ever held), 404 and 90210 still end 0/2, both by blood loss. The two that die spend
# 65% and 69% of their living ticks held, by 1.4 holders on average, and *38% and 49% of those
# held ticks with a tank too empty to pay STRUGGLE_STAMINA* -- and an empty tank is a hold with
# no exit, because nothing else in the build can pull somebody free. It is not player agency
# either: a driver mashing F every single tick changes nothing (404 still 0/2, the played
# survivor connects once in a whole campaign, and empty-tank ticks roughly double, because F
# spends the same stamina sooner). The levers left are the price of an escape (STRUGGLE_STAMINA,
# or stamina that recovers while held), somebody else being able to break a hold, or making
# contact rarer -- all three are calls about how the game should feel, not numbers to be picked
# here. docs/23's Milestone 2 status carries the measurement seed by seed.
#
# So the loop ships complete, gated and off for one more turn, the way
# SimMelee.REFUSE_EXHAUSTED_SWINGS did: check_m2_contact.gd turns it on explicitly, so every
# assertion there exercises the real thing rather than the shipped default.
#
# A static var rather than a const purely so that gate can switch it on for the worlds it builds;
# `_the_flag_actually_gates_acquisition` exercises both directions, which is what keeps the flag
# honest. Treat it as a compile-time constant everywhere else. It is deliberately NOT world state
# and deliberately not saved -- a flag that could differ between a save and its reload would be a
# determinism bug, and this one is set once, at boot or by a gate, and never again.
static var GRABS_ENABLED: bool = false
const BREAK_AWAY_TICKS: int = 26
const BREAK_AWAY_SPEED: float = 1.6

const SimLocomotionRes = preload("res://sim/locomotion.gd")
const SimTileMapRes = preload("res://sim/map/tilemap.gd")
# _roll_body_part is reused rather than reimplemented -- CLAUDE.md's shape is "one canonical
# place", and melee.gd:31 already is it.
const SimMeleeRes = preload("res://sim/modules/melee.gd")
# escape_chance already resolves the STR-scaled grab_escape modifier; this module has no
# business rolling its own escape maths.
const SimAptitudesRes = preload("res://sim/modules/aptitudes.gd")
# entity_index, so a victim's `grabbed.sources` sorts the same way regardless of spawn order --
# the save/replay-stable ordering the oracle's Grabbed component keeps.
const SimEntityStoreRes = preload("res://sim/entity_store.gd")
# max_of, so bite_damage_for scales against the same part table health.gd damages, and the
# held-bite location table -- preloaded rather than leaning on the global class name, the way
# every other cross-module reference in this file is.
const SimHealthRes = preload("res://sim/modules/health.gd")
const SimCombatRes = preload("res://sim/combat.gd")


static func default_shambler_speeds() -> Dictionary:
	var seek: float = SimLocomotionRes.zombie_speed(DEFAULT_LOCOMOTION["speed"])
	return {
		"seekSpeed": seek,
		"wanderSpeed": seek * float(DEFAULT_LOCOMOTION["wander"]),
		"millSpeed": seek * float(DEFAULT_LOCOMOTION["mill"]),
		"crawlFactor": float(DEFAULT_LOCOMOTION["crawl"]),
		"grabStrength": DEFAULT_GRAB_STRENGTH,
		"canGrab": true,
		"ticksToGrab": 0,
	}


static func make_shambler(world: Variant, entity: int, rng: Variant, type_id: String = "zombie.shambler") -> void:
	var loco: Dictionary = _locomotion_of(world, type_id)
	var grab: Dictionary = _grab_of(world, type_id)
	var seek_speed: float = SimLocomotionRes.zombie_speed(float(loco["speed"]))
	world.components.set_component(entity, "shambler", {
		"state": ShamblerState["Wander"],
		"ticksToTurn": int(rng.call("int_range", 20, 120)),
		"ticksMilling": 0,
		"ticksCommitted": 0,
		"bias": rng.call("float_range", -SPREAD_RADIANS, SPREAD_RADIANS),
		"ticksStaggered": 0,
		"seekSpeed": seek_speed,
		"wanderSpeed": seek_speed * float(loco["wander"]),
		"millSpeed": seek_speed * float(loco["mill"]),
		"crawlFactor": float(loco["crawl"]),
		"grabStrength": float(grab["strength"]),
		"canGrab": bool(grab["enabled"]),
		"ticksToGrab": 0,
	})


static func _get_content_entry(world: Variant, type_id: String, id: String) -> Variant:
	if world == null or world.content == null:
		return null
	var c: Variant = world.content
	if c is Object and (c as Object).has_method("get"):
		return (c as Object).call("get", type_id, id)
	if c is Dictionary:
		if (c as Dictionary).has(type_id):
			var by_id: Variant = (c as Dictionary)[type_id]
			if by_id is Dictionary:
				var hit: Variant = (by_id as Dictionary).get(id)
				if hit != null:
					return hit
		for v in (c as Dictionary).values():
			if v is Array:
				for entry in v as Array:
					if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
						return entry
			elif v is Dictionary and String((v as Dictionary).get("id", "")) == id:
				return v as Dictionary
	return null

static func _locomotion_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = _get_content_entry(world, "zombie", type_id)
	var loco: Dictionary = {}
	if entry != null:
		var l: Variant = (entry as Dictionary).get("locomotion")
		if l != null:
			loco = l as Dictionary
	return {
		"speed": float(loco.get("speed", DEFAULT_LOCOMOTION["speed"])),
		"wander": float(loco.get("wander", DEFAULT_LOCOMOTION["wander"])),
		"mill": float(loco.get("mill", DEFAULT_LOCOMOTION["mill"])),
		"crawl": float(loco.get("crawl", DEFAULT_LOCOMOTION["crawl"])),
	}


static func _grab_of(world: Variant, type_id: String) -> Dictionary:
	var entry: Variant = _get_content_entry(world, "zombie", type_id)
	if entry == null:
		return {"enabled": true, "strength": DEFAULT_GRAB_STRENGTH}
	var behaviours: Variant = (entry as Dictionary).get("behaviors")
	var enabled: bool = true
	if behaviours is Array:
		enabled = (behaviours as Array).has("grab")
	else:
		enabled = true
	var grab: Dictionary = {}
	var g: Variant = (entry as Dictionary).get("grab")
	if g != null:
		grab = g as Dictionary
	return {"enabled": enabled, "strength": float(grab.get("strength", DEFAULT_GRAB_STRENGTH))}


static func _steer_uphill(field: Variant, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary) -> bool:
	var uphill: Variant = field.uphill_noise(float(pos["x"]), float(pos["y"]))
	if uphill == null:
		return false
	var angle: float = atan2(float((uphill as Dictionary)["dy"]), float((uphill as Dictionary)["dx"])) + float(shambler_data["bias"])
	vel["dx"] = cos(angle) * float(shambler_data["seekSpeed"])
	vel["dy"] = sin(angle) * float(shambler_data["seekSpeed"])
	return true


static func _drift_upscent(field: Variant, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary) -> void:
	var uphill: Variant = field.uphill_scent(float(pos["x"]), float(pos["y"]))
	if uphill == null:
		return
	var speed: float = sqrt(float(vel["dx"]) * float(vel["dx"]) + float(vel["dy"]) * float(vel["dy"]))
	if speed == 0.0:
		return
	var current: float = atan2(float(vel["dy"]), float(vel["dx"]))
	var toward: float = atan2(float((uphill as Dictionary)["dy"]), float((uphill as Dictionary)["dx"])) + float(shambler_data["bias"])
	var delta: float = toward - current
	while delta > PI:
		delta -= PI * 2.0
	while delta < -PI:
		delta += PI * 2.0
	var angle: float = current + delta * SCENT_BIAS
	vel["dx"] = cos(angle) * speed
	vel["dy"] = sin(angle) * speed


static func _contact_target(survivors: Array, pos: Dictionary, radius_metres: float) -> Variant:
	var limit: float = radius_metres * radius_metres
	var best: Variant = null
	var best_dist: float = limit
	for survivor in survivors:
		var s: Dictionary = survivor as Dictionary
		var dx: float = float(s["x"]) - float(pos["x"])
		var dy: float = float(s["y"]) - float(pos["y"])
		var dist: float = dx * dx + dy * dy
		if dist <= best_dist:
			best = s["entity"]
			best_dist = dist
	return best


static func _gather_survivors(world: Variant) -> Array:
	var out: Array = []
	for entity in world.components.query(["position"]):
		var is_survivor: bool = world.components.has_component(int(entity), "controlled") \
			or world.components.has_component(int(entity), "identity")
		if not is_survivor:
			continue
		var at: Variant = world.components.get_component(int(entity), "position")
		if at == null:
			continue
		out.append({"entity": int(entity), "x": float((at as Dictionary)["x"]), "y": float((at as Dictionary)["y"])})
	return out


static func _chase(world: Variant, target: int, pos: Dictionary, vel: Dictionary, shambler_data: Dictionary) -> void:
	var at: Variant = world.components.get_component(target, "position")
	if at == null:
		return
	var dx: float = float((at as Dictionary)["x"]) - float(pos["x"])
	var dy: float = float((at as Dictionary)["y"]) - float(pos["y"])
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist == 0.0:
		return
	vel["dx"] = dx / dist * float(shambler_data["seekSpeed"])
	vel["dy"] = dy / dist * float(shambler_data["seekSpeed"])


static func _lean_to_light(world: Variant, entity: int, pos: Dictionary, vel: Dictionary) -> void:
	if not world.components.has_component(entity, "observer"):
		return
	var speed: float = sqrt(float(vel["dx"]) * float(vel["dx"]) + float(vel["dy"]) * float(vel["dy"]))
	if speed == 0.0:
		return
	var best_rem: float = 0.0
	var best_x: float = 0.0
	var best_y: float = 0.0
	for source in world.light.sources():
		var at: Variant = world.light.source_at(int(source))
		if at == null:
			continue
		var dx: float = float((at as Dictionary)["x"]) - float(pos["x"])
		var dy: float = float((at as Dictionary)["y"]) - float(pos["y"])
		var rem: float = float((at as Dictionary)["magnitude"]) - sqrt(dx * dx + dy * dy)
		if rem <= best_rem:
			continue
		if world.vision.detail(int(entity), float((at as Dictionary)["x"]), float((at as Dictionary)["y"])) == 0:
			continue
		best_rem = rem
		best_x = float((at as Dictionary)["x"])
		best_y = float((at as Dictionary)["y"])
	if best_rem <= 0.0:
		return
	var current: float = atan2(float(vel["dy"]), float(vel["dx"]))
	var toward: float = atan2(best_y - float(pos["y"]), best_x - float(pos["x"]))
	var delta: float = toward - current
	while delta > PI:
		delta -= PI * 2.0
	while delta < -PI:
		delta += PI * 2.0
	var angle: float = current + delta * LIGHT_BIAS * LIGHT_SENSITIVITY
	vel["dx"] = cos(angle) * speed
	vel["dy"] = sin(angle) * speed


# What one bite takes out of one part. Public and static so a gate can assert the arithmetic
# without standing up a hold, and so there is exactly one place the scaling lives -- the publish
# site below is the only caller.
#
# The band edge is deliberate and worth naming, because it moves a wound's severity, not just its
# number: wounds.gd bands severity on damage / part max, and an arm bite used to be 8/20 = 0.40,
# sitting exactly on the DeepWound boundary. Scaled, an arm takes 7.0 of 20 = 0.35, which is a
# Laceration -- a fifth of the bleed rate (BLEED_PER_TICK 0.004 against 0.02). That is the
# intended side of the line: a bite on a forearm you were using to fend a mouth off should be a
# nasty tear you can bandage, and the deep wounds should belong to the torso and the throat.
static func bite_damage_for(body: Variant, part: String) -> float:
	if not (body is Dictionary):
		return BITE_DAMAGE
	var part_max: Variant = SimHealthRes.max_of(body as Dictionary, part)
	if part_max == null or int(part_max) <= 0:
		return BITE_DAMAGE
	return maxf(BITE_DAMAGE_MIN, minf(BITE_DAMAGE, BITE_DAMAGE_PART_FRACTION * float(int(part_max))))


# A short physical reach may cross screening foliage, but never a solid wall or window.
# Three samples along the ray rather than a full raycast, matching the oracle's clearContact
# (src/sim/modules/shambler.ts:628) -- world.is_blocked_tile is the Godot equivalent of the
# oracle's blockedAt, and floori() here matches world.gd's own _blocked_at exactly.
static func _clear_contact(world: Variant, from: Dictionary, to: Dictionary) -> bool:
	for fraction in [0.25, 0.5, 0.75]:
		var x: float = float(from["x"]) + (float(to["x"]) - float(from["x"])) * fraction
		var y: float = float(from["y"]) + (float(to["y"]) - float(from["y"])) * fraction
		if world.is_blocked_tile(floori(x), floori(y)):
			return false
	return true


# Opens a hold. Idempotent: a source that already has a grabState is left alone rather than
# re-rolling ticksUntilBite, and a victim already held by someone else just gains a second
# source rather than a second `grabbed` component.
static func _start_grab(world: Variant, source: int, victim: int) -> void:
	if world.components.has_component(source, "grabState"):
		return
	world.components.set_component(source, "grabState", {"victim": victim, "ticksUntilBite": FIRST_BITE_TICKS})
	var existing: Variant = world.components.get_component(victim, "grabbed")
	var grabbed: Dictionary
	if existing is Dictionary:
		grabbed = existing as Dictionary
	else:
		# CLAUDE.md trap #1: a plain Array, never a PackedInt32Array -- appending to a packed
		# array read out of a Dictionary appends to a copy and silently does nothing.
		grabbed = {"sources": [], "struggleTicks": 0, "heldTicks": 0}
		world.components.set_component(victim, "grabbed", grabbed)
	var sources: Array = grabbed["sources"] as Array
	if not sources.has(source):
		sources.append(source)
		# Slot-ordered by entity index, not insertion order, so a save/load or a replay sees
		# the same holder list regardless of which shambler's think-loop happened to run first.
		sources.sort_custom(func(a, b) -> bool: return SimEntityStoreRes.entity_index(int(a)) < SimEntityStoreRes.entity_index(int(b)))
	world.events.publish({"type": "grab.started", "victim": victim, "source": source})


# Closes one hold. Always arms the STRUGGLE_TICKS re-grab cooldown on the source, regardless of
# why the hold ended (escape, geometry, or the holder dying) -- a freed survivor gets one clear
# second before the same shambler can close on them again.
static func _release_grab(world: Variant, source: int) -> void:
	var hold: Variant = world.components.get_component(source, "grabState")
	if not (hold is Dictionary):
		return
	world.components.remove(source, "grabState")
	var shambler_data: Variant = world.components.get_component(source, "shambler")
	if shambler_data is Dictionary:
		(shambler_data as Dictionary)["ticksToGrab"] = REGRAB_COOLDOWN_TICKS
	var grabbed: Variant = world.components.get_component(int((hold as Dictionary)["victim"]), "grabbed")
	if not (grabbed is Dictionary):
		return
	var sources: Array = (grabbed as Dictionary)["sources"] as Array
	var index: int = sources.find(source)
	if index != -1:
		sources.remove_at(index)
	if sources.is_empty():
		var freed: int = int((hold as Dictionary)["victim"])
		world.components.remove(freed, "grabbed")
		_break_away(world, freed, source)


# Points a just-freed survivor directly away from whoever was holding them and commits them to
# that heading for BREAK_AWAY_TICKS. Direction is taken once, at the moment of release, rather
# than re-derived per tick: this is somebody shoving off and stumbling clear, not a pursuit
# solver, and re-aiming every tick would have it orbit a shambler that follows.
static func _break_away(world: Variant, victim: int, from_source: int) -> void:
	var at: Variant = world.components.get_component(victim, "position")
	var away_from: Variant = world.components.get_component(from_source, "position")
	if not (at is Dictionary) or not (away_from is Dictionary):
		return
	var dx: float = float((at as Dictionary)["x"]) - float((away_from as Dictionary)["x"])
	var dy: float = float((at as Dictionary)["y"]) - float((away_from as Dictionary)["y"])
	var length: float = sqrt(dx * dx + dy * dy)
	if length == 0.0:
		return
	world.components.set_component(victim, "breakAway", {
		"dx": dx / length * BREAK_AWAY_SPEED,
		"dy": dy / length * BREAK_AWAY_SPEED,
		"ticksLeft": BREAK_AWAY_TICKS,
	})


# Frees a victim from every hand holding them at once -- the whole point of the contextual F
# struggle, and what entity.killed routes through when the victim dies. Duplicated first: each
# _release_grab call mutates the same sources array the loop would otherwise be walking.
static func _release_victim(world: Variant, victim: int) -> void:
	var grabbed: Variant = world.components.get_component(victim, "grabbed")
	if not (grabbed is Dictionary):
		return
	var sources: Array = ((grabbed as Dictionary)["sources"] as Array).duplicate()
	for source in sources:
		_release_grab(world, int(source))


# Commits one escape attempt, whoever asked for it. The three intakes below -- the player's F,
# the held survivor's instinct, and an NPC's -- differ only in *when* they call this; what an
# attempt costs and whether it is affordable is decided once, here, so a lever moved for one of
# them cannot quietly miss the other two. Returns whether an attempt was actually armed.
#
# Arming resets `heldTicks`, which is what makes instinct a gap between attempts rather than the
# age of the hold: a survivor who has just spent a tankful failing gets the same beat before the
# next try, and a player who presses F pushes instinct back by doing so.
static func _arm_struggle(world: Variant, victim: int) -> bool:
	var grabbed: Variant = world.components.get_component(victim, "grabbed")
	if not (grabbed is Dictionary):
		return false
	var g: Dictionary = grabbed as Dictionary
	if int(g["struggleTicks"]) > 0:
		return false
	var stamina: Variant = world.components.get_component(victim, "stamina")
	if stamina is Dictionary and float((stamina as Dictionary)["current"]) < STRUGGLE_STAMINA:
		return false
	g["struggleTicks"] = STRUGGLE_TICKS
	g["heldTicks"] = 0
	world.events.publish({"type": "stamina.spent", "entity": victim, "amount": STRUGGLE_STAMINA})
	return true


static func register_module(world: Variant, _map: Variant) -> void:
	world.systems.register("shambler.think", "ai", 0, func(w: Variant) -> void:
		var rng: Variant = w.rng.stream("shambler")
		var field: Variant = w.field
		var survivors: Array = _gather_survivors(w)
		var audible: float = float(field.calibration["floor"]) / NOISE_SENSITIVITY
		var detectable: float = float(field.calibration["scentFloor"]) / SCENT_SENSITIVITY
		for entity in w.components.query(["position", "velocity", "shambler"]):
			var shambler_comp: Variant = w.components.get_component(int(entity), "shambler")
			var pos: Variant = w.components.get_component(int(entity), "position")
			var vel: Variant = w.components.get_component(int(entity), "velocity")
			if shambler_comp == null or pos == null or vel == null:
				continue
			var sd: Dictionary = shambler_comp as Dictionary
			var vd: Dictionary = vel as Dictionary
			var pd: Dictionary = pos as Dictionary
			var heard: bool = field.noise_at(float(pd["x"]), float(pd["y"])) >= audible
			var smelled: bool = field.scent_at(float(pd["x"]), float(pd["y"])) >= detectable
			if int(sd["ticksToGrab"]) > 0:
				sd["ticksToGrab"] = int(sd["ticksToGrab"]) - 1
			if w.components.has_component(int(entity), "grabState"):
				# Holding is neither pathfinding nor pursuit. Both bodies stay exactly where
				# the mistake happened until the survivor escapes or something knocks the
				# grabber away -- see the hold-lifecycle loops below this state machine for
				# what actually resolves a hold (validate, struggle, bite, then acquire).
				vd["dx"] = 0.0
				vd["dy"] = 0.0
				continue
			match int(sd["state"]):
				ShamblerState["Staggered"]:
					vd["dx"] = 0.0
					vd["dy"] = 0.0
					sd["ticksStaggered"] = int(sd["ticksStaggered"]) - 1
					if int(sd["ticksStaggered"]) <= 0:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = 0
				ShamblerState["Pursue"]:
					var target: Variant = _contact_target(survivors, pd, RELEASE_METRES)
					if target == null:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = int(rng.call("int_range", 20, 120))
					else:
						_chase(w, int(target), pd, vd, sd)
				ShamblerState["Seek"]:
					var caught: Variant = _contact_target(survivors, pd, CONTACT_METRES)
					if caught != null:
						sd["state"] = ShamblerState["Pursue"]
						sd["ticksCommitted"] = 0
						_chase(w, int(caught), pd, vd, sd)
					elif _steer_uphill(field, pd, vd, sd):
						sd["ticksCommitted"] = COMMIT_TICKS
					elif heard:
						sd["state"] = ShamblerState["Investigate"]
						sd["ticksMilling"] = MILL_TICKS
						sd["ticksToTurn"] = 0
					elif int(sd["ticksCommitted"]) - 1 > 0:
						sd["ticksCommitted"] = int(sd["ticksCommitted"]) - 1
					else:
						sd["ticksCommitted"] = 0
						sd["state"] = ShamblerState["Investigate"]
						sd["ticksMilling"] = MILL_TICKS
						sd["ticksToTurn"] = 0
				ShamblerState["Investigate"]:
					sd["ticksMilling"] = int(sd["ticksMilling"]) - 1
					if int(sd["ticksMilling"]) <= 0:
						sd["state"] = ShamblerState["Wander"]
						sd["ticksToTurn"] = 0
					elif int(sd["ticksToTurn"]) <= 0:
						var angle: float = rng.call("float_range", 0.0, PI * 2.0)
						vd["dx"] = cos(angle) * float(sd["millSpeed"])
						vd["dy"] = sin(angle) * float(sd["millSpeed"])
						sd["ticksToTurn"] = int(rng.call("int_range", 10, 25))
					else:
						sd["ticksToTurn"] = int(sd["ticksToTurn"]) - 1
				_:
					var caught2: Variant = _contact_target(survivors, pd, CONTACT_METRES)
					if caught2 != null:
						sd["state"] = ShamblerState["Pursue"]
						_chase(w, int(caught2), pd, vd, sd)
					elif heard:
						sd["state"] = ShamblerState["Seek"]
						sd["ticksCommitted"] = COMMIT_TICKS
						_steer_uphill(field, pd, vd, sd)
					elif int(sd["ticksToTurn"]) <= 0:
						var angle2: float = rng.call("float_range", 0.0, PI * 2.0)
						vd["dx"] = cos(angle2) * float(sd["wanderSpeed"])
						vd["dy"] = sin(angle2) * float(sd["wanderSpeed"])
						sd["ticksToTurn"] = int(rng.call("int_range", 20, 120))
					else:
						sd["ticksToTurn"] = int(sd["ticksToTurn"]) - 1
					if smelled:
						_drift_upscent(field, pd, vd, sd)
					_lean_to_light(w, int(entity), pd, vd)

		# --- Hold lifecycle, alongside the state machine above rather than in a separate
		# combat-phase system (plan deviates from the oracle here on purpose). Order is
		# ported from the oracle's shambler.grab (src/sim/modules/shambler.ts:872-960) and
		# still matters: validate existing holds, resolve a completed struggle, deliver
		# due bites, then begin new holds. An escape that completes this tick therefore
		# wins a same-tick tie against a bite -- the released hold's grabState is gone by
		# the time the bite loop's query runs -- and the re-grab cooldown _release_grab
		# arms stops the final pass from taking the same survivor again immediately.
		var grab_rng: Variant = w.rng.stream("grab")

		# 1. Validate. A grabState pointing at a dead, despawned, or now-unreachable
		# victim does not persist -- the entity.killed subscription below handles death
		# and despawn across tick boundaries; this is the geometry half, the wall that
		# grew or the reach that widened between one tick and the next.
		for source in w.components.query(["grabState", "position", "shambler"]):
			var hold: Dictionary = w.components.get_component(int(source), "grabState") as Dictionary
			var victim: int = int(hold["victim"])
			var from_pos: Dictionary = w.components.get_component(int(source), "position") as Dictionary
			var at_pos: Variant = w.components.get_component(victim, "position")
			var still_here: bool = at_pos is Dictionary and w.entities.is_alive(victim)
			if still_here:
				var dx: float = float((at_pos as Dictionary)["x"]) - float(from_pos["x"])
				var dy: float = float((at_pos as Dictionary)["y"]) - float(from_pos["y"])
				still_here = sqrt(dx * dx + dy * dy) <= RELEASE_METRES and _clear_contact(w, from_pos, at_pos as Dictionary)
			if not still_here:
				_release_grab(w, int(source))
				var self_data: Dictionary = w.components.get_component(int(source), "shambler") as Dictionary
				self_data["state"] = ShamblerState["Wander"]
				self_data["ticksToTurn"] = 20
				continue
			var source_vel: Variant = w.components.get_component(int(source), "velocity")
			if source_vel is Dictionary:
				(source_vel as Dictionary)["dx"] = 0.0
				(source_vel as Dictionary)["dy"] = 0.0
			var victim_vel: Variant = w.components.get_component(victim, "velocity")
			if victim_vel is Dictionary:
				(victim_vel as Dictionary)["dx"] = 0.0
				(victim_vel as Dictionary)["dy"] = 0.0

		# 2. Resolve a completed struggle. shambler.struggle-intake (input, order 9) arms
		# struggleTicks; once it counts down to zero the escape roll happens exactly once.
		# A successful escape does not force the holder(s) back to Wander -- only geometry
		# failure (step 1) does that; an escaped-from shambler is still Pursuing and will
		# chase again next tick through the ordinary state machine above.
		# Deliberately not scoped to `controlled`: three intakes arm struggleTicks now -- the
		# player's F, a held survivor's instinct, and an NPC's own -- and all three resolve
		# through this one contest, which is why widening who may struggle has never meant
		# touching the escape maths.
		for victim in w.components.query(["grabbed"]):
			var grabbed: Dictionary = w.components.get_component(int(victim), "grabbed") as Dictionary
			if int(grabbed["struggleTicks"]) <= 0:
				continue
			grabbed["struggleTicks"] = int(grabbed["struggleTicks"]) - 1
			if int(grabbed["struggleTicks"]) > 0:
				continue
			var total_strength: float = 0.0
			for source2 in grabbed["sources"] as Array:
				var holder: Variant = w.components.get_component(int(source2), "shambler")
				if holder is Dictionary:
					total_strength += float((holder as Dictionary)["grabStrength"])
			if float(grab_rng.call("next")) < SimAptitudesRes.escape_chance(w, int(victim), total_strength):
				_release_victim(w, int(victim))

		# 3. Deliver due bites, over the holds that survived steps 1-2 -- a hold released
		# this tick simply no longer matches this query.
		for source3 in w.components.query(["grabState", "shambler"]):
			var hold2: Dictionary = w.components.get_component(int(source3), "grabState") as Dictionary
			var ticks_left: int = int(hold2["ticksUntilBite"]) - 1
			if ticks_left > 0:
				hold2["ticksUntilBite"] = ticks_left
				continue
			hold2["ticksUntilBite"] = REPEAT_BITE_TICKS
			var bite_victim: int = int(hold2["victim"])
			var victim_body: Variant = w.components.get_component(bite_victim, "body")
			# Held geometry, not swing geometry -- SimCombatRes.HELD_HIT_LOCATION_WEIGHTS carries
			# the reasoning for why the head share collapses inside a grapple. A zombie body
			# ignores the override (melee.gd); zombies do not grab each other today, but the
			# roll should not have to care.
			var bitten: String = SimMeleeRes._roll_body_part(grab_rng, victim_body, SimCombatRes.HELD_HIT_LOCATION_WEIGHTS)
			w.events.publish({
				"type": "bite.landed",
				"victim": bite_victim,
				"source": int(source3),
				"bodyPart": bitten,
				"damage": bite_damage_for(victim_body, bitten),
			})

		# 4. Begin new holds. Only a Pursuing shambler not already holding someone, not on
		# the post-release cooldown, and whose content entry permits grab at all.
		for source4 in w.components.query(["position", "shambler"]):
			var self_data2: Dictionary = w.components.get_component(int(source4), "shambler") as Dictionary
			if int(self_data2["state"]) != ShamblerState["Pursue"]:
				continue
			if not GRABS_ENABLED:
				continue
			if not bool(self_data2["canGrab"]) or int(self_data2["ticksToGrab"]) > 0:
				continue
			if w.components.has_component(int(source4), "grabState"):
				continue
			var from4: Dictionary = w.components.get_component(int(source4), "position") as Dictionary
			var new_victim: Variant = _contact_target(survivors, from4, GRAB_METRES)
			if new_victim == null:
				continue
			var at4: Dictionary = w.components.get_component(int(new_victim), "position") as Dictionary
			if _clear_contact(w, from4, at4):
				_start_grab(w, int(source4), int(new_victim))
	)

	# F is contextual: it starts a swing while free (melee.gd:138 already refuses one while
	# grabbed) and a committed escape attempt while held. Neither module writes the other's
	# state -- the meaning of F is decided here, in sim, not in presentation.
	world.systems.register("shambler.struggle-intake", "input", 9, func(w: Variant) -> void:
		var has_swing: bool = false
		for c in w.commands.current:
			if String((c as Dictionary).get("type", "")) == "swing":
				has_swing = true
				break
		# Age every hold once, before anything reads the clock, so the three intakes below all
		# see the same tick's number regardless of the order they run in.
		for held_ent in w.components.query(["grabbed"]):
			var timing: Dictionary = w.components.get_component(int(held_ent), "grabbed") as Dictionary
			timing["heldTicks"] = int(timing.get("heldTicks", 0)) + 1

		# Note the early return moved below the NPC loop's concern: a swing command gates the
		# *player's* struggle only. An NPC's is not a key press and must not depend on one.
		# Controlled only, as the oracle scopes it (src/sim/modules/shambler.ts:686). Without
		# this the player's F would arm a struggle on *every* held body in the district and
		# spend each of their stamina -- one key press buying escapes nobody asked for.
		for victim in (w.components.query(["grabbed", "controlled"]) if has_swing else []):
			_arm_struggle(w, int(victim))

		# Instinct: the same escape, taken without being asked for, once a held survivor has
		# spent STRUGGLE_INSTINCT_TICKS with nobody answering for them. Being grabbed is not a
		# state a person waits politely in, and the balance harness proved the cost of pretending
		# otherwise -- an unattended `controlled` survivor recorded 45 bites and 0 struggles in a
		# campaign, because F is a key press and a harness presses nothing.
		#
		# F stays the better answer rather than the only one: a player who reaches for it commits
		# the escape immediately, two seconds before instinct would have, and resets the clock by
		# arming. So this never takes a decision away from someone making one; it only refuses to
		# stand still on behalf of someone who is not.
		for waiting in w.components.query(["grabbed", "controlled"]):
			var patience: Dictionary = w.components.get_component(int(waiting), "grabbed") as Dictionary
			if int(patience.get("heldTicks", 0)) < STRUGGLE_INSTINCT_TICKS:
				continue
			_arm_struggle(w, int(waiting))

		# NPCs struggle on their own, because they have no F to press. Without this a single
		# shambler disables a survivor permanently: melee.gd:138 refuses a held body its swing
		# and npc_combat.gd's threat loop drops it entirely, so a guard taken at its post could
		# neither fight nor leave, for the rest of the run. That is not the grab being dangerous,
		# it is the grab being absorbing, and it is a regression this loop would otherwise have
		# introduced. They pay the same stamina and roll the same contest as the player; what
		# they lack is the choice of when, so they always take it -- with no instinct delay,
		# because there is no key press for them to be waiting on.
		for npc in w.components.query(["grabbed", "identity"]):
			if w.components.has_component(int(npc), "controlled"):
				continue
			_arm_struggle(w, int(npc))
	)

	# Zeroes a grabbed survivor's velocity before movement.integrate (phase "movement" order 0,
	# world.gd) runs, so a hold pins rather than letting the survivor take a step first. Order
	# -1 in the same phase, not "ai": a movement command may still turn the survivor (facing),
	# it just cannot translate them through the bodies holding them.
	world.systems.register("shambler.pin", "movement", -1, func(w: Variant) -> void:
		for victim in w.components.query(["grabbed", "velocity"]):
			var vel: Dictionary = w.components.get_component(int(victim), "velocity") as Dictionary
			vel["dx"] = 0.0
			vel["dy"] = 0.0
		# Break-away runs in the same pass, after the pin, so a survivor re-taken on the very
		# tick they were carrying separation is pinned rather than dragged: being held always
		# wins over getting clear.
		#
		# It overrides an NPC's job velocity on purpose. The first cut only wrote a velocity
		# that was already zero, which read as politeness and meant the feature never fired for
		# a single NPC -- jobs.gd always has them walking somewhere, so the balance harness came
		# back byte-identical. A survivor who has just torn free of a zombie is not resuming
		# their errand for the next second and a bit. The player is the exception: their own
		# move command outranks it, because taking the controls away from someone mid-fight is
		# the one thing worse than being grabbed.
		for freed in w.components.query(["breakAway", "velocity"]):
			var run: Dictionary = w.components.get_component(int(freed), "breakAway") as Dictionary
			run["ticksLeft"] = int(run["ticksLeft"]) - 1
			if int(run["ticksLeft"]) <= 0 or w.components.has_component(int(freed), "grabbed"):
				w.components.remove(int(freed), "breakAway")
				continue
			var vel2: Dictionary = w.components.get_component(int(freed), "velocity") as Dictionary
			var steering: bool = w.components.has_component(int(freed), "controlled") \
				and (float(vel2["dx"]) != 0.0 or float(vel2["dy"]) != 0.0)
			if steering:
				continue
			vel2["dx"] = float(run["dx"])
			vel2["dy"] = float(run["dy"])
	)

	# A grabState pointing at a dead entity, or a grabbed pointing at holders that no longer
	# exist, must not persist -- CLAUDE.md is explicit that entity.killed fires more than once
	# for the same individual (health.gd on a destroyed head, infection.gd on a put-down and
	# again on turning), so both release calls below are written idempotent on purpose: a
	# second firing for the same entity finds nothing left to release and does nothing.
	world.events.subscribe({"id": "shambler.release-dead", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		var dead: int = int(event.get("entity", -1))
		_release_grab(world, dead)
		_release_victim(world, dead)
	})
