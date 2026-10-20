class_name SimVisibility
extends RefCounted
## Who can see what — observer half of visibility primitive.
## Port of src/sim/vision/visibility.ts.
## One shadowcast per observer per tick at most, cached by tile+range+eye+generation.
## Geometry (shadowcast) + arcs (focal/peripheral dot product) + range check.

const SimTileMapRes = preload("res://sim/map/tilemap.gd")
const SimAimRes = preload("res://sim/aim.gd")
const Shadowcast = preload("res://sim/vision/shadowcast.gd")
const Clock = preload("res://sim/time/clock.gd")
const SimStancesRes = preload("res://sim/stances.gd")

enum Detail { Unseen = 0, Peripheral = 1, Focal = 2 }

var _views: Dictionary = {}
var recomputes: int = 0
## Observers whose eyes rest through the next `refresh`: their view is kept exactly as it stands,
## neither recast nor moved. `SimShambler`'s think marks a far body that will not think on the
## coming tick (FAR_THINK_EVERY), since nothing reads a zombie's view but its own think and the
## screamer's alarm, and neither can see a person 40 m away; `refresh` clears the marks it read.
## Derived inside the tick and never saved, so a restore rests the same bodies.
var resting: Dictionary = {}

## How far a `lit_target` observer (a zombie) walks from where it last cast before it casts
## again, in tiles (Chebyshev). See `refresh`.
const ZOMBIE_RECAST_TILES: int = 2

## Whether a dead observer a tile off its cast origin keeps its view across a map change its
## square never saw (see `refresh`). A gate-drivable static, like SimShambler's flags: a lane that
## pins it must restore it, one gate process sharing it across every world it boots.
static var DEAD_KEEP_VIEW: bool = true

## A person other than the player -- a colonist, a settler, a raider -- recasts once they have
## walked PERSON_RECAST_TILES from where they last cast, and that cast is spread over the next few
## ticks a quadrant at a time, PERSON_QUADRANTS_PER_TICK quadrants a tick for all of them together,
## the longest-waiting first. Their cast is the district's widest (48 m by day, ~7,000 cells, up to
## 6.5 ms of GDScript), and two of them crossing a tile on one tick was a 15 ms visibility step
## (A3's eighth slice). Until it lands they keep the view they had, a tile or two behind them --
## the approximation the dead already live with. The dead cast whole and at once, as they always
## have. STAGGER_PERSON_CASTS is the gate-drivable switch back to the old rule; a lane that pins it
## must restore it. One quadrant a tick since the eleventh slice: two of an open-ground cast were
## up to 2.8 ms on a tick that might also hold the player's, and a colonist re-queues only every
## two tiles, so the queue still drains.
const PERSON_RECAST_TILES: int = 2
const PERSON_QUADRANTS_PER_TICK: int = 1
static var STAGGER_PERSON_CASTS: bool = true
## Quadrants cast through that queue, and the most ticks any one person's cast took to land.
var quadrants_spread: int = 0
var longest_wait: int = 0

## The player's own cast, spread too since A3's eleventh slice, but only over two ticks: it still
## recasts on every tile it crosses, two quadrants on the tick it does and the other two on the
## next, landing whole there, so the view the screen cuts roofs and pools light from is one tick
## (50 ms) behind the step instead of current. It was the one whole 48 m cast left, about 3.5 ms on
## the tick the player crossed a tile. The first cast is whole, as a person's is. Its own budget,
## not the people's, so a colonist's queue can never hold the player's view back.
## STAGGER_PLAYER_CAST is the gate-drivable switch back to the whole cast; a lane that pins it must
## restore it.
const PLAYER_QUADRANTS_PER_TICK: int = 2
static var STAGGER_PLAYER_CAST: bool = true
## Quadrants cast for the player that way.
var player_quadrants: int = 0

## Daylight eyes — 48 m, 60° focal, 190° total FoV. Port of DAYLIGHT_EYES.
static func daylight_eyes() -> Dictionary:
	return {"range_metres": 48.0, "focal_half_angle": PI / 6.0, "peripheral_half_angle": 95.0 * PI / 180.0, "eye": 0}

## Shambler eyes — 12 m, mostly peripheral. Port of SHAMBLER_EYES, plus `lit_target`: a
## zombie's sight samples the light at the thing it is looking at, not at its own feet. The
## oracle's rule (`_sight_metres`: min(eyes, max(ambient, lit at the observer))) left every
## zombie 0.48 m of sight after dark and blind to a survivor under a floodlight -- the screamer's
## purpose inverted. The player's eyes keep the oracle's rule: `tiles_for(player)` is what cuts
## roofs out and pools the light wash, and a 48 m shadowcast at night would open every roof in
## sight. `check_m2_sight.gd` NIGHT-LIT pins both halves.
static func shambler_eyes() -> Dictionary:
	return {"range_metres": 12.0, "focal_half_angle": PI / 8.0, "peripheral_half_angle": 110.0 * PI / 180.0, "eye": 0, "lit_target": true}


func _map_generation(world: Variant) -> int:
	if world is Dictionary:
		return int(world.get("map_generation", 0))
	if world != null and "map_generation" in world:
		return int(world.map_generation)
	return 0


func _light_index(world: Variant) -> Variant:
	if world is Dictionary:
		return world.get("light")
	if world != null and "light" in world:
		return world.light
	return null


## The weather's sight multiplier arrives as a *parameter* rather than being read here: this
## module knows about walls, arcs and light, and has no business learning what a fog is
## (`attention.gd`'s idiom -- the field never learns what weather is either; SimBoot resolves
## `SimWeather.sight_mul` and hands it down). It scales `metres` and `cast_metres` together, so
## `range_squared` closes in for everybody and `full_squared` closes the lit-target escape with
## it: in fog the dead cannot see a lit survivor from any further than the fog lets the living
## see an unlit one, which is the symmetry docs/16 asks for. It is deliberately *not* folded
## into `_sight_metres` or `SimLight.sight_metres` -- their ratio against `range_metres` is the
## alpha of the night wash, so a fog hidden in there would paint midday in the night's colour.
## No extra invalidation is needed on the transition tick: `range_tiles` is part of the cache
## key, so a changed multiplier makes every observer's view stale and every one of them recasts.
func refresh(world: Variant, map: Variant, sight_mul: float = 1.0) -> void:
	var seen: Dictionary = {}
	var gen := _map_generation(world)
	# A world that logs where its map changed (world.gd's `map_unchanged_within`) lets a view cast
	# at an older generation stand when nothing changed inside its own square: the shadowcast reads
	# only tiles within `range_tiles` of its origin, so a door shutting across town cannot change
	# it. Before this one door swinging recast all 105 observers, a 200 ms tick (A3's second slice).
	var logs_changes: bool = world is Object and (world as Object).has_method("map_unchanged_within")
	# The hour's ambient factor, once for every observer rather than once each: it is a function
	# of the tick alone (A3's seventh slice).
	var now: int = _tick_of(world)
	var ambient_k: float = Clock.ambient_light_at(now)
	var queue: Array = []
	var player_queue: Array = []
	var light_index: Variant = _light_index(world)
	var rest: Dictionary = resting
	resting = {}
	# Six tables read straight (`SimComponentStore.table`, A3's tenth slice); a refresh writes
	# none of them.
	var positions: Dictionary = world.components.table("position")
	var observers: Dictionary = world.components.table("observer")
	var facings: Dictionary = world.components.table("facing")
	var aims: Dictionary = world.components.table("aim")
	var postures: Dictionary = world.components.table("posture")
	var controlled: Dictionary = world.components.table("controlled")
	for entity in world.components.query(["position", "observer"]):
		if rest.has(entity) and _views.has(entity):
			seen[entity] = true
			continue
		var pos: Variant = positions.get(entity)
		var obs: Variant = observers.get(entity)
		if pos == null or obs == null:
			continue
		# The eyes follow the head, and the head follows the aim (sim/aim.gd): a body walking one
		# way and looking another sees where it looks. An absent `aim` reads as `facing`, straight
		# off the table -- only a body the player has aimed carries one.
		var facing_rad: float = 0.0
		if aims.has(entity):
			facing_rad = SimAimRes.radians_of(world.components, entity)
		else:
			var facing_c: Variant = facings.get(entity)
			if facing_c != null:
				facing_rad = float((facing_c as Dictionary)["radians"])

		var tile_x: int = floori(float((pos as Dictionary)["x"]) / float(SimTileMapRes.TILE_METRES))
		var tile_y: int = floori(float((pos as Dictionary)["y"]) / float(SimTileMapRes.TILE_METRES))
		# Eye level follows the rung -- the write `SimStances.eye_of` existed for and nothing
		# called (docs/23's dead-socket list). Port of `stance.eyes` (src/sim/modules/stance.ts):
		# crouch and crawl look from Eye.Crouched, everything else from Eye.Standing, so docs/28's
		# Low occluder class finally has something to be low *relative to*. An entity with no
		# posture (a zombie; a fixture that never gave one) keeps whatever its `observer` record
		# was built with, which is `Eye.Standing` for every spawner in the tree today.
		var posture_c: Variant = postures.get(entity)
		if posture_c != null:
			(obs as Dictionary)["eye"] = SimStancesRes.eye_of(int((posture_c as Dictionary)["current"]))
		var lit_target: bool = bool((obs as Dictionary).get("lit_target", false))
		# A lit-target observer's ambient reach is ambient alone: standing in a light does not
		# let the dead see further into the dark (the light at the *target* is what `detail`
		# asks), and `lit_metres` walks every source in the district -- eighty observers asking
		# it every tick was the cost the eyes slice's driver found.
		var metres: float = (_ambient_metres(world, obs as Dictionary, ambient_k) if lit_target else _sight_metres(world, obs as Dictionary, float((pos as Dictionary)["x"]), float((pos as Dictionary)["y"]), ambient_k)) * sight_mul
		# A lit-target observer casts at its eyes' full reach: the geometry is walls, and whether
		# a tile inside it is *seen* is decided per target in `detail`, by distance or by light.
		# The sky's multiplier lands on that reach once and once only -- the non-lit arm is
		# `metres`, which already carries it.
		var cast_metres: float = float((obs as Dictionary)["range_metres"]) * sight_mul if lit_target else metres
		var range_tiles: int = SimTileMapRes.tile_range(cast_metres)
		var eye: int = int((obs as Dictionary)["eye"])

		var view: Variant = _views.get(entity)
		if view == null:
			view = {
				# The cache key, as five ints rather than one formatted string: with eighty
				# observers this comparison runs eighty times a tick, and formatting a String
				# for each was a measurable share of a 256-tile step (the eyes slice's driver).
				"tile_x": -1, "tile_y": -1, "range_tiles": -1, "eye": -1, "gen": -1,
				"tiles": Shadowcast.VisibleTiles.new(),
				"x": 0.0, "y": 0.0,
				"facing_x": 1.0, "facing_y": 0.0,
				"cos_focal": 1.0, "cos_peripheral": 1.0,
				"range_squared": 0.0,
				"full_squared": 0.0, "lit_target": false, "light": null,
				# Bumped every time the shadowcast below actually recomputes. The remembered-map
				# merge (SimSightings) pays for a base64 decode/re-encode only on the tick this
				# changes -- `cast_generation` is its read of the same counter, so a body that has
				# not moved costs that merge nothing.
				"cast_gen": 0,
			}
			_views[entity] = view

		var vd: Dictionary = view as Dictionary
		# The dead recast only once they have walked ZOMBIE_RECAST_TILES from where they last
		# cast, on the same map and range: a 12-tile cast is ~1.5 ms of GDScript and eighty
		# bodies crossing tiles cast ~2.6 times a tick, a third of a 256-tile step (the eyes
		# slice's driver). Walls a tile or two off their true offset are an approximation the
		# dead can afford; a person's cast moves with their tile as it always has.
		var moved: int = maxi(absi(tile_x - int(vd["tile_x"])), absi(tile_y - int(vd["tile_y"])))
		var stale: bool = int(vd["range_tiles"]) != range_tiles or int(vd["eye"]) != eye
		var cast_tiles: int = int(vd["range_tiles"])
		# A person moves their cast with their tile, so a person who keeps a view here is one still
		# on the tile they cast from, and the kept cells are exactly what a recast would give. The
		# dead may be up to a tile off their origin (ZOMBIE_RECAST_TILES above) and keep that view
		# across a bump too -- the same tile-or-so approximation they already live with between
		# bumps. Before this, every bump recast every dead body a tile off its origin, which is
		# half the district on a door swing and every tile a car crosses: a 140 ms tick. It is the
		# one place A3 changes behaviour rather than cost (docs/22's "Bringing the tick to
		# budget"), and DEAD_KEEP_VIEW is the gate-drivable switch back to the old rule.
		if not stale and int(vd["gen"]) != gen and moved > 0 and not (lit_target and DEAD_KEEP_VIEW):
			stale = true
		if not stale and int(vd["gen"]) != gen:
			var square := Rect2i(int(vd["tile_x"]) - cast_tiles, int(vd["tile_y"]) - cast_tiles, cast_tiles * 2 + 1, cast_tiles * 2 + 1)
			if logs_changes and world.map_unchanged_within(int(vd["gen"]), square):
				vd["gen"] = gen
			else:
				stale = true
		# A person who is not the player, and who has a view already: a view never cast is not a
		# tile behind but blind, so it is cast whole like the player's.
		var is_player: bool = controlled.has(entity)
		var spread: bool = STAGGER_PERSON_CASTS and not lit_target and cast_tiles >= 0 and not is_player
		var player_spread: bool = STAGGER_PLAYER_CAST and not lit_target and cast_tiles >= 0 and is_player
		if spread or player_spread:
			if vd.get("pending") == null and (stale or (moved >= PERSON_RECAST_TILES if spread else moved > 0)):
				if vd.get("back") == null:
					vd["back"] = Shadowcast.VisibleTiles.new()
				vd["pending"] = [now, int(entity), tile_x, tile_y, range_tiles, eye, gen, Shadowcast.Quadrant.North]
			if vd.get("pending") != null:
				(queue if spread else player_queue).append(vd["pending"])
		elif stale or (moved >= ZOMBIE_RECAST_TILES if lit_target else moved > 0):
			Shadowcast.shadowcast(map, tile_x, tile_y, range_tiles, vd["tiles"] as Shadowcast.VisibleTiles, eye)
			vd["pending"] = null
			_landed(vd, tile_x, tile_y, range_tiles, eye, gen)

		(view as Dictionary)["x"] = float((pos as Dictionary)["x"])
		(view as Dictionary)["y"] = float((pos as Dictionary)["y"])
		(view as Dictionary)["facing_x"] = cos(facing_rad)
		(view as Dictionary)["facing_y"] = sin(facing_rad)
		# The arcs' cosines change only when the eyes do, which is never for most bodies: kept
		# beside the angle they came from rather than taken twice a body a tick (A3's eighth slice).
		var fh: float = float((obs as Dictionary)["focal_half_angle"])
		if float(vd.get("focal_half", NAN)) != fh:
			vd["focal_half"] = fh
			vd["cos_focal"] = cos(fh)
		var ph: float = float((obs as Dictionary)["peripheral_half_angle"])
		if float(vd.get("peripheral_half", NAN)) != ph:
			vd["peripheral_half"] = ph
			vd["cos_peripheral"] = cos(ph)
		(view as Dictionary)["range_squared"] = metres * metres
		(view as Dictionary)["full_squared"] = cast_metres * cast_metres
		(view as Dictionary)["lit_target"] = lit_target
		(view as Dictionary)["light"] = light_index if lit_target else null
		seen[entity] = true

	# The people's queue: longest-waiting first, ties by id, so it is deterministic and nobody
	# waits behind somebody who started walking later. A pending cast is [since, entity, tile_x,
	# tile_y, range_tiles, eye, gen, next quadrant], cast into the view's back buffer and swapped
	# in whole once its fourth quadrant lands -- `tiles_for` never hands out half a circle.
	queue.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	quadrants_spread += _spend(map, queue, PERSON_QUADRANTS_PER_TICK, now, true)
	player_quadrants += _spend(map, player_queue, PLAYER_QUADRANTS_PER_TICK, now, false)

	for entity in _views.keys():
		if not seen.has(entity):
			_views.erase(entity)


# Cast `budget` quadrants of the pending casts in `queue`, in order, into each view's back buffer,
# swapping a view in whole once its fourth lands. Returns the quadrants cast. `people` is whether
# this is the people's queue, whose waits `longest_wait` reports.
func _spend(map: Variant, queue: Array, budget: int, now: int, people: bool) -> int:
	var spent: int = 0
	for pend in queue:
		if budget <= 0:
			break
		var pd: Dictionary = _views[int(pend[1])] as Dictionary
		var q: int = int(pend[7])
		var last: int = mini(int(Shadowcast.Quadrant.West), q + budget - 1)
		Shadowcast.shadowcast(map, int(pend[2]), int(pend[3]), int(pend[4]), pd["back"] as Shadowcast.VisibleTiles, int(pend[5]), q, last)
		budget -= last - q + 1
		spent += last - q + 1
		if last < int(Shadowcast.Quadrant.West):
			pend[7] = last + 1
			continue
		var done: Variant = pd["back"]
		pd["back"] = pd["tiles"]
		pd["tiles"] = done
		pd["pending"] = null
		if people:
			longest_wait = maxi(longest_wait, now - int(pend[0]) + 1)
		_landed(pd, int(pend[2]), int(pend[3]), int(pend[4]), int(pend[5]), int(pend[6]))
	return spent


# A cast has landed in `tiles`: the view's key now names where and how it was cast.
func _landed(vd: Dictionary, tile_x: int, tile_y: int, range_tiles: int, eye: int, gen: int) -> void:
	vd["tile_x"] = tile_x
	vd["tile_y"] = tile_y
	vd["range_tiles"] = range_tiles
	vd["eye"] = eye
	vd["gen"] = gen
	vd["cast_gen"] = int(vd["cast_gen"]) + 1
	recomputes += 1


func _tick_of(world: Variant) -> int:
	if world is Dictionary:
		return int(world.get("tick", 0))
	if world != null and "tick" in world:
		return int(world.tick)
	return 0


# `ambient_k`, when not negative, is `Clock.ambient_light_at` of this tick, already read by the
# caller (`refresh` reads it once for every observer).
func _ambient_metres(world: Variant, observer: Dictionary, ambient_k: float = -1.0) -> float:
	if ambient_k < 0.0:
		ambient_k = Clock.ambient_light_at(_tick_of(world))
	return float(observer["range_metres"]) * ambient_k


func _sight_metres(world: Variant, observer: Dictionary, x: float, y: float, ambient_k: float = -1.0) -> float:
	if ambient_k < 0.0:
		var tick: int = 0
		if world is Dictionary:
			tick = int(world.get("tick", 0))
		elif world != null and "tick" in world:
			tick = int(world.tick)
		ambient_k = Clock.ambient_light_at(tick)
	var ambient: float = float(observer["range_metres"]) * ambient_k
	var lit: float = 0.0
	var light_idx: Variant = _light_index(world)
	if light_idx != null:
		lit = light_idx.lit_metres(x, y)
	return min(float(observer["range_metres"]), max(ambient, lit))


## How many times this observer's shadowcast has actually recomputed, or -1 for an observer with
## no view at all (never refreshed). A body standing still reads the same number tick after tick;
## the remembered-map merge in `sightings.gd` uses that to skip its own cost on every tick but the
## one where the geometry genuinely changed.
func cast_generation(observer: int) -> int:
	var v: Variant = _views.get(observer)
	if v == null:
		return -1
	return int((v as Dictionary).get("cast_gen", 0))


func tiles_for(observer: int) -> Variant:
	var v: Variant = _views.get(observer)
	if v == null:
		return null
	return (v as Dictionary)["tiles"]


func detail(observer: int, x: float, y: float) -> int:
	var view: Variant = _views.get(observer)
	if view == null:
		return Detail.Unseen
	var tiles: Variant = (view as Dictionary)["tiles"]
	var has: bool = (tiles as Shadowcast.VisibleTiles).has_tile(floori(x / float(SimTileMapRes.TILE_METRES)), floori(y / float(SimTileMapRes.TILE_METRES)))
	if not has:
		return Detail.Unseen
	var dx: float = x - float((view as Dictionary)["x"])
	var dy: float = y - float((view as Dictionary)["y"])
	var d2: float = dx * dx + dy * dy
	if d2 > float((view as Dictionary)["range_squared"]) and not _lit_in_reach(view as Dictionary, d2, x, y):
		return Detail.Unseen
	if d2 == 0.0:
		return Detail.Focal
	var cosine: float = (dx * float((view as Dictionary)["facing_x"]) + dy * float((view as Dictionary)["facing_y"])) / sqrt(d2)
	if cosine >= float((view as Dictionary)["cos_focal"]):
		return Detail.Focal
	if cosine >= float((view as Dictionary)["cos_peripheral"]):
		return Detail.Peripheral
	return Detail.Unseen


# The lit-target half of `detail`: beyond the ambient reach, a `lit_target` observer still sees
# a target whose own tile is lit, out to its eyes' full range. The shadowcast (walls) has
# already been asked by the caller; this is only the range question.
func _lit_in_reach(view: Dictionary, d2: float, x: float, y: float) -> bool:
	if not bool(view.get("lit_target", false)):
		return false
	if d2 > float(view.get("full_squared", 0.0)):
		return false
	var light_idx: Variant = view.get("light")
	if light_idx == null:
		return false
	return float(light_idx.lit_metres(x, y)) > 0.0


func can_see(observer: int, x: float, y: float) -> bool:
	return detail(observer, x, y) != Detail.Unseen


func observer_count() -> int:
	return _views.size()


## Geometry only — walls and range, with no facing arc. What a bullet is stopped by, which is not
## the same question as what an observer is looking at: `detail` narrows by focal and peripheral
## cones because attention is directional, and a shot leaving a barrel is not. `ranged.gd` and,
## through it, `npc_combat.gd` ask this one; anything about *noticing* something asks `detail`.
## Unseen for an observer with no view at all — callers that must stay permissive for a fixture
## without eyes check `tiles_for` first, which is the one thing that distinguishes "no eyes" from
## "eyes, and a wall".
func line_of_sight(observer: int, x: float, y: float) -> bool:
	var view: Variant = _views.get(observer)
	if view == null:
		return false
	var tiles: Variant = (view as Dictionary)["tiles"]
	if not (tiles as Shadowcast.VisibleTiles).has_tile(floori(x / float(SimTileMapRes.TILE_METRES)), floori(y / float(SimTileMapRes.TILE_METRES))):
		return false
	var dx: float = x - float((view as Dictionary)["x"])
	var dy: float = y - float((view as Dictionary)["y"])
	return dx * dx + dy * dy <= float((view as Dictionary)["range_squared"])
