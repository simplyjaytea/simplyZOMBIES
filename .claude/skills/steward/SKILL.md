---
name: steward
description: How to drive a pull request on this repository to green -- what CI runs, what to run before a push, and what never to do to get a check passing.
---

# Driving a pull request here

The routing table in `AGENTS.md` says where a change lives and which gate judges it; this file
is only about the pull request around it.

## What CI runs

`.github/workflows/ci.yml`, three jobs. `check` is the one that decides: the TypeScript oracle
(`npm run typecheck`, `lint`, `format:check`, `npm test`), `npm run sprites:check` (needs
Pillow), `npm run check:routing`, the R1 parity and R6 gates, and then the whole
`npm run godot:m2` chain -- about twelve minutes on its own. `godot-exports` packages Windows
and web on a Windows runner and only runs once `check` is green. `performance` runs the two
TypeScript benchmarks; a budget breach there is a failure, not a warning (docs/00, pillar 6).

## Before every push

- `npm run godot:m2` for anything under `godot/`; `npm test` as well for anything under
  `godot/content/` (the oracle's Ajv recurses where `godot:validate` does not).
- `npm run typecheck && npm run lint && npm run format:check` for any `.ts`, `.mjs`, `.json` or
  `.yml` change -- prettier covers the workflows and `.claude/settings.json`, not `docs/` or
  `*.md`.
- `npm run check:routing` for anything touching `package.json` scripts, `scripts/run-godot.mjs`,
  a `godot/check_*.gd`, or the routing table.
- `npm run sprites:check` after touching `tools/sprites/` or a PNG it generates.

## Reading a red check

- `ObjectDB ... leaked at exit` and `resources still in use` after an `_OK` line are engine
  shutdown noise. Read the `_OK` line and the exit code.
- `BENCH_OVER_BUDGET` from `godot:bench` exits 0 on purpose; `npm run bench` (TypeScript) does
  gate.
- The `check` job's timeout is 30 minutes, sized to the measured chain. A run that dies with every
  gate green and the balance harness still going is the chain having grown, not a flake: re-measure
  and move the number in the workflow comment, never bump the timeout blind.
- A `godot:m2` gate that goes red on a branch that did not touch its system is still this PR's to
  root-cause: gate worlds share one process, and a `static var` or an unrestored flag in one lane
  leaks into the next (the traps in `CLAUDE.md`).

## Never

- Never skip, disable or loosen a gate to get green. `CLAUDE.md`'s standing bans and the
  "a gate that cannot fail is worse than no gate" convention are the reason each gate exists.
- Never decide something `HANDOFF.md` lists as waiting on the owner, even when a reviewer asks;
  reply with the measurement and leave the call.
- Never put a number back on the player HUD, a checkbox ledger in `HANDOFF.md`, or a status copy
  anywhere but docs/23.
- Never change the engine pin in one place. `4.7.1` and its SHA-512 live in `ci.yml`, `pages.yml`
  and `scripts/setup-web-session.sh` together.

## Landing

A slice lands with its record: the piece deleted from docs/23's what's-left and written into the
record, by system, in the same commit. A PR whose diff has no docs/23 change and claims a
feature is missing its step 7.
