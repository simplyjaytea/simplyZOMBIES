Closes #

## What changed

The piece in two or three sentences: what is different, and anything the issue did not settle
and the default that was built.

## The gate

The `npm run` script that can fail it, its exact `_OK` line, and the planted failure that turned
it red. A mechanism names the assertion that something *reads* it.

## Measured

Any balance or performance claim, with the before and after from the same driver. Leave empty
rather than theorise.

## Pictures

For a change a player can see: the look sheet's before and after pairs
(`npm run godot:shots:look`), the stations that show it, and the critic's verdict on this head.
Otherwise delete this section.

## Review

For art, a shared sim module or the save format: the independent reviewer's verdict, the head it
judged, and which findings were taken. Otherwise delete this section.

## Verified

- [ ] The gates for what the change touched, rerun on this head (CLAUDE.md, Verifying a change)
- [ ] The planted failure goes red
- [ ] `npm test` (any content edit; the oracle's Ajv recurses)
- [ ] `npm run typecheck && npm run lint && npm run format:check` (any `.ts`, `.mjs`, `.json`, `.yml`)
- [ ] `npm run check:routing` (any script, runner mode, `check_*.gd`, or ROUTING.md)
- [ ] A visible change: the pairs above, `npm run godot:check:fp_look` and each plant red, and
      `npm run godot:frames:look` before and after under Measured
- [ ] A decision taken has its own file under `docs/decisions/`
