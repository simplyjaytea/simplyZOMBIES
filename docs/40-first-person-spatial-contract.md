# 40 — First-person spatial combat and perception: the engineering contract

*Why this exists: [docs/39](39-first-person-pivot.md#spatial-combat-and-perception) asks for one
authority for collision, shot obstruction, melee reach, body-part hits and perception, so that the
3D camera and the sim cannot disagree. Today there are three obstruction answers, none of them has
a height, and the first-person view draws geometry the sim does not have. This document names the
one authority, the height model it reads, the slices that build it, and the calls that are the
owner's rather than ours.*

This is a contract for work not yet built. Nothing here has shipped; docs/23 owns that evidence.
Points marked **(engineering)** are choices this contract makes and a slice may revise with a
reason. Points marked **(owner)** are design questions, collected in
[What the owner decides](#what-the-owner-decides) with a recommended default each. A slice that
needs an owner answer does not start until it has one.

## What the code does today

Every claim below was read on `main` at `95717d9a` (the foundation scene on
`origin/pivot/first-person-foundation`).

- **Movement** is `SimWorld._integrate_movement` (`godot/sim/world.gd`): an axis-separated box of
  half-width `BODY_RADIUS` 0.35 m tested at its two leading corners against `map_cells`, which
  `adopt_map` fills from `SimTileMap.is_solid`. It has no height. A `Tile.Low` tile is not
  solid (`SimTileMap.SOLID`), so a body walks through a car; worldgen writes cars as `Tile.Low`
  on purpose (`worldgen.gd`, `_vehicle_tails`' header: "cover you can shoot over").
- **Sight** is `SimVisibility.refresh` (`godot/sim/vision/visibility.gd`) running
  `SimShadowcast.shadowcast` per observer on integer tiles, cached per tile, with one height bit:
  `observer.eye`, written from posture by `SimStances.eye_of` (crouch and crawl give
  `Eye.Crouched`). `SimTileMap.blocks_sight` makes `Opacity.Low` opaque to a crouched eye only.
  `detail` then adds range, light and the focal/peripheral arcs. **The target's stance is never
  asked**: a standing zombie sees a crouched survivor behind a car, which contradicts docs/29's
  "sight blocked by Low cover, in both directions".
- **Shot obstruction** is `SimRanged.can_target` (`godot/sim/modules/ranged.gd`) calling
  `SimVisibility.line_of_sight`: is the target's tile in the shooter's shadowcast set, inside
  range. `_fire_shot` then takes the **nearest living body inside the cone** (`coneHalf`, from
  `_refresh_cone`) and hits it with certainty; no direction is drawn. The part is
  `rng.next() < 0.2` head, else torso, on the `ranged` stream.
- **Melee reach** is `SimMelee._resolve_strike` (`godot/sim/modules/melee.gd`): nearest body
  within `reachMetres + MELEE_REACH_FUDGE` (0.35) and inside `SimCombat.COS_SWING_HALF_ANGLE`.
  **It asks no obstruction question at all.** Two bodies pressed to either face of a one-metre wall
  are 1.70 m apart, inside the default 1.75 m, so a swing lands through the wall. The part is
  `_roll_body_part` over `SimCombat.SURVIVOR_HIT_LOCATION_WEIGHTS` or `HIT_LOCATION_WEIGHTS`.
- **Zombie contact** is `SimShambler._clear_contact` (`godot/sim/modules/shambler.gd`): three
  samples along the segment against `world.is_blocked_tile`, i.e. solidity, not opacity. So the
  zombie's reach is refused by a window and the survivor's is not.
- **NPC combat** (`godot/sim/modules/npc_combat.gd`) picks threats with `_nearest_threat` and
  `_ordered_target`, both gated on `SimRanged.can_target`; `can_strike`'s melee arm is distance
  alone. Zombies and the screamer perceive through `vision.detail` (`shambler.gd`,
  `screamer.gd`).
- **Aim** is one angle: the `aim` command lands in `SimWorld` and goes through `SimAim.propose`
  (`godot/sim/aim.gd`), which holds an aim apart from the heading only at Walk or slower. The
  foundation pushes `{"type": "aim", "radians": atan2(dir.z, dir.x)}` from `_push_aim` and keeps
  pitch in presentation only.
- **The foundation view** (`district_view.gd`, `_solid_surface`) draws a box only where
  `is_solid` is true. So its `Tile.Low` and `Tile.Screen` arms are unreachable: cars and thickets
  are invisible though the sim treats them as cover and as opaque. A window is drawn as a
  full-height 2.55 m box that the sim sees and shoots through. An open door draws nothing, so
  there is no lintel. The camera sits at a fixed `EYE_HEIGHT_M` 1.62 whatever the stance, and
  `body_view.gd` draws bodies at radius 0.30 against the sim's 0.35.
- **Save**: `SimSerialize.SAVE_VERSION` is 33 (`godot/sim/kernel/serialize.gd`). An optional key on
  an existing component has been added repeatedly without a bump (the tourniquet, the walk home).

## The one authority

**(engineering)** A new pure sim module, `godot/sim/space/space.gd` (`class_name SimSpace`), owns
every spatial question with a height. It reads the tile map and the overlays `SimFortify.sync_map`
already writes, and nothing else. It owns:

1. **The profile**: for a tile index, the solid and opaque bands it occupies, in integer
   millimetres, over a full-tile footprint. One table, `SimSpace.PROFILE`, keyed by tile class and
   overlay kind and stage.
2. **`segment_clear(map, a, b, purpose)`**: whether the segment between two points (metres x/y,
   millimetre height) passes every band. `purpose` is `Sight`, `Shot` or `Reach`, because opacity
   and solidity are different properties (docs/28) and a band declares which purposes it stops.
3. **`ray_first_hit(world, origin, direction, reach, ignore)`**: the first band or body cylinder a
   ray meets, returning the point, the tile or entity, and the height of contact.
4. **Body volumes**: `SimSpace.body_of(world, entity)` is a vertical cylinder of radius
   `HIT_RADIUS` and a height from posture, or from zombie state.
5. **Eye points**: `SimSpace.eye_of(world, entity)`, the eye height from posture.

Movement stays `SimWorld._integrate_movement` against `map_cells`. It needs no height on one floor,
and the profile is defined so a tile that is solid for movement is a full-footprint band from 0
upward. **The presentation builds its geometry from `SimSpace.PROFILE` and from nothing else**,
and draws bodies at `SimSpace.body_of`. That is the whole agreement mechanism: the camera renders
the same bands the sim traces, so a ray that is blocked on screen is blocked in the sim. The
presentation never decides a hit, a reach or a sighting. It draws what the sim publishes.

Every current answer routes through it. `SimRanged.can_target`, `SimMelee._resolve_strike`,
`SimShambler._clear_contact`, `npc_combat.can_strike` and `SimVisibility.detail` ask `SimSpace`.
No module keeps a private obstruction test. A gate's READS lane (below) asserts each one does.

## The height model

Metres on the ground plane and millimetres for height, as integers (docs/37: a boundary compared
byte for byte is not decided in float). Sim x/y map to Godot x/z; Godot +Y is height; one tile is
one metre (`SimTileMap.TILE_METRES`). One walkable floor at height 0. The proposed values are
**(engineering)** starting points chosen to satisfy rules that already exist; their meaning is
**(owner)** question 3.

| Profile entry | Bands (mm) | Movement | Sight | Shot, reach |
|---|---|---|---|---|
| Wall, closed door, scrap, timber, stone | 0–2550 | blocks | blocks | blocks |
| Window (no board) | 0–1000 and 2100–2550 | blocks | through 1000–2100 | through 1000–2100 |
| Board, stages 0–2 | 0–2550 | blocks | blocks | blocks |
| Board, stage 3 (today `Opacity.Low`) | 0–1100 and 2100–2550 | blocks | above 1100 | above 1100 |
| Open door, broken door | 2200–2550 (lintel) | open | under 2200 | under 2200 |
| Wire fence | 0–2000, transparent | blocks | through | through (reach blocked) |
| Low (car, low wall, rubble) | 0–1100 | open today, **(owner)** Q4 | above 1100 | above 1100 |
| Screen (curtain, foliage) | 0–2550, opaque, not solid | open | blocks | stops a shot, not a reach |
| Tree | 0–2550 over the full tile | blocks | blocks | blocks |
| Deep water | none above 0 | blocks | through | through |

These rules fix the numbers: Low's top (1100) is above a crouched eye, or the existing rule that
Low cover blinds a crouching body is false on screen. A window sill (1000) is above a crouched eye,
so crouching under a window hides you. A lintel matters only at steep pitch. A tree is a full-tile
column because the sim's tree is a full opaque tile; the view must not draw a thin trunk with gaps
the sim treats as opaque.

| Body | Eye (mm) | Cylinder height (mm) |
|---|---|---|
| Survivor at Walk, Jog, Sprint | 1620 | 1750 |
| Survivor crouched | 950 | 1150 |
| Survivor crawling | 300 | 450 |
| Shambler | 1450 | 1650 |
| Zombie whose legs are destroyed (docs/14's crawler) | 300 | 450 |

`HIT_RADIUS` is 300 mm, the radius the foundation draws, and stays separate from the 0.35 m
movement box, which is not changed. **(engineering)** During a stance change the sim uses the rung
`posture.current` names. The camera interpolates between the previous and current tick's eye height,
exactly as it interpolates position, so it is never ahead of the sim.

## Aim: yaw and pitch

**(engineering)** The `aim` command gains an optional `pitch` in radians, clamped to ±1.30 (the
foundation's `PITCH_LIMIT`) and collapsed through `SimAim.canonical` so a negative zero never
reaches the serializer. The `aim` component carries it as an optional key; `SimAim.pitch_of` reads
it and an absent key reads 0, so every fixture, every NPC and every headless campaign describes the
world it did before. `SimAim.propose` writes yaw and pitch together or neither, so a refused aim
leaves no half-written pitch. `SimAim.follow_facing` leaves pitch alone; snapping yaw to the
heading does not tilt the head. An NPC that faces a target (`npc_combat._face`) sets pitch toward
the target's chest through `SimSpace`; one facing a remembered place (`_face_at`) aims at standing
chest height. A zombie never carries an aim. Slice 3 found that an NPC has no aim to carry a pitch
on, so a colonist's aim holds a pitch and no yaw, and reads its facing for the yaw (docs/30, "A
pitch with no yaw").

The yaw rule is unchanged and it has a first-person consequence. At Jog, `SimAim.holds` is false
and `_integrate_movement` snaps aim to the heading, so a player who strafes at a jog while looking
ahead holds an aim the camera does not show. The contract forbids a shot down that hidden aim.
**(engineering)** While the sim aim and the camera's pushed aim differ, the view draws the weapon
lowered, and the fire and swing commands carry the yaw and pitch they were pressed with. The sim
refuses them, with a reason, when `SimAim.propose` would refuse that aim. Whether running should
instead keep the aim on the camera is **(owner)** question 5.

## The shot

**(engineering, subject to owner question 1)** `_fire_shot` stops choosing the nearest body in the
cone. At release it:

1. takes the origin as `SimSpace.eye_of(shooter)`. The round leaves the sight line, not a modelled
   muzzle, so the centre of the view is the line the round starts on. The barrel is drawn, never
   traced;
2. draws a deviation within the cone from a **new named stream, `ranged.spread`**: two draws, a
   uniform point in the disc of half-angle `coneHalf × DISPERSION`, applied to yaw and pitch.
   `_refresh_cone`, the twist, the ammo scaling and the cap are untouched, so `godot:m2:aim` keeps
   judging the number the dispersion is drawn from. `DISPERSION` is one named constant set by a
   measured balance slice;
3. calls `SimSpace.ray_first_hit` out to `rangeMetres` against bands that stop a `Shot` and against
   the cylinders of living bodies, with the shooter ignored. The first contact wins;
4. publishes `weapon.fired` with its existing keys and, beside them, the origin height, the pitch
   and the contact point `ex, ey, ez`. A body hit publishes `attack.connected` exactly as today.

`can_target` keeps its permissive no-eyes branch. It still gates the NPC's decision to fire,
because a colonist must not turn and shoot at what it cannot see. It no longer gates the round:
geometry does. That is a change with a reach beyond the camera: a round fired into the dark, or
past a corner the cast does not see round, can now strike a body the shooter cannot see. docs/09
allows the shot, and owner question 1 covers the hit. The view draws the tracer and the decal from
`weapon.fired` alone, so the drawn impact is the sim's impact by construction. A body the player
cannot see is never revealed by being hit: the tracer simply ends. Noise, flash, wear, brass,
jams, falloff (`keep`) and recoverable arrows are unchanged. Falloff now takes the ray distance to
contact.

The `ranged` stream keeps its draw order: the jam roll, then the part roll and the recovery roll,
unless owner question 2 removes the part roll for shots. The slice that does so records it. The
spread draws live on their own stream so that no existing stream moves for them.

## Melee reach

**(engineering)** `_resolve_strike` keeps its reach, its arc, its nearest-first choice, its
`melee` stream and its single part roll. One test is added: a candidate counts only if
`SimSpace.segment_clear(a, b, Reach)` holds from the attacker's shoulder (eye minus 400 mm) to the
target cylinder's mid-height or its chest (three quarters of its height). Slice 2 added the chest:
to the mid-height alone, a standing shoulder dips under the sill inside the window tile, so no
window swing could land (docs/30, "The reach arrives at the chest as well as the middle"). Swings
through walls stop. A swing through an unboarded window
works, because the window passes `Reach` at 1000–2100 mm. A crouched swing under a sill does not.
`SimShambler._clear_contact` becomes the same call, and `godot:m2:swipe` and `godot:m2:contact`
must stay green unchanged. It is not the same answer everywhere a full-height band stands: the old
test sampled three points on the line, so a wall corner the line clipped between them did not stop
a claw or a grab, and the tile walk now does (slice 2, `godot:m2:space` CLIPPED).
`npc_combat.can_strike`'s melee arm asks the same test, so a colonist stops walking where the blow
will actually land. Pitch does not move a swing's target **(owner)**, question 2.

## Body-part selection

**(owner, question 2)**. The default proposed is geometric for shots: the contact height on the
cylinder picks a band, and the contact's side of the target's facing picks left or right.

| Survivor band, fraction of cylinder height | Part |
|---|---|
| 0.87–1.00 | head |
| 0.50–0.87, inner 60 % of the width | torso |
| 0.50–0.87, outer 40 % | arm left or right; hand below 0.55 |
| 0.06–0.50 | leg left or right |
| 0.00–0.06 | foot left or right |

A zombie's three parts use 0.88 head and 0.45 legs. A crouched or crawling body uses the same
fractions of its own cylinder. Melee and bites keep `_roll_body_part` and its tables, because a
swing is not a ray. `HELD_HIT_LOCATION_WEIGHTS` in particular is a lethality decision (its comment
in `godot/sim/combat.gd`).

## Perception

**(engineering)** Visibility keeps its shape: one computation per observer, cached per tile, the
symmetric shadowcast as the 2D layer. It gains a vertical test, so that what a survivor sees and
what a zombie sees obey the same bands the camera draws.

- **The 2D layer casts for everyone as a standing eye.** `Eye.Crouched` stops being passed to
  `shadowcast`, so Low no longer blocks in 2D. The tile-level consumers (the explored bitset in
  `sightings.gd`, square bounds, light) see Low as transparent. Light already casts `Eye.Standing`
  in `SimLight.refresh`.
- **`detail(observer, x, y)` gains an optional target height.** After the tile, range, light and
  arc tests pass, it runs `SimSpace.segment_clear(eye, point, Sight)`, but only when the 2D line
  crosses a partial-height tile (Low, a window, a stage-3 board, a lintel). The cast records whether
  its square holds any such tile, so an observer in open ground pays nothing new.
- **A body is seen if its head point or its chest point clears.** A new `detail_body(observer,
  entity)` takes both points from `SimSpace.body_of`. Sightings, `shambler.gd`, `screamer.gd`,
  `jobs.gd`, `orders.gd`, `work_read.gd` and the view all switch to it when they are asking about a
  body. They keep `detail` when they are asking about a place.

The result is the physical one. A shambler standing six metres off cannot see a crouched survivor
behind a car. It can see a standing one. The crouched survivor sees a standing head over the car,
not a crouched body. Someone crouched under a window is unseen from outside except from close and
above the sill. An open door shows the room and a closed one does not. Symmetry holds wherever both
heights are equal, and it is no longer claimed between bodies of different heights. That matches
the world and docs/29's "in both directions", and it changes docs/28's Low row from "blocks a
crouched eye" to "blocks the line below its top" **(owner)**, question 3.

The view draws a body only when `detail_body(player, body) != Unseen`, with depth testing on and no
outline, glow or silhouette through geometry. The camera's near plane stays under the 0.35 m
movement half-width (the foundation's 0.05), so pressing the face to a wall can never clip the
camera through it. Noise and scent are unchanged; neither has a height.

## Determinism, save and replay

- **Determinism.** Every new decision is in `godot/sim/`, reads no presentation state, and uses
  integer tile stepping with millimetre heights. The one float step per shot or query is the
  direction from angles and a single interpolation per tile crossed. That is the same class of
  float use as today's cone dot products, with nothing accumulated across cells. The new
  randomness is one named stream, `ranged.spread`. A stream a v33 save lacks is reseeded from
  `derive_seed` by `SimRngRegistry.restore`, which is what a fresh run would hold.
- **Save.** The default plan adds no component and no required key. `pitch` is an optional key on
  `aim`. Profiles, eyes and cylinders are derived from tiles, overlays and posture, all of which a
  save already holds or rebuilds. **No `SAVE_VERSION` bump.** The slice that adds `pitch` writes the
  usual "No version bump" note in `serialize.gd`'s ladder. A bump becomes necessary if owner
  question 4 makes Low solid, because a v33 body standing on a car would load inside a solid tile.
  A bump is also needed if any slice changes the meaning of an existing key.
- **Replay.** The `aim`, `fire` and `swing` commands gain optional keys. Parity's
  `godot/parity/r1-walking-skeleton.json` holds only `move` and `wait`, so `npm run godot:test`
  cannot move. `SimCommandQueue`'s opt-in `recorded` log carries the new keys verbatim. A command
  without them replays as level pitch.

## What stays green, and what is replaced

These must stay green with no change to their assertions. A red one means the slice broke a rule
that survives the pivot: `godot:m2:aim`, `ammo`, `attach`, `hands`, `contact`, `swipe`, `stance`,
`save`, `fortify`, `district`, `light_burn`, `lethality`, `raiders`, `upkeep`, `godot:test`,
`godot:ban:healthbar`, `godot:check:hud` and the foundation's `check_first_person.gd`.

These pin a planar rule, and each gets an explicit replacement in the slice that changes it.
None is deleted or loosened:

- `check_m2_sight.gd`'s EYE lane (a crouched observer's cast blocked by a Low tile) becomes a
  HEIGHT lane with the paired cases under Perception.
- `check_m2_tick.gd`'s CAST lane holds `shadowcast` to `blocks_sight` at both eyes. It stays
  green unchanged, because `shadowcast` keeps its `eye` parameter and only `refresh` stops passing
  `Eye.Crouched`. A new VERTICAL lane holds the cached vertical test to a fresh `SimSpace` answer
  for every observer and target, the way CAST holds the cache to the slow cast.
- `check_m2_ranged.gd`'s lanes assume a body in the cone is hit. They pin `SimRanged.SPREAD`
  (a `static var`, restored after, like `GRABS_ENABLED`) to zero, and a new lane proves the shipped
  boot has it on.
- `check_m2_npc_combat.gd`'s melee, ranged and blocked lanes are re-expressed through `SimSpace`.
- `check_decals.gd` keeps its 2D fields and adds a lane for the contact point.
- `godot:m2:balance` and `godot:m2:harness` will move. The before and after numbers are a slice's
  record, not a reason to loosen a bound.

## The slices

Each slice is one session with one gate that has a true positive and a true negative. A new gate
touches the five places PLAYBOOK.md lists, plus a routing row. **Shared** marks a slice that touches
a shared sim module and so runs the full `npm run godot:m2` chain before its commit. The slices
assume the foundation has merged.

1. **The profile, drawn.** `godot/sim/space/space.gd` (`PROFILE`, `body_of`, `eye_of`, no consumer
   in the sim yet); `district_view.gd` and `body_view.gd` build from it. Gate
   `godot:check:fp_geometry`: for a fixture holding every class, overlay and stage, each tile's
   built mesh bounds equal its bands and each body's mesh equals its cylinder. Negative: a fixture
   drawn the old way (a window as a solid box, a Low tile undrawn) is refused. Not shared.
2. **The segment, and melee stops going through walls.** `segment_clear`. `_resolve_strike`,
   `_clear_contact` and `can_strike` ask it. Gate `godot:m2:space`: paired wall, window, sill,
   board, door, lintel, Low and screen cases for each purpose; a swing through a wall refused and
   the same swing through an open window landing; mirrored inputs give the same answer twice; a
   READS lane naming each caller. **Shared** (`melee.gd`, `shambler.gd`, `npc_combat.gd`).
3. **Pitch on the aim.** The `aim` command, `SimAim.pitch_of`, the NPC's pitch, and the
   foundation's `_push_aim` sending it. Gate: a PITCH lane in `check_m2_aim.gd`. Positive: a
   pitch round-trips a save and an absent one reads 0. Negative: a refused aim writes no pitch, and
   a negative zero never reaches the serializer. **Shared** (`world.gd`, `aim.gd`,
   `npc_combat.gd`).
4. **Perception with heights.** `detail` and `detail_body`, and the standing broadphase. Gate: the
   HEIGHT lane in `check_m2_sight.gd`, with every pair under Perception as hit and miss, and the
   VERTICAL lane in `godot:m2:tick`. Measured: `godot:bench` and docs/22's tick numbers before
   and after, because budgets are correctness. **Shared** (`visibility.gd`, `sightings.gd`,
   `shambler.gd`, `screamer.gd`).
5. **The shot as a ray.** Needs owner question 1. `ray_first_hit`, `ranged.spread`, the
   `weapon.fired` contact point, and `decals.gd` reading it. Gate lanes in `godot:m2:space`, paired:
   a shot through a window aperture lands and the same shot below the sill strikes the wall; over a
   car a standing head is hit and a crouched body behind it is not; a body inside the cone but off
   the ray is not hit; the same seed twice is identical; a save between steady and release fires
   the same round. **Shared** (`ranged.gd`, `decals.gd`).
6. **Parts from geometry.** Needs owner question 2. The band table in `SimCombat`, read by
   `_fire_shot`. Gate lanes: a head-height ray yields head, a shin-height ray a leg, and left and
   right follow the target's facing. Negative: a shot no longer draws a part roll from `ranged`.
   **Shared** (`ranged.gd`, `combat.gd`).
7. **Camera and sim agree, in the scene.** The eye from posture, the tracer and decal from
   `weapon.fired`, bodies drawn through `detail_body`. Gate: lanes in `check_first_person.gd`.
   Positive: five hundred seeded rays cast against the built meshes with `Geometry3D` meet first
   contact within 10 mm of `SimSpace.ray_first_hit`; a zombie through a window is drawn, shot and
   hit. Negative: shifting the drawn sill by 100 mm turns the agreement lane red; a zombie behind
   a wall is not drawn and a shot at it marks the wall. Not shared.
8. **The balance re-measure.** Sets `DISPERSION` and records `godot:m2:balance`,
   `godot:m2:harness` and one `godot:playtest`, before and after slices 2, 4, 5 and 6, on the same
   driver. No new gate; the numbers are the record.
9. **Low becomes solid**, only if owner question 4 says so. `map_cells`, pathing, the
   `SAVE_VERSION` bump. Gate lanes in `godot:m2:space`: a body is stopped by a car and still
   shoots over it. **Shared** (`world.gd`, the path code, `serialize.gd`).

The scavenging piece's reach to a container and the foundation's ledger test
(`interaction_verdict`, which today decides reach in presentation) should ask
`SimSpace.segment_clear(…, Reach)` when that piece lands. It is named here so it does not grow a
second answer.

## What the owner decides

Each has a recommended default, and none is taken here.

1. **Does a round go where it is pointed, or to the nearest body in the cone?** Today any body
   inside the cone is hit for certain. A first-person ray can miss everything. *Default: the ray,
   with `DISPERSION` tuned by measurement so a steady, skilled shot at a standing torso at fifteen
   metres usually lands.*
2. **Does aim choose the body part?** *Default: yes for shots, from where the ray meets the body;
   melee and bites keep their weighted tables, and pitch does not steer a swing.* Free headshots
   are bounded by dispersion, and lethality is re-measured in slice 8.
3. **Do Low cover and windows work by height?** That means a crouched survivor sees standing heads
   over a car, a standing zombie loses a crouched survivor behind one, and a crouched body under a
   sill is hidden. It also confirms the starting heights: Low 1.10 m, sill 1.00 m, crouched eye
   0.95 m. *Default: yes; docs/28's Low row is amended to say so.*
4. **Can a body walk through a car?** It does today, and in first person it will look broken.
   *Default: Low becomes solid for movement (slice 9, a save bump), with climbing over as the timed
   action docs/29 already names, built later.*
5. **What does looking away from your run cost in first person?** Decision 7 snaps the aim at Jog.
   *Default: keep it; the weapon lowers and fire is refused while the camera looks off the
   heading, so no hidden aim fires.*
6. **Is there anything at the centre of the screen?** docs/09 bans a reticle that reports
   accuracy. *Default: no screen reticle; a raised weapon's drawn sights, swaying with `coneHalf`,
   are the aim, which is docs/09's sway made literal.*
7. **Glass, and shots through foliage.** Windows have no glass state, and a screen stops sight
   but not a body. Today a screen also stops a round, because `can_target` refuses what the
   shooter's cast cannot see. *Default: unchanged for now. Windows are open apertures, and a
   screen stops a round and passes a reach. A glass state and a shot that tears foliage come
   later, each as its own piece.*

---

**Previous:** [39 — First-person pivot](39-first-person-pivot.md) ·
[Doc index](../README.md#documentation)
