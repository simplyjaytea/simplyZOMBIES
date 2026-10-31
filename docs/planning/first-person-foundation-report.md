# First-person foundation

The owner-authorized first-person pivot begins here, as a bounded additive foundation rather than a
conversion. Nothing in the shipped top-down presentation, the shared sim or the frozen TypeScript
oracle changed. The new scene is opt-in; the default `godot/presentation/main.tscn` still boots.

## What landed

- `godot/presentation/first_person/first_person.tscn` and `first_person.gd`: boot
  `SimBoot.playable` on a deterministic 64-tile district, step it on the same 20 Hz tick, and read
  the sim without writing it.
- `district_view.gd`: one floor quad per tile and one box per solid tile, so what is drawn is the
  map the sim collides against. Sim `(x, y)` maps to Godot `(x, z)`, one tile to one metre.
- `body_view.gd`: placeholder capsules for sim-owned bodies, interpolated between ticks. The
  player has no third-person body; the camera is the eye.
- `prop_view.gd` and `assets.gd`: a desk and ledger near the safe spawn, built from the optional
  GLB seam or a box of the published size. `godot/assets/first_person/desk.glb` and `ledger.glb`
  are read when they exist; the rest of the seam is reserved.
- `hud.gd`: prose condition and needs, a control line, a crosshair and an interaction prompt. No
  bar, no digit.
- `godot/check_first_person.gd`: the headless gate, wired as `npm run godot:check:first_person`
  and into the `godot:m2` chain and shard 1. `npm run godot:run:first_person` launches the scene.

## Controls

`WASD` walks relative to where you are looking, the mouse turns yaw and pitch, `E` uses the
ledger when it is in reach and in front of you, `Escape` closes the ledger and gives the mouse and
walking back, and `P` holds the world still. There is no key that opens the work panel from
anywhere: the only way in is the physical ledger.

## How it is judged

The gate instantiates the actual scene, pushes real key events through the viewport, and drives
the scene's own frame function. It asserts:

- sim `x`/`y` on Godot `x`/`z`, with the axes not swapped;
- a fresh boot has no colonist job, and twenty sim ticks produce one while the tick count advances
  by exactly twenty;
- `W` sends the existing `move` and `aim` commands, the camera follows the interpolated sim
  position, and release stops the body;
- a wall blocks the sim's movement into it while the opposite direction crosses the tile;
- `E` is refused out of reach and refused off the aim, each with words on screen, and accepted at
  the ledger where it opens the real `ui/work_panel.gd`;
- a click on a priority cell dispatches `job.priority`, changes the colonist's row and turns it
  Manual, and the player is never a row;
- a walking key does not move the body behind the open panel, `J` does not open or switch it, and
  `Escape` restores the mouse and movement;
- the HUD's every line is digit-free, it names the controls and the ledger, and no progress bar
  exists in the tree;
- the scene owns no physics body or collision shape, with a planted `CharacterBody3D` proving the
  scanner can fail.

## Verified

- `npm run godot:check:first_person` prints `FIRST_PERSON_OK` with every lane above.
- `npm run godot:smoke`, `npm run godot:validate`, `npm run godot:check:play` and
  `npm run godot:check:ui_skin` stay green, so the shipped boot, content, top-down scene and UI
  kit are untouched.
- `npm run check:routing`, `npm run check:shards`, `npm run check:timing`,
  `npm run check:runtime-budget`, `npm run lint` and `npm run format:check` stay green.

## Limits

Inventory, combat, artwork and the whole conversion are later pieces. The desk and bodies are
placeholders and have no physical collision of their own; the sim remains the one authority on
walls. The optional GLBs are not required and are not read until the art pass lands them.
