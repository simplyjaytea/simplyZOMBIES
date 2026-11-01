# First-person stance and gait

The first-person scene takes the top-down game's stance and gait keys, and its camera's eye height
follows the sim's posture. Presentation only: no file under `godot/sim/` changed, and the stance
command is the sim's own.

## Keys

The keys are read from `godot/presentation/input_map.gd`'s `BINDINGS`, the table the top-down game
reads, so the two scenes cannot disagree:

| Key | Stance (`SimStances.Stance`) | Command |
|---|---|---|
| Ctrl+Z | Crawl (prone) | `{"type": "stance", "stance": 0}` |
| Ctrl+C | Crouch | `{"type": "stance", "stance": 1}` |
| Ctrl+S | Walk (stand) | `{"type": "stance", "stance": 2}` |
| Ctrl+V | Jog | `{"type": "stance", "stance": 3}` |
| Shift (held) | Sprint | `{"type": "stance", "stance": 4}`, and back to the last Ctrl rung on release |

Shift is the sprint latch, as in `input_map.gd`. The last Ctrl rung pressed is kept in
`_selected_stance`, so releasing Shift returns to it. A Ctrl-modified key is a stance and never a
step: Ctrl+S stands the body up and does not walk it backwards. The keys are refused while the
ledger is open, because the ledger's branch consumes every key before the stance branch runs.

The sim decides the request. The zero-stamina gate in `world.gd`'s `stance` command refuses a sprint
on an empty tank, and the body and the eye stay standing.

## Eye

`first_person.gd` no longer has a fixed eye height. `_eye_target()` reads
`SimSpace.eye_of(world, player)` in millimetres and converts it to metres. `_ease_eye(delta)` moves
`_eye_m` toward it with an exponential ease, `1 - exp(-delta / EYE_EASE_TAU_S)` with
`EYE_EASE_TAU_S = 0.035`. From standing (1.62 m) to crouched (0.95 m), the eye is within 1 cm of its
target after 0.15 s: 0.67 m times `exp(-0.15 / 0.035)` is about 9 mm. `_update_render` writes the
camera's height from `_eye_m` every frame. `look_toward` and `interaction_verdict` use the same
`_eye_m`, so the ledger's reach and aim, and the door verb's eye tile, see the eye the camera shows.

Only the camera's height and the eye point the aim tests use change. Nothing else in the camera moves.

## HUD

`hud.gd` adds one line: `You are <posture>.`, with the word from `SimStances.name_of`. That is the
word the top-down paper doll prints under its figure: walking, crouching, crawling, jogging or
sprinting. The line has no digit.

The HUD does not name the keys. A key name such as `Ctrl+C` is not a digit, but this piece does not
change the help line, so the keys are not listed on screen yet.

## Gate

`npm run godot:check:first_person`, the STANCE lane:

- **True positive, crouch.** Ctrl+C, then ten ticks: the sim's `posture.current` is Crouch. One frame
  after the key, the eye is still more than 5 cm from its crouched target, so it eased. After settling,
  the camera's height is within 1 cm of `SimSpace.eye_of`'s crouched value, and that value is 0.950 m.
- **True positive, stand and prone.** Ctrl+S returns the body to Walk and the eye to 1.620 m. Ctrl+Z
  makes the body Crawl, and the eye is the sim's crawl eye.
- **True negative, ledger open.** Ctrl+C changes neither the stance nor the eye.
- **True negative, refused sprint.** With the stamina component at zero, Shift does not produce a Sprint
  and the eye stays at standing height. With a full tank, Shift sprints and releasing it returns to Walk.

Mutation-tested, each reverted after the run:

| Change | Result |
|---|---|
| Stance keys ignored | `STANCE: Ctrl+C did not make the body crouch` |
| Eye ease removed (eye held at standing) | `the eye stands at 1.620 m after the crouch, not the sim's 0.950 m` |
| Eye set straight to the target | `the eye jumped to the crouch in one frame, not an ease` |

## Verified

- `npm run godot:check:first_person`: `FIRST_PERSON_OK`.
- `npm run godot:m2:stance`: `M2_STANCE_OK`.
- `npm run godot:check:fp_geometry`: `FP_GEOMETRY_OK`.
- `npm run godot:smoke`: exits 0.
- `npm run check:routing`: `ROUTING_OK`.

## Not in this piece

- Aim and fire under a stance are the sim's rule (`SimStances.CAN_AIM`, `CAN_SWING`). This piece does
  not change the first-person fire or swing path, and no gate here checks a shot from a crawl.
- The eye is not interpolated between ticks. The ease is per frame, which keeps the camera off the
  sim's tick boundary, but it is not the between-tick interpolation docs/40 describes for the position.
- No key is named on the HUD yet.
- Slice 7 of docs/40 (the eye read by the shot and perception) is not here. This piece only moves the
  camera.
