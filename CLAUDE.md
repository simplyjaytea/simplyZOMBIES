# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

It holds the rules of the repository: what the project is, the commands, how the code fits
together, how a change is verified, and what must not be broken. It carries no status, no roster
and no commit hash, so it cannot drift. [ROUTING.md](ROUTING.md) maps every system to its spec,
its code and its gate. `README.md` is for players.

## Commands

```bash
bash scripts/setup-web-session.sh   # verify or install the pinned engine and npm packages
npm run godot:smoke                 # the project boots
npm run godot:run                   # play it, first person
npm run godot:run:topdown           # the legacy top-down game, kept for testing
npm run godot:editor                # open the project in the Godot editor
npm run godot:m2:needs              # one gate while iterating: any godot:m2:<name> or godot:check:<name>
npm run godot:m2 -- --shard=1/4     # one of CI's four shards of the full chain
npm run godot:m2                    # the full gate chain
npm run godot:validate              # content validation (shallow; see Conventions)
npm run check:routing               # ROUTING.md's claims, and every gate reachable
npm run check:shards                # every gate is in a CI shard
npm test                            # the frozen TypeScript oracle (vitest)
npx vitest run test/unit/<file>     # one oracle test file
npm run typecheck && npm run lint && npm run format:check
xvfb-run -a npm run godot:shots     # review screenshots of fixed scenes (godot/review/scenes.gd)
xvfb-run -a npm run godot:shots:look -- --out=DIR    # the look sheet: fixed first-person stations
xvfb-run -a npm run godot:frames:look -- --out=DIR   # the same stations, timed
npm run godot:check:fp_look         # the look as structure; `-- --plant=<name>` must end red
bash scripts/new-piece.sh <piece>   # a worktree and a branch for one piece, ready to run
npm run godot:playtest              # one seed, ten days, a line per day: a measurement, not a gate
```

Godot must be exactly 4.7.1 and Node 22. `scripts/run-godot.mjs` refuses any other engine; set
`GODOT_BIN` if `godot` is not on `PATH`. Run every Godot gate, capture and Blender job under
`xvfb-run -a` so no window opens on the desktop. Never send OS-level input or take desktop
screenshots: drive Godot from inside (the gate harness, `Input.parse_input_event`, a throwaway
GDScript driver) and capture only the game viewport.

## What the project is

A hardcore zombie survival colony sim set in the fictional Kagase valley, in the mountains west
of Tokyo (inspired by Ome–Okutama; every place name, business and brand is fictional,
[docs/42](docs/42-ome-okutama-setting.md)). One attention system (noise, scent, light) ties
survival to the pressure the dead put on the colony: the better you live, the harder they come.
[docs/00](docs/00-vision.md) is the vision and [docs/01](docs/01-hardcore-contract.md) the
hardcore contract.

- **Godot is the only implementation that ships.** The game is `godot/`: Godot 4.7.1
  (Compatibility renderer), typed GDScript. New behaviour goes there and nowhere else.
  `npm run build` is `godot:export`, and GitHub Pages publishes the web build.
- **First person is the game; top-down is legacy.** The default boot is the first-person scene
  ([docs/39](docs/39-first-person-pivot.md), [docs/40](docs/40-first-person-spatial-contract.md)).
  The top-down game keeps its gates and gets no new features unless the owner asks. Shared sim
  modules serve both. Top-down rules in docs/30 and docs/32 govern only the legacy build.
- **The TypeScript oracle is frozen, not gone.** `src/`, `test/`, `bench/` and the Vite and
  vitest configs are a reference that CI's `check` job still runs (`npm test`, `typecheck`,
  `lint`, `format:check`, `bench`). Add no features to it, port no Godot change into it, and do
  not delete it or let it go red. The one exception: a stat id that shared content names is
  registered in `src/sim/modifiers/stats.ts` (ids and base/min only) so the oracle's content
  check can judge the file. Its parity fixtures under `godot/parity/` are what
  `npm run godot:test` compares against; tag `ts-oracle-final` is the rollback point.
- **The engine pin is exact.** The same version and SHA-512 appear in `scripts/run-godot.mjs`,
  `.github/workflows/ci.yml`, `.github/workflows/pages.yml`, `.github/workflows/release.yml` and
  `scripts/setup-web-session.sh`. Change one, change all.
- **Facts that hold every session.** A day is one real hour (`Clock.DAY_SECONDS`), 72,000 ticks.
  The boot colony is three: the player, Mara and Ellis. `SimShambler.GRABS_ENABLED` ships `true`.
  The speed ladder is 1x and 3x.

## How the code fits together

[docs/19](docs/19-architecture.md) and [docs/20](docs/20-ecs-and-content.md) are the specs.

- **The sim is a deterministic ECS stepped at 20 Hz.** `SimWorld` (`godot/sim/world.gd`) owns the
  entity and component stores, a command queue, an event bus, named RNG streams
  (`rng_registry.gd`) and a system registry with twelve fixed phases, input to cleanup
  (`system_registry.gd`). `step()` takes the tick's commands, runs every system in phase order,
  and only then drains the events, so a handler runs after the tick's systems.
- **A sim module registers itself.** Most files under `godot/sim/modules/` expose
  `register_module(world)`. `SimBoot.register_playable_modules` (`godot/sim/boot.gd`) is the one
  list that installs them; a module missing from it is a dead socket. `SimBoot.playable(seed)`
  builds the shipped district world, and gates and drivers boot through it.
- **Presentation reads the sim and never writes it.** `godot/presentation/first_person/` is the
  game's scene (`first_person.tscn`); `godot/presentation/main.gd` (`main.tscn`) is the legacy
  top-down one. Each steps the world, draws bodies between ticks, and turns input into commands.
  The screen reads the sim through read models (`godot/sim/condition.gd`, `attention_read.gd`,
  `context.gd`), never through raw components. `godot/ui/` holds the panels, `godot/platform/`
  the content loader and validator, and `godot/content/` the JSON the sim and the looks read.
- **A gate is a headless script.** Each `godot/check_*.gd` boots its own worlds, prints
  `<NAME>_OK` or `<NAME>_FAIL`, and exits non-zero on failure. A new gate touches five places:
  the script, a mode in `scripts/run-godot.mjs`, a `package.json` script, the `godot:m2:chain`
  list, and a shard in `scripts/m2-shards.mjs`. It also needs a row in ROUTING.md. Gates in one
  process share `static var`s, so a lane that pins a flag restores it.
- **First-person art is built, not drawn by hand.** Each kit under `tools/blender/` is a
  reproducible Blender builder with a `-- --check` mode and planted-error modes, and a
  `<kit>.manifest.json` in `godot/assets/first_person/`. Texel density is 64 px/m for the world,
  128 px/m for bodies and arms and 256 px/m for heads, measured on the exported GLB. Compare
  rebuilt files by pixels, not bytes: this machine's Blender links zlib-ng, so bytes differ from
  other builds.

## Verifying a change

Correctness for a Godot change is the Godot gates, not tests. Before a commit, run the gates for
what the change touched:

- its `godot:m2:<name>` or `godot:check:<name>` lane (ROUTING.md names it);
- `godot:smoke` and `godot:validate` for a boot or content change;
- `godot:check:play` for a scene or input change;
- `godot:check:fp_look`, the look sheet's before and after pairs and `godot:frames:look` for a
  change to the first-person picture ([docs/46](docs/46-the-look.md));
- `npm test` for anything under `godot/content/` (the oracle's Ajv recurses where
  `godot:validate` does not);
- `typecheck`, `lint` and `format:check` for a `.ts` file or a prettier-covered path;
- `check:routing` for a script, a runner mode, a `check_*.gd` or ROUTING.md;
- **the full `npm run godot:m2` chain for a shared sim module or the save format.**

CI runs the full chain on every pull request and every push to `main`, split across four shards,
and nothing merges red. Never skip, disable or loosen a gate to get green. The commands, timings
and CI jobs are in [docs/35](docs/35-gates.md).

**Measure balance claims; never theorise them.** A claim about campaign outcomes comes from a
throwaway driver, run before and after on the same driver, deleted afterwards. Do the throughput
arithmetic first from a fresh measurement: recorded throughput has ranged from under 30 to over
100 ticks/s. No lever is judged on three seeds; the standing measurement is ten seeds and a
median wipe day.

**Known noise, not failure:** `godot:check:worldgen` fails past 90 seconds and can trip on a
loaded machine (CI is the judge); the Windows `godot-exports` job sometimes crashes on import and
a re-run settles it; `ObjectDB ... leaked at exit` or `resources still in use at exit` after an
`_OK` line is engine shutdown noise. Read the `_OK` line and the exit code.

## Standing bans

These are settled by the owner. Re-read the linked clause before proposing a change; do not
quietly amend them.

- **No health bar, and no way to compute one.** The
  [condition view](docs/05-health-injury.md#the-condition-view) hands the screen a state and a
  sentence per body part and carries no integrity value, maximum or fraction.
  `godot/sim/condition.gd` is the one builder; `npm run godot:ban:healthbar` asserts the absence
  with a key allowlist. If it goes red, re-read
  [hardcore contract clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable)
  rather than widening the assertion.
- **Information stays scarce and unreliable.** Do not add certainty the player is not supposed
  to have: exact quality, counts, positions, or anything through walls.
- **The HUD speaks in words.** `npm run godot:check:hud` allows no digits on the player HUD
  except the day counter. The one amendment: an item's `name` may carry a digit (`.308
  Winchester Match`), judged by `SimItems.name_is_allowed`. Do not widen it to a second field.
- **Budgets are correctness.** Tick: at most 8 ms mean and 16 ms worst
  (`npm run godot:bench:runtime`). Draw: at most 10 ms mean (`npm run godot:bench:frame`, needs a
  display). The shipped game is over both, recorded as debt in
  [docs/22](docs/22-performance.md); do not add to it.

## Conventions

- Typed GDScript. `godot/sim/` is deterministic and never reads presentation state. Effects are
  sim-owned and command-driven. New randomness gets its own named RNG stream.
- Content is data under `godot/content/`. The validator is shallow: it checks top-level property
  types and keys and does not recurse, so a nested shape needs its own gate
  (`check_appearance.gd` is the model).
- How a thing looks is content, not code: `appearance` in a content entry, resolved by
  `godot/presentation/appearance.gd`. Never branch on an id in a draw loop.
- **A gate that cannot fail is worse than no gate.** Every assertion wants a true positive and a
  true negative. An assertion with no data to judge says so and skips; it never passes quietly.
- **The dead-socket rule.** Complete, gated code that nothing reads has turned up many times. A
  mechanism needs an assertion that something reaches it.
- **Readers before content, pictures a stage behind.** A stat nothing resolves is not authored.
- The owner decides design: anything a player would notice, and everything under
  [Waiting on the owner](docs/33-owner-decisions.md#waiting-on-the-owner). Engineering calls,
  including tuning numbers that come out of a measurement, get a file under
  [docs/decisions/](docs/decisions/README.md). Before changing anything that looks arbitrary,
  search `docs/decisions/` and [docs/30](docs/30-decisions.md) (the earlier ones) for the system.
- Never put per-item checkboxes in a status file. Status is prose in which each claim names the
  gate that proves it.
- Commits use the repository's local git identity and carry no attribution trailer. Commits, PR
  text, code comments and docs never name the model or agent that wrote them (the owner's call,
  docs/30).
- Prose is hand-wrapped; `.prettierignore` excludes `docs/` and `*.md` for that reason.
- `CONTEXT.md` is the domain vocabulary (Need, Job, Focus, Stockpile and so on). Use its terms
  and avoid the words it lists as wrong.

## The workflow

One orchestrator session runs the work. It fans a job out to agents it spawns, through scripted
workflows that run them in parallel, each with a fresh context, and it keeps its own context for
judgement: what to build, whether the evidence holds, what merges. Nothing stands between
sessions: no seat, no roster, no status file. The agents are defined under `.claude/agents/`,
and each agent's file names the model it runs on; nothing else in the repository names one.

| Role | Does | Never |
|---|---|---|
| Orchestrator (the session) | Plans with the owner, cuts a job into pieces, scripts the workflow, reads every diff and every picture, integrates, merges | Takes a report as evidence |
| `scout` | Maps the code, the rules and the gates a job touches, with path and line, before anything is designed | Edits |
| `builder` | Builds one piece in its own worktree: the change, its gate, its plant, and for a visible change its pictures | Pushes, merges, or edits a file another piece owns |
| `critic` | Judges a visible change from pictures it makes itself, against [docs/46](docs/46-the-look.md) | Edits; takes the builder's pictures on trust |
| `reviewer` | Reads one diff fresh, and reruns its gates and plants | Edits; reads the author's account |
| `worker` | One small, fully specified piece for a builder or the orchestrator | Decides anything the brief did not |

**A job runs in four passes.** The orchestrator reads the result of each before it starts the
next.

1. **Understand.** Scouts map what the job touches: the code, the rules that bind it, the gates
   that judge it. A design made before this pass is a guess.
2. **Design.** The orchestrator cuts the job into pieces and gives each the files it owns, the
   gate that judges it and what done means. Pieces do not share a file where it can be helped;
   where they must, each is told which functions are its own, and a shared list (`package.json`,
   `scripts/`, ROUTING.md) is edited by the orchestrator alone.
3. **Build.** One builder per piece, in parallel. A builder ends with commits, the exact result
   lines of the gates it ran, the plant it watched go red, and for a visible change the before
   and after pictures and the frame cost.
4. **Verify.** Nobody checks their own work. A critic makes its own pictures. A reviewer reads
   the diff and reruns the gates and plants. Their notes go back to a builder, and a finding is
   reproduced before it is acted on.

The rules that hold whatever the job:

- **GitHub is the record.** A piece that waits in the backlog, or will outlive the session, is
  an issue from the template: the change, the files, the gate, what done means. A piece cut and
  landed inside one session is specified by its brief and reported by its pull request, which
  says what the issue would have said. No file carries status, a roster of who holds what, or a
  log of sessions; the one pinned issue "Where we are" says where to start.
- **One piece, one worktree, one branch.** `bash scripts/new-piece.sh <piece>` makes
  `.claude/worktrees/<piece>` on `claude/<piece>` from `origin/main`, with `node_modules`
  linked and the Godot import done. The main checkout stays on `main`; nobody switches branches
  in it. Remove a piece's worktree when its work has merged.
- **Pieces judged together land together.** A pass whose pieces make one picture, or would each
  re-run the others' CI, is built on piece branches that the orchestrator merges into one
  integration branch, `claude/<pass>`. The pass is verified there as a whole, a piece that
  fails is left out, and the branch is one pull request. Anything else is one pull request per
  piece. At most three pull requests are open for merge.
- **Reports are reproduced, not trusted.** Builders have reported work done when it was not.
  Before a push, the gates a piece names are rerun and its plant is watched go red by someone
  other than its builder. The orchestrator reads the diff and CI before it merges.
- **Independent review.** Every change a player can see is judged by a `critic` from its own
  pictures. Every art change and every change to a shared sim module or the save format is read
  by the `reviewer`, briefed with the base and head only, never the author's account. A push
  that changes the reviewed paths voids the review.
- **A visible change is judged by pictures.** [docs/46](docs/46-the-look.md) is the target for
  the first-person look and says how a change to it is judged: the look sheet's before and
  after pairs, the lanes of `godot:check:fp_look`, and the frame cost of the same stations.
- **Agents are cut off without warning.** The session and its agents share one usage pool. A
  builder commits as it goes, and every brief says to continue from the branch if it already
  has work, so a relaunch loses little. Never `git add -A` in a worktree.
- **Merging.** A pull request merges when its head contains `origin/main`, CI is green on that
  head, and the diff is read: `gh pr merge <n> --merge --match-head-commit <full SHA>`. Merge
  commits only. Only the orchestrator merges; nobody rebases or force-pushes a pushed branch or
  pushes to `main`. `.claude/hooks/guard-git.sh` blocks the last two for everyone.
- **One waiver, and it is the owner's.** A CI job that fails in a step that only fetches from
  outside the repository (a browser or package download) while every gate, `check` and export
  job passes may be waived by the owner, per pull request, in the owner's own words. Rerun the
  job first. Nothing else merges red, and no gate is ever skipped or loosened.
- **Decisions.** A call taken gets its own file under `docs/decisions/` in the same pull
  request. `docs/30` holds the earlier ones and gains no new entries.
- **Design questions go to the owner once, with a default.** Build the default, say so in the
  pull request, and keep going. A step that cannot be undone waits for the owner's own words.
  The first-person look is delegated
  ([the decision](docs/decisions/2026-11-12-the-look-is-judged-by-pictures.md)): a visible
  change inside docs/46 is not a card.

**Starting a session.** Read the pinned issue first (`gh issue list --label resume`, titled
"Where we are"): the orchestrator rewrites it at every pause, and it names `main`, every open
piece with its issue, pull request and branch, the next things in order, and what waits on the
owner. Then `gh pr list` for what moved since, and `git worktree list` for pieces with work
that has not merged.

A piece too long for one session may run in its own terminal instead of as a spawned agent. It
is then an issue, and the terminal carries it the whole way to a pull request:

```bash
bash scripts/new-piece.sh <piece>
hc run --bg --name <piece> --cwd .claude/worktrees/<piece> --outlive-parent --keep --no-notify \
  -- env SZ_SEAT=builder claude --agent builder --permission-mode auto
hc send <piece> "Your piece is issue #N. Work it without stopping."
```

Alone on its piece, that builder owns the whole diff, the shared lists included. It merges
`origin/main` into its branch (never rebases), pushes, opens the pull request from the template
with `Closes #N`, comments on the issue with the head and the exact result lines, and stops;
the orchestrator merges. `SZ_SEAT` is what the guard hook reads to refuse a merge from that
terminal. This is the exception; a spawned builder is the rule.

**Pausing.** Every piece stops at a safe point with its work committed (a WIP commit says so)
and pushed. The orchestrator comments on each open issue or pull request what works, what
fails, what is next, the branch and head; merges what is ready; rewrites the pinned "Where we
are" issue; and removes the worktrees whose work has merged. Nothing about the pause is written
to a file.

## Traps

The traps that have already cost someone a session are in [docs/37](docs/37-traps.md). Read them
before touching the sim. Two that bite outside it:

- A both-kept merge of a `switch` in `scripts/run-godot.mjs` can drop a `break;`, so one gate
  silently runs another. After such a merge, run the gate and its planted failure.
- `docs/23` and `godot/review/scenes.gd` conflict on every parallel branch. Keep both sides, and
  add a scene in a small, separate hunk.

## The docs map

| Need | Read |
|---|---|
| Where a system's code lives, its spec and its gate | [ROUTING.md](ROUTING.md) |
| What is built and what remains, with evidence | [docs/23](docs/23-roadmap.md) (large: read the entry for your piece) |
| Why something is shaped the way it is | [docs/decisions/](docs/decisions/README.md); before 2026-11-12, [docs/30](docs/30-decisions.md) (large: search by system name) |
| Decisions waiting on the owner | [docs/33](docs/33-owner-decisions.md) |
| Every gate, its timing, and what CI runs | [docs/35](docs/35-gates.md) |
| The state of the build and the dead-socket list | [docs/36](docs/36-state-of-the-build.md) |
| The first-person direction, spatial contract and plan | [docs/39](docs/39-first-person-pivot.md), [docs/40](docs/40-first-person-spatial-contract.md), [docs/41](docs/41-weapons-characters-world-plan.md) |
| What the first-person game should look like, and how a change to it is judged | [docs/46](docs/46-the-look.md) |
| The setting, and the wider world by rail | [docs/42](docs/42-ome-okutama-setting.md), [docs/45](docs/45-wider-world-by-rail.md) |
| Running the game, containers, screenshots | [docs/34](docs/34-agents-and-environment.md) |
| What sessions before 2026-11-11 did (closed) | [docs/43](docs/43-session-log.md) |
| Driving a pull request to green | `.claude/skills/steward/SKILL.md` |

The design specs (docs/00 to docs/29) are numbered in the order they were written. New to the
design? Read docs/00, 01, 03, then 23.
