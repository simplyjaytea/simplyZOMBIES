---
name: steward
description: How to drive a pull request on this repository to green -- what CI runs, what to run before a push, and what never to do to get a check passing.
---

# Driving a pull request here

The routing table in `CLAUDE.md` says where a change lives and which gate judges it; this file
is only about the pull request around it.

## What CI runs

`.github/workflows/ci.yml`, on every pull request and every push to main:

- `check` (25 min): the frozen TypeScript oracle (`npm run typecheck`, `lint`, `format:check`,
  `npm test`), `npm run sprites:check` (needs Pillow), `check:routing`, `check:timing`,
  `check:shards`, `check:runtime-budget`, R1 parity, the smoke, the content validator, the
  headless bench and the four R6 gates.
- `godot-m2 shard N of 4` (25 min each): the `npm run godot:m2` chain split by
  `scripts/m2-shards.mjs`. Shard 4 is `godot:m2:balance` alone. A gate added to the chain must
  be added to a shard in the same commit, or `check:shards` goes red.
- `godot-m2` (5 min): the required check. It passes only when every shard passed.
- `godot-exports`: packages Windows and web on a Windows runner once `check` and `godot-m2` are
  green. It sometimes crashes on import; a re-run settles it.
- `performance`: the two TypeScript benchmarks. A budget breach there is a failure, not a
  warning (docs/00, pillar 6).

## Before every push

The policy is CLAUDE.md's "Verifying a change" (the owner's 2026-10-19 call, docs/30): the gates
for what the change touched, locally; the full chain in CI.

- The `godot:m2:<name>` lane of each system touched. A change to a shared sim module or the save
  format runs the full `npm run godot:m2` locally as well.
- `npm run godot:smoke` and `npm run godot:validate` for a boot or content change;
  `npm run godot:check:play` for a scene or input change; `npm test` as well for anything under
  `godot/content/` (the oracle's Ajv recurses where `godot:validate` does not).
- `npm run typecheck && npm run lint && npm run format:check` for any `.ts`, `.mjs`, `.json` or
  `.yml` change -- prettier covers the workflows and `.claude/settings.json`, not `docs/` or
  `*.md`.
- `npm run check:routing` for anything touching `package.json` scripts, `scripts/run-godot.mjs`,
  a `godot/check_*.gd`, or the routing table.
- `npm run check:timing` for runner, timing-wrapper or `godot:m2:chain` changes.
- `npm run sprites:check` after touching `tools/sprites/` or a PNG it generates.

## Reading a red check

- `ObjectDB ... leaked at exit` and `resources still in use` after an `_OK` line are engine
  shutdown noise. Read the `_OK` line and the exit code.
- `BENCH_OVER_BUDGET` from legacy `godot:bench` exits 0; the real `godot:bench:runtime` and
  `godot:bench:frame` commands fail on overruns. CI currently enforces their deterministic
  contract, not their real timings; product performance debt remains in docs/23.
- Each shard's timeout is 25 minutes. A shard that dies with every gate green and a gate still
  going is the chain having grown, not a flake: re-measure, rebalance `scripts/m2-shards.mjs`,
  and move the number in the workflow comment. Never bump the timeout blind.
- A `godot:m2` gate that goes red on a branch that did not touch its system is still this PR's to
  root-cause: gate worlds share one process, and a `static var` or an unrestored flag in one lane
  leaks into the next (the traps in `CLAUDE.md`).

## Never

- Never skip, disable or loosen a gate to get green. `CLAUDE.md`'s standing bans and the
  "a gate that cannot fail is worse than no gate" convention are the reason each gate exists.
- Never decide something docs/33-owner-decisions.md lists, even when a reviewer asks;
  reply with the measurement and leave the call.
- Never put a number back on the player HUD, a checkbox ledger in any status file, or a status copy
  anywhere but docs/23.
- Never change the engine pin in one place. `4.7.1` and its SHA-512 live in `ci.yml`, `pages.yml`
  and `scripts/setup-web-session.sh` together; `scripts/run-godot.mjs` enforces the same version.

## Landing

A slice lands with its record: the piece deleted from docs/23's what's-left and written into the
record, by system, in the same commit. A PR whose diff has no docs/23 change and claims a
feature is missing its step 7.
