# First-person foundation

The owner-authorized first-person pivot begins here, as a bounded additive foundation rather than a
conversion. Nothing in the shipped top-down presentation, the shared sim or the frozen TypeScript
oracle changed. The new scene is opt-in; the default `godot/presentation/main.tscn` still boots.

## What landed

- `godot/presentation/first_person/first_person.tscn` and `first_person.gd`: boot
  `SimBoot.playable` on a deterministic 64-tile district, step it on the same 20 Hz tick, and read
  the sim without writing it. The scene's only outputs are commands; the gate's teleport setup
  lives in the gate, not in presentation.
- `district_view.gd`: one floor quad per tile and one box per solid tile, so what is drawn is the
  map the sim collides against. Sim `(x, y)` maps to Godot `(x, z)`, one tile to one metre.
- `body_view.gd`: placeholder capsules for sim-owned bodies, interpolated between ticks and shown
  only where `world.vision.detail` says the player can see them. The player has no third-person
  body; the camera is the eye.
- `prop_view.gd` and `assets.gd`: a desk and ledger near the safe spawn, built from the optional
  GLB seam or a box of the published size. `godot/assets/first_person/desk.glb` and `ledger.glb`
  are read when they exist; the rest of the seam is reserved.
- `prop_preview.tscn` and `prop_preview.gd`: a render-only shelf showing all five exports (desk,
  ledger, shelf, barricade, wall module), so every path has a reader when the art lands. It is
  explicitly labelled, creates no sim entity and owns no collision. `npm run
  godot:run:first_person:props` launches it.
- `hud.gd`: prose condition and needs, a control line, a crosshair and an interaction prompt. No
  bar, no digit.
- `godot/check_first_person.gd`: the headless gate, wired as `npm run godot:check:first_person`
  and into the `godot:m2` chain and shard 1. `npm run godot:run:first_person` launches the scene.

## Controls

`WASD` walks relative to where you are looking, the mouse turns yaw and pitch, `E` uses the
ledger when it is in reach and in front of you, and `P` holds the world still. Outside the ledger,
`Escape` releases the mouse and a click resumes looking; with the ledger open, `Escape` goes back
from the skill web to the work grid, and again closes the ledger and gives the mouse and walking
back. There is no key that opens the work panel from anywhere: the only way in is the physical
ledger.

## How it is judged

The gate instantiates the actual scene, pushes real key events through the viewport, and drives
the scene's own frame function. It asserts:

- sim `x`/`y` on Godot `x`/`z`, with the axes not swapped;
- a fresh boot has no colonist job, and twenty sim ticks produce one while the tick count advances
  by exactly twenty;
- `W` sends the existing `move` and `aim` commands, the camera follows the interpolated sim
  position, and release stops the body; a camera turn while `W` is held sends the new direction
  at once, and losing window focus clears the held keys and queues a zero move;
- a wall blocks the sim's movement into it while the opposite direction crosses the tile;
- bodies the sim cannot see are not drawn, while a body the player looks at is; the player has no
  third-person body;
- `E` is refused out of reach, refused off the aim, and refused through an opaque wall, each with
  words on screen, and accepted at the ledger where it opens the real `ui/work_panel.gd`; the
  panel's row pick survives the per-frame refresh, and its skills button opens the existing
  read-only `ui/web_panel.gd` on that colonist;
- a click on a priority cell dispatches `job.priority`, changes the colonist's row and turns it
  Manual, and the player is never a row;
- a walking key does not move the body behind the open panel, `J` does not open or switch it, and
  `Escape` returns from the web to the grid and from the grid to the street; `Escape` outside the
  ledger releases the mouse and a click resumes it, and losing focus clears held keys, queues a
  zero move and releases the pointer;
- the HUD's every line is digit-free, it names the controls and the ledger, and no progress bar
  exists in the tree;
- the scene owns no physics body or collision shape, with a planted `CharacterBody3D` proving the
  scanner can fail;
- the desk and ledger use the published 1.20 x 0.62 x 0.78 m and 0.30 x 0.22 x 0.026 m, and the
  model/placeholder decision follows what is actually on disk.

## Verified

- `npm run godot:check:first_person` prints `FIRST_PERSON_OK` with every lane above.
- `npm run godot:smoke`, `npm run godot:validate`, `npm run godot:check:play` and
  `npm run godot:check:ui_skin` stay green, so the shipped boot, content, top-down scene and UI
  kit are untouched.
- `npm run check:routing`, `npm run check:shards`, `npm run check:timing`,
  `npm run check:runtime-budget`, `npm run lint` and `npm run format:check` stay green.
- Headed review captures (temporary, not committed):
  `C:/Users/jtf/AppData/Local/Temp/opencode/first_person_foundation.png` (opening view with the
  desk and ledger), `first_person_colonist.png` (a sim-driven body) and
  `first_person_props.png` (the render-only prop preview).

## Limits

Inventory, combat, artwork and the whole conversion are later pieces. The desk stands on an open
floor tile and has no sim collision of its own, so the player can walk through it; aligning it to
an existing blocked sim tile is deferred rather than faked with a second physics body. The
placeholder bodies are capsules and the tile surfaces are flat colours; the pixel-textured art is
the next stage. The optional GLBs are not required, and are read only when the art branch lands
them.
