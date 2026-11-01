# First-person succession and the end of a run

Death, succession and run over in the first-person scene. The sim already owns all of it --
`SimRecruits.handle_death` hands `world.player` to an heir or sets `world.runOver` -- so this slice
adds only the screen's read of those two facts: a camera cut, the top-down chronicle's own words,
and an end panel. No sim file changed.

Stacked on `opencode/fp-containers` (PR #271), which is stacked on the first-person foundation
(PR #269). The worktree is `fp-death`; the branch is `opencode/fp-death`.

## What landed

- `godot/presentation/first_person/first_person.gd`:
  - `_watch_identity()` reads `world.player` and `world.runOver` after every tick and at the top of
    every frame, so a death that landed inside a tick is seen on the next frame and a death a
    caller triggers outside a step is seen at once.
  - A handoff cuts the camera: `_prev_player` and `_curr_player` are both set to the heir's sim
    position and the rig is rendered in the same call, so there is no interpolated glide from the
    dead body to a heir across the district. `_bodies.reset` re-collects with the heir as the eye,
    so the dead body is drawn on that frame when it is in sight.
  - Any open ledger or inventory sheet closes, held keys clear and a zero move is queued, and the
    HUD gets the chronicle's own succession sentence -- "You are Mara Sato now." / "You are
    someone else now." -- read back from `SimChronicle.epitaph` rather than written a second time.
  - `world.runOver` raises an end panel built from `SimChronicle.epitaph`, the shell's "the run is
    over" heading and its "There is nobody left to be." fallback. The mouse is released, the clock
    holds still (the top-down end screen does the same), and the one action is to leave: Escape or
    Enter quits. W, the mouse and every other key do nothing.
  - `_waiting_for_heir()` is the belt-and-braces guard for a frame between a death and the handoff:
    input is swallowed and no move or aim is proposed. The sim currently hands over inside
    `handle_death`, so it has no such frame; the guard is there so a later async handoff cannot
    walk a corpse.
- `godot/presentation/first_person/body_view.gd`: a human corpse is a drawn body now, in the
  corpse colour the file already carried but never used, instead of being skipped. On a succession
  the dead player is the first one the heir can see; a body that vanished would be the camera
  changing with nothing on screen to explain it. The player's own body is still absent while it is
  the body being driven.
- `godot/presentation/first_person/hud.gd`: a `news` line for the succession sentence, and the
  end-of-run panel -- the shell's danger frame and heading, the chronicle's epitaph, and "Escape
  quits". Every line is prose, with no digit and no bar.
- `godot/check_first_person.gd`: the SUCCESSION and RUN-OVER lanes (below), and `FIRST_PERSON_OK`
  now names them.

## Controls

Nothing new to learn while alive. At a succession the camera is the heir and the HUD says who
that is. At the end of the run the panel is up, the mouse is free, and Escape (or Enter) leaves;
nothing else is a command. There is no first-person title flow yet, so an end is a quit rather than
a new run.

## How it is judged

`npm run godot:check:first_person` instantiates the real scene, kills bodies through the sim's own
`SimHealth.finish_death` (the API `check_m2_jobs.gd` and `check_m2_recruits.gd` use), and drives the
scene's own frame function.

- SUCCESSION, true positive: kill the player with an heir alive. `world.runOver` stays false, the
  heir is controlled, the scene's rendered position and the camera's `x`/`z` equal the heir's sim
  position on the next frame (a cut, not a glide), the HUD carries the chronicle's exact "You are
  <name> now.", W walks the heir, and `body_node_for(dead)` exists and is visible with the heir
  looking at the corpse.
- SUCCESSION, true negative: kill a body that is not the player (a shambler if one is alive, else a
  colonist while two others remain). `world.player` and the camera do not move. A lane with no such
  body skips by name rather than passing quietly.
- RUN-OVER: kill every colony body. The run ends, the end panel is up, the mouse is released, the
  panel says "the run is over" and the chronicle's "There is nobody left to be.", every line is
  digit-free, and W on the next two frames records no `move` and no `aim` command and leaves the
  camera still.

## Verified

- `npm run godot:check:first_person`: `FIRST_PERSON_OK ... cuts the camera to an heir with the
  chronicle's succession words while drawing the dead body, then shows a digit-free end panel that
  ignores W when the last colony body dies` (every lane, no skips)
- `npm run godot:m2:roster`: `M2_ROSTER_OK ...` (the sim's own death and body rules unchanged)
- `npm run godot:smoke`: `GODOT_PROJECT_SMOKE_OK`
- `npm run check:routing`: `ROUTING_OK` (147 paths, 106 check scripts, self-test held)
- `npm run godot:check:play`: `PLAY_OK ...` (the top-down scene and its own run-over screen are
  untouched; run for the input change in the first-person scene)

## Limits

- There is no first-person title flow: the over screen's one action quits the process, where the
  top-down shell offers "new run" and "quit to title". The shell is the next piece.
- The dead body is still the placeholder capsule, now in the corpse colour; no lying pose, no fall
  animation. Corpse art belongs to the art pass.
- The run-over panel pins the clock still and draws the chronicle's last lines; it does not save,
  offer a continue, or animate the death. A finished run still writes nothing, matching
  `session.gd`'s rule.
- The dead-and-waiting guard is defensive: `SimRecruits._handoff` runs inside `handle_death`, so
  the sim produces no frame between the player's death and the heir. The guard is what would stop
  input walking a corpse if that ever became asynchronous; no lane can catch a frame the sim does
  not produce, and the report says so rather than claiming one.
- The succession sentence is read from the epitaph's newest "You are ... now." line. If the
  chronicle record is drained after the screen asks (a death triggered outside a tick), the
  top-down fallback "You are someone else now." is used until the next frame; normal play drains
  the tick before the handoff is read.
