extends RefCounted
# The run's lifecycle: which world is standing, and which of the four states the game is in.
#
# This is the second half of the alpha shell's "net first, split second" (docs/30, "The alpha
# shell, 2026-09-16") -- the input split took the keys out of `main.gd`, and this takes the run
# out of it. Booting a world, starting a new one, writing the save and reading it back were four
# methods on a 2,000-line scene node that also owned the drawing; they are here, with the state
# machine that says when each of them is allowed to happen. `main.gd` keeps the screen.
#
# It is a `RefCounted` and not a Node on purpose: nothing here wants a frame, a notification or a
# place in the tree. `main.gd` owns one of these and asks it questions.
#
# **`main.gd` keeps its own plain `var world`**, assigned after every transition. Sixteen gates
# and `test/project_smoke.gd` read `main.get("world")` one frame after instantiating the scene,
# and a field that became `session.world` would have turned every one of them into a dead socket
# at once. The duplication is deliberate and it is one line in `_on_world_replaced`.
#
# Nothing in this file reads presentation state, and nothing in it draws. The sim is written
# through `SimBoot` and `SimSave` and in no other way.

const SimBoot = preload("res://sim/boot.gd")
const SimTileMap = preload("res://sim/map/tilemap.gd")
const SimSave = preload("res://sim/save.gd")
const PlatformStorage = preload("res://platform/storage.gd")
const Clock = preload("res://sim/time/clock.gd")

# TITLE is drawn *over* a booted world, never instead of one: the smoke and the HUD gates assert
# `main.get("world") != null` one frame after instantiation, so a deferred boot would have been a
# red chain the moment the title landed. The title is a state, and the district behind it is real.
enum State { TITLE = 0, PLAYING = 1, PAUSED = 2, RUN_OVER = 3 }

const TICK_HZ: int = 20

# What the title says when a save will not load. One fixed sentence, never the decoder's own
# message: `SimSave.decode_save` says "save format 31, this build reads 32", which is both a digit
# on a player's screen and a number that means nothing to the person reading it.
const STALE_NOTICE: String = "that save was written by another version of the game"
const CORRUPT_NOTICE: String = "that save could not be read"

var state: int = State.TITLE
var world: Variant = null
# The map object `SimBoot` hands back beside the world. **Nothing reads it** -- it was `main.gd`'s
# `_map`, written by every boot since the district landed and read by no line of the game, and it
# is carried across rather than quietly deleted because that is a separate decision from this
# slice's. Named here so it is a socket somebody can see, not one somebody has to find again; the
# drawing reaches the same map through `world.tilemap`.
var map: Variant = null
var fixture: Dictionary = {}
var district_id: String = SimBoot.DEFAULT_DISTRICT
var region_id: String = ""
var seed: int = SimBoot.DISTRICT_SEED
# Why the last `load()` said no, as a sentence the title can print, or "" when it said yes.
var notice: String = ""


# Boots (or reboots) the playable world on a given seed and district. This is the one boot path:
# `main.gd`'s `_ready` calls it once at startup and the shell's "new run" calls it again, and
# nothing about standing a world up may live anywhere else.
#
# It does not touch the UI, the camera or the caches over the old world -- those are presentation
# and they belong to `main.gd`'s `_on_world_replaced`, which runs after every call to this.
func boot(seed_val: int, district: String, region: String = "") -> void:
	region_id = region
	var booted: Dictionary = SimBoot.playable_region(seed_val, region) if not region.is_empty() else SimBoot.playable(seed_val, SimTileMap.DISTRICT_TILES, district)
	world = booted["world"]
	map = booted["map"]
	fixture = {"seed": int(world.seed), "tick_hz": TICK_HZ}
	district_id = district
	seed = seed_val
	notice = ""


# The fixed default town, from the title, the pause menu and the run-over screen alike -- the
# owner's decision of 2026-09-16. It is deliberately *not* a reroll: F2 used to boot a random
# seed and was deleted with the same decision, because a new run that lands somewhere else every
# time is a game nobody can learn and nobody can report a bug against.
func new_run() -> void:
	boot(SimBoot.DISTRICT_SEED, district_id, region_id)


# The save slot, written. Returns whether anything was written, so the autosave edge below and
# the menu's own row can both say what happened rather than assume it.
func save() -> bool:
	if world == null:
		return false
	PlatformStorage.write_save(SimSave.encode_save(SimSave.create_save(world)))
	return true


# The save slot, read back into the standing world. Returns false and sets `notice` when it will
# not load, so the title can say one sentence and stay where it is.
func load() -> bool:
	notice = ""
	if world == null:
		return false
	var raw: String = PlatformStorage.read_save()
	if raw.is_empty():
		return false
	var parsed: Dictionary = SimSave.decode_save(raw)
	if parsed.has("__error"):
		notice = STALE_NOTICE if String(parsed["__error"]) == "StaleSaveError" else CORRUPT_NOTICE
		return false
	var snap: Variant = parsed.get("snapshot", {})
	if snap is Dictionary and bool((snap as Dictionary).get("runOver", false)):
		# A run that ended is not a run to go back to. The title does not offer it either --
		# `has_continue` asks the same question of the same file.
		return false
	if bool(world.runOver):
		return false
	SimSave.apply_save(world, parsed)
	return true


# Is there a run to continue? A slot that exists, decodes, and is not the wreck of a finished
# run. Static because the title asks it before anything has been loaded, and it answers off the
# file rather than off the world standing behind the menu.
static func has_continue() -> bool:
	var raw: String = PlatformStorage.read_save()
	if raw.is_empty():
		return false
	var parsed: Dictionary = SimSave.decode_save(raw)
	if parsed.has("__error"):
		return false
	var snap: Variant = parsed.get("snapshot", {})
	if not (snap is Dictionary):
		return false
	return not bool((snap as Dictionary).get("runOver", false))


# The autosave edge: the first tick of a day. Called once a frame with the tick the frame began
# on and the tick it ended on, because a frame carries as many as fifty ticks at speed ten and
# the edge can fall anywhere inside it -- asking "is it dawn now" would miss the crossing and
# then write a save on every one of the ticks after it that is still dawn.
#
# A finished run never writes: the slot would be a run-over save, `has_continue` would refuse it
# and the player would be left with a title offering nothing where a moment ago there was a run.
func autosave_if_dawn(prev_tick: int, tick: int) -> bool:
	if world == null or bool(world.runOver):
		return false
	if not crossed_into_dawn(prev_tick, tick):
		return false
	return save()


# Did any tick in (prev, tick] begin a dawn? Phase-derived rather than arithmetic on DAY_TICKS:
# the clock owns where dawn is, and a modulo here would be a second copy of that decision.
static func crossed_into_dawn(prev_tick: int, tick: int) -> bool:
	if tick <= prev_tick:
		return false
	for t in range(prev_tick + 1, tick + 1):
		if Clock.phase_of(t) == Clock.Phase.Dawn and Clock.phase_of(t - 1) != Clock.Phase.Dawn:
			return true
	return false


func enter(next: int) -> void:
	state = next


# A run is standing and has not ended: the question "quit to title" and the window's close
# request both ask before they autosave.
func is_live() -> bool:
	return state == State.PLAYING or state == State.PAUSED
