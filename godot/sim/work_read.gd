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
# where she is, what is near her or what she has found.

const SimNeeds = preload("res://sim/modules/needs.gd")
const SimJobs = preload("res://sim/modules/jobs.gd")

# A job kind as the screen says it. Every kind the job tick writes is here, so a new kind without a
# line is caught by the gate (`check_m2_jobs.gd`'s DOING lane walks this table against the source).
const JOB_WORDS: Dictionary = {
	"Haul": "hauling",
	"Scavenge": "out scavenging",
	"Construct": "building",
	"Cook": "cooking",
	"Doctor": "tending the hurt",
	"Rest": "resting",
	"Patient": "laid up, being treated",
	"Guard": "on watch at the gate",
	"Water": "fetching water",
	"Clean": "cleaning up",
	"Bury": "burying the dead",
	"Repair": "mending gear",
	"Retreat": "heading home, the dead are close",
	"Rearm": "finding a weapon",
	"Dress": "putting on armour",
}

# What a Seek walks for, by the need `seek_kind` names.
const SEEK_WORDS: Dictionary = {
	"thirst": "going for a drink",
	"hunger": "going to eat",
	"relief": "going to the latrine",
	"rest": "going to bed",
	"temperature": "getting out of the weather",
	"hygiene": "going to wash",
}

# An order by its kind. Not `SimOrders.hud_clause`: that names the hauled item, and an item's name
# may carry a digit (the cartridge amendment), which this line must not.
const ORDER_WORDS: Dictionary = {
	"go": "on the way to the spot you picked",
	"hold": "holding the spot you picked",
	"haul": "hauling to the stockpile, as you asked",
}

const IDLE: String = "idle"


## One short lowercase phrase, or "" for somebody this does not describe (the dead, the player's own
## body, an entity with no needs).
static func doing(world: Variant, ent: int) -> String:
	if world == null or ent < 0 or not world.entities.is_alive(ent):
		return ""
	if world.components.has_component(ent, "corpse"):
		return ""
	if world.components.has_component(ent, "grabbed"):
		return "held by the dead"
	var n: Dictionary = SimNeeds.of(world, ent)
	if String(n.get("crisis", "none")) == "passed_out":
		return "passed out"
	if world.components.has_component(ent, "leaving"):
		return "walking out on the colony"
	if world.components.has_component(ent, "sleeping"):
		return "asleep"
	if int(world.tick) < int(n.get("refusedUntilTick", -1)):
		return "refusing work"
	var order: Variant = world.components.get_component(ent, SimJobs.ORDER_COMPONENT)
	if order is Dictionary and ORDER_WORDS.has(String((order as Dictionary).get("kind", ""))):
		return String(ORDER_WORDS[String((order as Dictionary)["kind"])])
	var job: Variant = world.components.get_component(ent, "job")
	if job is Dictionary:
		var kind: String = String((job as Dictionary).get("kind", ""))
		if kind == "Seek":
			var need: String = SimNeeds.seek_kind(world, ent)
			return String(SEEK_WORDS.get(need, "seeing to a need"))
		if JOB_WORDS.has(kind):
			return String(JOB_WORDS[kind])
	return IDLE
