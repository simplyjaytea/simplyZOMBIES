class_name SimNeeds
extends RefCounted

# Six Needs (0001–0002, 0005–0006, 0008). One file; each Need is its own system id.
# ponytail: drain every tick; swap to 1 s if a 20-survivor bench shows up in the 8 ms tick.

const Clock = preload("res://sim/time/clock.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimInventory = preload("res://sim/modules/inventory.gd")
const SimItems = preload("res://sim/modules/items.gd")
const SimLightMod = preload("res://sim/modules/light.gd")
const SimAttention = preload("res://sim/modules/attention_emitter.gd")
const SimHealth = preload("res://sim/modules/health.gd")
const SimWeather = preload("res://sim/modules/weather.gd")

const HUNGER_EMPTY_DAYS: float = 2.0
const THIRST_EMPTY_DAYS: float = 1.0
const SEEK_START: float = 40.0
const SEEK_STOP: float = 80.0
const SEEK_NEVER_ABOVE: float = 50.0
const SOFT: float = 30.0
const HARD: float = 0.0
const STARVE_DAYS: float = 1.0
const DEHYDRATE_DAYS: float = 0.25
const CAMPFIRE_HEAT_M: float = 4.0
# What counts as body armour when the sun is out: torso coverage at or above this. See
# `wearing_armor`.
const ARMOR_TORSO_HEAT: float = 0.4
const CAMPFIRE_LIGHT_M: float = 20.0
const CAMPFIRE_SCENT: float = 5.0
const CAMPFIRE_COOK_SCENT: float = 15.0
const RAW_SPOIL_DAYS: float = 2.0
const COOKED_SPOIL_DAYS: float = 1.0
const NEED_SOURCES: Array[String] = ["need.hunger", "need.thirst", "need.rest", "need.temperature", "need.hygiene", "need.relief"]

# --- the bathroom need (docs/04) ---------------------------------------------------------------
#
# docs/04's cut list used to read "Latrines exist as a *scent emitter* and a hygiene facility, but
# individual survivors do not track a bladder meter". The owner reversed that; this is the need,
# and the shape is the one the file already uses for a periodic bodily need -- a draining pool with
# `pressure` bands, not a banded state. Hunger, thirst and rest are pools because they empty on a
# clock and are refilled by an act; temperature and hygiene are bands because they are read off the
# world around the body. Relief empties on a clock and is refilled by an act, so it is a pool, and
# being one it inherits the seek ladder, the crossing events and the HUD prose for free.
#
# It is deliberately the *cheapest* need to satisfy and the *fastest* to come back: twice a day at
# rest, faster if you have just eaten and drunk, and answered in one visit to a latrine you already
# own. What it costs is time and position -- it walks people out of the annex, on a clock that
# eating and drinking speed up, which is exactly the pressure docs/04 asks a need to create.
const RELIEF_EMPTY_DAYS: float = 0.5
# A sleeping body is quieter. Half rate rather than none, so a survivor who went to bed on a nearly
# empty pool gets up in the night -- and one who went before bed does not.
const RELIEF_SLEEP_MUL: float = 0.5
# Intake feeds it. A meal and a drink each move the clock forward by a named amount rather than by
# a fraction of what they restore, so rebalancing food does not silently rebalance this.
const RELIEF_PER_MEAL: float = 12.0
const RELIEF_PER_DRINK: float = 18.0

# The one base the Water job refills and the wound ladder cleans with. Drinking itself is no longer
# keyed on this id -- anything with a `drink` block is drinkable (`drink_spec`) -- but the NPC thirst
# job and the wash verb still reach for water by name, and this is the one copy of the name.
const WATER_ID: String = "item.water.bottle"
# What the well fills a bottle with. docs/04: "untreated water carries illness" -- a bottle of it
# drinks like clean water and rolls the food-poisoning bout; boiling at a lit fire makes it WATER_ID.
const UNTREATED_ID: String = "item.water.bottle.untreated"

# --- stimulants (docs/04) ----------------------------------------------------------------------
#
# docs/04: "No caffeine-style hard reset. Stimulants exist as rare loot with a real crash
# afterward." A stimulant is a drink whose `drink` block carries `rest` (the lift, paid into the
# rest pool now) and `crashRest` + `crashAfterTicks` (the same pool debited later). It is a move
# on the pool and not a modifier on a stat, so every reader of rest -- the drain, work_mul, the
# HUD clause, the passed-out crisis -- sees it without a second code path. The debt sits on the
# needs component as `stimulantCrashRest` with its clock `stimulantUntilTick`; a second can inside
# one lift adds to the debt and pushes the clock out, so chaining defers the crash and makes it
# bigger, and a pool that hits the floor when it lands is the ordinary collapse.

# The latrine. Scent 12 is docs/03's emitter table, unchanged -- a latrine was always going to be
# an emitter; what is new is that somebody has a reason to walk to it.
const LATRINE_SCENT: float = 12.0
const LATRINE_REACH: float = 1.5

# Nowhere to go. The consequence is *never* damage: docs/04 has no bodily-harm clause for this, and
# the sim already owns the two prices that fit -- a hygiene band (which carries its own mood and
# doubles scent through `_scent_mul`) and shame. Shame is shaped like grief and arguments, for the
# same reason they are: one modifier from one source, accumulating to a cap and draining away, so a
# bad week is a drag rather than a spiral that empties the colony through LEAVE_AT.
const SOIL_MOOD: float = 12.0
const SOIL_CAP: float = 24.0
# Per mood tick (every 20 ticks). At 0.02 a survivor at the cap is clear after about two in-game
# hours -- the same order as an argument, and deliberately shorter than grief.
const SOIL_DECAY: float = 0.02
const SOIL_SOURCE: String = "mood.soiled"

# --- mood consequences (docs/04) -----------------------------------------------------------
#
# "Low mood does not produce a rage meltdown. It produces: slower work, more mistakes, more
# injuries; refusing assigned jobs; arguments -- which damage other survivors' mood, so misery
# spreads; ... at the extreme: leaving." Only the extreme was wired: mood <= LEAVE_AT publishes
# mood.threshold and recruits.gd walks the survivor out. Everything between "fine" and "gone" did
# nothing at all, which is the opposite of the document's own summary -- "a slow, sour decline
# where the colony stops functioning ... more frightening and more recoverable than a dramatic
# break". A cliff at -80 is a dramatic break.
#
# So there are bands rather than a threshold, and each one adds a consequence to the one below it.
# The numbers sit between the existing mood sources (a filthy survivor is already -20, three needs
# below SOFT another -30) and LEAVE_AT, so the bands are reachable by ordinary neglect rather than
# only by contrivance.
const MOOD_LOW: float = -20.0
const MOOD_MISERABLE: float = -50.0
const LEAVE_AT: float = -80.0

# What each band is called. Ordered worst-first, and the strings are the vocabulary every
# consequence and every gate uses -- jobs.gd matches on these rather than re-deriving thresholds,
# so a band boundary moves in one place.
const MOOD_BANDS: Array[String] = ["breaking", "miserable", "low", "content"]

# Arguments. A miserable survivor within ARGUMENT_METRES of another takes it out on them every
# ARGUMENT_TICKS, and the damage accumulates on the *victim* toward a cap.
#
# The cap is the whole design of this: an unbounded source would let two miserable survivors drive
# each other past LEAVE_AT in a few minutes and empty the colony, which is the "rage meltdown"
# docs/04 explicitly rules out. Capped and decaying, arguments are a drag that makes a bad mood
# spread and stick without becoming a spiral that cannot be pulled out of -- feed and rest people
# and it drains away.
const ARGUMENT_METRES: float = 4.0
const ARGUMENT_TICKS: int = 600
const ARGUMENT_PER: float = 6.0
const ARGUMENT_CAP: float = 24.0
# Recovered per mood tick (every 20 ticks) once nobody is arguing at you. At 0.05 a survivor at the
# cap is clear in about two in-game hours of peace.
const ARGUMENT_DECAY: float = 0.05
const ARGUMENT_SOURCE: String = "mood.argument"

# Grief. docs/04 lists "grief" and "witnessing a death" as two of the negative mood sources, and
# docs/23's death-and-succession item asks for "the colony morale hit on a death". This is that,
# and deliberately not the relationship system: docs/07 scales grief by closeness through pairwise
# opinions, which are Milestone 3A. What is here is the part that does not need them -- somebody
# the colony lived with is dead, and everybody feels it, more if they watched it happen.
#
# **Witnessing is a real distinction now and could not have been made before this milestone.**
# Until every survivor got eyes, `world.vision` answered for the player alone, so "did anybody see
# this" had no answer for a colonist. It does now, through the same `line_of_sight` a shot is
# refused by.
#
# The cap is the argument cap's argument, for the same reason: three deaths in a bad night must
# not empty the colony through LEAVE_AT in one stroke. Grief is heavy, it stacks, and it stops.
const GRIEF_WITNESSED: float = 18.0
const GRIEF_HEARD: float = 7.0
# docs/06's response #5 -- putting somebody down yourself -- is supposed to have a price, and
# docs/07 says relationships are "what gives response #5 its price". Without relationships this is
# the part of that price that can be paid: it is worse for everyone when the colony did it.
const GRIEF_PUT_DOWN_MUL: float = 1.6
# docs/07's Optimist: "slower mood decay, less grief transmission".
const GRIEF_OPTIMIST_MUL: float = 0.5
const GRIEF_CAP: float = 40.0
# Per mood tick (every 20 ticks). At 0.005 a survivor at the cap is clear after about thirteen
# in-game hours -- grief lasts most of a day and then it does not.
const GRIEF_DECAY: float = 0.005
const GRIEF_SOURCE: String = "mood.grief"

# --- sleep quality (docs/04, docs/05) -----------------------------------------------------------
#
# docs/04's Rest clause: "recovery quality depends on bed quality, warmth, darkness, quiet, and
# safety." docs/05 lists sleep last among what pain degrades: "accuracy, work speed, mood, sleep
# quality" -- which is why this was blocked on itself (docs/23): there was no sleep-quality value
# for pain to degrade. Of that factor list, what the sim already tracks a state for is a bed, a
# temperature band, felt pain and the noise field; darkness and safety are not modelled by
# anything today, and adding a stat nothing else reads is the exact dead-socket failure this
# milestone keeps finding, so they are not faked here -- this ships the tractable half.
#
# Derived every sleeping tick, never stored as truth -- the same discipline `SimWounds.pain_of`
# already keeps: a cached number is one more thing that can disagree with the state it summarises.
const SLEEP_FULL_NIGHT: float = 100.0
const SLEEP_QUALITY_FLOOR: float = 0.2
const SLEEP_PENALTY_ROUGH: float = 0.5
const SLEEP_PENALTY_TEMP_SEEK: float = 0.05
const SLEEP_PENALTY_TEMP_SOFT: float = 0.25
# `extremely_cold` must cost at least as much as `very_cold` -- it is the harder band -- so this is
# a strictly larger number rather than one a future rebalance could let tie or slip under it.
const SLEEP_PENALTY_TEMP_HARD: float = 0.45
# Below this, felt pain (post-suppression) is a rounding error rather than a bad night -- the gap
# that lets painkillers buy a genuinely undisturbed sleep rather than a merely-less-bad one.
const SLEEP_PAIN_FLOOR: float = 0.05
const SLEEP_PENALTY_PAIN: float = 0.4
const SLEEP_PENALTY_NOISE: float = 0.2
# A multiplier on the penalties a bad night already has, not on the total -- a light sleeper in a
# quiet room sleeps exactly as well as anybody else; the trait is what makes a disturbance cost
# more, not a tax on a night that never disturbed them.
const SLEEP_LIGHT_SLEEPER_MUL: float = 1.5
const SLEEP_WORD_GOOD: float = 0.7
# What a bad night costs in mood, and how it stops costing it -- `_apply_grief`'s shape exactly:
# one modifier from one source, replaced rather than stacked, capped, and drained on the mood tick.
const SLEEP_MOOD: float = 16.0
const SLEEP_MOOD_CAP: float = 16.0
const SLEEP_DECAY: float = 0.05
# Deliberately not in NEED_SOURCES: `_apply_muls` strips every NEED_SOURCES entry on every pool
# crossing, and a bad night's cost must outlive the crossing that did not cause it -- the same
# reason SOIL_SOURCE sits outside that list (see the comment at `_apply_soiled`).
const SLEEP_SOURCE: String = "mood.sleep"

# The needs that are pools rather than bands. One list, because "below SOFT costs work and mood"
# was written out twice as a literal array and a fourth pool would have joined one of them and
# quietly missed the other -- the same shape as the seven copies of the job countdown.
const POOLS: Array[String] = ["hunger", "thirst", "rest", "relief"]

const TEMP_ORDER: Array[String] = [
	"extremely_cold", "very_cold", "a_little_cold", "comfortable", "a_little_hot", "very_hot", "extremely_hot",
]
const HYG_ORDER: Array[String] = ["clean", "a_little_dirty", "dirty", "filthy"]
# --- food is content (docs/12) ----------------------------------------------------------------
#
# docs/12's content-shape section: "Resources, location loot tables, and spoilage rules are JSON."
# The loot tables moved out a slice ago; this is the spoilage half. What a food restores, what it
# does to mood, how long it keeps and how likely it is to make you ill are a `food` block on the
# item base now, so rebalancing the diet -- or adding a food -- is a data edit.
#
# The table below is gone, not merely bypassed. It read:
#
#   item.food.canned  {hunger: 40, mood:  0, spoilDays: 0}
#   item.food.raw     {hunger: 25, mood: -8, spoilDays: 2}
#   item.food.cooked  {hunger: 60, mood:  8, spoilDays: 1}
#
# and those numbers are now in content/items/supplies.json unchanged, so this slice moves where
# they live without moving what they say.

# What a food does, read from content. Returns null for anything that is not food, which is how
# every caller here asks "is this edible" as well as "what does it do".
static func food_spec(world: Variant, base_id: String) -> Variant:
	var base: Variant = SimItems.content_entry(world, "item", base_id)
	if not (base is Dictionary):
		return null
	var spec: Variant = (base as Dictionary).get("food")
	return spec if spec is Dictionary else null


static func is_food(world: Variant, base_id: String) -> bool:
	return food_spec(world, base_id) != null


# The `drink` block, judged whole, or null. Presence is what makes an item a drink -- the `food`
# rule -- but a block with a `rest` lift and no crash behind it is refused outright rather than
# drunk for free: the content validator does not recurse, and a free stimulant is exactly the
# wrong number nothing would report. Same reason SimVehicles.drive_of answers {} for a half block.
static func drink_spec(world: Variant, base_id: String) -> Variant:
	var base: Variant = SimItems.content_entry(world, "item", base_id)
	if not (base is Dictionary):
		return null
	var spec: Variant = (base as Dictionary).get("drink")
	if not (spec is Dictionary):
		return null
	var d: Dictionary = spec as Dictionary
	var thirst: Variant = d.get("thirst")
	if not (thirst is float or thirst is int) or float(thirst) < 0.0:
		return null
	var lift: Variant = d.get("rest", 0.0)
	if not (lift is float or lift is int) or float(lift) < 0.0:
		return null
	if float(lift) > 0.0:
		var crash: Variant = d.get("crashRest")
		var after: Variant = d.get("crashAfterTicks")
		if not (crash is float or crash is int) or float(crash) <= 0.0:
			return null
		if not (after is int or after is float) or int(after) <= 0:
			return null
	# An illness chance outside the unit interval is a typo the shallow validator cannot see; refuse
	# the block rather than clamp it, so the wrong number is reported by an undrinkable bottle.
	if d.has("illnessChance"):
		var ill: Variant = d.get("illnessChance")
		if not (ill is float or ill is int) or float(ill) < 0.0 or float(ill) > 1.0:
			return null
	return d


static func is_drink(world: Variant, base_id: String) -> bool:
	return drink_spec(world, base_id) != null


# --- foodborne illness (docs/04) --------------------------------------------------------------
#
# docs/04: "Quality matters, not just quantity: raw and spoiled food fills the bar but damages mood
# and carries illness risk". The mood half shipped; the illness half did not, so raw food was a
# mood tax and nothing else and there was never a reason to cook anything you were not enjoying.
#
# Kept deliberately distinct from both zombie infection and sepsis, per docs/23's own line that
# bacterial infection stays separate from zombie infection. This is neither: it is a bounded,
# self-limiting bout of food poisoning that costs mood and work and then passes. Nobody dies of it
# in Milestone 2, which is why it lives here in needs.gd rather than growing a module.
const ILLNESS_TICKS: int = 3600
const ILLNESS_MOOD: float = -14.0
const ILLNESS_WORK_MUL: float = 0.6
const ILLNESS_SOURCE: String = "need.illness"
const ILLNESS_STREAM: String = "illness"

# What a completely empty stamina pool costs work speed. docs/04 lists work speed among the four
# things exhaustion degrades; melee.gd's _apply_exhaustion owns the other three, which are
# modifiers. This one is not, so it lives with work_mul.
const EXHAUSTION_WORK_PENALTY: float = 0.35

# What eating something that has gone off does to mood, regardless of what the base declares --
# spoiled is spoiled. Lifted out of the eat path as a constant so the one magic number in this
# area has a name.
const SPOILED_MOOD: float = -16.0

# Spoiled food is worse than merely raw, whatever the base declares. A multiplier rather than a
# second authored number, so a content edit to illnessChance moves both together.
const SPOILED_ILLNESS_MUL: float = 2.5

# --- a meal's mood is a mood, not a trait -----------------------------------------------------
#
# Every other mood source in this file pairs its `add` with a `remove_by_source` -- shame, grief,
# arguments, illness -- and eating did not. `eat` added a modifier with the fixed source
# `need.food` and nothing ever took one away, so thirty meals over a ten-day campaign were thirty
# entries, all summing: a colony that ate cooked food was permanently and unboundedly cheerful,
# and one that lived on spoiled tins was permanently miserable, for reasons no clock could undo.
#
# So it is bounded twice, in the shape `_fall_ill` already uses: one modifier from one source,
# replaced rather than stacked, and expiring on a clock of its own. A good meal is worth three
# in-game hours of goodwill (36000 ticks at 12000 to the in-game hour) and after that it is a
# memory -- comfortably shorter than the gap between meals, so two meals can never be carried at
# once even before the replacement above rules it out.
const MEAL_MOOD_SOURCE: String = "need.food"
const MEAL_MOOD_TICKS: int = 36000


# Whether this meal makes them ill. `iron_stomach` is immunity here rather than a reduction: the
# trait already zeroes the mood penalty, and a trait that half-protects from two things is harder
# to reason about than one that fully protects from both.
static func _rolls_ill(world: Variant, entity: int, spec: Dictionary, spoiled: bool) -> bool:
	if has_trait(world, entity, "iron_stomach"):
		return false
	var chance: float = float(spec.get("illnessChance", 0.0))
	if spoiled:
		chance *= SPOILED_ILLNESS_MUL
	if chance <= 0.0:
		return false
	return float(world.rng.stream(ILLNESS_STREAM).call("float_range", 0.0, 1.0)) < clampf(chance, 0.0, 1.0)


# A bout of food poisoning: bounded, self-limiting, and refreshed rather than stacked by a second
# bad meal. Nobody dies of it in Milestone 2 -- it costs mood and work and then passes, which is
# what makes cooking worth the fuel without making one bad tin a death sentence.
static func _fall_ill(world: Variant, entity: int) -> void:
	var n: Dictionary = of(world, entity)
	n["illUntilTick"] = int(world.tick) + ILLNESS_TICKS
	if world.modifiers != null:
		world.modifiers.call("remove_by_source", ILLNESS_SOURCE, entity)
		world.modifiers.call("add", {"stat": "mood", "op": "add", "value": ILLNESS_MOOD, "source": ILLNESS_SOURCE}, entity)
	world.events.publish({"type": "illness.contracted", "entity": entity, "ticks": ILLNESS_TICKS})


static func is_ill(world: Variant, entity: int) -> bool:
	return int(world.tick) < int(of(world, entity).get("illUntilTick", -1))


# The lift (or the sting) a meal leaves behind. Removed before it is added, so a second meal
# replaces the first rather than joining it, and stamped with the tick it runs out on -- an int on
# the needs component, which is what survives a save. Zero means the meal said nothing about mood,
# and that clears the clock rather than leaving one running over nothing.
static func _apply_meal_mood(world: Variant, entity: int, mood: float) -> void:
	if world.modifiers == null:
		return
	var n: Dictionary = of(world, entity)
	world.modifiers.call("remove_by_source", MEAL_MOOD_SOURCE, entity)
	if mood == 0.0:
		n["mealMoodUntilTick"] = -1
		return
	n["mealMoodUntilTick"] = int(world.tick) + MEAL_MOOD_TICKS
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": mood, "source": MEAL_MOOD_SOURCE}, entity)


# And it wears off. The illness clock's shape exactly: one comparison per survivor, and the
# modifier goes when the clock does, so nothing is left behind for the next meal to sum with.
static func _tick_meal_mood(world: Variant) -> void:
	if world.modifiers == null:
		return
	for ent in _survivors(world):
		var n: Dictionary = of(world, int(ent))
		var until: int = int(n.get("mealMoodUntilTick", -1))
		if until < 0 or int(world.tick) < until:
			continue
		n["mealMoodUntilTick"] = -1
		world.modifiers.call("remove_by_source", MEAL_MOOD_SOURCE, int(ent))
		world.events.publish({"type": "mood.mealFaded", "entity": int(ent)})


# Clears the modifier once the bout has run its course. Driven from the mood tick rather than its
# own system: it is one comparison per survivor and does not need a phase slot of its own.
static func _tick_illness(world: Variant) -> void:
	if world.modifiers == null:
		return
	for ent in _survivors(world):
		var n: Dictionary = of(world, int(ent))
		var until: int = int(n.get("illUntilTick", -1))
		if until < 0 or int(world.tick) < until:
			continue
		n["illUntilTick"] = -1
		world.modifiers.call("remove_by_source", ILLNESS_SOURCE, int(ent))
		world.events.publish({"type": "illness.passed", "entity": int(ent)})


static func blank() -> Dictionary:
	return {
		"hunger": 100.0,
		"thirst": 100.0,
		"rest": 100.0,
		"relief": 100.0,
		"temperature": "comfortable",
		"hygiene": "clean",
		"crisis": "none",
		"starvingSinceTick": -1,
		"dehydratingSinceTick": -1,
		# Wet until this tick, or -1: set by rain on an unroofed body, brought forward by a lit fire.
		"wetUntilTick": -1,
		"slept": "up",
		"wakeJob": "",
		"dirtyWake": false,
		"mealMoodUntilTick": -1,
		"coldSinceTick": -1,
		"hotSinceTick": -1,
		"sleepQuality": 1.0,
		"sleepQualityTicks": 0,
		"sleptMood": 0.0,
		"stimulantUntilTick": -1,
		"stimulantCrashRest": 0.0,
	}


static func attach(world: Variant, entity: int, pools: Dictionary = {}) -> void:
	var n: Dictionary = blank()
	for k in pools.keys():
		n[k] = pools[k]
	world.components.set_component(entity, "needs", n)


static func of(world: Variant, entity: int) -> Dictionary:
	var raw: Variant = world.components.get_component(entity, "needs")
	return raw as Dictionary if raw is Dictionary else blank()


static func hold_max(world: Variant) -> bool:
	return bool(world.needsHoldMax) if world != null and "needsHoldMax" in world else false


static func drain_hunger() -> float:
	return 100.0 / (HUNGER_EMPTY_DAYS * float(Clock.DAY_TICKS))


static func drain_thirst() -> float:
	return 100.0 / (THIRST_EMPTY_DAYS * float(Clock.DAY_TICKS))


static func drain_rest() -> float:
	# Wake = dawn+day+dusk = 0.75 of a day.
	return 100.0 / (0.75 * float(Clock.DAY_TICKS))


static func drain_relief() -> float:
	return 100.0 / (RELIEF_EMPTY_DAYS * float(Clock.DAY_TICKS))


static func pressure(pool: float) -> String:
	if pool <= HARD:
		return "hard"
	if pool < SOFT:
		return "soft"
	if pool <= SEEK_START:
		return "seek"
	return "ok"


static func band_pressure(kind: String, band: String) -> String:
	if kind == "temperature":
		if band == "extremely_cold" or band == "extremely_hot":
			return "hard"
		if band == "very_cold" or band == "very_hot":
			return "soft"
		if band.begins_with("a_little_"):
			return "seek"
		return "ok"
	if band == "filthy":
		return "hard"
	if band == "dirty":
		return "soft"
	if band == "a_little_dirty":
		return "seek"
	return "ok"


static func sepsis_mul(band: String) -> float:
	match band:
		"a_little_dirty":
			return 1.25
		"dirty":
			return 1.75
		"filthy":
			return 2.5
		_:
			return 1.0


static func work_mul(world: Variant, entity: int) -> float:
	var n: Dictionary = of(world, entity)
	if String(n.get("crisis", "none")) != "none":
		return 0.0
	var m: float = 1.0
	for k in POOLS:
		if float(n.get(k, 100.0)) < SOFT:
			m = minf(m, 0.85)
	var t: String = String(n.get("temperature", "comfortable"))
	var h: String = String(n.get("hygiene", "clean"))
	# Read through band_pressure rather than by naming the bands, so the deep band -- which is
	# worse than `very_cold` and used to be unreachable -- cannot be the one case a list forgets.
	var tp: String = band_pressure("temperature", t)
	if tp == "soft" or tp == "hard" or h == "dirty" or h == "filthy":
		m = minf(m, 0.85)
	# Food poisoning is the one need-adjacent state that is worse than being merely uncomfortable,
	# so it multiplies rather than joining the 0.85 floor the others share.
	if is_ill(world, entity):
		m *= ILLNESS_WORK_MUL
	var Wounds: GDScript = load("res://sim/modules/wounds.gd") as GDScript
	if Wounds != null and bool(Wounds.call("is_septic", world, entity)):
		m *= float(Wounds.get("SEPSIS_WORK_MUL"))
	# docs/05: pain "degrades everything -- accuracy, work speed, mood". Accuracy and mood are
	# modifiers and live in wounds.gd; work speed is this multiplier, which is not a modifier, so
	# it is applied here. Scaled by the pain actually felt, so a dose of painkillers speeds
	# somebody up without healing them -- which is the tactical option, and the trap.
	if Wounds != null:
		var pain: float = float(Wounds.call("pain_of", world, entity))
		if pain > 0.0:
			m *= 1.0 - float(Wounds.get("PAIN_WORK_PENALTY")) * pain
	# docs/04 lists work speed among what exhaustion degrades. Read off stamina directly rather
	# than through a modifier, because this multiplier is not one.
	var stamina: Variant = world.components.get_component(entity, "stamina")
	if stamina is Dictionary:
		var maxv: float = maxf(1.0, float((stamina as Dictionary).get("max", 100)))
		var emptiness: float = clampf(1.0 - float((stamina as Dictionary).get("current", maxv)) / maxv, 0.0, 1.0)
		m *= 1.0 - EXHAUSTION_WORK_PENALTY * emptiness
	return maxf(0.0, m)


static func accuracy_mul(world: Variant, entity: int) -> float:
	return work_mul(world, entity) if work_mul(world, entity) > 0.0 else 0.85


static func has_trait(world: Variant, entity: int, trait_id: String) -> bool:
	var ident: Variant = world.components.get_component(entity, "identity")
	if not ident is Dictionary:
		return false
	var traits: Variant = (ident as Dictionary).get("traits", [])
	return traits is Array and (traits as Array).has(trait_id)


static func wearing_wrap(world: Variant, entity: int) -> bool:
	for item in SimInventory.equipped_items(world, entity):
		var base: Variant = world.components.get_component(item, "itemBase")
		if base is Dictionary and String((base as Dictionary).get("baseId", "")) == "item.wrap.cloth":
			return true
	return false


# Body armour, for the heat wave: anything equipped whose base armours the torso at
# ARMOR_TORSO_HEAT or better. Read off the coverage rather than off the equip slot, because the
# slot answers the wrong question twice -- `item.vest.scrap` armours the torso 0.6 from the
# `vest` slot, and `item.wrap.cloth` sits in the `torso` slot armouring it 0.3, which is a
# garment, not a plate. As shipped this is the leather jacket (0.5) and the scrap vest (0.6);
# the wrap is out, and stays what it has always been -- a band of warmth, in the sun as at
# night. Its own accessor rather than SimInfection.armor_coverage_of, which resolves affixes and
# condition per body part and is a per-tick cost this does not need.
static func wearing_armor(world: Variant, entity: int) -> bool:
	for item in SimInventory.equipped_items(world, entity):
		var base: Variant = SimItems.item_base_of(world, item)
		if not base is Dictionary:
			continue
		var a: Variant = (base as Dictionary).get("armor")
		if a is Dictionary and float((a as Dictionary).get("torso", 0.0)) >= ARMOR_TORSO_HEAT:
			return true
	return false


static func register_module(world: Variant) -> void:
	if not "needsHoldMax" in world:
		world.needsHoldMax = false
	world.systems.register("need.hunger", "needs", 10, func(w: Variant) -> void:
		_tick_pools(w, "hunger", drain_hunger(), "starving", STARVE_DAYS)
	)
	world.systems.register("need.thirst", "needs", 11, func(w: Variant) -> void:
		# The sky is read inside the lambda, not at registration: the kind flips mid-run, and a
		# rate frozen at boot would be a socket nothing ever reaches (docs/adr/0016).
		_tick_pools(w, "thirst", drain_thirst() * SimWeather.thirst_mul(w), "dehydrating", DEHYDRATE_DAYS)
	)
	world.systems.register("need.rest", "needs", 12, func(w: Variant) -> void:
		_tick_rest(w)
	)
	world.systems.register("need.stimulant", "needs", 11, func(w: Variant) -> void:
		_tick_stimulant(w)
	)
	world.systems.register("need.relief", "needs", 12, func(w: Variant) -> void:
		_tick_relief(w)
	)
	world.systems.register("need.illness", "needs", 11, func(w: Variant) -> void:
		_tick_illness(w)
	)
	world.systems.register("need.mealMood", "needs", 11, func(w: Variant) -> void:
		_tick_meal_mood(w)
	)
	world.systems.register("need.arguments", "needs", 12, func(w: Variant) -> void:
		_tick_arguments(w)
	)
	world.systems.register("need.grief", "needs", 12, func(w: Variant) -> void:
		_tick_grief(w)
	)
	world.systems.register("need.sleptMood", "needs", 12, func(w: Variant) -> void:
		_tick_slept_mood(w)
	)

	# Marked on the body rather than remembered in a module-level set: a static would be shared
	# between the two worlds a gate boots, and it would not survive a save. `putDown` is read by
	# the grief handler below and by nothing else.
	world.events.subscribe({"id": "needs.mark-put-down", "type": "survivor.putDown", "handler": func(event: Dictionary) -> void:
		# Handlers run at drain, by which point the put-down has already been reaped, and a
		# reap that ended in a despawn leaves nothing to mark. `set_component` on a dead id
		# would happily create a component nothing can ever reach or remove -- `components`
		# is keyed by id and does not consult `entities` -- so it would sit in every save
		# from then on. SimInfection.put_down sets the marker before it reaps for exactly
		# this reason; this stays the marker for a put-down published by anything else.
		if not bool(world.entities.call("is_alive", int(event["entity"]))):
			return
		world.components.set_component(int(event["entity"]), "putDown", {})
	})
	world.events.subscribe({"id": "needs.grieve", "type": "entity.killed", "handler": func(event: Dictionary) -> void:
		_grieve_for(world, event)
	})
	world.systems.register("need.mood", "needs", 13, func(w: Variant) -> void:
		_tick_mood(w)
	)
	world.systems.register("need.temperature", "needs", 14, func(w: Variant) -> void:
		_tick_temperature(w)
	)
	world.systems.register("need.hygiene", "needs", 15, func(w: Variant) -> void:
		_tick_hygiene(w)
	)
	world.systems.register("need.spoilage", "needs", 16, func(w: Variant) -> void:
		_tick_spoilage(w)
	)
	world.systems.register("need.intake", "input", 12, func(w: Variant) -> void:
		for cmd in w.commands.current as Array:
			var c: Dictionary = cmd as Dictionary
			var kind: String = String(c.get("type", ""))
			if kind == "item.use" or kind == "item.wash":
				for actor in w.components.query(["controlled", "needs"]):
					use_item(w, int(actor), int(c.get("item", -1)), kind == "item.wash" or bool(c.get("wash", false)))
	)
	world.events.subscribe({"id": "need.wake-alarm", "type": "alarm.tripped", "handler": func(_e: Dictionary) -> void:
		_wake_all(world)
	})
	world.events.subscribe({"id": "need.wake-grab", "type": "grab.started", "handler": func(e: Dictionary) -> void:
		_wake(world, int(e.get("victim", -1)))
	})
	world.events.subscribe({"id": "need.wake-hit", "type": "attack.connected", "handler": func(e: Dictionary) -> void:
		_wake(world, int(e.get("target", -1)))
	})


static func _survivors(world: Variant) -> Array[int]:
	return world.components.query(["needs"])


static func _tick_pools(world: Variant, key: String, rate: float, crisis: String, death_days: float) -> void:
	var hold: bool = hold_max(world)
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			_hold_one(world, ent, n)
			continue
		if world.components.has_component(ent, "sleeping") and key != "hunger" and key != "thirst":
			continue
		var before: float = float(n.get(key, 100.0))
		var after: float = maxf(0.0, before - rate)
		n[key] = after
		_cross(world, ent, n, key, before, after)
		if after <= HARD:
			if String(n.get("crisis", "none")) == "none" or String(n.get("crisis", "none")) == "passed_out":
				n["crisis"] = crisis
				var since_key: String = "starvingSinceTick" if crisis == "starving" else "dehydratingSinceTick"
				if int(n.get(since_key, -1)) < 0:
					n[since_key] = int(world.tick)
			var since: int = int(n.get("starvingSinceTick" if crisis == "starving" else "dehydratingSinceTick", -1))
			if since >= 0 and int(world.tick) - since >= int(death_days * float(Clock.DAY_TICKS)):
				world.events.publish({"type": "entity.killed", "entity": ent, "need": key})
				var Health: GDScript = load("res://sim/modules/health.gd") as GDScript
				Health.call("finish_death", world, ent)
		else:
			if String(n.get("crisis", "")) == crisis:
				n["crisis"] = "none"
				n["starvingSinceTick" if crisis == "starving" else "dehydratingSinceTick"] = -1


# The bathroom need's clock. No crisis and no death path: an empty pool is an accident, not a
# corpse, so this does not go near `_tick_pools`'s starve/dehydrate machinery.
static func _tick_relief(world: Variant) -> void:
	var hold: bool = hold_max(world)
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			n["relief"] = 100.0
			n["soiled"] = 0.0
			_apply_soiled(world, ent, 0.0)
			continue
		var rate: float = drain_relief()
		if world.components.has_component(ent, "sleeping"):
			rate *= RELIEF_SLEEP_MUL
		var before: float = float(n.get("relief", 100.0))
		var after: float = maxf(0.0, before - rate)
		n["relief"] = after
		_cross(world, ent, n, "relief", before, after)
		if after <= HARD:
			_soil(world, ent, n)
	# Shame drains on the same cadence every other mood source does, and for everybody, so a
	# survivor recovers on the tick the accounting happens rather than a cycle later.
	if int(world.tick) % 20 == 0:
		for ent2 in _survivors(world):
			_decay_soiled(world, int(ent2))


# Nowhere to go, and no longer able to wait. The pool resets because the body has been relieved --
# what is left behind is a hygiene band and the shame of it.
static func _soil(world: Variant, ent: int, n: Dictionary) -> void:
	n["relief"] = 100.0
	n["soiled"] = minf(SOIL_CAP, float(n.get("soiled", 0.0)) + SOIL_MOOD)
	_apply_soiled(world, ent, float(n["soiled"]))
	# After the modifier, because `_dirt` re-runs `_apply_muls`, and this way one accident leaves
	# the body in one consistent state rather than two half-applied ones.
	_dirt(world, ent, 1)
	world.events.publish({"type": "need.soiled", "entity": ent})


static func soiled_of(world: Variant, entity: int) -> float:
	return float(of(world, entity).get("soiled", 0.0))


static func _decay_soiled(world: Variant, ent: int) -> void:
	var n: Dictionary = of(world, ent)
	var carried: float = float(n.get("soiled", 0.0))
	if carried <= 0.0:
		return
	n["soiled"] = maxf(0.0, carried - SOIL_DECAY)
	_apply_soiled(world, ent, float(n["soiled"]))


# One modifier from one source, replaced rather than stacked -- the argument and grief rule, and
# for the same reason: a second modifier per accident would accumulate behind the cap this thinks
# it is enforcing. Its source is deliberately *not* in NEED_SOURCES, because `_apply_muls` strips
# those every time a pool crosses a mark and shame must outlive the accident that caused it.
static func _apply_soiled(world: Variant, ent: int, amount: float) -> void:
	if world.modifiers == null:
		return
	world.modifiers.call("remove_by_source", SOIL_SOURCE, ent)
	if amount <= 0.0:
		return
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": -amount, "source": SOIL_SOURCE}, ent)


# The relief verb, place-bound. Refuses when the latrine is missing, is not a latrine, or is out of
# reach -- there is no relieving yourself at a distance, and no relieving yourself into thin air.
static func relieve_at(world: Variant, entity: int, latrine: int) -> bool:
	if latrine < 0 or not world.components.has_component(latrine, "latrine"):
		return false
	var here: Variant = world.components.get_component(entity, "position")
	var there: Variant = world.components.get_component(latrine, "position")
	if not (here is Dictionary) or not (there is Dictionary):
		return false
	var dx: float = float((there as Dictionary)["x"]) - float((here as Dictionary)["x"])
	var dy: float = float((there as Dictionary)["y"]) - float((here as Dictionary)["y"])
	if dx * dx + dy * dy > LATRINE_REACH * LATRINE_REACH:
		return false
	var n: Dictionary = of(world, entity)
	n["relief"] = 100.0
	_apply_muls(world, entity, n)
	world.events.publish({"type": "need.relieved", "entity": entity, "latrine": latrine})
	return true


# The same verb without a named target: the nearest latrine, if one is close enough. Returns false
# for a colony that has not built one, which is what makes the accident above reachable.
static func relieve(world: Variant, entity: int) -> bool:
	var here: Variant = world.components.get_component(entity, "position")
	if not (here is Dictionary):
		return false
	var latrine: int = nearest_latrine(world, float((here as Dictionary)["x"]), float((here as Dictionary)["y"]))
	return relieve_at(world, entity, latrine)


# Intake feeds the clock: what goes in comes out. Kept in one place so eat and drink cannot drift
# apart, and clamped at zero rather than allowed to trigger an accident on the spot -- a meal
# should hurry you along, not humiliate you mid-bite.
static func _intake(world: Variant, entity: int, amount: float) -> void:
	var n: Dictionary = of(world, entity)
	n["relief"] = maxf(0.0, float(n.get("relief", 100.0)) - amount)
	if float(n["relief"]) <= HARD:
		n["relief"] = 0.01
	_apply_muls(world, entity, n)


static func _tick_rest(world: Variant) -> void:
	var hold: bool = hold_max(world)
	var phase: int = Clock.phase_of(int(world.tick))
	var prev: int = Clock.phase_of(int(world.tick) - 1)
	var dawn: bool = phase == Clock.Phase.Dawn and prev != Clock.Phase.Dawn
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			_hold_one(world, ent, n)
			continue
		var sleeping: bool = world.components.has_component(ent, "sleeping")
		if sleeping:
			_refill_sleep(world, ent, n)
		elif phase != Clock.Phase.Night:
			var before: float = float(n.get("rest", 100.0))
			var after: float = maxf(0.0, before - drain_rest())
			n["rest"] = after
			_cross(world, ent, n, "rest", before, after)
			if after <= HARD:
				n["crisis"] = "passed_out"
				_start_sleep(world, ent, -1)
		if dawn:
			n["wakeJob"] = ""
			n["dirtyWake"] = false
		if String(n.get("crisis", "")) == "passed_out" and float(n.get("rest", 0.0)) >= 20.0:
			n["crisis"] = "none"
			_wake(world, ent)


# The stimulant clock: one comparison per survivor, the illness clock's shape. The crash lands
# whatever phase it is -- rest does not drain at night, but a debt is not a drain.
static func _tick_stimulant(world: Variant) -> void:
	if hold_max(world):
		return
	for ent in _survivors(world):
		var n: Dictionary = of(world, int(ent))
		var until: int = int(n.get("stimulantUntilTick", -1))
		if until < 0 or int(world.tick) < until:
			continue
		_land_crash(world, int(ent), n)


static func _land_crash(world: Variant, ent: int, n: Dictionary) -> void:
	var debt: float = float(n.get("stimulantCrashRest", 0.0))
	n["stimulantCrashRest"] = 0.0
	n["stimulantUntilTick"] = -1
	var before: float = float(n.get("rest", 100.0))
	var after: float = maxf(0.0, before - debt)
	n["rest"] = after
	_cross(world, ent, n, "rest", before, after)
	# _tick_rest's own collapse, verbatim, guarded against a body already in a bed: _start_sleep
	# on a sleeper would overwrite `sleeping.bed` and leave the bed's `occupiedBy` set.
	if after <= HARD and not world.components.has_component(ent, "sleeping"):
		n["crisis"] = "passed_out"
		_start_sleep(world, ent, -1)
	world.events.publish({"type": "need.crashed", "entity": ent, "rest": debt})


static func _refill_sleep(world: Variant, ent: int, n: Dictionary) -> void:
	# A full night in bed at perfect quality is still 100, spread across night ticks -- the
	# calibration constraint sleep_quality's docstring names: an ordinary good night is unchanged.
	var quality: float = sleep_quality(world, ent)
	var night_ticks: float = 0.25 * float(Clock.DAY_TICKS)
	var full: float = SLEEP_FULL_NIGHT * quality
	n["rest"] = minf(100.0, float(n.get("rest", 0.0)) + full / night_ticks)
	# The running mean of tonight's quality so far, reset at `_start_sleep` and read at `_wake` --
	# so the mood charge reflects the whole night rather than whatever tick happened to catch it.
	var ticks: int = int(n.get("sleepQualityTicks", 0))
	var mean: float = float(n.get("sleepQuality", 1.0))
	n["sleepQuality"] = (mean * float(ticks) + quality) / float(ticks + 1)
	n["sleepQualityTicks"] = ticks + 1
	n["slept"] = _slept_word(quality)
	if float(n.get("rest", 0.0)) >= 100.0 and String(n.get("crisis", "")) == "passed_out":
		n["crisis"] = "none"


static func _tick_mood(world: Variant) -> void:
	if hold_max(world):
		for ent in _survivors(world):
			_strip_need_mood(world, ent)
		return
	if int(world.tick) % 20 != 0:
		return
	for ent in _survivors(world):
		if world.components.has_component(ent, "controlled"):
			continue
		if world.modifiers == null:
			continue
		var mood: float = float(world.modifiers.call("resolve", "mood", ent))
		if mood <= LEAVE_AT:
			world.events.publish({"type": "mood.threshold", "entity": ent, "mood": mood})


# The one canonical mood-band read. Every consequence matches on the string this returns rather
# than comparing against a threshold of its own, so a boundary moves in one place.
static func mood_band(world: Variant, entity: int) -> String:
	if world.modifiers == null:
		return "content"
	var mood: float = float(world.modifiers.call("resolve", "mood", entity))
	if mood <= LEAVE_AT:
		return "breaking"
	if mood <= MOOD_MISERABLE:
		return "miserable"
	if mood <= MOOD_LOW:
		return "low"
	return "content"


# docs/04: "arguments -- which damage other survivors' mood, so misery spreads". A miserable
# survivor argues with the nearest other survivor in earshot; the damage lands on the *other* one,
# accumulates toward ARGUMENT_CAP, and drains away once nobody is arguing at them.
#
# Deliberately not symmetric: the arguer does not also lose mood. They are already miserable --
# that is the precondition -- and charging both sides would make any two unhappy people a spiral,
# which is the meltdown docs/04 rules out.
static func _tick_arguments(world: Variant) -> void:
	if int(world.tick) % 20 != 0:
		return
	var everyone: Array = _survivors(world)
	# Decay first, and for everybody, so a survivor nobody has argued with this cycle recovers on
	# the same tick the arguing happens rather than a cycle later.
	for ent in everyone:
		_decay_argument(world, int(ent))
	if hold_max(world):
		return
	if int(world.tick) % ARGUMENT_TICKS != 0:
		return
	for ent in everyone:
		if mood_band(world, int(ent)) != "miserable" and mood_band(world, int(ent)) != "breaking":
			continue
		if world.components.has_component(int(ent), "sleeping"):
			continue
		var victim: int = _nearest_other_survivor(world, int(ent), everyone)
		if victim < 0:
			continue
		_argue(world, int(ent), victim)


static func _nearest_other_survivor(world: Variant, ent: int, everyone: Array) -> int:
	var here: Variant = world.components.get_component(ent, "position")
	if not (here is Dictionary):
		return -1
	var best: int = -1
	var best_sq: float = ARGUMENT_METRES * ARGUMENT_METRES
	for other in everyone:
		if int(other) == ent:
			continue
		var there: Variant = world.components.get_component(int(other), "position")
		if not (there is Dictionary):
			continue
		var dx: float = float((there as Dictionary)["x"]) - float((here as Dictionary)["x"])
		var dy: float = float((there as Dictionary)["y"]) - float((here as Dictionary)["y"])
		var sq: float = dx * dx + dy * dy
		if sq <= best_sq:
			best_sq = sq
			best = int(other)
	return best


static func _argue(world: Variant, arguer: int, victim: int) -> void:
	var n: Dictionary = of(world, victim)
	var before: float = float(n.get("argued", 0.0))
	if before >= ARGUMENT_CAP:
		# Already as sour as arguing can make them. Still worth publishing -- the colony is having
		# the argument either way, and a listener that wants to say so should hear it.
		world.events.publish({"type": "mood.argument", "entity": arguer, "victim": victim, "capped": true})
		return
	n["argued"] = minf(ARGUMENT_CAP, before + ARGUMENT_PER)
	_apply_argument(world, victim, float(n["argued"]))
	world.events.publish({"type": "mood.argument", "entity": arguer, "victim": victim, "capped": false})


static func _decay_argument(world: Variant, ent: int) -> void:
	var n: Dictionary = of(world, ent)
	var carried: float = float(n.get("argued", 0.0))
	if carried <= 0.0:
		return
	n["argued"] = maxf(0.0, carried - ARGUMENT_DECAY)
	_apply_argument(world, ent, float(n["argued"]))


# --- grief ------------------------------------------------------------------------------------

# A survivor died. Everybody else takes it, more if they saw it.
#
# **Deduplicated on the body.** CLAUDE.md is explicit that `entity.killed` fires more than once for
# the same individual -- health.gd on a destroyed head, infection.gd on a put-down and again on
# turning -- so counting the event would charge the colony two or three times for one funeral. The
# `mourned` component is set the first time and checked every time.
static func _grieve_for(world: Variant, event: Dictionary) -> void:
	var dead: int = int(event.get("entity", -1))
	if dead < 0:
		return
	# Only people. A shambler going down is not a bereavement, and the same event carries both.
	if not world.components.has_component(dead, "needs"):
		return
	if world.components.has_component(dead, "mourned"):
		return
	world.components.set_component(dead, "mourned", {"tick": int(world.tick)})

	var at: Dictionary = _death_place(world, dead, event)
	var put_down: bool = world.components.has_component(dead, "putDown")
	var witnesses: int = 0
	for ent in _survivors(world):
		var mourner: int = int(ent)
		if mourner == dead or not _alive(world, mourner):
			continue
		var saw: bool = _saw(world, mourner, at)
		if saw:
			witnesses += 1
		var amount: float = GRIEF_WITNESSED if saw else GRIEF_HEARD
		if put_down:
			amount *= GRIEF_PUT_DOWN_MUL
		if has_trait(world, mourner, "optimist"):
			amount *= GRIEF_OPTIMIST_MUL
		var n: Dictionary = of(world, mourner)
		n["grief"] = minf(GRIEF_CAP, float(n.get("grief", 0.0)) + amount)
		_apply_grief(world, mourner, float(n["grief"]))
	world.events.publish({"type": "colony.bereaved", "entity": dead, "witnesses": witnesses, "putDown": put_down})


# Where it happened. health.gd's event carries the position; infection.gd's put-down does not, so
# the body's own position is the fallback rather than a silent (0, 0) that everybody can see.
static func _death_place(world: Variant, dead: int, event: Dictionary) -> Dictionary:
	if event.has("x") and event.has("y"):
		return {"x": float(event["x"]), "y": float(event["y"]), "known": true}
	var pos: Variant = world.components.get_component(dead, "position")
	if pos is Dictionary:
		return {"x": float((pos as Dictionary)["x"]), "y": float((pos as Dictionary)["y"]), "known": true}
	return {"x": 0.0, "y": 0.0, "known": false}


# Geometry and range, through the same primitive that decides whether a shot connects. A survivor
# with no eyes -- every pre-sightlines fixture -- witnesses nothing and grieves the lighter amount,
# which is the honest reading of "we have no idea whether they saw it".
static func _saw(world: Variant, mourner: int, at: Dictionary) -> bool:
	if not bool(at.get("known", false)):
		return false
	if world.vision == null:
		return false
	if world.vision.call("tiles_for", mourner) == null:
		return false
	return bool(world.vision.call("line_of_sight", mourner, float(at["x"]), float(at["y"])))


static func _alive(world: Variant, ent: int) -> bool:
	if world.components.has_component(ent, "corpse"):
		return false
	var body: Variant = world.components.get_component(ent, "body")
	return body is Dictionary and SimHealth.is_alive(body as Dictionary)


static func grief_of(world: Variant, entity: int) -> float:
	return float(of(world, entity).get("grief", 0.0))


# Drains on the mood tick, exactly as an argument does. Same shape, same reason: one modifier from
# one source, replaced rather than stacked.
static func _tick_grief(world: Variant) -> void:
	if world.modifiers == null or int(world.tick) % 20 != 0:
		return
	for ent in _survivors(world):
		var n: Dictionary = of(world, int(ent))
		var g: float = float(n.get("grief", 0.0))
		if g <= 0.0:
			continue
		g = maxf(0.0, g - GRIEF_DECAY)
		n["grief"] = g
		_apply_grief(world, int(ent), g)


static func _apply_grief(world: Variant, ent: int, amount: float) -> void:
	if world.modifiers == null:
		return
	world.modifiers.call("remove_by_source", GRIEF_SOURCE, ent)
	if amount <= 0.0:
		return
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": -amount, "source": GRIEF_SOURCE}, ent)


# One modifier from one source, replaced rather than stacked. Adding a second modifier per
# argument would accumulate without bound behind the cap this module thinks it is enforcing.
static func _apply_argument(world: Variant, ent: int, amount: float) -> void:
	if world.modifiers == null:
		return
	world.modifiers.call("remove_by_source", ARGUMENT_SOURCE, ent)
	if amount <= 0.0:
		return
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": -amount, "source": ARGUMENT_SOURCE}, ent)


# --- sleep quality, continued -------------------------------------------------------------------
#
# The derivation itself. 0..1, floored rather than allowed to zero -- a night can be bad, never a
# night that restores nothing, which is the same "never a dead night" shape `pain_of` already
# guarantees a survivor cannot be swallowed by.
static func sleep_quality(world: Variant, entity: int) -> float:
	var n: Dictionary = of(world, entity)
	var sl: Variant = world.components.get_component(entity, "sleeping")
	var on_bed: bool = sl is Dictionary and int((sl as Dictionary).get("bed", -1)) >= 0
	var penalty: float = 0.0
	if not on_bed:
		penalty += SLEEP_PENALTY_ROUGH
	var tp: String = band_pressure("temperature", String(n.get("temperature", "comfortable")))
	match tp:
		"seek":
			penalty += SLEEP_PENALTY_TEMP_SEEK
		"soft":
			penalty += SLEEP_PENALTY_TEMP_SOFT
		"hard":
			penalty += SLEEP_PENALTY_TEMP_HARD
	# Read through `SimWounds.pain_of`, which already applies suppression -- so a dose of
	# painkillers buys a night's sleep without touching a single wound, exactly as docs/05 asks.
	var Wounds: GDScript = load("res://sim/modules/wounds.gd") as GDScript
	if Wounds != null:
		var pain: float = float(Wounds.call("pain_of", world, entity))
		if pain > SLEEP_PAIN_FLOOR:
			penalty += SLEEP_PENALTY_PAIN * pain
	# Guarded exactly the way sim/attention_read.gd:69 guards the same field, for the same reason:
	# a world booted without one (most gates, most fixtures) must still be able to sleep rather
	# than crash reaching for it.
	if world.field != null:
		var pos: Variant = world.components.get_component(entity, "position")
		if pos is Dictionary:
			var noise_v: float = float(world.field.call("noise_at", float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"])))
			var floor_v: float = float((world.field.calibration as Dictionary).get("floor", 0.05))
			if noise_v > floor_v:
				penalty += SLEEP_PENALTY_NOISE
	if has_trait(world, entity, "light_sleeper"):
		penalty *= SLEEP_LIGHT_SLEEPER_MUL
	return clampf(1.0 - penalty, SLEEP_QUALITY_FLOOR, 1.0)


# The quality word `slept` carries onto the HUD -- grown from a plain "bed"/"rough" into a word
# that actually says how the night went, the way every other band in this file already does.
static func _slept_word(quality: float) -> String:
	if quality <= SLEEP_QUALITY_FLOOR + 0.001:
		return "barely_slept"
	if quality < SLEEP_WORD_GOOD:
		return "broken"
	return "rested"


# One modifier from one source, replaced rather than stacked -- `_apply_grief`'s shape exactly,
# for the reason every other bounded mood source in this file shares it.
static func _apply_slept(world: Variant, ent: int, amount: float) -> void:
	if world.modifiers == null:
		return
	world.modifiers.call("remove_by_source", SLEEP_SOURCE, ent)
	if amount <= 0.0:
		return
	world.modifiers.call("add", {"stat": "mood", "op": "add", "value": -amount, "source": SLEEP_SOURCE}, ent)


# Charged at `_wake`, proportional to how bad the night's mean quality was -- a perfect night
# charges nothing, and the charge accumulates toward the cap exactly as an argument or a grief
# does, so three bad nights in a row cost more than one but never past the cap.
static func _charge_slept_mood(world: Variant, entity: int) -> void:
	var n: Dictionary = of(world, entity)
	var mean: float = clampf(float(n.get("sleepQuality", 1.0)), 0.0, 1.0)
	var charge: float = SLEEP_MOOD * (1.0 - mean)
	if charge <= 0.0:
		return
	var total: float = minf(SLEEP_MOOD_CAP, float(n.get("sleptMood", 0.0)) + charge)
	n["sleptMood"] = total
	_apply_slept(world, entity, total)


# Drains on the mood tick, exactly as grief and arguments do: once nobody is having a bad night,
# the cost fades rather than sitting there forever.
static func _tick_slept_mood(world: Variant) -> void:
	if world.modifiers == null or int(world.tick) % 20 != 0:
		return
	for ent in _survivors(world):
		var n: Dictionary = of(world, int(ent))
		var s: float = float(n.get("sleptMood", 0.0))
		if s <= 0.0:
			continue
		s = maxf(0.0, s - SLEEP_DECAY)
		n["sleptMood"] = s
		_apply_slept(world, int(ent), s)


# --- the deep cold, which used to be unreachable ----------------------------------------------
#
# `extremely_cold` was in TEMP_ORDER, was the only "hard" temperature `band_pressure` could return,
# had its own HUD line, and drove jobs.gd's mid-job interrupt -- and `_tick_temperature` could
# write `comfortable`, `very_cold` and `a_little_cold` and nothing else. So the hard band was
# unreachable, every branch keyed to it was dead, and a night outdoors read the same on the first
# tick as on the last however long somebody stood in it.
#
# Cold is a dose, not a reading of the sky. docs/04 lists the consequences in order -- "mood
# damage, then temporary movement and fine-motor penalties, then hypothermia" -- which is a thing
# that gets worse the longer it lasts. So a survivor left in the `very_cold` case keeps a clock,
# and once they have been out in it for EXPOSURE_TICKS the band deepens. Any warmth at all -- a
# roof, a lit fire, the end of the night -- clears the clock, so the deep band is the price of a
# sustained night outdoors rather than a moment of one, and the cloth wrap (which shifts one band
# toward comfortable) is worth a real hour and a half out there.
#
# 18000 ticks is an hour and a half in game, a quarter of the six-hour night.
const EXPOSURE_TICKS: int = 18000


static func _tick_temperature(world: Variant) -> void:
	var hold: bool = hold_max(world)
	var night: bool = Clock.phase_of(int(world.tick)) == Clock.Phase.Night
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			n["temperature"] = "comfortable"
			n["coldSinceTick"] = -1
			n["hotSinceTick"] = -1
			n["wetUntilTick"] = -1
			continue
		var pos: Variant = world.components.get_component(ent, "position")
		if not pos is Dictionary:
			continue
		var tx: int = floori(float((pos as Dictionary)["x"]))
		var ty: int = floori(float((pos as Dictionary)["y"]))
		var indoors: bool = world.tilemap != null and SimTileMap.is_indoors(world.tilemap, tx, ty)
		var fire: bool = lit_campfire_near(world, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]), CAMPFIRE_HEAT_M)
		# Wetness (docs/adr/0015, docs/04 "being wet is a multiplier on cold"): a body out in the
		# rain is wet `wetAfterTicks` after it started standing there, stays wet `dryAfterTicks`
		# once the rain stops or a roof is found, and a lit fire brings that forward to
		# `dryByFireTicks`. One integer on the component; `wet` is derived from it every tick.
		var wet_until: int = int(n.get("wetUntilTick", -1))
		if SimWeather.raining(world) and not indoors:
			var soaking: int = int(n.get("rainSinceTick", -1))
			if soaking < 0:
				soaking = int(world.tick)
			n["rainSinceTick"] = soaking
			if int(world.tick) - soaking >= SimWeather.wet_after_ticks(world):
				wet_until = int(world.tick) + SimWeather.dry_after_ticks(world)
		else:
			n["rainSinceTick"] = -1
		if fire and wet_until > int(world.tick) + SimWeather.dry_by_fire_ticks(world):
			wet_until = int(world.tick) + SimWeather.dry_by_fire_ticks(world)
		n["wetUntilTick"] = wet_until
		var wet: bool = int(world.tick) < wet_until
		var before: String = String(n.get("temperature", "comfortable"))
		var exposed: bool = night and not fire and not indoors
		var since: int = int(n.get("coldSinceTick", -1))
		if not exposed:
			since = -1
		elif since < 0:
			since = int(world.tick)
		n["coldSinceTick"] = since
		# Heat is a dose too, and this is the cold clock's mirror: it runs while the sky is hot
		# and the body is out under it by day, and any roof, the night, or the end of the spell
		# clears it. Read below the shift block for what the dose buys.
		var shift: int = SimWeather.temp_shift(world)
		var baking: bool = shift > 0 and not night and not indoors
		var hot_since: int = int(n.get("hotSinceTick", -1))
		if not baking:
			hot_since = -1
		elif hot_since < 0:
			hot_since = int(world.tick)
		n["hotSinceTick"] = hot_since
		var band: String = "comfortable"
		if night:
			if fire:
				band = "comfortable"
			elif not indoors:
				band = "very_cold"
				if since >= 0 and int(world.tick) - since >= EXPOSURE_TICKS:
					band = "extremely_cold"
			else:
				band = "a_little_cold"
		# The sky's own shift (docs/adr/0016), between the base and the wet: a cold snap reads
		# one band colder day and night, indoors too -- a roof is shelter from the wet, not from
		# the cold -- and only a lit fire cancels it; a heat wave reads one band hotter by day
		# outdoors, and nothing cancels it (the night is its own relief). The hot half of the
		# ladder is reachable through this line and no other.
		if shift < 0 and not fire:
			for _s in -shift:
				band = _colder(band)
		elif baking:
			# The sky's band, one more for body armour at once -- docs/16's "armor becomes
			# punishing" -- one more once the body has been out in it for EXPOSURE_TICKS, and
			# the deepest band only for a body that has spent twice that in armour. So the sun
			# alone can make somebody very hot and nothing else; heatstroke is what armour in a
			# heat wave costs, which is the choice the kind exists to force.
			var armored: bool = wearing_armor(world, ent)
			var steps: int = shift
			if armored:
				steps += 1
			var baked: int = int(world.tick) - hot_since
			if hot_since >= 0 and baked >= EXPOSURE_TICKS:
				steps += 1
			for _s in steps:
				band = _hotter(band)
			if not (armored and hot_since >= 0 and baked >= 2 * EXPOSURE_TICKS):
				band = _no_hotter_than(band, "very_hot")
		# Wet first, then the wrap: a wet body reads one band colder, and a wrap buys one back,
		# so a soaked survivor in a wrap on a mild day reads comfortable and a soaked one at
		# night by no fire is freezing at once.
		if wet:
			band = _colder(band)
		if wearing_wrap(world, ent):
			band = _shift_temp(band, 1)
		n["temperature"] = band
		if band != before:
			_apply_muls(world, ent, n)


# One band colder, clamped at the cold end. `_shift_temp` cannot do this: it moves *toward*
# comfortable and answers "comfortable" for a body already there.
static func _colder(band: String) -> String:
	var i: int = TEMP_ORDER.find(band)
	if i < 0:
		return "a_little_cold"
	var c: int = TEMP_ORDER.find("comfortable")
	if i > c:
		# The hot bands are unreachable today (docs/adr/0002); a wet hot body would step toward
		# comfortable, which is the right direction whenever they land.
		return TEMP_ORDER[i - 1]
	return TEMP_ORDER[maxi(0, i - 1)]


# One band hotter, clamped at the hot end -- `_colder`'s mirror, for the heat wave. A cold body
# steps toward comfortable, which is the right direction for a cold body in the sun.
static func _hotter(band: String) -> String:
	var i: int = TEMP_ORDER.find(band)
	if i < 0:
		return "a_little_hot"
	return TEMP_ORDER[mini(TEMP_ORDER.size() - 1, i + 1)]


# A ceiling on the hot half of the ladder. Written as a clamp rather than as one fewer `_hotter`
# call because the sky's shift is content and could be 2, and because the cap is the rule -- the
# sun alone never reaches heatstroke -- rather than an arithmetic accident of how many steps ran.
static func _no_hotter_than(band: String, cap: String) -> String:
	var i: int = TEMP_ORDER.find(band)
	var c: int = TEMP_ORDER.find(cap)
	if i < 0 or c < 0:
		return band
	return TEMP_ORDER[mini(i, c)]


static func is_wet(world: Variant, entity: int) -> bool:
	return int(world.tick) < int(of(world, entity).get("wetUntilTick", -1))


static func _shift_temp(band: String, toward_comfy: int) -> String:
	var i: int = TEMP_ORDER.find(band)
	if i < 0:
		return "comfortable"
	var c: int = TEMP_ORDER.find("comfortable")
	if i < c:
		return TEMP_ORDER[mini(c, i + toward_comfy)]
	if i > c:
		return TEMP_ORDER[maxi(c, i - toward_comfy)]
	return "comfortable"


static func _tick_hygiene(world: Variant) -> void:
	var hold: bool = hold_max(world)
	var dusk: bool = Clock.phase_of(int(world.tick)) == Clock.Phase.Dusk and Clock.phase_of(int(world.tick) - 1) != Clock.Phase.Dusk
	for ent in _survivors(world):
		var n: Dictionary = of(world, ent)
		if hold:
			n["hygiene"] = "clean"
			_scent_mul(world, ent, "clean")
			continue
		if dusk and bool(n.get("dirtyWake", false)):
			_dirt(world, ent, 1)
		_scent_mul(world, ent, String(n.get("hygiene", "clean")))
		if dusk:
			_daily_sepsis(world, ent, n)


static func _daily_sepsis(world: Variant, ent: int, n: Dictionary) -> void:
	var inj: Variant = world.components.get_component(ent, "injuries")
	if not inj is Dictionary:
		return
	var wounds: Array = (inj as Dictionary).get("wounds", []) as Array
	if wounds.is_empty():
		return
	var mul: float = sepsis_mul(String(n.get("hygiene", "clean")))
	world.events.publish({"type": "sepsis.checked", "entity": ent, "mul": mul, "kind": "wound"})
	# The socket, finally connected. This published its multiplier every dusk and nothing
	# subscribed, so `sepsis_mul` was gated, correct, and reached no wound. wounds.gd owns the
	# wound record and the recovery clock sepsis has to block, so the roll lives there; hygiene
	# lives here, so the multiplier is computed here and handed over rather than re-derived.
	var Wounds: GDScript = load("res://sim/modules/wounds.gd") as GDScript
	if Wounds != null and Wounds.has_method("roll_sepsis"):
		var SkillsRes: GDScript = load("res://sim/modules/skills.gd") as GDScript
		var medicine: int = int(SkillsRes.call("points", world, ent, "Medicine")) if SkillsRes != null else 0
		Wounds.call("roll_sepsis", world, ent, mul, medicine)


static func treat_sepsis_mul(world: Variant, treater: int) -> float:
	return sepsis_mul(String(of(world, treater).get("hygiene", "clean")))


# Spoilage is a clock the pantry-keeper can slow. `spoilage_rate` was declared in stats.gd, bought
# through the `surv.cook` web node ("a careful pantry", x0.95) and resolved by nothing -- a node a
# survivor could own and nobody could feel (docs/23's defect list). The owner's rule (2026-09-06):
# every perishable ages at the rate of the **best living colonist**, resolved once a tick, because
# the pantry is the colony's and one careful pair of hands keeps all of it. `aged` is the clock,
# advanced by the rate each tick, so the old `bornTick` comparison becomes a special case of it
# at rate 1.0; the field is defaulted from `bornTick` when absent so a spoilage record written
# before this key existed keeps its age.
static func _tick_spoilage(world: Variant) -> void:
	var items: Array[int] = world.components.query(["spoilage"])
	if items.is_empty():
		return
	# Times the sky's own factor, written once and generically: a heat wave doubles it and a cold
	# snap halves it, and neither kind is named here -- the number is the kind's content entry.
	var rate: float = pantry_rate(world) * SimWeather.spoilage_mul(world)
	for item in items:
		var sp: Variant = world.components.get_component(int(item), "spoilage")
		if not sp is Dictionary:
			continue
		var s: Dictionary = sp as Dictionary
		if bool(s.get("spoiled", false)):
			continue
		var need: int = int(s.get("spoilTicks", 0))
		if need <= 0:
			continue
		var aged: float = float(s.get("aged", int(world.tick) - int(s.get("bornTick", 0)))) + rate
		s["aged"] = aged
		if aged >= float(need):
			s["spoiled"] = true


# The colony's spoilage rate: the lowest `spoilage_rate` any living colonist resolves to, or 1.0
# with nobody to keep a pantry. Corpses lose `needs` at `_make_corpse`, so the dead drop out.
static func pantry_rate(world: Variant) -> float:
	var best: float = 1.0
	if world.modifiers == null:
		return best
	for ent in _survivors(world):
		if world.components.has_component(int(ent), "recruit"):
			continue
		best = minf(best, float(world.modifiers.call("resolve", "spoilage_rate", int(ent))))
	return maxf(0.0, best)


static func mark_spoilage(world: Variant, item: int, base_id: String) -> void:
	var spec: Variant = food_spec(world, base_id)
	if spec == null:
		return
	var days: float = float((spec as Dictionary).get("spoilDays", 0.0))
	if days <= 0.0:
		return
	world.components.set_component(item, "spoilage", {
		"bornTick": int(world.tick),
		"spoilTicks": int(days * float(Clock.DAY_TICKS)),
		"spoiled": false,
		"aged": 0.0,
	})


static func _hold_one(world: Variant, ent: int, n: Dictionary) -> void:
	n["hunger"] = 100.0
	n["thirst"] = 100.0
	n["rest"] = 100.0
	n["relief"] = 100.0
	n["temperature"] = "comfortable"
	n["hygiene"] = "clean"
	n["crisis"] = "none"
	n["starvingSinceTick"] = -1
	n["dehydratingSinceTick"] = -1
	n["coldSinceTick"] = -1
	n["hotSinceTick"] = -1
	n["wetUntilTick"] = -1
	n["rainSinceTick"] = -1
	n["soiled"] = 0.0
	_apply_soiled(world, ent, 0.0)
	n["sleepQuality"] = 1.0
	n["sleepQualityTicks"] = 0
	n["sleptMood"] = 0.0
	n["stimulantUntilTick"] = -1
	n["stimulantCrashRest"] = 0.0
	_apply_slept(world, ent, 0.0)
	_strip_need_mood(world, ent)


static func _strip_need_mood(world: Variant, ent: int) -> void:
	if world.modifiers == null:
		return
	for src in NEED_SOURCES:
		world.modifiers.call("remove_by_source", src, ent)


static func _cross(world: Variant, ent: int, n: Dictionary, key: String, before: float, after: float) -> void:
	var marks: Array[float] = [SEEK_STOP, SEEK_NEVER_ABOVE, SEEK_START, SOFT, HARD]
	var hit: bool = false
	for m in marks:
		if (before > m and after <= m) or (before <= m and after > m):
			hit = true
			break
	if hit:
		_apply_muls(world, ent, n)
		world.events.publish({"type": "need.crossed", "entity": ent, "need": key, "value": after})


static func _apply_muls(world: Variant, ent: int, n: Dictionary) -> void:
	if world.modifiers == null:
		return
	_strip_need_mood(world, ent)
	if hold_max(world):
		return
	var work: float = work_mul(world, ent)
	var acc: float = accuracy_mul(world, ent)
	if work != 1.0 and work > 0.0:
		world.modifiers.call("add", {"stat": "ranged_accuracy", "op": "mul", "value": acc, "source": "need.hunger"}, ent)
	var mood_v: float = 0.0
	for k in POOLS:
		if float(n.get(k, 100.0)) < SOFT:
			mood_v -= 10.0
	var t: String = String(n.get("temperature", "comfortable"))
	var h: String = String(n.get("hygiene", "clean"))
	# Same reading as work_mul's, and for the same reason: the deep band is worse than `very_cold`,
	# and a list of band names is exactly where it went missing before.
	var tp: String = band_pressure("temperature", t)
	if tp == "seek" or h == "a_little_dirty":
		mood_v -= 4.0
	if tp == "soft" or h == "dirty":
		mood_v -= 10.0
	if tp == "hard":
		mood_v -= 20.0
	if h == "filthy":
		mood_v -= 20.0
	if mood_v != 0.0:
		world.modifiers.call("add", {"stat": "mood", "op": "add", "value": mood_v, "source": "need.hunger"}, ent)


static func _scent_mul(world: Variant, ent: int, band: String) -> void:
	var em: Variant = world.components.get_component(ent, "attention_emitter")
	if not em is Dictionary:
		return
	var base: float = 1.0
	if band == "dirty":
		base = 2.0
	elif band == "filthy":
		base = 3.0
	(em as Dictionary)["scent"] = base


static func dirt(world: Variant, entity: int, bands: int = 1) -> void:
	_dirt(world, entity, bands)


static func _dirt(world: Variant, entity: int, bands: int) -> void:
	var n: Dictionary = of(world, entity)
	var i: int = HYG_ORDER.find(String(n.get("hygiene", "clean")))
	if i < 0:
		i = 0
	n["hygiene"] = HYG_ORDER[clampi(i + bands, 0, HYG_ORDER.size() - 1)]
	_apply_muls(world, entity, n)
	_scent_mul(world, entity, String(n["hygiene"]))


static func wash(world: Variant, entity: int) -> bool:
	if not _consume_base(world, entity, WATER_ID):
		return false
	return wash_at_source(world, entity)


static func wash_at_source(world: Variant, entity: int) -> bool:
	var n: Dictionary = of(world, entity)
	n["hygiene"] = "clean"
	_apply_muls(world, entity, n)
	_scent_mul(world, entity, "clean")
	return true


# Water, by name: what the NPC thirst job reaches for. Same signature it always had; the +50 it
# used to carry as a literal now comes off the bottle's own `drink` block through drink_item.
static func drink(world: Variant, entity: int) -> bool:
	var bottle: int = _carried_base(world, entity, WATER_ID)
	return bottle >= 0 and drink_item(world, entity, bottle)


# Any drink, by item. Consumed first, so a refused consume leaves nothing behind (the `eat` rule);
# then the pool moves, and if the block carries a lift the crash is booked against the same pool.
static func drink_item(world: Variant, entity: int, item: int) -> bool:
	var base: Variant = world.components.get_component(item, "itemBase")
	if not base is Dictionary:
		return false
	var bid: String = String((base as Dictionary).get("baseId", ""))
	var spec_v: Variant = drink_spec(world, bid)
	if spec_v == null:
		return false
	var spec: Dictionary = spec_v as Dictionary
	# docs/04: "untreated water carries illness". Rolled before the bottle is consumed and applied
	# after, the `eat` rule, so a refused consume cannot leave somebody ill from a drink they did
	# not have. A clean bottle declares no chance and never rolls.
	var ill: bool = _rolls_ill(world, entity, spec, false)
	if not _consume_item(world, entity, item):
		return false
	var n: Dictionary = of(world, entity)
	n["thirst"] = minf(100.0, float(n.get("thirst", 0.0)) + float(spec.get("thirst", 0.0)))
	if String(n.get("crisis", "")) == "dehydrating" and float(n["thirst"]) > 0.0:
		n["crisis"] = "none"
		n["dehydratingSinceTick"] = -1
	var lift: float = float(spec.get("rest", 0.0))
	if lift > 0.0:
		n["rest"] = minf(100.0, float(n.get("rest", 0.0)) + lift)
		# Accumulate the debt and reset the clock: chaining defers the crash and compounds it,
		# never wipes it.
		n["stimulantCrashRest"] = float(n.get("stimulantCrashRest", 0.0)) + float(spec.get("crashRest", 0.0))
		n["stimulantUntilTick"] = int(world.tick) + int(spec.get("crashAfterTicks", 0))
	if spec.has("mood"):
		_apply_meal_mood(world, entity, float(spec["mood"]))
	if ill:
		_fall_ill(world, entity)
	_apply_muls(world, entity, n)
	_intake(world, entity, RELIEF_PER_DRINK)
	world.events.publish({"type": "need.drank", "entity": entity, "item": item, "baseId": bid, "stimulant": lift > 0.0, "ill": ill})
	return true


# Untreated water, by name: what a thirsty NPC with no fire and nothing clean drinks, and a verb
# the player reaches through `item.use` on the bottle itself.
static func drink_untreated(world: Variant, entity: int) -> bool:
	var bottle: int = _carried_base(world, entity, UNTREATED_ID)
	return bottle >= 0 and drink_item(world, entity, bottle)


# The well's product. One producer, so `check_m2_gear.gd`'s CATALOGUE lane can read this file for
# the id: a filled bottle is untreated water, never clean.
static func fill_bottle(world: Variant, bottle: int) -> void:
	var base: Variant = world.components.get_component(bottle, "itemBase")
	if base is Dictionary:
		(base as Dictionary)["baseId"] = UNTREATED_ID


# Boil one carried bottle of untreated water at a lit fire. Instant, and the same rename the well
# does in reverse -- no despawn, no RNG, the bottle keeps its instance. Refused with a reason the
# screen can say: no fire in reach, a fire that is not lit, nothing untreated in the pack.
static func boil(world: Variant, actor: int, fire: int) -> Dictionary:
	var cf: Variant = world.components.get_component(fire, "campfire")
	if fire < 0 or not (cf is Dictionary):
		return {"ok": false, "reason": "no-fire"}
	if not bool((cf as Dictionary).get("lit", false)):
		return {"ok": false, "reason": "unlit"}
	var bottle: int = _carried_base(world, actor, UNTREATED_ID)
	if bottle < 0:
		return {"ok": false, "reason": "no-bottle"}
	var base: Dictionary = world.components.get_component(bottle, "itemBase") as Dictionary
	base["baseId"] = WATER_ID
	world.events.publish({"type": "need.boiled", "entity": actor, "item": bottle, "fire": fire})
	return {"ok": true}


static func eat(world: Variant, entity: int, item: int) -> bool:
	var base: Variant = world.components.get_component(item, "itemBase")
	if not base is Dictionary:
		return false
	var bid: String = String((base as Dictionary).get("baseId", ""))
	var spec_v: Variant = food_spec(world, bid)
	if spec_v == null:
		return false
	var spec: Dictionary = spec_v as Dictionary
	var hunger: float = float(spec.get("hunger", 0.0))
	var mood: float = float(spec.get("mood", 0.0))
	var spoiled: bool = false
	var sp: Variant = world.components.get_component(item, "spoilage")
	if sp is Dictionary:
		spoiled = bool((sp as Dictionary).get("spoiled", false))
	if spoiled:
		mood = SPOILED_MOOD
	# docs/04: raw and spoiled food "carries illness risk". Rolled before the item is consumed but
	# applied after, so a refused consume cannot leave somebody ill from a meal they did not eat.
	var ill: bool = _rolls_ill(world, entity, spec, spoiled)
	var iron: bool = has_trait(world, entity, "iron_stomach")
	if iron and mood < 0.0:
		mood = 0.0
	if not _consume_item(world, entity, item):
		return false
	var n: Dictionary = of(world, entity)
	n["hunger"] = minf(100.0, float(n.get("hunger", 0.0)) + hunger)
	if String(n.get("crisis", "")) == "starving" and float(n["hunger"]) > 0.0:
		n["crisis"] = "none"
		n["starvingSinceTick"] = -1
	_apply_meal_mood(world, entity, mood)
	if ill:
		_fall_ill(world, entity)
	_apply_muls(world, entity, n)
	_intake(world, entity, RELIEF_PER_MEAL)
	return true


static func use_item(world: Variant, entity: int, item: int, as_wash: bool = false) -> bool:
	if item < 0 or not SimInventory.owns(world, entity, item):
		return false
	var base: Variant = world.components.get_component(item, "itemBase")
	if not base is Dictionary:
		return false
	var bid: String = String((base as Dictionary).get("baseId", ""))
	if as_wash:
		return wash(world, entity)
	if drink_spec(world, bid) != null:
		# Water on a filthy body is a wash unless you are dying of thirst -- keyed on the base's
		# cleanTier rather than its id, because "this is water" is content.
		var entry: Variant = SimItems.content_entry(world, "item", bid)
		var is_water: bool = entry is Dictionary and String((entry as Dictionary).get("cleanTier", "")) == "water"
		var n: Dictionary = of(world, entity)
		if is_water and String(n.get("hygiene", "clean")) == "filthy" and String(n.get("crisis", "none")) != "dehydrating":
			return wash(world, entity)
		return drink_item(world, entity, item)
	if is_food(world, bid):
		return eat(world, entity, item)
	return false


static func _carried_base(world: Variant, actor: int, base_id: String) -> int:
	for item in SimInventory.carried_items(world, actor):
		var base: Variant = world.components.get_component(item, "itemBase")
		if base is Dictionary and String((base as Dictionary).get("baseId", "")) == base_id:
			return int(item)
	return -1


static func _consume_base(world: Variant, actor: int, base_id: String) -> bool:
	var item: int = _carried_base(world, actor, base_id)
	return item >= 0 and _consume_item(world, actor, item)


static func consume_base(world: Variant, actor: int, base_id: String) -> bool:
	return _consume_base(world, actor, base_id)


static func consume_item(world: Variant, actor: int, item: int) -> bool:
	return _consume_item(world, actor, item)


# The one place a unit of anything is spent -- a drink, a wash, a wound cleaned with the bottle, a
# can poured -- so the one place what is left behind (`empties`) is decided.
static func _consume_item(world: Variant, actor: int, item: int) -> bool:
	var base: Variant = world.components.get_component(item, "itemBase")
	var bid: String = String((base as Dictionary).get("baseId", "")) if base is Dictionary else ""
	var stack: Variant = world.components.get_component(item, "stack")
	if stack is Dictionary and int((stack as Dictionary).get("count", 1)) > 1:
		(stack as Dictionary)["count"] = int((stack as Dictionary)["count"]) - 1
	else:
		SimInventory.remove_from_container(world, item)
		world.despawn(item)
	_leave_empty(world, actor, bid)
	return true


# What a spent unit leaves in the hand: the base its `empties` names, stowed where the unit was or
# dropped at the feet when nothing has room. A scavenged spawn draws no RNG (its tier has no
# affixes to roll), so this cannot move a seeded run.
static func _leave_empty(world: Variant, actor: int, base_id: String) -> void:
	var entry: Variant = SimItems.content_entry(world, "item", base_id)
	if not (entry is Dictionary):
		return
	var empties: String = String((entry as Dictionary).get("empties", ""))
	if empties.is_empty() or SimItems.content_entry(world, "item", empties) == null:
		return
	var left: int = SimItems.spawn_item(world, empties, {"tier": "scavenged"})
	if SimInventory.stow(world, actor, left):
		return
	if not SimInventory.drop_at_feet(world, actor, left):
		world.despawn(left)


static func start_sleep(world: Variant, entity: int, bed: int) -> void:
	_start_sleep(world, entity, bed)


static func wake(world: Variant, entity: int) -> void:
	_wake(world, entity)


static func _start_sleep(world: Variant, entity: int, bed: int) -> void:
	world.components.set_component(entity, "sleeping", {"bed": bed, "since": int(world.tick)})
	if bed >= 0:
		var b: Variant = world.components.get_component(bed, "bed")
		if b is Dictionary:
			(b as Dictionary)["occupiedBy"] = entity
	var vel: Variant = world.components.get_component(entity, "velocity")
	if vel is Dictionary:
		(vel as Dictionary)["dx"] = 0.0
		(vel as Dictionary)["dy"] = 0.0
	# Reset for the night that is about to be measured, so a running mean does not carry a stale
	# tail over from whatever happened the last time this survivor slept.
	var n: Dictionary = of(world, entity)
	n["sleepQuality"] = 1.0
	n["sleepQualityTicks"] = 0


static func _wake(world: Variant, entity: int) -> void:
	if entity < 0:
		return
	var sl: Variant = world.components.get_component(entity, "sleeping")
	if sl is Dictionary:
		var bed: int = int((sl as Dictionary).get("bed", -1))
		if bed >= 0:
			var b: Variant = world.components.get_component(bed, "bed")
			if b is Dictionary and int((b as Dictionary).get("occupiedBy", -1)) == entity:
				(b as Dictionary)["occupiedBy"] = -1
		# Charged only for a survivor who was actually asleep this call -- `_wake` is also reached
		# by wake-hit and wake-alarm handlers for entities that were never sleeping in the first
		# place, and charging those would bill a night nobody had.
		_charge_slept_mood(world, entity)
	world.components.remove(entity, "sleeping")


static func _wake_all(world: Variant) -> void:
	for ent in world.components.query(["sleeping"]):
		_wake(world, int(ent))


static func make_campfire(world: Variant, x: float, y: float, lit: bool = false) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "campfire", {"lit": lit, "cooking": false})
	var em: Dictionary = SimAttention.PERSON_EMITTER.duplicate(true)
	em["walking"] = 0.0
	em["sprinting"] = 0.0
	em["ambient"] = 0.0
	em["scent"] = 0.0
	SimAttention.make_emitter(world, ent, em)
	if lit:
		set_lit(world, ent, true)
	return ent


static func make_bed(world: Variant, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "bed", {"occupiedBy": -1})
	return ent


static func make_water_source(world: Variant, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "water_source", {})
	return ent


# A latrine: the place the bathroom need is answered. Shaped exactly like the well -- a position, a
# marker component, and a factory here -- because it is the same kind of thing, a station the
# colony owns that a need walks somebody to. The emitter is the part that is not free: docs/03's
# table prices a latrine at scent 12, so building one is a comfort you pay for in attention, which
# is the trade docs/04 says every comfort is.
static func make_latrine(world: Variant, x: float, y: float) -> int:
	var ent: int = int(world.entities.spawn())
	world.components.set_component(ent, "position", {"x": x, "y": y})
	world.components.set_component(ent, "latrine", {})
	var em: Dictionary = SimAttention.PERSON_EMITTER.duplicate(true)
	em["walking"] = 0.0
	em["sprinting"] = 0.0
	em["ambient"] = 0.0
	em["scent"] = LATRINE_SCENT
	SimAttention.make_emitter(world, ent, em)
	return ent


static func nearest_latrine(world: Variant, x: float, y: float) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for e in world.components.query(["latrine", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(e)
	return best


static func nearest_water_source(world: Variant, x: float, y: float) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for e in world.components.query(["water_source", "position"]):
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(e)
	return best


static func set_lit(world: Variant, fire: int, lit: bool, cooking: bool = false) -> void:
	var cf: Variant = world.components.get_component(fire, "campfire")
	if not cf is Dictionary:
		return
	(cf as Dictionary)["lit"] = lit
	(cf as Dictionary)["cooking"] = cooking
	var em: Variant = world.components.get_component(fire, "attention_emitter")
	if em is Dictionary:
		(em as Dictionary)["scent"] = (CAMPFIRE_COOK_SCENT if cooking else CAMPFIRE_SCENT) if lit else 0.0
		(em as Dictionary)["ambient"] = 0.0
	if lit:
		SimLightMod.make_light_source(world, fire, CAMPFIRE_LIGHT_M)
	elif world.components.has_component(fire, "light_source"):
		world.components.remove(fire, "light_source")
		world.events.publish({"type": "light.changed", "entity": fire, "magnitude": 0.0})


static func toggle_fire(world: Variant, fire: int) -> void:
	var cf: Variant = world.components.get_component(fire, "campfire")
	if cf is Dictionary:
		set_lit(world, fire, not bool((cf as Dictionary).get("lit", false)))


static func lit_campfire_near(world: Variant, x: float, y: float, metres: float) -> bool:
	var r2: float = metres * metres
	for e in world.components.query(["campfire", "position"]):
		var cf: Variant = world.components.get_component(int(e), "campfire")
		if not cf is Dictionary or not bool((cf as Dictionary).get("lit", false)):
			continue
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		if dx * dx + dy * dy <= r2:
			return true
	return false


static func nearest_campfire(world: Variant, x: float, y: float, lit_only: bool = false) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for e in world.components.query(["campfire", "position"]):
		var cf: Variant = world.components.get_component(int(e), "campfire")
		if lit_only and (not cf is Dictionary or not bool((cf as Dictionary).get("lit", false))):
			continue
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(e)
	return best


static func nearest_bed(world: Variant, x: float, y: float, free_only: bool = true) -> int:
	var best: int = -1
	var best_d: float = 1e12
	for e in world.components.query(["bed", "position"]):
		var b: Variant = world.components.get_component(int(e), "bed")
		if free_only and b is Dictionary and int((b as Dictionary).get("occupiedBy", -1)) >= 0:
			continue
		var p: Variant = world.components.get_component(int(e), "position")
		if not p is Dictionary:
			continue
		var dx: float = float((p as Dictionary)["x"]) - x
		var dy: float = float((p as Dictionary)["y"]) - y
		var d: float = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = int(e)
	return best


static func is_stockpile_tile(world: Variant, tx: int, ty: int) -> bool:
	if world.tilemap == null:
		return false
	if not SimTileMap.is_indoors(world.tilemap, tx, ty):
		return false
	if SimTileMap.tile_at(world.tilemap, tx, ty) != SimTileMap.Tile.Floor:
		return false
	# The stockpile is the annex's indoor floor, and where the annex is comes off the map now
	# rather than out of `SimDirector.ANNEX`. An unstamped district reports the empty rect, which
	# has no points -- so it has no stockpile, rather than one at somebody else's coordinates.
	var annex: Rect2i = SimTileMap.annex_rect(world.tilemap)
	if annex.size.x <= 0 or annex.size.y <= 0:
		return false
	return annex.has_point(Vector2i(tx, ty))


static func stockpile_items(world: Variant) -> Array[int]:
	var out: Array[int] = []
	for item in SimInventory.ground_items(world):
		var p: Variant = world.components.get_component(item, "position")
		if not p is Dictionary:
			continue
		if is_stockpile_tile(world, floori(float((p as Dictionary)["x"])), floori(float((p as Dictionary)["y"]))):
			out.append(item)
	return out


static func seek_kind(world: Variant, entity: int) -> String:
	if hold_max(world) or world.components.has_component(entity, "controlled"):
		return ""
	var n: Dictionary = of(world, entity)
	var best: String = ""
	var best_rank: int = 99
	# Relief sits between hunger and rest: more urgent than sleep, less urgent than the two needs
	# that can actually kill you, and cheap enough that letting it interrupt work is not a tax.
	var order: Array[String] = ["thirst", "hunger", "relief", "rest", "temperature", "hygiene"]
	for i in order.size():
		var k: String = order[i]
		var p: String = ""
		if k == "temperature" or k == "hygiene":
			p = band_pressure(k, String(n.get(k, "comfortable" if k == "temperature" else "clean")))
		else:
			p = pressure(float(n.get(k, 100.0)))
			if p == "seek" and float(n.get(k, 100.0)) > SEEK_NEVER_ABOVE:
				p = "ok"
		var rank: int = 99
		if p == "hard":
			rank = i
		elif p == "soft":
			rank = 10 + i
		elif p == "seek":
			rank = 20 + i
		if rank < best_rank:
			best_rank = rank
			best = k
	if best_rank >= 99:
		return ""
	# already recovering: stop seek at 80
	if POOLS.has(best):
		if float(n.get(best, 0.0)) >= SEEK_STOP and best_rank >= 20:
			return ""
	return best


static func hud_clause(world: Variant, entity: int, panel: bool = false) -> String:
	var n: Dictionary = of(world, entity)
	var first: bool = world.components.has_component(entity, "controlled")
	var name: String = "You"
	var ident: Variant = world.components.get_component(entity, "identity")
	if ident is Dictionary:
		name = String((ident as Dictionary).get("name", "They"))
	var picks: Array[Dictionary] = []
	_hud_pool(picks, "thirst", float(n.get("thirst", 100.0)), String(n.get("crisis", "none")), panel)
	_hud_pool(picks, "hunger", float(n.get("hunger", 100.0)), String(n.get("crisis", "none")), panel)
	_hud_pool(picks, "rest", float(n.get("rest", 100.0)), String(n.get("crisis", "none")), panel)
	_hud_pool(picks, "relief", float(n.get("relief", 100.0)), String(n.get("crisis", "none")), panel)
	_hud_band(picks, "temperature", String(n.get("temperature", "comfortable")), panel)
	_hud_band(picks, "hygiene", String(n.get("hygiene", "clean")), panel)
	if float(n.get("soiled", 0.0)) > 0.0:
		# Ranked above the pool's own "you need to go" and below the crisis lines: it has already
		# happened, so it is news, but it is not the thing about to kill anybody.
		# Phrased "You're <adjective>" like the grief line, so the third-person rewrite below turns
		# it into a glimpse of somebody rather than a report about them.
		picks.append({"rank": 8, "hud": "You're humiliated.", "panel": "You're humiliated — soiled, and needing a wash."})
	# Ranked between the pool rows above and the grief row below: a bad night is not the thing
	# about to kill anybody, but it is worse news than an ordinary need reading. Silent for a
	# `rested` night, the same convention every other band in this file already keeps -- a good
	# reading says nothing rather than congratulating itself.
	match String(n.get("slept", "up")):
		"broken":
			picks.append({"rank": 36, "hud": "You're groggy.", "panel": "You're groggy — last night's sleep was broken."})
		"barely_slept":
			picks.append({"rank": 34, "hud": "You're reeling.", "panel": "You're reeling — you barely slept last night."})
	# The stimulant's tell: below groggy (a bad night already had is worse news than a lift you
	# chose), above shaken. This is the rule the player can read -- the crash is coming, and the
	# word says so -- rather than a roll nobody can see.
	if int(n.get("stimulantUntilTick", -1)) > int(world.tick):
		picks.append({"rank": 38, "hud": "You're wired.", "panel": "You're wired — it will wear off, and then it will cost you."})
	# Wet: above the mild need rows (it is why the cold band is what it is) and below "very cold".
	if int(n.get("wetUntilTick", -1)) > int(world.tick):
		picks.append({"rank": 20, "hud": "You're soaked.", "panel": "You're soaked — a fire or a roof will dry you."})
	if world.modifiers != null:
		var mood: float = float(world.modifiers.call("resolve", "mood", entity))
		if float(n.get("grief", 0.0)) >= GRIEF_HEARD and mood > -80.0:
			# Phrased as "You're <adjective>" so the third-person rewrite below reads as a
			# glimpse of somebody else rather than a report about them.
			picks.append({"rank": 45, "hud": "You're shaken.", "panel": "You're shaken."})
		if mood <= -80.0 and not first:
			picks.append({"rank": -1, "hud": "They're going to leave.", "panel": "They're going to leave."})
		elif mood <= -25.0:
			picks.append({"rank": 50, "hud": "Mood is turning.", "panel": "Mood is turning."})
	if picks.is_empty():
		return ""
	picks.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	var line: String = String(picks[0]["panel" if panel else "hud"])
	if first:
		return line
	if line.begins_with("You're "):
		return name + " looks " + line.substr(7)
	if line.begins_with("They’re") or line.begins_with("They're"):
		return line
	return name + " — " + line


static func hud_panel(world: Variant, entity: int) -> PackedStringArray:
	# Full panel: every non-fine Need. HUD glimpse is worst only.
	var out: PackedStringArray = []
	var clause: String = hud_clause(world, entity, true)
	if not clause.is_empty():
		out.append(clause)
	return out


static func _hud_pool(picks: Array[Dictionary], key: String, v: float, crisis: String, _panel: bool) -> void:
	if key == "hunger":
		if crisis == "starving" or v <= 0.0:
			picks.append({"rank": 2, "hud": "You're starving.", "panel": "You're starving. You can't work."})
		elif v < SOFT:
			picks.append({"rank": 12, "hud": "You're hungry.", "panel": "You're hungry — work and aim are off."})
		elif v <= SEEK_STOP:
			picks.append({"rank": 22, "hud": "You're peckish.", "panel": "You're peckish."})
	elif key == "thirst":
		if crisis == "dehydrating" or v <= 0.0:
			picks.append({"rank": 1, "hud": "You're drying out.", "panel": "You're drying out."})
		elif v < SOFT:
			picks.append({"rank": 11, "hud": "You're thirsty.", "panel": "You're thirsty — work and aim are off."})
		elif v <= SEEK_STOP:
			picks.append({"rank": 21, "hud": "You're thirsty.", "panel": "You're thirsty."})
	elif key == "relief":
		# No crisis line: the pool never sits at empty, because emptying it is the accident. The
		# shame that follows speaks for itself, in hud_clause.
		if v < SOFT:
			picks.append({"rank": 16, "hud": "You badly need to go.", "panel": "You badly need to go — find a latrine."})
		elif v <= SEEK_STOP:
			picks.append({"rank": 26, "hud": "You need to go.", "panel": "You need to go."})
	elif key == "rest":
		if crisis == "passed_out" or v <= 0.0:
			picks.append({"rank": 3, "hud": "", "panel": "Collapsed. Sleeping where they fell."})
		elif v < SOFT:
			picks.append({"rank": 13, "hud": "You're exhausted.", "panel": "You're exhausted."})
		elif v <= SEEK_STOP:
			picks.append({"rank": 23, "hud": "You're tired.", "panel": "You're tired."})


static func _hud_band(picks: Array[Dictionary], key: String, band: String, _panel: bool) -> void:
	if key == "temperature":
		match band:
			"a_little_cold":
				picks.append({"rank": 24, "hud": "You're uncomfortable — cold.", "panel": "You're uncomfortable — cold."})
			"very_cold":
				picks.append({"rank": 14, "hud": "You're very cold.", "panel": "You're very cold."})
			"extremely_cold":
				# Its own words now that the band is reachable: it outranks "very cold" and used to
				# read identically to it, which would have made the deep band invisible in play.
				picks.append({"rank": 4, "hud": "You're freezing.", "panel": "You're freezing — get to a fire or indoors."})
			# The hot half, reachable since the sky got kinds (docs/adr/0016), on the cold half's
			# three ranks exactly, so hot and cold sort against the other needs identically.
			"a_little_hot":
				picks.append({"rank": 24, "hud": "You're uncomfortable — hot.", "panel": "You're uncomfortable — hot."})
			"very_hot":
				picks.append({"rank": 14, "hud": "You're overheating.", "panel": "You're overheating — find shade."})
			"extremely_hot":
				picks.append({"rank": 4, "hud": "Heatstroke — get out of the sun.", "panel": "Heatstroke — get out of the sun, and out of that armour."})
	elif key == "hygiene":
		match band:
			"a_little_dirty":
				picks.append({"rank": 25, "hud": "You're uncomfortable — unwashed.", "panel": "You're uncomfortable — unwashed."})
			"dirty":
				picks.append({"rank": 15, "hud": "You need a wash.", "panel": "You need a wash."})
			"filthy":
				picks.append({"rank": 5, "hud": "You're filthy.", "panel": "You're filthy. Don't cook. Don't treat."})
