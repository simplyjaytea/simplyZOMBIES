extends RefCounted
# What a colonist is doing right now, in words: the Colony screen's "now" line (docs/32's coverage
# row for the roster asks for "truthful current activity"). A read model like `condition.gd` and
# `attention_read.gd`: it reads components and never writes one, so the screen can ask it every
# frame and the sim is no different for having been asked.
#
# Truthful means it says only what the sim is acting on: the job component's `kind`, the need a
# Seek walks for (`SimNeeds.seek_kind`, the same call the job tick makes), the player's order (the
# order component `SimOrders` writes), a grab, a crisis, a sulk. It does not guess at a
# destination, a duration or a count, and it carries no digit, so it obeys the HUD's prose rule.
#
# These are the player's own people. Telling the player that Mara is out scavenging while she is
# out of sight is what a colony manager knows about the people it manages; it reveals nothing about
# where she is, what is near her or what she has found. Two lines would reveal what is near her,
# so neither is said out of sight: a grab reads as "held by the dead", and the walk home a zombie
# within reach starts reads as "heading home" ("staying in" once she is there and waiting it out),
# only while the player can see her. Out of sight the line stays what she was last set to do, which
# is what the colony would believe: the job under the grab, or the errand the walk home broke off
# (the Retreat job's `was`).
#
# Every phrase is MAX_CHARS or shorter, so it fits the Colony row at 1280x720 whole
# (`check_play.gd`'s COLONY lane measures every one of `phrases()` against the drawn room).

const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")

const MAX_CHARS: int = 18

# A job kind as the screen says it. Every kind the job tick writes is here, so a new kind without a
# line is caught by the gate (`check_m2_jobs.gd`'s DOING lane walks this table against the source).
const JOB_WORDS: Dictionary = {
	"Haul": "hauling",
	"Scavenge": "out scavenging",
	"Construct": "building",
	"Cook": "cooking",
	"Doctor": "tending the hurt",
	"Rest": "resting",
	"Patient": "being treated",
	"Guard": "on watch",
	"Water": "fetching water",
	"Clean": "cleaning up",
	"Bury": "burying the dead",
	"Repair": "mending gear",
	"Retreat": "heading home",
	"Rearm": "finding a weapon",
	"Dress": "putting on armour",
}

# What a Seek walks for, by the need `seek_kind` names.
const SEEK_WORDS: Dictionary = {
	"thirst": "getting a drink",
	"hunger": "going to eat",
	"relief": "using the latrine",
	"rest": "going to bed",
	"temperature": "seeking shelter",
	"hygiene": "going to wash",
}

# An order by its kind. Not `SimOrders.hud_clause`: that names the hauled item, and an item's name
# may carry a digit (the cartridge amendment), which this line must not.
const ORDER_WORDS: Dictionary = {
	"go": "going where told",
	"hold": "holding a spot",
	"haul": "hauling, as told",
}

const IDLE: String = "idle"
const HELD: String = "held by the dead"
const PASSED_OUT: String = "passed out"
const LEAVING: String = "leaving the colony"
const ASLEEP: String = "asleep"
const REFUSING: String = "refusing work"
const SEEING_TO: String = "seeing to a need"
const STAYING_IN: String = "staying in"


## Every phrase `doing` can return, for the gate that measures them against the row.
static func phrases() -> Array[String]:
	var out: Array[String] = [IDLE, HELD, PASSED_OUT, LEAVING, ASLEEP, REFUSING, SEEING_TO, STAYING_IN]
	for table in [JOB_WORDS, SEEK_WORDS, ORDER_WORDS]:
		for v in (table as Dictionary).values():
			out.append(String(v))
	return out


## Does the player see `ent` right now: the same `detail` test the player's own sightings use, so a
## colonist behind a wall or behind the player's back is not seen.
static func in_sight(world: Variant, ent: int) -> bool:
	if world.vision == null:
		return false
	var at: Variant = world.components.get_component(ent, "position")
	if not at is Dictionary or int(world.player) < 0:
		return false
	return int(world.vision.call("detail", int(world.player), float((at as Dictionary)["x"]), float((at as Dictionary)["y"]))) != 0


## One short lowercase phrase, or "" for somebody this does not describe (the dead, the player's own
## body, an entity with no needs).
static func doing(world: Variant, ent: int) -> String:
	if world == null or ent < 0 or not world.entities.is_alive(ent):
		return ""
	if world.components.has_component(ent, "corpse"):
		return ""
	if world.components.has_component(ent, "grabbed") and in_sight(world, ent):
		return HELD
	var n: Dictionary = SimNeeds.of(world, ent)
	if String(n.get("crisis", "none")) == "passed_out":
		return PASSED_OUT
	if world.components.has_component(ent, "leaving"):
		return LEAVING
	if world.components.has_component(ent, "sleeping"):
		return ASLEEP
	if int(world.tick) < int(n.get("refusedUntilTick", -1)):
		return REFUSING
	var order: Variant = world.components.get_component(ent, SimJobs.ORDER_COMPONENT)
	if order is Dictionary and ORDER_WORDS.has(String((order as Dictionary).get("kind", ""))):
		return String(ORDER_WORDS[String((order as Dictionary)["kind"])])
	var job: Variant = world.components.get_component(ent, "job")
	if job is Dictionary:
		var kind: String = String((job as Dictionary).get("kind", ""))
		if kind == "Retreat":
			if in_sight(world, ent):
				return STAYING_IN if (job as Dictionary).has("until") else String(JOB_WORDS["Retreat"])
			kind = String((job as Dictionary).get("was", ""))
		if kind == "Seek":
			var need: String = SimNeeds.seek_kind(world, ent)
			return String(SEEK_WORDS.get(need, SEEING_TO))
		if JOB_WORDS.has(kind) and kind != "Retreat":
			return String(JOB_WORDS[kind])
	return IDLE
