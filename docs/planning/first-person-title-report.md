# First person from the title

The first-person scene is reachable from the game's own title screen now, and gets back. The title
gains one row, **first person (experimental)**; choosing it swaps the whole scene for
`godot/presentation/first_person/first_person.tscn`, which boots the sim on the shipped district.
The ordinary title, New run, Continue and the default `project.godot` main scene are untouched;
the pivot's default switch remains a later, owner-verified piece (docs/39).

Stacked on `opencode/fp-death` (PR #274), which is stacked on #271 and #269. Worktree `fp-title`,
branch `opencode/fp-title`.

## What landed

- `godot/ui/shell.gd`: one extra title row, `["first_person", "first person (experimental)"]`,
  above **quit** so leaving stays last. It is drawn by the same shell code as every other row --
  same kit frame, same font ladder, same focus pulse -- and its label is words only.
- `godot/presentation/main.gd`: the `first_person` action calls
  `get_tree().change_scene_to_file("res://presentation/first_person/first_person.tscn")`. The
  path is a named constant; a failed change stays on the title and says so. Nothing about the
  default boot, New run, Continue, the session or `project.godot` changed.
- `godot/presentation/first_person/first_person.gd`:
  - `DISTRICT_TILES` is now `SimTileMap.DISTRICT_TILES` (the shipped 256-tile district) instead of
    the foundation's 64-tile cut, so the row opens the world the game is about rather than the
    gates' miniature. The seed is unchanged (`20260805`, the shipped default).
  - `return_to_title()` changes the scene back to `res://presentation/main.tscn`, which boots into
    its own title state. The run-over panel's one action (Escape or Enter) now calls it instead of
    quitting the process.
  - Escape with the mouse already released also calls it. The first Escape still only frees the
    pointer; a second one leaves the experiment. The HUD help line says "Esc release or title".
  - `_input` and `_unhandled_input` return early when the node has no viewport, because the scene
    change can free this node while the same key dispatch still has its release behind it.
- `godot/presentation/first_person/hud.gd`: the end panel's action reads "Escape returns to the
  title" (no digits), and the help line names the title retreat.
- `godot/check_play.gd`: a FIRST-PERSON lane (below) and the PLAY_OK line now names it.

## Controls

From the title, choose **first person (experimental)**. Inside the scene, Escape releases the
mouse as before; a second Escape, with the mouse already free, returns to the title. On the
end-of-run panel, Escape or Enter returns to the title. There is no first-person save slot on this
branch, so there is no Continue for the experiment: leaving it ends the run, as the top-down
"quit to title" does for a run with no save.

## How it is judged

`npm run godot:check:play` boots the real title scene and pushes real keys. The FIRST-PERSON lane:

- true negative: Enter on the title's first row, **new run**, leaves `current_scene` as
  `main.tscn`'s top-down scene with a real world, in `PLAYING`, and no first-person scene node
  anywhere in the tree;
- true positive: moving the cursor to **first person (experimental)** and pressing Enter changes
  `current_scene` to `presentation/first_person/first_person.gd`, which has a live `world` with a
  player and a current 3D camera (the sim booted);
- Escape once only releases the mouse and leaves the first-person scene current; Escape twice
  returns `current_scene` to `main.tscn` with the title visible and the session in `TITLE`;
- re-entering and raising the scene's own end panel (the run-over flag; the real death-to-panel
  path is `check_first_person.gd`'s RUN-OVER lane), Escape on the panel returns to the title with
  the title up.

## Verified

- `npm run godot:check:play`: `PLAY_OK ... opens the first-person experiment from the title and
  comes back ...` (no lane skipped; `BUDGET OK 32188 ms of the 60000 ms budget`)
- `npm run godot:check:first_person`: `FIRST_PERSON_OK ...` (the scene now boots the shipped
  256-tile district and every lane stays green, 4.5 s)
- `npm run godot:check:ui_skin`: `UI_SKIN_OK ...` (the new row is drawn by the shell's existing
  kit rows; no new surface)
- `npm run godot:check:hud`: `HUD_OK ...` (the shell's words and the title's rows carry no digit)
- `npm run godot:smoke`: `GODOT_PROJECT_SMOKE_OK`
- `npm run check:routing`: `ROUTING_OK` (147 paths, 106 check scripts, self-test held)

The exported build was not run: this machine has no Godot export templates installed
(`%APPDATA%/Godot/export_templates` is absent), so `godot:export` can only fail for an environment
reason. The export preset is `export_filter="all_resources"` with no exclude filter, so
`first_person.tscn` is in the PCK, and the scene change is a `res://` path load, not a preloaded
resource whose reachability could be stripped.

## Limits

- The row is deliberately labelled experimental. The default scene, New run and Continue still
  boot the top-down game; switching the default is the pivot's later end-to-end piece and needs
  the owner's verification.
- There is no first-person save slot or Continue on this branch (`save_slot.gd` is #272 and not
  here); returning to the title ends the experiment's run. The top-down title does not offer it
  as a Continue.
- The title scene is reloaded fresh on the way back: the top-down world is rebooted and sits
  still behind its title, exactly as a normal boot does. A first-person run does not autosave.
- The title row is in the web build too. The exported web payload will carry the first-person
  scene because the preset exports all resources; the experiment is the same door on both.
- The first-person scene now builds the 256-tile district's ground and wall meshes at boot. The
  gate measures the whole scene at about four and a half seconds headless; the art pass still owns
  the placeholder geometry.
