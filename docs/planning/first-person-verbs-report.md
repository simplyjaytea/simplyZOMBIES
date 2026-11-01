# First-person world verbs: E on a door or window

In the first-person scene, E now does what the top-down right-click menu would do at the tile the eye
is on. Presentation only: no sim file changed, and no verb was added. The sim's own
`SimContext.verbs_at` decides what is offered, and E pushes the row's own command, as
`main._context_pick` does for a click.

## What landed

- `first_person.gd`, in its own hunks:
  - `eye_tile_hit()`: the look ray is walked through the tile grid, in 0.02 m steps, from the sim's
    position out to the ledger's reach (1.8 m). It returns the first tile that is a door, a window or
    solid. A door tile is kind `door`; anything else is kind `ground`. The function carries a comment
    that slice 2 of docs/40 moves this test into `SimSpace.segment_clear`.
  - `verb_row()`: `SimContext.verbs_at` for that hit, for the acting player. It returns the first row
    with a command. Cached per tick and tile, since the sim's answer changes only with those.
  - `verb_prompt()`: `"E " + the row's text`, or `""` when the sim offers nothing.
  - `try_interact()`: the ledger keeps priority (verdict `ok` opens it). Otherwise a verb row is pushed
    verbatim. Otherwise the old alerts stand.
  - `_update_hud()`: the prompt is the ledger's when the ledger is in reach and aimed at, then the verb's,
    then the ledger's approach words.
- `check_first_person.gd`: the VERBS lane, below.

## The door's reach is the sim's, not the view's

`SimContext.verbs_at` offers the door rows only when the door is the tile the actor faces one step
ahead (`SimFortify._door_in_reach`: the facing tile, or the tile underfoot). So a door 1.5 m away, looked
at across an empty tile, gets no prompt, and E does nothing there. That is the sim's rule, and the view
does not second-guess it. The 1.8 m eye reach only decides which tile is looked at. The gate's
out-of-reach case is refused by this same rule. It is not a separate proof of the 1.8 m bound.

## Gate

`npm run godot:check:first_person`, the VERBS lane:

- **True positive.** Stand beside a closed door, look at it, and the prompt reads `E open the door`.
  E changes the door's sim state to open. The prompt becomes `E shut the door`, and E closes it again.
  The door prompt has no digit.
- **True negative, out of reach.** Three tiles back on the same line, looking at the door: the door is
  unchanged and no prompt names it.
- **True negative, look turned away.** Beside the door but looking the other way: the door is
  unchanged and no prompt names it.
- **True negative, plain wall.** Looking at a plain wall from an open tile beside it: the prompt is
  empty.

Mutation-tested: with E made to push nothing, the lane fails (`E in reach and aimed at did not change
the door`, then the prompt after E). Extending the presentation's eye reach to 12 m did not turn the
lane red, which is the reach limit above, not a gap in the lane.

## Not covered

- Windows: a window gets a prompt only when `verbs_at` offers a board-up row for it (the rung ladder's
  window rung, which is also facing-tile bound). No gate lane asserts it.
- The LEDGER lanes still pass unchanged. A door in front of the player at a ledger spot does not alter
  the ledger's own refusals, because the ledger keeps priority and the verb falls through only when
  nothing is offered.
- `Low`, screen and fence tiles are not candidates, as the brief asked: only solid, door and window
  tiles are.
- The HUD prints the row's own words. A row with a digit in it (an item's name) would print it; no
  verb at a door or a plain wall carries one, and the gate asserts the door prompt is digit-free.

## Verified

- `npm run godot:check:first_person`: `FIRST_PERSON_OK`.
- `npm run godot:check:context`: `CONTEXT_OK`.
- `npm run godot:check:fp_geometry`: `FP_GEOMETRY_OK`.
- `npm run godot:smoke`: exits 0.
- `npm run check:routing`: `ROUTING_OK`.
