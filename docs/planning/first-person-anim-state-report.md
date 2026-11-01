# First-person animation state from the sim

The read model the character art will play from: for every drawn body, the animation state the sim
says it is in, plus a phase within the clip. The placeholder capsules use it now, so a tester can see
that the state is right before the character GLBs land.

Presentation only. Nothing under `godot/sim/` changed, nothing here writes a component, and
`godot/sim/` never reads it.

## The model

`godot/presentation/first_person/anim_state.gd`, pure and static:

- `AnimState.of(world, entity)` -> `{"state": ..., "phase": 0..1}`.
- `AnimState.state_of(world, entity)` -> the state string.
- `AnimState.phase_of(world, entity, state)` -> the phase.
- `AnimState.kind_of(world, entity)` -> `survivor` or `shambler`.
- `AnimState.clip_for(kind, state)` -> the nearest existing clip name.

`of()` is the readable API. `body_view.gd` calls `state_of` + `phase_of`, so the per-body per-frame
path builds no Dictionary; the state strings are constants.

## Where each state comes from

| State | Sim fact |
|---|---|
| `death` | the `corpse` component. Checked first, so a corpse is death whatever else it holds. |
| `grab` | `grabbed` on a victim, or `grabState` on a holder: the body is in a grapple. |
| `swing` | a survivor's `swing.state` is WindUp or Recover (melee.gd's `SwingState`). |
| `stagger` | a shambler's `shambler.state == Staggered` (shambler.gd). |
| `lunge` | a shambler in `Pursue` with `ticksToSwipe` off its resting `SWIPE_FIRST_TICKS`: a swipe is armed and in reach. |
| `crawl` | `SimSpace`/`SimHealth.is_crawling` says the legs are gone; also a survivor whose posture is `Crawl`. |
| `crouch_idle`, `crouch_walk` | posture `Crouch`, with `velocity` zero or not. |
| `run` | posture `Jog` or `Sprint` and moving. |
| `walk` | posture `Walk` (or an unlisted rung) and moving; a shambler moving. |
| `idle` | everything else, including a still body and a dormant shambler. |

A survivor's stagger is published only as `entity.staggered`, on the event bus, and no component
holds it. A pure read of `(world, entity)` therefore cannot name it; a survivor in that moment reads
as its locomotion state. The top-down's `presentation/anim_clock.gd` still plays its flinch one-shot
from the event. When the character art needs the state, a sim-held timer would be the change, and it
is not in this piece.

## The clip table

`clip_for(kind, state)` is the documented fallback: a state with no clip in the character art yet
borrows the nearest one that exists, so the table grows with the art and no caller changes. Clip
names and lengths are the character kit's (`tools/blender/first_person_kit/README.md` on its branch).

| State | Survivor clip | Why | Shambler clip | Why |
|---|---|---|---|---|
| `idle` | `idle` | exact | `idle` | exact |
| `walk` | `walk` | exact | `shamble` | exact |
| `run` | `walk` | no run clip; the one walk cycle is nearest, and phase runs faster | `shamble` | no run clip; the shamble is nearest |
| `crouch_idle` | `crouch_idle` | exact | `idle` | no crouch clip |
| `crouch_walk` | `crouch_idle` | no crouch walk clip; the crouched idle is nearest | `shamble` | no crouch walk clip; the shamble is nearest |
| `crawl` | `crouch_idle` | no prone clip; the crouched idle is the lowest existing | `shamble` | no prone clip; the shamble is nearest |
| `swing` | `walk` | no attack clip; the walk's arm swing is nearer than breathing | `lunge` | a shambler's swipe is the lunge |
| `lunge` | `walk` | no lunge clip; the walk is nearest | `lunge` | exact |
| `grab` | `idle` | no hold clip; the upright idle is nearest | `lunge` | the lunge's held forward pose is the hold |
| `stagger` | `idle` | no stagger clip; the upright idle is nearest | `idle` | no stagger clip; the upright idle is nearest |
| `death` | `death` | exact | `death` | exact |

Clip lengths: survivor idle 2.0 s, walk 1.0 s loop, crouch_idle 2.0 s loop, death 1.5 s held;
shambler idle 2.4 s, shamble 1.4 s loop, lunge 1.0 s held, death 1.7 s held.

## Phase

0..1 within the chosen clip.

- **Loops** (idle, walk, run, crouch_idle, crouch_walk, crawl) advance on the sim tick, with a
  per-entity seat (`fposmod(entity * 0.618, 1) * length`, the golden-ratio stagger `AnimClock.seat`
  uses), so a crowd does not breathe or step as one. The phase is deterministic: the same world at
  the same tick gives the same phase.
- **Lunge** reads the swipe countdown: 1 at the arming, approaching 0 at contact. The first swing's
  window is `SWIPE_FIRST_TICKS`; after a strike the sim re-arms over `SWIPE_RECOVER_TICKS`, and the
  phase uses whichever window the countdown is in.
- **Grab** reads the hold's `ticksUntilBite`: 1 just after a bite, approaching 0 at the next.
- **Swing** is 0 in WindUp and 1 in Recover: the sim's state names which half, and the art clock will
  time the one-shot (the component does not carry the weapon's own duration).
- **Death** is 1: the clip's held final pose.
- **Stagger** is 0: the sim keeps a countdown from a total it never publishes.

## The placeholder

`body_view.gd` poses the existing cylinder from the state, so the read model is visible before the
art lands:

- swing, lunge and grab lean forward (0.35, 0.55 and 0.25 radians), pivoting at the feet: the
  cylinder's centre drops by `cos(lean)` so a tilted body does not float.
- stagger rolls sideways (0.45 radians).
- death lies the cylinder on its side at the hit radius, the corpse colour still gating it by sight.
- crouch and crawl need no pose: `SimSpace.body_of` already gives the shorter cylinder.
- everything else stands straight, and the rotation is reset every frame.

The phase is not drawn yet; the character GLBs will play the named clip at it. No new node, texture
or allocation is made, and the frame cost is a handful of component reads per drawn body.

## The gate

`npm run godot:check:first_person` gains an ANIM lane (`godot/check_first_person.gd`) and prints
`FIRST_PERSON_OK`:

- True positives: standing, a walk command, a jog as `run`, a crouch at rest and moving, a crawl, a
  swing's wind-up and recover, a shambler's armed swipe as `lunge`, a hold as `grab`, a stagger, and
  a death.
- True negatives: a body that stops is `idle` on the next tick; a corpse is still `death` after
  thirty ticks and never returns to idle; no living body reports `death`.
- Every named state's phase is asserted to lie in 0..1, and every state is one of the vocabulary.

The lane uses the sim's own routes where they exist (move and stance commands, the scene's F) and
stages the components only for states with no command (a shambler's swipe, hold and stagger),
restoring them afterwards.

## Not in this piece

- No character art is drawn: the clip table names clips that the character GLBs (#288) will carry.
- A survivor's stagger is not named, because the sim holds no component for it.
- No animation playback: phase is computed but the placeholder does not use it.
- Work animations: a colonist working in place has no walk, so it reads `idle`; the character kit has
  no work clip.
