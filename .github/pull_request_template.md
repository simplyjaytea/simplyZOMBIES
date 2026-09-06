## The piece

Which named piece from [what's left](../docs/23-roadmap.md#whats-left-in-milestone-2) this lands,
or which defect or debt entry it closes. Work not on that list is named there first.

## The gate

The `npm run` script that can fail it, its `_OK` line, and the true negative it carries. A
mechanism names the assertion that something *reads* it.

## Measured

Any balance claim, with the before and after from the same driver. Leave empty rather than
theorise.

## Recorded

The docs/23 record entry (and the docs/30 entry, if a call was taken) in this same diff.
`HANDOFF.md` only if what waits on the owner changed.

## Verified

- [ ] `npm run godot:m2`
- [ ] `npm test` (any content edit; the oracle's Ajv recurses)
- [ ] `npm run typecheck && npm run lint && npm run format:check` (any `.ts`, `.mjs`, `.json`, `.yml`)
- [ ] `npm run check:routing` (any script, runner mode, `check_*.gd`, or the routing table)
- [ ] `npm run sprites:check` (anything under `tools/sprites/`)
