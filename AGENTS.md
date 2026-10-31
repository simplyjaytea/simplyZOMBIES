# AGENTS.md

The fast on-ramp. This file is deliberately short so it cannot drift: it carries no status, no
dates, and no list of open work. The rules live in [CLAUDE.md](CLAUDE.md) — read it top to bottom
before touching anything. How the project runs (who decides what, how a pull request reaches
`main`, the shared folder) is [docs/38, the playbook](docs/38-playbook.md).

## The facts that cost a session to learn the hard way

- **Only Godot ships.** The game is `godot/` (Godot 4.7.1, typed GDScript); `npm run build` is
  `godot:export`. `src/`, `test/`, `bench/` are a *frozen* TypeScript oracle that CI keeps green:
  add no features to it, port no Godot change into it, and do not delete it or let it go red.
- **The engine pin is exact.** `scripts/run-godot.mjs` rejects any engine whose `--version` does
  not start with `4.7.1`; the same version and SHA-512 are repeated in the CI and Pages workflows
  and `scripts/setup-web-session.sh`. Change one, change all.
- **Correctness is Godot gates, not tests.** A change is verified by its `godot:m2:<name>` lane
  (plus `godot:smoke` and `godot:validate` for boot/content, `godot:check:play` for scene/input,
  and `npm test` for anything under `godot/content/`). A new gate must be reachable — add it to
  the `godot:m2:chain` script and `scripts/m2-shards.mjs`, or `npm run check:routing` /
  `npm run check:shards` go red. Full policy: [CLAUDE.md "Verifying a change"](CLAUDE.md#verifying-a-change).
- **One piece, one branch, one pull request.** Branch off `main`, base on `main`, push only your
  own branch — never `main`. No model identifiers in anything pushed. Merge with a merge commit,
  and never the thread that wrote it.

## First commands

```bash
bash scripts/setup-web-session.sh   # install or verify the pinned engine and npm packages
npm run godot:smoke                 # the project boots
npm run check:routing               # the routing table and every gate reachable
npm run godot:m2 -- --shard=1/4     # one of CI's four shards of the full chain
npx vitest run test/unit/<file>     # one file of the frozen oracle
```

## Before touching the sim

- [docs/37, the traps](docs/37-traps.md) — each one already cost someone a session.
- [docs/30, the decisions](docs/30-decisions.md) — before changing anything that looks arbitrary
  (it usually is not); search by system name, not the whole file.

[CLAUDE.md](CLAUDE.md)'s routing table maps every system to its code, its gate, and where its
record is written; [docs/23](docs/23-roadmap.md) is the live list of what is open.
