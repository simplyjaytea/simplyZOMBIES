# First-person containers

The first slice of [docs/39](../39-first-person-pivot.md)'s "Scavenging and personal equipment": the
district's sim cupboards stand in the first-person scene as labelled placeholders, and E at one
opens the real grid inventory sheet on the player's own bags with that box beside them. Nothing in
the sim changed; the scene reads containers and sends the same commands the top-down screen sends.

Based on `pivot/first-person-foundation` (PR #269). The worktree is `fp-containers`, the branch
`opencode/fp-containers`.

## What landed

- `godot/presentation/first_person/container_view.gd`: one placeholder box and a floating
  `Label3D` per sim entity carrying `searchable` + `position`, at the sim's own `(x, y)` and
  labelled with the sim's own `kind` word ("cupboard", "tool chest", "wardrobe"). It reads the sim
  and writes nothing; it owns no physics body or collision shape.
- `godot/presentation/first_person/first_person.gd`:
  - E at a container in reach and in the eye's 30-degree cone pushes
    `{"type": "container.open", "container": <entity>}` -- exactly the command the top-down
    context menu's "open the cupboard" row pushes, so the sim keeps reach, the first-open table
    roll, and the `opening` component. Nothing is stowed or spawned by presentation.
  - The existing `ui/inventory_panel.gd` opens on the player's inventory. The open box is the
    sheet's first column through `SimContainers.open_view`, the same read model the top-down
    sheet uses, so taking an item is the sheet's ordinary `item.move` and every fit, rotation,
    nesting and reach rule is unchanged.
  - Escape closes the sheet, sends `container.close` so the sim does not leave the box open behind
    a closed screen, and recaptures the mouse. Movement keys are swallowed while the sheet is up,
    and the name field, item rotation and the sheet's own Escape ladder are handed to the panel.
  - Containers join the HUD's prose: "E open the cupboard", "Turn to the cupboard.", "You have
    already been through this cupboard."
- `godot/presentation/first_person/hud.gd`: the help line now names E for opening, and the line
  list can say the inventory is open. Every line is still digit-free.
- `godot/check_first_person.gd`: a new CONTAINER lane (below), and the FIRST_PERSON_OK line now
  names containers.

### Inventory pause policy

Marked in `first_person.gd` as a **reversible default**, not a design decision; docs/33 still
leaves inventory/ledger pause policy open. It copies `main.gd` exactly: the inventory sheet does
not stop the clock (`main.gd`'s `_process` steps while the session is PLAYING and `P` is not
held), and the body is stopped by clearing the held keys and queueing one zero move, with the
movement keys swallowed by the sheet's focus. The one place to change if the owner later picks a
time-stopped inventory is the accumulator hold in `_process`.

## Controls

`E` opens the container you are looking at when it is in reach and in sight; the sheet appears on
the player's inventory with the box in the first column. Drag between grids, ctrl-click to send,
or use the sheet's inspect buttons. `Escape` puts down a lifted item or the sheet's own menu first,
then closes the sheet and returns mouse look. `R` rotates a lifted item. `WASD` does nothing while
the sheet is open. `P` still stops the world; the sheet does not.

## How it is judged

`npm run godot:check:first_person` instantiates the real scene, pushes real key events through the
viewport and drives the scene's own frame function. The CONTAINER lane asserts:

- the scene draws one labelled placeholder for every sim `searchable` container, at its sim
  position, with the sim's `kind` word;
- E in reach and in aim sends a `container.open` command naming that entity, and the sim has it
  open; the real `ui/inventory_panel.gd` is visible and open, the box is its first column and the
  player's pockets are beside it; the mouse is released;
- a take through the sheet's own quick move dispatches `item.move` into the player, the item is in
  the player's inventory and no longer in the box, and the box-plus-player item total is unchanged
  (no duplication);
- a walking key does not move the body behind the open sheet, and the clock keeps running (the
  copied `main.gd` default);
- Escape closes the sheet, sends `container.close`, drops the sim's open box, gives the mouse back
  and leaves no held key;
- true negatives: E off the aim is refused with "not looking at it" words; E five metres away is
  refused with "Nothing within reach" words; E through an opaque wall, still inside the sim's
  own reach, is refused with "behind a wall" words. The through-wall fixture slides one container
  0.3 m toward a sight-blocking wall so a body on the far side is inside `SEARCH_REACH` (1.5 m);
  a whole wall tile costs two metres between tile centres, so no untouched tile-centre box can
  sit behind a wall and still be in reach. The position is restored afterwards.

The gate's other lanes are unchanged and still green.

## Verified

- `npm run godot:check:first_person`:
  `FIRST_PERSON_OK ... draws the district's sim containers as labelled placeholders and opens one
  in reach through the top-down container.open command into the real grid inventory sheet, moves a
  real item into the player's inventory without duplication ...` (all lanes, no skips)
- `npm run godot:check:inventory`: `INVENTORY_OK ...` (the sheet's own LOOT, STOCKPILE and VERBS
  lanes are untouched and green)
- `npm run godot:check:play`: `PLAY_OK ...`
- `npm run godot:smoke`: `GODOT_PROJECT_SMOKE_OK`; `npm run godot:validate`: `GODOT_CONTENT_OK`
- `npm run check:routing`: `ROUTING_OK` (147 paths, 106 check scripts, self-test held)

## Limits

- The boxes are placeholders: one size, one colour, no per-kind art, and the label is the only
  readable state. The art pass owns the real meshes.
- Containers have no sim collision of their own, like the desk; the player can walk through one.
  Sim collision for furniture is deferred rather than faked with a physics body.
- Boxes are not hidden by the sim's vision: they are static furniture and the 3D walls already
  occlude them. The `searched` state is not drawn on the box; the sheet and the HUD's prose say it.
- The first-person sheet is the full inventory screen, not the top-down game's small transfer
  window. That is the adaptation the task asks for; the window remains the top-down presentation's.
- Only the set of keys the sheet needs in first person is routed (Escape, R, the name field).
  Number-key belt spending, Tab-to-open-without-a-container, and the nav bar's Colony/Skills
  screens are not wired into this scene.
- A searched-and-empty container is refused ("already been through") rather than opening a blank
  grid, mirroring the top-down E ladder's `Want.Openable` rung.
- Pause policy is the reversible `main.gd` default above; it is not an owner decision.
