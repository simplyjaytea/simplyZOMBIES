# First-person save and load

The first-person scene saves and loads on F5 and F9, through the same sim API the top-down game uses
(`godot/sim/save.gd`: `create_save`, `encode_save`, `decode_save`, `apply_save`). Nothing under
`godot/sim/` changed.

## Slot

The top-down game writes `PlatformStorage.SAVE_KEY`, `simplyzombies.save`, which is
`user://simplyzombies.save.json` on desktop. The first-person scene writes its own key,
`simplyzombies.first_person` (`godot/presentation/first_person/save_slot.gd`, `DEFAULT_KEY`), which is
`user://simplyzombies.first_person.json` on desktop. The two scenes never overwrite each other's save.
The slot goes through the same storage adapter as the top-down game (`platform/storage.gd`): atomic
temp-and-rename on desktop, double-buffered on web. The adapter's keyed functions are called directly,
because its `read_save` and `write_save` hard-code the top-down key.

A save written by one scene is not offered by the other's slot. Both write the same sim snapshot in the
same save format (`SAVE_VERSION`), so a save from one build loads in the other only if it is copied
across by hand, which nothing does.

## Behaviour

- **F5** writes the slot and says `Saved.` on the HUD. If the write fails it says `The save did not
  write.` and nothing else changes.
- **F9** reads the slot back into the standing world (`SimSave.apply_save`). It refuses, saying
  `That save will not load.`, a save that does not decode, a save from a finished run, and a load into
  a finished run. These are the same refusals the top-down load makes (`presentation/session.gd`).
- **F9 with no save** says `Nothing to load.` and changes nothing.
- **After a load** the scene re-reads the restored sim (`_after_load`): an open ledger closes, held
  keys clear, aim and move are re-sent, the body views are rebuilt from the restored entities
  (`BodyView.reset`), and the camera snaps to the restored position with no interpolation from the
  old one (`snap_render_to_sim`). The restored world is the same world object, so no other cache needs
  clearing.
- **Under the ledger** the ledger consumes every key while it is open, so F5 and F9 are refused there
  exactly as the other keys are. Nothing is written and nothing is loaded.

## Feedback

Words only, through the HUD's existing alert line, which holds for three seconds. Every message is
digit-free and the HUD's digit scan (SPEECH lane) still holds.

The HUD does not name the keys. A key name such as `F5` contains a digit, and the HUD may not show a
digit except the day counter. The save keys are therefore not on the screen; the feedback says what
happened.

## Judged by

`npm run godot:check:first_person`, the SAVE lane. It sets `SaveSlot.slot_key` to a throwaway key
(`first_person_save_gate.slot`), deletes it before and after, and restores the real key, so no real
player's save is touched. The lane asserts first that the throwaway key is not the real slot.

- True negative: F9 with no save says `Nothing to load.`, writes nothing, and leaves the tick and the
  body where they were.
- True negative: F5 with the ledger open writes nothing and leaves the ledger open.
- True positive: walk, F5, walk further, F9. The sim body, the rendered body, the camera's position and
  the tick all equal the saved values, and the HUD says `Loaded.`.

Mutation tests, each reverted before the final run:

- Removing the `snap_render_to_sim` call from `_after_load`: the lane fails on the rendered body and on
  the camera (`the camera is at (3.5, 3.5) after F9, not the saved (3.5, 2.5025)`).
- Making `save_game` skip the write: the lane fails with `F5 wrote no save`.
- Moving the F5 handler ahead of the ledger's key block: the lane fails with
  `F5 with the ledger open wrote a save`.

## Verified

- `npm run godot:check:first_person` prints `FIRST_PERSON_OK`.
- `npm run godot:m2:save` prints `M2_SAVE_OK` (the shared save path is unchanged).
- `npm run godot:smoke` exits 0.
- `npm run check:routing` prints `ROUTING_OK`.

## Limits

- The first-person save holds only what the sim holds. Yaw and pitch are presentation state and are not
  saved, so a load keeps the look direction the player has now.
- `onboarding` (the top-down hint record) is not written. The first-person scene has no hints.
- The ledger's place and the desk are fixed by the district and the seed, so a load does not need to
  restore them.
