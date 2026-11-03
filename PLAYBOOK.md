# PLAYBOOK.md

The one entry point for anyone changing this repository, agent or person. It says what the
project is, who works on it and how the work is dispatched inside Orca, where the work is, how a
unit of work runs, how to verify and push it, what must not be broken, how the project around
the repository runs (who decides what, how a pull request reaches `main`, the shared folder, what
is open), what the last session did and left, and where every system lives. `README.md` is for
players; this file is for builders. Other assistants read it too: it is the project's rules, not
a Claude-only file (`CLAUDE.md` imports it so Claude Code loads it, and `AGENTS.md` points here).
Where it states a fact about the build, it names the file or gate that proves it. Where it says
how the owner works, it records the owner's standing instructions.

It merged `CLAUDE.md`, `AGENTS.md` and docs/38 on 2026-11-01, the owner's call (docs/30, "The
playbook, one file"). Those three are now stubs that point here, and their old anchors land on
the matching headings below.

## Start here

```bash
bash scripts/setup-web-session.sh   # verify or install the pinned engine and npm packages
npm run godot:smoke                 # the project boots
npm run check:routing               # the routing table below, and every gate reachable
npm run godot:run                   # play it, first person (DISPLAY=:1 on a headless VM; docs/34)
npm run godot:run:topdown           # the top-down testing game
npm run godot:m2:needs              # one gate while iterating: any godot:m2:<name> or godot:check:<name>
npm run godot:m2 -- --shard=1/4     # one of CI's four shards of the full chain
npx vitest run test/unit/<file>     # one test file of the frozen oracle
```

Then read, in order:

1. This file, top to bottom.
2. [What's left in Milestone 2](docs/23-roadmap.md#whats-left-in-milestone-2), the open work, and
   [the record, by system](docs/23-roadmap.md#the-record-by-system) for how the neighbouring
   systems landed. Both are far too large to read whole: read your piece's entry and the record
   of the systems it touches ([briefing a thread](#how-work-flows)).
3. [Waiting on the owner](docs/33-owner-decisions.md#waiting-on-the-owner): decisions that are
   not yours to make.
4. [docs/37, the traps](docs/37-traps.md), before touching the sim.
5. [docs/30, the decisions](docs/30-decisions.md), before changing anything that looks
   arbitrary. It usually is not. Read the entries for the system you touch (search by its name),
   not the whole file.

## The team

The owner decides. Everything else is done by agents running as terminals inside Orca, each
on its own model, coordinated by one of them. The owner's call of 2026-11-01: this roster may
name models; the rule against model identifiers still holds for authorship (a commit, PR title
or body, code comment or doc never says which model wrote it).

| Role | Agent and model | Does | Does not |
|---|---|---|---|
| Coordinator | Claude Code, Opus 5.5, high effort | Reads the state, picks the pieces, writes every task spec, dispatches, judges every render and report, merges after the owner's go-ahead, keeps the owner informed | Write the work itself, beyond small reads and checks |
| Workhorse | Claude Code, Haiku 5.5, high effort | Mechanical and engineering work: tooling, presentation code, gates, keeping pull requests current with main, driving CI green; spawns its own subagents | Merge; touch art builders it does not own |
| Modeler | Kimi Code, K3.1 Pro, thinking high | 3D models: Blender builders, meshes, rigs, UVs, animation, `--check` and plant modes | Paint the final textures (Codex does) |
| Art | Codex, GPT-6.1-Sol (the owner runs it at high; it ran at medium on 2026-11-01) | Painted pixel textures on the modeler's UV layout, 2D look targets, palette, and an independent second eye on every model round | Edit the modeler's worktree |
| Strong tier, on demand | Claude Code, Opus 5.5, high, started by the coordinator | Shared sim modules, the save format, taking over a modeler who ran out of usage, independent art reviews and their confirmation passes | Merge |
| Writer, on demand | Claude Code, Fable 5.1, started by the coordinator | Large writing and restructuring work, such as this playbook's merge | Merge |

Kimi has priority for models. When Kimi runs out of usage, an Opus worker takes over the same
worktree from Kimi's handoff (see [When a worker runs out](#when-a-worker-runs-out)).

**Model routing, by role.** The owner assigns models by role, and the roster above is the
current assignment. The roles that hold whatever the models are:

- The coordinator, and the end review of a feature, on the coordinator's model.
- Working threads, on the fast tier at high effort.
- On the strongest tier at high effort, from the start: planning threads; anything that cannot
  be undone (merges, deletes); all art, design and visual placement, and the art reviewers; and
  any piece that touches a shared sim module (`godot/sim/modules/jobs.gd`,
  `godot/sim/modules/stockpile.gd`, `godot/sim/modules/needs.gd` and the like) or the save format
  (the owner's call, 2026-10-27).

## The Orca workflow

The owner calls this the most crucial part of the playbook. One coordinator in the Orca app
dispatches work into live agent terminals and subagents, and every worker reports back through
Orca's orchestration commands, never through a terminal nobody reads.

### The loop

1. **Orient.** The coordinator reads the state: open PRs (`gh pr list`), `origin/main` against
   the local checkout, the worktrees, and the owner's request. It renders the current asset
   before judging it.
2. **One run per objective.** `orca orchestration run-create --objective "..."`. Every task of
   the session hangs off it.
3. **Specs live in the shared folder.** Each task is a self-contained markdown spec in
   `C:/Users/jtf/orca/sz-shared/<piece>/task-<who>.md`: target worktree and branch, the change,
   constraints, ownership, observable acceptance. A brief shared by several workers
   (`BRIEF.md`) carries the owner's words verbatim and the technical contract.
4. **One worktree per worker.** The coordinator creates it first:
   `git worktree add -b <agent>/<piece> .claude/worktrees/<piece> origin/main` (or off the PR it
   stacks on). Workers never share a worktree at the same time. Every worktree sits under
   `.claude/worktrees/` (ignored by git) on a branch named `<agent>/<piece>`; every terminal
   shares the main checkout, so nobody switches branches there.
5. **Dispatch.** Into an existing terminal: `orca orchestration task-create --run <run> --spec
   "$(cat spec.md)"` then `orca orchestration dispatch --task <id> --to <handle> --inject`. A
   new agent terminal: `orca orchestration worker-start --spec "..." --worktree path:<dir>
   --agent claude --model <model-id> --effort high`. Handles come from `orca terminal list
   --json` and change between Orca runs.
6. **Wait without polling.** A small watcher script (`orchestration check --wait`, acking
   heartbeat-only batches, exiting on the first question, status or worker_done) runs in the
   background; the coordinator acts on each message, replies with `orchestration reply`, sends
   follow-ups with `orchestration send --to dispatch:<id>`, and acks the batch.
7. **Settle each worker.** On `worker_done` the coordinator checks the claim (renders, CI, SHAs)
   and then reuses the terminal with a new dispatch, retains it (`worker-retain`) or releases
   it (`worker-release`).

### Art in rounds

- The modeler publishes the UV layout early (`uv_layout.png` + `.json` with island rects,
  orientation, landmarks, mirroring and a position bake) so the painter starts in parallel.
- Every round renders the same views, side by side with the owner's concept: Blender clay and
  textured, plus the in-engine sheet from `npm run godot:shots:survivor -- --glb=<path>
  --out=<dir>`. The coordinator judges the in-engine sheet, not only Blender.
- Codex reviews each round independently (`review_round-N.md`); the coordinator writes a ranked
  verdict (`OPUS_VERDICT.md`) and sends both to the modeler. Geometry is locked before final
  paint, and paint is locked last.
- The owner sees the accepted model before any pull request.
- Art kits follow one shape: a reproducible Blender builder with `-- --check` and planted-error
  modes, a `<kit>.manifest.json` in `godot/assets/first_person/`, and an independent in-engine
  review before merge. The reviews keep finding the same faults (camouflage-like noise, paint
  that follows atlas cells, density claims the check did not measure, bodies that float or sink),
  so a new kit's builder should check those from the start.

### Independent review and the merge train

- An art PR merges only after an independent art review (an Opus subagent with only the PR, its
  own renders of base and head, and this file's rules) and, after fixes, a confirmation pass by
  the same reviewer against its first report. A push after a verdict voids it.
- The thread that wrote a PR never merges it. The coordinator merges with a merge commit, after
  re-checking the head SHA and CI (`gh pr merge <n> --merge --match-head-commit <sha>`), and
  only with the owner's go-ahead: the permission check blocks `gh pr merge` otherwise.
- The workhorse keeps the queue current: after each merge it merges `main` into the next PR
  (never rebase, never force-push), reruns the touched gates and reports a table: number, head,
  CI, local gates, preconditions, risk. Docs/23 record entries conflict on every merge; keep
  both sides.
- CI capacity is the bottleneck. When pieces stack and collide in code, one integration pull
  request that names the pieces it closes saves many merge-and-rerun cycles (#289 did twelve).
  Docs-only pull requests were merged after a clean local merge and `check:routing`, since no
  Godot gate reads them.

### When a worker runs out

1. Tell it to stop, commit a WIP checkpoint even if checks fail, write `HANDOFF.md` (method,
   what works, what fails and why, next steps, traps), and send `worker_done --outcome failed`.
2. Wait for that `worker_done` before anything else touches the worktree.
3. Start the replacement in the same worktree with `worker-start --worktree path:<dir> --agent
   claude --model <opus id> --effort high`, its spec pointing at the handoff and the original
   task.

### Standing rules for workers

- **No OS-level input and no desktop screenshots, ever.** Drive Godot from inside (the gate
  harness, `Input.parse_input_event`, a throwaway GDScript driver) and capture only the game
  viewport, or capture through Blender. A worker's synthetic keys once landed in the owner's
  browser.
- Never push to main, never merge, never skip or loosen a gate.
- A worker asks the coordinator with the orchestration `ask` command; it never opens a local
  question prompt nobody can answer.

## What the project is

**Current direction: the first-person survival colony pivot, authorized 2026-11-01.**
Read [docs/39](docs/39-first-person-pivot.md) before new presentation or art work.
The owner has superseded the flat-top-down art direction for the conversion;
the default boot has been first person since the owner's call of 2026-11-01 (docs/30); the
top-down game remains as the testing build (`npm run godot:run:topdown`).
The existing game is preserved by the GitHub source archive linked in docs/39.
Colony systems, skills, authored/generated people and the captive roadmap remain.
Management moves to physical ledgers and conversations. Earlier projection and
sprite rules describe the preserved baseline, not constraints on new 3D assets.
The standing verification and merge rules remain.

A hardcore zombie survival colony sim: RimWorld's colony management and work priorities,
Project Zomboid's unforgiving survival, Zero Sievert's top-down pixel art. One attention system
(noise, scent, light) ties survival to the pressure the dead put on the colony: the better you
live, the harder they come. [docs/00](docs/00-vision.md) is the vision and
[docs/01](docs/01-hardcore-contract.md) the hardcore contract.

**Godot is the only implementation that ships.** The game is `godot/`: Godot 4.7.1
(Compatibility), typed GDScript. New behaviour goes there and nowhere else. `npm run build` is
`godot:export`, and Pages publishes the Godot build at `/`.

**The TypeScript oracle is frozen, not gone.** `src/`, `test/`, `bench/` and the Vite and vitest
configs are on `main`, and CI's `check` job runs `npm test`, `typecheck`, `lint`, `format:check`
and `bench` against them. It is a reference, not a second product: add no features to it, port
no Godot change into it, and do not delete it or let it go red. The one exception is the stat
registry: a stat id that shared content names is registered in `src/sim/modifiers/stats.ts`, ids
and base/min only, so the oracle's content check can judge the file (docs/30, "The oracle stat
registry mirrors content stat ids"). No behaviour is ported with it. Its frozen parity fixtures under
`godot/parity/` are what `npm run godot:test` compares against; tag `ts-oracle-final` is the
rollback point.

**The engine pin is exact.** `scripts/run-godot.mjs` rejects any engine whose `--version` does
not start with `4.7.1`, and the same version and SHA-512 appear in `.github/workflows/ci.yml`,
`.github/workflows/pages.yml` and `scripts/setup-web-session.sh`. Change one, change all.

## How the code fits together

The parts that take several files to see. [docs/19](docs/19-architecture.md) and
[docs/20](docs/20-ecs-and-content.md) are the specs.

- **The sim is a deterministic ECS stepped at 20 Hz.** `SimWorld` (`godot/sim/world.gd`) owns
  the entity and component stores, a command queue, an event bus, named RNG streams
  (`rng_registry.gd`) and a system registry with twelve fixed phases, input to cleanup
  (`system_registry.gd`). `step()` takes the tick's commands, runs every system in phase order,
  and only then drains the events, so a handler runs after the tick's systems (docs/37).
- **A sim module registers itself.** Most files under `godot/sim/modules/` expose
  `register_module(world)`, which registers its systems and event handlers.
  `SimBoot.register_playable_modules` (`godot/sim/boot.gd`) is the one list that installs them.
  A module missing from it is a dead socket. `SimBoot.playable(seed)` builds the shipped district
  world, and gates and drivers boot through it.
- **Presentation reads the sim and never writes it.** `godot/presentation/main.gd` (scene
  `main.tscn`) steps the world on a clamped accumulator, draws bodies between ticks, and turns
  input into commands. The screen reads the sim through read models (`condition.gd`,
  `attention_read.gd`, `context.gd`), never through raw components. `godot/ui/` holds the panels,
  `godot/platform/` the content loader and validator, and `godot/content/` the JSON the sim and
  the looks read.
- **A gate is a headless script.** Each `godot/check_*.gd` boots its own worlds, prints
  `<NAME>_OK` or `<NAME>_FAIL`, and exits non-zero on failure. A new gate touches five places: the
  script, a mode in `scripts/run-godot.mjs`, a `package.json` script, the `godot:m2:chain` list,
  and a shard in `scripts/m2-shards.mjs`. It also needs a routing row. Gates in one process share
  `static var`s, so a lane that pins a flag restores it.

## Where the work is

Milestone 2, the vertical slice: one district, a handful of survivors, enough of every system to
find out whether the loop is fun. Its exit criterion is ten in-game days, permanent loss,
succession, and still wanting another run. The alpha plan's pieces (A0 to A24, written
2026-10-19) have all landed, each with its gate, in
[the record, by system](docs/23-roadmap.md#the-record-by-system). What comes next is set by
[the release plan](#the-release-plan), the owner's five stages of 2026-10-26: stage 1, alpha
closed, lands what is in flight, the sim pieces that need no owner call, the UI overhaul's next
bullets and the first pieces of [the content arcs](#the-content-arcs) (readers before content,
pictures a stage behind); stage 2 is the post-alpha balance wall (docs/23's "Balance after the
alpha"). [docs/23](docs/23-roadmap.md) is the authority on what is built and what remains,
piece by piece under [what's left](docs/23-roadmap.md#whats-left-in-milestone-2). Facts that
matter every session:

- **The survival loop is built, gated and on.** `SimShambler.GRABS_ENABLED` ships `true`. Any
  gate that pins the flag restores the previous value.
- **The alpha stopped at a balance wall on 2026-10-21.** The target was a colony alive on day 10
  on 2 of 3 seeds, and it was not met. The numbers, the traces and the next measurement are in
  docs/23's "Balance after the alpha" (under what's left). The next measurement is ten seeds and
  a median wipe day, on `main` and on each candidate. No lever is judged on three seeds again.
- **The presentation is flat top-down, not isometric,** in the Dungeon Settlers look decided
  2026-09-03. Read docs/30 in date order before changing a body or a tile.
- **A day is one real hour** (`Clock.DAY_SECONDS`, the owner's 2026-10-19 call). The speed
  ladder is 1x and 3x; 10x waits on the tick budget.
- **The boot colony is three**, the player, Mara and Ellis, by the owner's 2026-09-01 decision.
- **Dead sockets.** Complete, correct, gated code that nothing reads has turned up many times. A
  mechanism needs an assertion that something reaches it.
- **The whole-interface redesign is a proposal being built slice by slice,** not a shipped
  change. Read [docs/32](docs/32-ui-overhaul.md) and
  [the owner's 2026-10-03 decision](docs/30-decisions.md#the-whole-interface-2026-10-03) before
  applying older kit, font or chart requirements. Its work list is
  [docs/23's UI overhaul group](docs/23-roadmap.md#ui-overhaul).
- **For the current `main`,** run `git log origin/main -1` and look at its CI. This file carries
  no commit hash on purpose, because a hash written here is out of date after the next merge.

The longer state notes, the art history and the full dead-socket list are in
[the state of the build](docs/36-state-of-the-build.md). What the last session did and left is
under [What the session of 2026-11-01 did](#what-the-session-of-2026-11-01-did) and
[To do](#to-do) below.

## The workflow

How a unit of work goes through this repo, the same loop for a person, an agent, or both. The
pattern that works here is the **slice**: one named piece, built together with the gate that can
fail it, measured if it claims anything about balance, recorded in the same commit.

1. **Orient before touching anything.** [Start here](#start-here), then the
   [routing table](#routing-table) for where the work lives and which gate judges it.
2. **Pick one named piece from what's left.** Pieces are sized to land in a session. Owner
   decisions are not pickable: deciding one unilaterally is the one mistake no gate catches.
   Work that is not on the list gets named and added there first (or asked about), never
   smuggled in beside a slice.
3. **Design inside the seams.** Effects are sim-owned and command-driven; `godot/sim/` never
   reads presentation state; how a thing looks is content; new randomness gets its own named RNG
   stream. Anything player-facing goes through the standing bans *before* it is built.
4. **Build the gate with the thing.** Every assertion wants a true positive *and* a true
   negative, and every mechanism wants the assertion that something **reads** it (the dead-socket
   rule). An assertion with no data to judge says so and skips; it never passes quietly.
5. **Measure balance claims; never theorise them.** A claim about campaign outcomes comes from a
   throwaway driver, run before and after on the same driver. Do the throughput arithmetic
   first, from a fresh measurement on the machine you have: a game day is 72,000 ticks, and
   recorded throughput has ranged from under 30 to over 100 ticks/s by district and machine.
   `npm run godot:playtest` (one seed, ten days) is the standing whole-run driver; docs/35 has
   its last timing. Drivers are deleted afterwards; anything that stays gets a gate.
6. **Verify before committing,** per [Verifying a change](#verifying-a-change).
7. **Record in the same commit.** Delete the piece from what's left; write its record (named,
   gated, measured) into the record, by system. Update docs/33 only when what waits on the owner
   changed. Prose is hand-wrapped.
8. **Leave it honest.** No checkbox ledgers anywhere; every claim names the gate that proves it;
   where only half a thing shipped, the record says which half.

## Verifying a change

Correctness for a Godot change is the Godot gates, not tests. **Policy (the owner's call,
2026-10-19, docs/30):** before a commit, run the gates for what the change touched: its
`godot:m2:<name>` lane, `godot:smoke` and `godot:validate` for a boot or content change,
`godot:check:play` for a scene or input change, and `npm test` for anything under
`godot/content/` (the oracle's Ajv recurses where `godot:validate` does not). Touching a `.ts`
file or a prettier-covered path adds `typecheck`, `lint` and `format:check`; touching a script, a
runner mode, a `check_*.gd` or the routing table adds `check:routing`. **A change to a shared sim
module or the save format runs the full `npm run godot:m2` chain locally before its commit.** CI
runs the full chain on every pull request and every push to main, split across four shards, and
nothing merges red.

A new gate must be reachable: it goes into the `godot:m2:chain` script and into
`scripts/m2-shards.mjs` in the same commit, or `npm run check:routing` and
`npm run check:shards` go red.

The commands, timings and CI jobs are in [the gate list](docs/35-gates.md).

## Pushing and pull requests

- **One piece, one branch, one pull request,** opened from a fresh branch off `main` and based
  on `main`. A session pushes only its own branch. Never push to `main`. A fix to another open
  pull request is a pull request based on that one's branch ([How work flows](#how-work-flows)).
- **No model identifiers in anything pushed, with one amendment.** Commit messages, PR titles
  and bodies, code comments and docs never name the model that wrote them. That includes a
  `Co-Authored-By` trailer naming a model: leave it out and keep the session link
  (`Claude-Session:`). The amendment (the owner's call, 2026-11-01, docs/30): [the team
  roster](#the-team) in this file may name the model each role runs on, because a roster says
  who runs what, not who wrote what. Authorship stays unnamed everywhere, the roster included.
- **Fill in the PR template** (`.github/pull_request_template.md`): the piece, the gate, the
  measurement, the record, what was verified.
- **Drive it green** by the steward skill. Never skip, disable or loosen a gate to get there.
- **Merge with a merge commit,** after re-checking the head and CI right before merging. Pieces
  built side by side merge one by one as each goes green, and the thread that wrote a pull
  request never merges it ([How work flows](#how-work-flows)).
- **Cloud sessions cannot delete remote branches** (the git proxy returns 403 for any ref but
  the session's own). Name the branches that should go and let the owner delete them.

## Standing bans

These are settled. Re-read the linked clause before proposing a change to either; do not quietly
amend them.

**No health bar, and no way to compute one.** The
[condition view](docs/05-health-injury.md#the-condition-view) hands the screen a state and a
sentence per part — `{parts:[{part, state, prose, wounded, infected, armored, bleeding, bandage}],
stance, worst}`, whose every added field is a word or a boolean — and deliberately carries
**no integrity value, no maximum, and no fraction**, so a fill is not merely discouraged, it is
not computable from what the screen has. `godot/sim/condition.gd` is the one builder;
`npm run godot:ban:healthbar` serialises its output and asserts the absence, with a key
allowlist that fails the moment a numeric field is added. That gate is the ban made mechanical —
if it goes red, re-read
[hardcore contract clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable)
rather than widening the assertion.

**Information stays scarce and unreliable.** A bite can present as a scratch. Do not add
certainty the player is not supposed to have — exact quality, counts, positions, or anything
through walls.

**The HUD speaks in words.** `npm run godot:check:hud` allows **no digits on the player HUD
except the day counter**. Needs, condition, and attention all arrive as prose from sim read
models (`needs.hud_clause`, `sim/condition.gd`, `sim/attention_read.gd`). The numeric
developer sheet still exists and is still useful — it lives behind the `M` toggle, where the
gate ignores it.

**The one amendment, and it is narrow.** Since the owner's decision of 2026-09-12
([docs/30](docs/30-decisions.md), "The cartridge on the label") an **item's `name`** may carry a
digit, so a round can be called `.308 Winchester Match` rather than named around the ban. One
predicate, `SimItems.name_is_allowed` (in the sim since 2026-10-27, so the `item.name` command and
the gates ask the same question; `check_inventory.gd`'s `_name_is_allowed` calls it), is called by
both lanes that scan a name (STRIP and INSPECT) and refuses a name with no letter in it, which is a
quantity. A name the player gives a weapon they rebuilt (docs/33 items 23 and 24) is that same
`name`, read through `SimItems.item_name`, under that same predicate: it is not a second field.
**Nothing else moved**: `description`, every other value in the inspect pane, and every line
`check_hud.gd` reads are under the full ban, and the lane proves it by refusing the identical string
the moment it is a description instead. Do not widen this to a second field without the owner —
the whole reason it is written down here is that a ban amended once is a ban that gets amended
again.

**Budgets are correctness.** [docs/00 pillar 6](docs/00-vision.md): a feature that breaks budget
does not ship until it is fixed. Exceeding a budget fails the build at the same severity as a
failing test.

## Conventions

- Typed GDScript. `godot/sim/` is deterministic and must not read presentation state.
- Content is data under `godot/content/`, validated by `npm run godot:validate`. Note the
  validator is **shallow** — it checks top-level property types and rejects unexpected top-level
  keys, but does not recurse into nested objects. A nested shape needs its own gate; see
  `check_appearance.gd`.
- **How a thing looks is content, not code.** `appearance: {sprite, tint}` in a content entry;
  `presentation/appearance.gd` resolves it and falls back to role colours when there is no art.
  Never reintroduce a `if id == "zombie.x": col = ...` branch in the draw loop — that is what
  this replaced, and `godot:check:appearance` fails if the tints move back into code.
  `godot/assets/sprites/README.md` has the top-down grid and anchor convention.
- Prose is hand-wrapped; `.prettierignore` excludes `docs/` and `*.md` for that reason.
- **A gate that cannot fail is worse than no gate.** Every assertion wants a true positive *and* a
  true negative — `check_ban_health_bar.gd` set the convention after a field that was always
  `false` passed a "no leak" test, and `check_m2_npc_combat.gd` follows it. The same rule caught a
  seed loop that ran four seeds and proved one. If an assertion has no data to judge (a shortened
  campaign the director never pressured), make it **say so and skip**, never pass quietly.
- Update [docs/23's milestone status section](docs/23-roadmap.md#where-milestone-2-stands) in the
  same commit as the work it describes (workflow step 7). **Never** put per-item checkboxes in
  any status file: the retired `HANDOFF.md` ledger drifted four times, most recently by ~34
  shipped-but-unticked items, which is why status is condensed prose with each claim naming the
  gate that proves it. No gate enforces this, so the discipline is the convention. Where only
  half an item shipped, say which half.

## Traps

The traps that have already cost someone a session are in [docs/37](docs/37-traps.md). Read them
before touching the sim. Each one was found the expensive way. The known noise around the
gates, which is not a failure:

- **The worldgen gate's own clock.** `godot:check:worldgen` fails past 90 seconds
  (`BUDGET_SECONDS` in `godot/check_worldgen.gd`). On a loaded local machine it can trip on time
  alone. CI is the judge.
- **The Windows export job.** `godot-exports` sometimes crashes on import. A re-run settles it
  (the steward skill).
- **Engine shutdown noise.** `ObjectDB ... leaked at exit` after an `_OK` line is not a failure.
  Read the `_OK` line and the exit code.

## Who decides what

- **The owner decides design.** That covers new mechanics, changed rules a player would notice,
  the look, and everything under
  [Waiting on the owner](docs/33-owner-decisions.md#waiting-on-the-owner). Examples of new
  mechanics that went to the owner: quiet hours, noise-free repairs, a new water source, a held
  colonist striking back.
- **Agents decide engineering.** That includes tuning numbers that come out of a measurement. A
  call that is taken gets an entry in [docs/30](docs/30-decisions.md).
- **Ask once, with a default, and keep going.** In a Claude project, a design question goes to
  the owner as a decision card with one recommended option. Elsewhere, put it in the pull
  request. The card never blocks work: build the default, say that you did, and change it if
  the owner picks something else.
- **Steps that cannot be undone wait for the owner's own words.** Merging under the owner's
  standing authorization (below) is the one exception.

## How the owner works

- Mostly autonomous. The owner wants results and decision cards, not progress reports or
  numbered lists of questions.
- The alpha target is "basic mechanics playable, not polished". Sound is not a priority.
- Art follows Zero Sievert, and the outpost pack sets the quality floor. Animation must be
  fluid. A one-sided bob or a loop that pops blocks a merge.
- A colony wiped at home in its first days is an alpha blocker. Ten-day playtest numbers are a
  measurement, not a merge gate.
- `README.md` is for players and this file is for agents.
- The owner closes idle threads, and threads whose pull requests have merged get resolved.

## How work flows

In a Claude project, a coordinator talks with the owner in the project chat and opens one thread
per piece of work; in Orca, the coordinator dispatches terminals ([The Orca
workflow](#the-orca-workflow)). The rules below hold for any agent.
[docs/34](docs/34-agents-and-environment.md) covers branch naming and worktrees for agents
working outside a project.

1. **One piece, one branch, one pull request.** Branch off `main`, base the pull request on
   `main`, and push only your own branch. Fill in `.github/pull_request_template.md`. In a Claude
   project the rule is enforced: a thread's git proxy refuses (403) a push to any ref but the
   thread's own branch.
2. **A fix to someone else's open pull request is a pull request onto its branch.** Branch off
   that pull request's head, push your own branch, and open a pull request whose base is its
   branch. CI runs on it, because `ci.yml` runs on every pull request whatever its base. It merges
   into that branch under the same rules as a merge into `main` (step 4). #230 onto #228's branch
   was the first.
3. **Drive it green** by `.claude/skills/steward/SKILL.md`. Never skip, disable or loosen a gate.
4. **Claude merges, with a merge commit, and never the thread that wrote it.** The owner
   authorized merging. The coordinator, or a thread it names on the strongest tier, does it; the
   thread that wrote a pull request does not merge its own. Re-check the head commit and CI right
   before you merge. After a merge, tell the open threads the new `main`.
5. **Pieces built side by side merge one by one, each as it goes green** (the owner's call,
   2026-10-27). Merge the first green one. The next one then merges `main` in, waits for CI on
   its new head, and merges in turn. Conflicts in the tails of docs/23 and docs/30 are settled in
   that merge of `main`, by keeping both entries. A bundle of pieces in one integration pull
   request is only for two pieces that conflict in code, and it names the pull requests it
   closes. A piece that waits on another names it in its body and merges after it.
6. **Follow-ups start fresh.** A merged pull request is finished. New work goes on a fresh branch
   from `main` with a new pull request, never on top of merged history.
7. **Cloud sessions cannot delete remote branches.** The git proxy returns 403 for every ref but
   the session's own. Name the branches that should go, and the owner deletes them. Merged head
   branches come back after each merge unless "Automatically delete head branches" is on in the
   repository settings.
8. **Usage limits and restarts.** Containers restart, and sessions pause at usage limits. Push
   at a clean point before a long run. A thread revived after days can wake with stale context:
   brief it on the current `main` before it acts.

**Briefing a thread.** docs/23 and docs/30 are far too large to read whole at the start of a
piece; "read in order" under [Start here](#start-here) means the parts that bear on it. A brief
that opens a thread names them: the piece's entry in docs/23's what's left, its row in the
[routing table](#routing-table), the record entries of the systems it touches, and the docs/30
entries for those systems (search by the system's name). The thread reads this file, docs/37,
and those parts. A thread that finds it needs more reads more; the brief is a floor, not a fence.

**Art and placement review.** Before an art or placement pull request merges, an independent
read-only reviewer checks it (the owner's call, 2026-10-27):

- **The coordinator spawns the reviewer, never the thread that made the art.** Its brief is
  fixed: the pull request, its head commit, its base commit, and the shared folder for the
  report. A confirmation pass also gets the previous report. It is not told the thread's account
  of what changed or the decisions so far: those are what it checks.
- **The reviewer makes its own shots.** It runs `godot:shots` on the base and on the head commit
  and compares them, and it does not judge from the thread's exports. It measures the noise
  floor (base against base) before calling a difference. The report names both commits; a push
  after the verdict voids it.
- **Rounds.** Findings land as commits on the same pull request, and the review repeats until it
  is clear. Round 3 is the last full round. A later pass is a confirmation pass: it checks only
  the previous findings and raises only blockers. Minor findings in a clear round go into
  docs/23.
- Docs-only, gate-only and 1 to 2 px gate-verified follow-ups need no review.

## The release plan

Decided by the owner on 2026-10-26 ([docs/30](docs/30-decisions.md#the-release-plan-and-the-content-arcs-2026-10-26)).
Five stages, each with the thing it has to prove. Pieces are named in docs/23's what's left;
this section says which stage each group belongs to, and nothing here is ticked. The art style
does not change between stages: flat top-down, 32 px a tile at 2x, the outpost pack as the
floor, the Dungeon Settlers mood (docs/30, 2026-09-03 and 2026-09-17). An isometric view was
asked about and declined on 2026-10-26, for the third time; depth where wanted is oblique
treatment inside this projection. The first-person pivot of 2026-11-01 (docs/39) adds
conversion work ahead of this sequence and supersedes the flat-top-down art direction for the
conversion; the stages below are the preserved plan for the game's systems.

1. **Alpha closed: it loops.** Milestone 2's exit criterion in code, not balance. Everything in
   flight lands (colonist self-care, the buildables, the floodlight take-down, the Colony screen
   nits), then the sim pieces that need no owner call: round choice and the magazine's memory,
   the tourniquet, the purifier refill, the alarm and noisemaker priced, the plate that wears, the
   ranged affix readers, the repair economy. UI overhaul bullets three to five. The first
   worker-sized pieces of the content arcs below (the readers and the melee frames). Proof: the
   `godot:m2` chain green, `godot:check:play` covering every shell state.
2. **Alpha open: it survives.** The balance wall, judged only by ten seeds and a median wipe day.
   The named levers (a well inside the wall, the antibiotic weight, the six-survivor checkpoint,
   Guard and Scout, the night-3 table) and the speed pieces (sleep fast-forward, 3x and 10x, the
   tick to its 8 ms budget) so ten days fit an evening. The first zombie kinds and raider doctrine
   land here because they move the table. Release: the Windows build plus a Linux preset, and a
   seed you can type on the web build.
3. **The art pass: it looks finished.** Runs beside stage 2, on the art tier. The remaining pack
   wall states, pictures for the buildables and every new kind, part and frame from stage 1,
   remembered marks, the glimpse disc on the art grid, the last two held weapons, aim following
   the cursor, stamina in the world, the re-illustrated anatomy and the 1280x720 drawer, a roster
   for a large colony. Full before-and-after review at both windows. World draw to its 10 ms
   budget by baking chunks.
4. **Beta: people and the world.** Milestone 3A and the near half of 3B: relationships and grief,
   the six attributes, the full work grid, scars and the blind eye, diagnosis by skill, procedural
   people, the captive arc, explosives, the remaining zombie kinds and raider archetypes, the
   camp's labour cost, evolving camps, outposts that draw raiders, the region as the default boot
   if it plays. The save format freezes here and migrates from then on.
5. **1.0: breadth.** The rest of 3B and Milestone 4: streaming and district tiers, breakdowns and
   mobile bases, the industrial yard, factions and trade, the escape endgame, storyteller presets,
   a signed macOS build. Multiplayer (3C) is off this track and is 1.x unless the owner pulls it
   forward.

## The content arcs

Opened by the owner on 2026-10-26, the same entry. Four arcs, each a group in docs/23's what's
left with one piece per line there; this is the shape and the order, not the list. The rule that
binds all four: **readers before content, pictures a stage behind.** A stat nothing resolves is
not authored; a kind, part or frame gets its picture in the stage after its sim piece.

- **Zombies, seven to fourteen kinds.** Shipped: shambler, runner, stalker, screamer, bloater,
  heavy, armored (`godot/content/zombies/`). Planned, in landing order, each a content file and
  one behaviour hook with its own lane: the crawler (under sightline height, grabs ankles), the
  bloodhound (follows scent alone, deaf to noise), the gassed bloater (a lingering tile cloud),
  the lurker (dormant indoors, wakes on indoor noise), the juggernaut (shoves barricades), the
  burner (spreads fire to timber; waits on fire as a sim fact), the feigner (lies among corpses,
  rises on approach). Each re-baselines the ten-seed table and says so.
- **Raiders, four to nine archetypes, and a doctrine on the band.** Shipped: scav, looter,
  lookout, gunhand (`godot/content/raiders/`). A band gains a `doctrine` the director draws by
  day: probe, raid, siege, trade. Siege camps outside the wall and waits; trade approaches
  unarmed and offers barter, the one verb of Milestone 4's faction seam landed early. New
  archetypes: breacher, marksman, medic, arsonist (waits on fire), dog handler (the hound is a
  scent sensor and pairs with the bloodhound). A raider's weapon is assembled from the same part
  tables, so a dead marksman yields the rifle as he built it. The captive arc already in docs/23
  slots here unchanged.
- **Firearms: every number is a sum of its parts.** The assembly model exists: a base is the
  receiver, it spawns holding real parts, a conversion moves caliber, the bench and the field
  swap are split (`godot/sim/modules/gunsmith.gd`, `attachments.gd`, docs/10). The arc deepens
  it, readers first: the three stats that resolve against nothing (`noise_emission`,
  `condition_loss`, `repair_cost`) gain readers in the shot, the wear event and the repair verb;
  the barrel governs velocity, noise, accuracy and wear by length, quality and material;
  conversions become kits (barrel, bolt or cylinder, magazine, all three or it jams) drawn from a
  realism table in docs/10 keyed by receiver family, about twelve across the twelve receivers;
  furniture reads into aim time, recoil recovery and stance; internals are parts with condition
  and jam chance derives from the worst of them; magazines remember their load, the player picks
  the round, hand-loads are worse; Gunsmithing decides what is field work and the botch chance.
  The bench says it in words, never in numbers.
- **Melee: frames, not weapons, and bespoke results.** The nineteen melee weapons become frames
  in four families (club, blade, polearm, tool) and the slots widen from head, haft and wrap to
  add stud (nails, screws, barbed wire, glass), guard and weight. About twenty-five physically
  plausible recipes, each with what the modification costs the frame: nails split an aluminium
  bat and want wood; a pitchfork head on a pipe wants cordage and a fixing; glass cuts the hand
  without a wrap. Wear is specific: studs fall out on hits (the `hit` wear word, the attacker's
  side; `struck` is the target's, worn by a plate), an edge dulls and wants a whetstone, a lashed
  head flies off one swing in N. A weapon with three or more parts of the player's own may be
  named by the player, which is how bespoke reads on a screen with no stat line. Finished
  2026-10-27; its pictures are owed in stage 3.

**Open owner calls from the arcs** (docs/33 carries them): the realism table for conversions
(the coordinator writes it, the owner vetoes); whether fire becomes a sim fact in stage 1 or
stage 4 (it unlocks the burner, the arsonist and timber walls that burn); whether raiders may
trade before factions exist.

## Open owner calls

[docs/33](docs/33-owner-decisions.md#waiting-on-the-owner) is the list, and the only one. This
file names no card on purpose: a list copied here is out of date after the next card, the same
reason it carries no commit hash. Every card has a default that is already built, so none of them
blocks a piece.

## The shared folder

In Orca, the shared folder is `C:/Users/jtf/orca/sz-shared/`, one subfolder per piece, holding
each task's spec (`task-<who>.md`), a shared `BRIEF.md` where several workers share one, the
art reviews (`review_round-N.md`, `OPUS_VERDICT.md`) and handoffs. It is not in the repository.

A Claude project shares `/mnt/project-files/` between its threads. The folder is not in the
repository, and agents outside the project do not have it. It holds evidence and plans, not
instructions.

| Folder | What is in it |
|---|---|
| `planning/` | Plans, one subfolder per topic. Dated plans (the 2026-10-19 alpha plan, the 2026-10-24 feature plans) sit at the top. |
| `planning/balance/` | Playtest reports (`report.md`, `report-noise.md`, `report-ten-seed.md`), raw runs, and `ten-seed/`, one file per commit and seed |
| `planning/<topic>/` | One per feature or slice (`stockpile/`, `night-torch/`, `ui-slice-N/` and so on): its review, its before and after shots, its QA rounds |
| `planning/repo-cleanup/` | The branch audit and the 2026-10-23 cleanup plan |
| `a7-animation/` | Walk exports |
| `a8-actions/` | Action strips (`clothed/`, `clothed/falls-roundN/`, `zombies/roundN/`), each round with its QA report `qa-roundN.md` |
| `a9-aim/` | Aim exports |

- Put new files in a topic subfolder.
- The folder is a network mount. Put a trailing slash on its path, and read a shared file again
  before you change it, because the last write wins.
- **Never cite a shared-folder path inside the routing table.** `npm run check:routing` resolves
  every backticked path in that section against the repository, so such a path turns the gate
  red.

## Art and animation conventions

In the game:

- A tile is 32 art px, drawn at 2x on the boot zoom (`godot/project.godot`'s display comment).
- A body canvas is 32x40 with the soles on row 39. The heavy's canvas is 40x48 with the soles on
  row 47 (`godot/assets/sprites/README.md`).
- A clothing sheet has one row per view (S, E, N, W). Column 0 is the rest picture, columns 1 to 8
  are the walk, and column 9 is the breath (`godot/art/simplyzombies/clothing/README.md`).
- `npm run godot:check:action` holds every fall, lunge and stagger to the art review's bounds.
  Its header in `godot/check_action.gd` is the full list. The main ones:
  - Per step, the mass changes at most 15%, the centre moves at most 4 columns, and no edge moves
    more than 6 px.
  - The sole row is held. A stagger may rise one row for the knock-back.
  - A fall keeps at least half a head on every beat, and the head ends within 4 px of the
    corpse's head.

In the review exports in the shared folder:

- Survivor reload strips use 48x56 cells, with the sole on row 43 and the head top on row 16. In
  the game the same frames use the 32x40 canvas.
- Zombie action strips use 112x60 cells at 4x, with the sole on row 55.

Read the QA report of the previous round before you start a new one.

## Performance

The targets are in [docs/22](docs/22-performance.md#targets):

- **Tick:** at most 8 ms mean and 16 ms worst. `npm run godot:bench:runtime` measures it.
- **Draw:** at most 10 ms mean. `npm run godot:bench:frame` measures it at 1280x720 and needs a
  display.

The shipped game is over both targets, which is recorded as product debt. CI does not run the
two Godot timing commands. It runs only their exit contract (`npm run check:runtime-budget`).
Measure performance on a quiet machine, and take the median of interleaved runs.

## Screenshots for review

```bash
xvfb-run -a npm run godot:shots     # every scene at 1280x720 and 1920x1080
npm run godot:check:shots           # the gate; its PIXELS lane skips without a display
```

The scenes and window sizes are in `godot/review/scenes.gd`. Many branches edit that file, so it
attracts merge conflicts. Add your scene in a small, separate hunk, and rebase onto `main` before
you push.

## Where we left off (2026-11-01, paused by the owner)

The first-person conversion ([docs/39](docs/39-first-person-pivot.md)) is the work in hand. The
default boot is the first-person scene; the top-down game is reached with
`npm run godot:run:topdown`, and the title's "first person" row returns to first person. This
section is the handoff written when the owner paused the morning's work; the queue it lists has merged since
(#288 to #302, through #306's integration), and the session record below it is the current
state. Read both, then `gh pr list` and each pull request's CI, because both move.

**On `main`.** The pivot plan (docs/39), the spatial contract
([docs/40](docs/40-first-person-spatial-contract.md)), the first-person foundation and its
integration (containers, save and load, death and succession, doors, stance and gait, interim
fighting, the title row, day, night and the carried light, the ledger's Reports page, the shipped
district size, art that loads from a clean checkout), spatial slice 1 (`SimSpace`'s height
profile) and slice 2 (melee and zombie reach stop at walls), game speed, the Blender starter kit
and the weapon kit, the README's first-person section, the owner cards in docs/33, and the
review follow-ups in docs/23's first-person group.

**The queue that has since landed, in the order it merged.** Each merged `main` in and waited
for CI on its new head first (How work flows, step 5); the conflicts were docs/23's record list
(keep both entries) and the lane list and OK sentence of `godot/check_first_person.gd` (keep both
lanes).

1. #292 the starter kit drawn in the scene (walls, boards, shelves), and #290 aim pitch
   (spatial slice 3; the save stays at its version, reasoned in docs/30 "A pitch with no yaw").
2. #294 body animation state, then #297 talking to a colonist (stacked on #294); #295 the F1
   key reference; #296 the end-to-end expedition gate.
3. #299 the loot-item kit (art review clear after three rounds), then #301 the model loader
   (reads every `*.manifest.json`, shares one mipmapped texture per atlas, draws loose items),
   then #300 the held weapon assembled from the sim's installed parts.
4. #288 the survivor and shambler, after the independent art review's round 3. Then the body
   view plays its clips from #294's animation state.
5. #302, docs only: the weapon and item kit polish minors.

**In flight when paused.** The Kimi terminal was researching and prototyping better buildings
and walls (the owner: they look rather large and not good enough; make them look like Project
Zomboid). Its brief: a proposal at the coordinator's scratch path, a prototype on branch
`kimi/fp-buildings-proto` (no pull request), and before-and-after captures. The likely cause is
that a wall is a whole 1 m tile 2.55 m tall where Zomboid's walls are thin and on tile edges;
the proposal separates art-only fixes from sim changes (edge walls, a finer grid, a lower wall
band), which touch shared modules and may be owner calls. Read the branch and its report before
starting anything on buildings.

**Next, in order.** Review Kimi's buildings proposal with the owner. Then
[docs/41](docs/41-weapons-characters-world-plan.md), the plan for weapons, characters and a
bigger world: the bodies and the held weapon in the scene first, then a dressed and furnished
town, modular weapons, and docs/40's slices 4 to 7. The seven zombie kinds are the art lead's
next piece after the characters clear. A small cleanup is owed: `check_first_person.gd` prints
one hand-written OK sentence that every parallel branch edits; generate it from the lane list so
it stops conflicting.

**Waiting on the owner.** docs/33's first-person cards (the seven questions from docs/40 and the
pause policy), and docs/41's "For the owner" list. Every one has a default already being built.

## What the session of 2026-11-01 did

- **The survivor base body.** The box-segment `survivor.glb` was replaced by an organic,
  smooth-skinned woman matching the owner's concept art: 7,810 triangles, a modelled face,
  volumed hair with a high bun, painted pixel textures at 256 px/m (head) and 128 px/m (body).
  Four model rounds and five atlas versions. The modeler began it and handed off for usage; an
  Opus worker finished it. Committed on `kimi/fp-survivor-base`, not yet pushed; the owner
  called it "a good base, it can be improved upon. A lot."
- **The in-engine review driver** (`godot:shots:survivor`), PR #312, merged.
- **First person is the default boot;** F2 toggles a third-person testing view; the top-down
  game opens with `npm run godot:run:topdown`. PR #313.
- **The first-person arms contract** (`sz-shared/fp-arms/CONTRACT.md`) with the owner's answers:
  bare hands (gloves only when worn), inspect on a held `L`, an own view-model FOV with no wall
  clipping, 128 px/m for arms and bodies. The arms art started on `claude/fp-arms`.
- **PR #310** (building finishes) failed its first independent review (windows drawn as
  solid wall, inside-out hip roofs, a CRLF manifest), was fixed by an Opus worker with a
  real-worldgen window gate, and passed its confirmation pass.
- **The merge train, done.** #312, #308, #307, #313, #309, #310 and #311 merged, in that order.
  The owner chose to merge the last five without waiting for CI on their final heads.
- **Repo cleanup:** 41 merged worktrees removed, 37 merged local branches deleted, local main
  fast-forwarded.
- **This playbook.** `CLAUDE.md`, `AGENTS.md` and docs/38 merged into one root file, the
  owner's call, and the roster amendment of the model-identifier rule (docs/30).

## To do

- Confirm CI green on `main` after the merge train (#307, #313, #309, #310 and #311 merged on the
  owner's call without waiting for CI), and fix forward whatever is red.
- Push `kimi/fp-survivor-base` as its own PR (independent art review first), then improve the
  survivor further (the owner: "a lot").
- First-person arms: art round 2 is in flight on `claude/fp-arms`. The presentation code
  (`arms_view.gd`) and its ARMS lane are built on `claude/fp-arms-view`, stacked on it; they
  merge after the art, and the swap timing, the screen lowering and the hold-class rule wait on
  the owner's look.
- Codex's paint scripts (`codex/fp-survivor-paint`) are local only; decide whether they land.
- The ceiling follow-up for #310 (`sz-shared/reviews/followup-ceilings.md`).
- The shambler and the other six zombie kinds on the new organic base, with a lighter version
  for hordes (measure the frame cost first).
- The clothing layer system that follows the worn slots: a design note for the owner first.
- Remote branch cleanup (the owner's call): 40 merged remote branches; unmerged leftovers
  `claude/fp-profile` (6 lines), `kimi/fp-buildings-proto` (a prototype the finishes appear to
  supersede), `claude/project-thread-jqq1u5` (unexamined).

## Known bugs

- In the third-person testing view the held weapon is not drawn in the body's hand. The view
  model hides there (`claude/fp-arms-view`), which ends it floating beside the body (#313's
  capture), but nothing draws it on the body yet.
- 78 indoor counter, shelf and partition tiles across 9 building templates have no ceiling; the
  sky shows from inside (found by #310's confirmation review).
- Godot generates untracked `*.translation` files from the art-docs CSVs
  (`godot/art/simplyzombies/docs/`); nothing ignores them, so worktrees show as dirty.
- `godot:check:fp_geometry` went from about 2 s to 18 s with #310's real-worldgen lane.
- In the survivor review scene the light is flat grey; it does not show the game's mood, so
  colour judgements made there run dark.
- No presentation code draws a lowered weapon yet (`SimAim.holds`, `FireState` have no reader).
- #309's bench screen does not hide the held weapon (`first_person.gd:887` on that branch); the
  arms on `claude/fp-arms-view` lower it behind every screen, the bench's included.

## Lessons from the session

- Render the existing asset before judging it; the "blocky" problem was visible in one render.
- The in-engine sheet is the judge; Blender renders flattered the model each round.
- A hand-painted 2D target for first-person arms did not converge; the 3D model sets the pose.
- An independent reviewer catches what a gate misses: the window bug passed its gate because
  the gate stamped templates without real worldgen.
- Stacked PRs (a PR based on another PR's branch) keep dependent work moving; the coordinator
  retargets them to main after the base merges.

## The docs map

| Need | Read |
|---|---|
| First-person conversion: approved direction, phases, spatial contracts and archive | [docs/39](docs/39-first-person-pivot.md) |
| What is open, what landed, with evidence | [docs/23, the roadmap](docs/23-roadmap.md) |
| Which release stage a piece belongs to, and the four content arcs | [The release plan](#the-release-plan), [The content arcs](#the-content-arcs) |
| Why something is shaped the way it is | [docs/30, the decisions](docs/30-decisions.md), oldest first |
| Decisions waiting on the owner | [docs/33](docs/33-owner-decisions.md) |
| Other agents, the two containers, MCP servers, running the game, screenshots | [docs/34](docs/34-agents-and-environment.md) |
| Every gate, its command, its timing, and what CI runs | [docs/35](docs/35-gates.md) |
| The state of the build in full, and the dead-socket list | [docs/36](docs/36-state-of-the-build.md) |
| Traps that already cost someone a session | [docs/37](docs/37-traps.md) |
| Performance targets and dated measurements | [docs/22](docs/22-performance.md) |
| The slice vocabulary | `CONTEXT.md` |
| How a pull request is driven to green | `.claude/skills/steward/SKILL.md` |
| A system's design spec | the "By system" table under [Routing table](#routing-table) |
| Where a system's code lives, and the gate that judges it | [Routing table](#routing-table) |
| Architecture, content, extensibility | [docs/19](docs/19-architecture.md), [docs/20](docs/20-ecs-and-content.md), [docs/21](docs/21-extensibility.md) |
| The UI overhaul's brief | [docs/32](docs/32-ui-overhaul.md) |
| Post-slice designs: the wider region, mobile bases, multiplayer | [docs/24](docs/24-world-and-scale.md), [docs/26](docs/26-mobile-bases.md), [docs/27](docs/27-multiplayer.md) |
| History: the engine move, the early need ADRs | [docs/31](docs/31-godot-rebuild-roadmap.md), `docs/adr/` |

The design specs are numbered in the order they were written, not reading order. New to the
design? Read docs/00, 01, 03, then 23.

## Routing table

Where a unit of work goes: what to read before touching it, where the code lives, the gate that
can fail it, and where its record is written. `npm run check:routing` judges this table -- every
path, script and link in this section must resolve, and every `godot/check_*.gd` must be reachable
from an npm script -- so a route here is a claim the build checks, not a note that drifts. Add a
row when a system gains a home; the gate goes red when a route stops being true.

**By the kind of work:**

| If the work is... | Read first | It lives in | The gate | Record it in |
|---|---|---|---|---|
| Starting a session cold | [PLAYBOOK.md](PLAYBOOK.md), then [what's left](docs/23-roadmap.md#whats-left-in-milestone-2) | -- | `npm run godot:smoke` proves the engine | -- |
| A decision named under [Waiting on the owner](docs/33-owner-decisions.md#waiting-on-the-owner) as the owner's | that entry, and [docs/30](docs/30-decisions.md) | nowhere: stop and ask | -- | -- |
| A sim mechanic (a need, a wound, a job, the weather) | the system's spec in the table below, [docs/30](docs/30-decisions.md), and the traps in [docs/37](docs/37-traps.md#traps-that-have-already-cost-someone-a-session) | `godot/sim/modules/`, `godot/sim/` | its `godot:m2:<name>` gate while iterating; `npm run godot:m2` before the commit | [the record, by system](docs/23-roadmap.md#the-record-by-system); a call taken goes in [docs/30](docs/30-decisions.md) |
| Content (an item, a zombie, a loot table, a weather kind) | [docs/20 Part 2](docs/20-ecs-and-content.md#part-2-content) and the schema under `godot/content/schemas/` | `godot/content/` | `npm run godot:validate` **and** `npm test` (only the oracle's Ajv recurses), plus the nested-shape gate for that block | the record |
| How a thing looks | [the Dungeon Settlers look](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03), `godot/assets/sprites/README.md` | `godot/presentation/`, `godot/assets/sprites/`, `tools/sprites/` | the `godot:check:<look>` gate for that layer; `npm run sprites:check` after touching `tools/sprites/` | the record |
| The first-person Blender starter kit | [the kit's README](tools/blender/first_person_kit/README.md) | `tools/blender/first_person_kit/`, `godot/assets/first_person/` | `blender --background --factory-startup --python tools/blender/first_person_kit/build_kit.py -- --check` proves dimensions, origins, atlas use and byte reproducibility | the record |
| First-person building finishes and glazing | [the building kit's README](tools/blender/first_person_buildings/README.md), [docs/41 section C](docs/41-weapons-characters-world-plan.md#c-a-bigger-world-and-procedural-generation) | `tools/blender/first_person_buildings/`, `godot/assets/first_person/buildings/`, `godot/assets/first_person/buildings.manifest.json`, `godot/presentation/first_person/building_view.gd` | `blender --background --factory-startup --python tools/blender/first_person_buildings/build_finishes.py -- --check` prints `BUILDINGS_CHECK_OK` (all 22 templates, bounds, contact, coplanar faces, density, look coverage, roof winding, open window apertures, byte reproducibility) and has eight failing `--plant` modes; `npm run godot:check:fp_geometry` proves drawn bands, solid-host attachment, and (its WORLDGEN lane, on all four generated districts) that every sim window in a finished building is drawn open and every sim wall drawn as a wall | the record |
| The first-person weapon kit: receivers, parts, melee, their sockets | [the weapon kit's README](tools/blender/first_person_weapons/README.md), the socket contract | `tools/blender/first_person_weapons/build_weapons.py`, `godot/assets/first_person/weapons/`, `godot/assets/first_person/weapons.manifest.json` | `blender --background --factory-startup --python tools/blender/first_person_weapons/build_weapons.py -- --check` prints `WEAPONS_CHECK_OK` (bounds, sockets against content slots, origins, single-sided single material, coplanar faces, texel density, assembly contact, byte reproducibility); `-- --prove` plants an error per check | the record |
| The first-person view-model arms: hands, sleeves, rig and clips for every hold class | [the arms kit's README](tools/blender/first_person_arms/README.md), the arms contract | `tools/blender/first_person_arms/build_arms.py`, `godot/assets/first_person/arms/` | `blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --check` prints `ARMS_CHECK_OK` (bytes, names, anchor, grip-land, wrap, sight-line, near-plane, stump, in-frame, chain, smooth, weights, cuff, density, paint-match, body-match, budget, measured on the exported GLB); `-- --plant <name>` turns each check red | the record |
| The first-person loot-item kit: world-pose models for the things a player picks up | [the item kit's README](tools/blender/first_person_items/README.md) | `tools/blender/first_person_items/build_items.py`, `godot/assets/first_person/items/`, `godot/assets/first_person/items.manifest.json` | `blender --background --factory-startup --python tools/blender/first_person_items/build_items.py -- --check` proves bounds, origins, bodies resting on the floor, item ids and coverage, every item within 2x of its expected size, no laddered item drawn as another item's own model, one single-sided closed material per model, no coplanar faces, texel density per face and byte reproducibility; each check has a `--plant` that turns it red | the record |
| First-person presentation | [the foundation report](docs/planning/first-person-foundation-report.md), [docs/37](docs/37-traps.md) | `godot/presentation/first_person/`, `godot/check_first_person.gd`, `godot/check_fp_expedition.gd` | `npm run godot:check:first_person` runs the headless gate, whose MODELS lane holds the manifest loader (`godot/presentation/first_person/models.gd`) and the loose items it draws (`godot/presentation/first_person/loose_view.gd`), and whose BODIES lane holds the character bodies (`godot/presentation/first_person/body_view.gd`), and whose ARMS lane holds the view-model arms and the weapon in their hand (`godot/presentation/first_person/arms_view.gd`); `npm run godot:check:fp_expedition` runs the one-run expedition gate (ledger, door, container take, F5/F9, a shambler struck, and two true negatives); `npm run godot:run:first_person` launches the opt-in scene | the report |
| Art somebody drew for us | [the brief](godot/assets/sprites/README.md), [art we did not generate](docs/30-decisions.md#art-we-did-not-generate-2026-09-09) | `godot/assets/sprites/authored.json` declares it; the PNG sits beside it | `npm run godot:check:authored` holds it to the published bounds and refuses art nothing reads; `npm run sprites:check` proves it is present at the canvas it declares | the record |
| Art from the outpost pack | [the pack's own README](godot/art/simplyzombies/README.md), [the outpost pack, adopted](docs/30-decisions.md#the-outpost-pack-adopted-2026-09-17) | `godot/assets/sprites/authored.json` declares it, with a `source` (a path, optional `crop`/`pad`) under `godot/art/simplyzombies/`, or as a member of a `source`-carrying `members` family | `npm run sprites:check` reproduces the committed PNG from its source and compares decoded pixels; `npm run godot:check:authored`'s MANIFEST, TIER and SOURCE lanes hold the declaration to shape and the READS lane to a real reader; the look gate of whichever family it lands in (`godot:check:<look>`) once that piece exists | the record |
| The screens' frames, glyphs, cursors and motion: the UI Field Kit | [the kit's own README](godot/art/simplyzombies-ui/README.md), [the UI Field Kit, live](docs/30-decisions.md#the-ui-field-kit-live-2026-09-25) | the approved kit under `godot/art/simplyzombies-ui/` (`godot/art/simplyzombies-ui/manifest.json` and `godot/art/simplyzombies-ui/styles/*.tres` are the spec, read as text; the game never loads a kit `.tres`), resolved by `godot/ui/kit.gd` and worn through `godot/ui/chrome.gd`'s helpers | `npm run godot:check:ui_skin` (`godot/check_ui_skin.gd`): KIT holds `Kit.NINE` to the manifest and the `.tres`, RESOLVE proves every consumed PNG loads headless, PANEL follows `Chrome.panel` to the kit, HELPERS refuses a chrome helper nothing calls, FONT holds every screen to `Chrome.font()` (the kit's VT323, `godot/art/simplyzombies-ui/fonts/VT323-Pixel.res`) and every text size to `Chrome.LADDER` | the record |
| What the screen says | [hardcore contract clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable), the vocabulary in [CONTEXT.md](CONTEXT.md) | `godot/ui/`, the read models `godot/sim/condition.gd`, `godot/sim/attention_read.gd`, `godot/sim/modules/chronicle.gd` and `SimSkills.web_map` in `godot/sim/modules/skills.gd`; the click that picks a colonist, `godot/presentation/pick.gd`, whose `Pick.pick_at` is also what is under a right-click; what you may do about it, `godot/sim/context.gd`'s `SimContext.verbs_at`, drawn by `godot/ui/context_menu.gd`; the keys that reach any of it, `godot/presentation/input_map.gd`; the run's four states and the three screens that are not the game, `godot/presentation/session.gd` and `godot/ui/shell.gd`; the afterimage and the dimmed remembered map, `godot/presentation/main.gd`'s `_draw_afterimages`/`_draw_district` and `godot/presentation/palette.gd`'s `remembered`; speech bubbles, `godot/sim/modules/speech.gd`'s `saying` component and `godot/presentation/main.gd`'s `_draw_bubbles`, drawn over a Focal body only (`_focal_drawn`) and never a name; the one bar over Survivor, Colony and Skills, `godot/ui/nav_bar.gd`, switched by `godot/presentation/main.gd`'s `_show_screen`; a picked body part's condition and care, `godot/ui/care_pane.gd`, offering only what `SimTreatment.options_for` in `godot/sim/modules/treatment.gd` allows; the Colony screen, `godot/ui/work_panel.gd`, its "now" line from `godot/sim/work_read.gd` | `npm run godot:check:hud`, `npm run godot:check:inventory`, `npm run godot:ban:healthbar`, `npm run godot:check:respond`, `npm run godot:check:web_look`; and `npm run godot:check:play`, which boots `godot/presentation/main.tscn` and presses the keys; `npm run godot:check:memory` (`godot/check_memory_look.gd`) for the afterimage and the remembered map; `npm run godot:check:context` (`godot/check_context.gd`) for the menu's rows, their dispatch, walk-here's speed and the scene that opens and closes it; `npm run godot:check:speech` (`godot/check_speech.gd`) for a bubble's content, its triggers and the draw path that reads it; the bar's keys, clicks and Escape in `godot:check:play`'s NAV lane, the Colony screen in its COLONY lane, and the care pane in `godot:check:inventory`'s CARE lane | the record |
| A claim about balance | [the workflow's step 5](PLAYBOOK.md#the-workflow), [docs/22 on measuring](docs/22-performance.md#measuring) | a throwaway driver, deleted afterwards; a claim about a whole run starts from the standing scripted survivor, `godot/playtest/ten_day.gd` (`npm run godot:playtest`, one seed, ten days, a line per day; `PLAYTEST_SEED`, `PLAYTEST_DAYS`, `PLAYTEST_LOG`) | `npm run godot:m2:balance` and `npm run godot:m2:harness`; the before/after numbers | the record, numbers included |
| The save format | [docs/19's save model](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd` (`SAVE_VERSION`), `godot/sim/save.gd` | `npm run godot:m2:save` | the record |
| A gate, new or fixed | [a gate that cannot fail](PLAYBOOK.md#conventions), the dead-socket rule in [PLAYBOOK.md](PLAYBOOK.md#where-the-work-is) | `godot/check_*.gd`, a mode in `scripts/run-godot.mjs`, a script in `package.json`, a link in the `godot:m2` chain, a shard in `scripts/m2-shards.mjs` | `npm run check:routing` proves it is reachable; `npm run check:shards` proves CI runs it | the record |
| The frozen TypeScript oracle | [What the project is](PLAYBOOK.md#what-the-project-is) | `src/`, `test/`, `bench/` | `npm run typecheck`, `npm run lint`, `npm run format:check`, `npm test`, `npm run bench` | nothing: it gains no features |
| CI, scripts, hooks, this table | [the verifying section](PLAYBOOK.md#verifying-a-change) | `.github/workflows/` (`.github/workflows/ci.yml` the gates, `.github/workflows/pages.yml` the web build, `.github/workflows/release.yml` the downloadable build, run by hand with a version or by a pushed `v` tag), `scripts/`, `.claude/` | `npm run check:routing`, `npm run check:timing`, `npm run format:check`; the engine pin in `scripts/run-godot.mjs` | the record's Kernel & tooling entry |
| Shipped runtime performance | [docs/22](docs/22-performance.md#shipped-godot-runtime-measurements) | `godot/bench/runtime_tick.gd`, `godot/bench/runtime_frame.gd`, `godot/bench/measured_main.gd`, `scripts/runtime-budget.mjs`, `scripts/run-godot.mjs` | `npm run check:runtime-budget` judges the production runner contract; `npm run godot:m2:tick` (`godot/check_m2_tick.gd`) holds each tick speed-up to the slow answer it replaced; `npm run godot:bench:runtime` and `npm run godot:bench:frame` measure actual timing on a quiet machine (frame needs a display). Existing overruns remain product debt; the real timing commands are not yet CI shipping gates. | docs/22's dated measurements and the record |
| Driving a pull request | `.claude/skills/steward/SKILL.md`, then [Pushing and pull requests](PLAYBOOK.md#pushing-and-pull-requests) | -- | whatever CI reports; the touched gates before every push, per [Verifying a change](PLAYBOOK.md#verifying-a-change) | the PR itself |
| The survivor body in the game's renderer: a candidate GLB under the first-person scene's sky, lens and eye, beside the concept | The header of `godot/review/survivor_shots.gd`, then the first-person loader `godot/presentation/first_person/models.gd` | `godot/review/survivor_shots.gd` (the driver; `--glb=` or `SURVIVOR_GLB` picks the model, `--out=` the folder), `godot/presentation/first_person/sky_view.gd` (the light the shots use) | `npm run godot:shots:survivor` renders and composes the sheet; it is a render, not a gate, and needs a display | the PR itself |
| Playing it, or a screenshot | [Running the game](docs/34-agents-and-environment.md#running-the-game-gui) below | `godot/presentation/first_person/first_person.tscn` (the default boot), `godot/presentation/main.tscn` (the top-down testing game) | `npm run godot:run` (first person), `npm run godot:run:topdown` | -- |
| Art review: before and after screenshots of fixed scenes at both windows | the header of `godot/review/shots.gd`, then `godot/review/scenes.gd` | `godot/review/scenes.gd` (each scene and its verify), `godot/review/shots.gd` (the capture driver, run with `DISPLAY=:1 npm run godot:shots`) | `npm run godot:check:shots` (`godot/check_shots.gd`); its PIXELS lane skips without a display | the record |

**By system** -- the spec, the code, and the gate that proves it. Where a row names several
gates, the first is the one to iterate on:

| System | Spec | Sim | Gate |
|---|---|---|---|
| Attention: noise, scent, light | [docs/03](docs/03-attention.md) | `godot/sim/field/attention.gd`, `godot/sim/modules/attention_emitter.gd`, `godot/sim/attention_read.gd` | `godot:m2:district` |
| Carried light, what burns it down and what feeds it | [docs/03](docs/03-attention.md), [docs/12](docs/12-resources.md) | `godot/sim/modules/light.gd`, `godot/sim/vision/light.gd`, `godot/content/items/lights.json`; the beam on screen, `godot/presentation/light_look.gd` | `godot:m2:light_burn`, `godot:m2:torch`, `godot:check:light` |
| Bait: noise you place, wind up and take back up | [docs/03](docs/03-attention.md#playing-the-field) | `godot/sim/modules/noise_device.gd`, `godot/sim/modules/fortify.gd`, `godot/content/items/noise.json` | `godot:m2:noise`, `godot:m2:fortify` |
| Needs | [docs/04](docs/04-survival-needs.md) | `godot/sim/modules/needs.gd` | `godot:m2:needs` |
| Clothing: warmth, wet and cooling | [docs/04](docs/04-survival-needs.md) | `godot/sim/modules/needs.gd`, `godot/content/items/clothing.json` | `godot:m2:warmth` |
| Comfort: something for your morale that is not a meal | [docs/04](docs/04-survival-needs.md) | `godot/sim/modules/needs.gd`, `godot/content/items/comfort.json` | `godot:m2:comfort` |
| Camping and utility gear: what you sleep on, what you wash with | [docs/04](docs/04-survival-needs.md), [docs/10](docs/10-items.md) | `godot/sim/modules/needs.gd` (`furnish_bed`, `_spend_soap`), `godot/content/items/camping.json` | `godot:m2:needs`, `godot:m2:gear` |
| Health, wounds, recovery | [docs/05](docs/05-health-injury.md) | `godot/sim/modules/health.gd`, `godot/sim/modules/wounds.gd`, `godot/sim/condition.gd` | `godot:m2:wounds`, `godot:m2:armor`, `godot:m2:recovery`, `godot:m2:splint`, `godot:ban:healthbar` |
| Infection and treatment | [docs/06](docs/06-infection.md) | `godot/sim/modules/infection.gd`, `godot/sim/modules/treatment.gd` | `godot:m2:treatment`, `godot:m2:medicine`, `godot:m2:lethality`, `godot:check:respond` |
| Survivors, recruits, the roster | [docs/07](docs/07-survivors.md) | `godot/sim/modules/survivors.gd`, `godot/sim/modules/recruits.gd`, `godot/sim/modules/roster.gd`, `godot/sim/modules/aptitudes.gd` | `godot:m2:roster`, `godot:m2:recruits`, `godot:m2:stats` |
| The skill web, Focus, jobs | [docs/08](docs/08-skill-web.md) | `godot/sim/modules/skills.gd`, `godot/sim/modules/jobs.gd`, `godot/sim/work_read.gd` (what a colonist is doing now, for the Colony screen) | `godot:m2:web`, `godot:m2:autonomy`, `godot:m2:jobs`, `godot:m2:upkeep` |
| Colonist orders: go there, hold there, haul that | [docs/08](docs/08-skill-web.md), the A16 entry of the alpha plan in the project files | `godot/sim/modules/orders.gd` (the command, what it accepts, the HUD line), `godot/sim/modules/jobs.gd` (`_follow_order`, `_follow_haul`, the reservation), `godot/sim/context.gd` (`_order_rows`), `godot/presentation/main.gd` (`_draw_orders`) | `godot:m2:orders`, `godot:check:context` |
| Books that teach: an item that pays into the web | [docs/08](docs/08-skill-web.md) | `godot/sim/modules/skills.gd` (`teach`, `PRACTICE_POINTS`), `godot/sim/modules/needs.gd` (`read_book`), `godot/content/items/books.json` | `godot:m2:teach` |
| Combat, stances, aim | [docs/09](docs/09-combat.md), [docs/29](docs/29-movement-and-stances.md) | `godot/sim/modules/melee.gd`, `godot/sim/modules/ranged.gd`, `godot/sim/modules/npc_combat.gd`, `godot/sim/stances.gd`, `godot/sim/combat.gd` | `godot:m2:swipe`, `godot:m2:hands`, `godot:m2:space`, `godot:m2:ranged`, `godot:m2:ammo`, `godot:m2:aim`, `godot:m2:stance`, `godot:m2:npc`, `godot:m2:contact` |
| Items, inventory, attachments, gunsmithing, modification | [docs/10](docs/10-items.md), [docs/11](docs/11-crafting.md) | `godot/sim/modules/items.gd`, `godot/sim/modules/inventory.gd`, `godot/sim/inventory/grid.gd`, `godot/sim/modules/attachments.gd`, `godot/sim/modules/gunsmith.gd`, `godot/sim/modules/modification.gd`, `godot/sim/modules/containers.gd` | `godot:m2:attach`, `godot:m2:armor`, `godot:m2:ammo`, `godot:m2:bench`, `godot:m2:gear`, `godot:m2:filter`, `godot:check:mods`, `godot:check:inventory` |
| Loot and resources | [docs/12](docs/12-resources.md) | `godot/sim/loot.gd`, `godot/content/loot/` | `godot:check:loot` |
| Stockpile: where the colony keeps things | [docs/12](docs/12-resources.md#storage-and-spoilage) | `godot/sim/modules/stockpile.gd` (the zone, its mark command and `preview`), `godot/sim/modules/needs.gd` (`is_stockpile_tile`), `godot/sim/stockpile_read.gd` (what the Colony screen says is kept, in words); marking it on screen, the Z brush in `godot/presentation/input_map.gd` (`_mark_input`) and the overlay in `godot/presentation/stockpile_look.gd`, drawn by `godot/presentation/main.gd`'s `_draw_stockpile` | `godot:m2:stockpile`, `godot:m2:jobs`, `godot:check:play` (MARK, STOCKPILE), `godot:check:memory` (STOCKPILE) |
| Cooking and water: what one thing turns into | [docs/04](docs/04-survival-needs.md), [docs/12](docs/12-resources.md) | `godot/sim/modules/jobs.gd` (the cook job), `godot/sim/modules/needs.gd` (boil, purify), `godot/content/items/kitchen.json` | `godot:m2:transform` |
| Zombies | [docs/14](docs/14-zombies.md) | `godot/sim/modules/shambler.gd`, `godot/sim/modules/bloater.gd`, `godot/sim/modules/screamer.gd` | `godot:m2:contact`, `godot:m2:swipe`, `godot:m2:filter`, `godot:m2:lethality` |
| Zombie variants, their walk cycles and settled corpses | [the sprite brief](godot/assets/sprites/README.md), [docs/14](docs/14-zombies.md) | `godot/presentation/appearance.gd`, `godot/presentation/main.gd`, `godot/sim/world.gd`, `godot/sim/modules/recruits.gd`, `godot/content/zombies/` | `godot:check:zombie_art` (`godot/check_zombie_art.gd`), `godot:check:authored`, `sprites:check` |
| Survivor clothing: torso, legs and feet painted on every frame, and the default outfit | [the clothing README](godot/art/simplyzombies/clothing/README.md), [the sprite brief](godot/assets/sprites/README.md) | `godot/art/simplyzombies/clothing/` (the painter and its sheets), `godot/assets/sprites/authored.json` (kind `wear`), `godot/presentation/appearance.gd` (`outfit_of`, `body_texture`), `godot/content/players/player.json` (`appearance.outfit`) | `godot:check:worn` (COVERAGE, DRESSED, STEP), `godot:check:authored` (WEAR), `sprites:check`, and `python3 godot/art/simplyzombies/clothing/build_clothing.py --check` after touching the painter |
| Fortification, and the benches built the same way | [docs/15](docs/15-base-building.md) | `godot/sim/modules/fortify.gd`, `godot/sim/modules/gunsmith.gd` | `godot:m2:fortify`, `godot:m2:bench` |
| Build materials: what a recipe is made of | [docs/12](docs/12-resources.md) | `godot/sim/modules/fortify.gd` (the kind vocabulary and the recipe table), `godot/content/items/materials.json` | `godot:m2:materials` |
| Weather | [docs/16](docs/16-weather.md) | `godot/sim/modules/weather.gd`, `godot/content/weather/`, `godot/content/climate/` | `godot:m2:weather`, `godot:m2:storm`, `godot:m2:cold`, `godot:m2:heat`, `godot:m2:warmth`, `godot:m2:fog`, `godot:check:weather` |
| The director and the raiders | [docs/17](docs/17-director.md), [docs/18](docs/18-factions.md) | `godot/sim/modules/director.gd`, `godot/sim/modules/raiders.gd`, `godot/sim/modules/allegiance.gd` | `godot:m2:director`, `godot:m2:raiders` |
| The district and world generation | [docs/24](docs/24-world-and-scale.md) | `godot/sim/map/`, `godot/content/districts/`, `godot/content/buildings/` | `godot:check:worldgen`, `godot:check:buildings`, `godot:m2:district` |
| The region: several districts in one space | [docs/24](docs/24-world-and-scale.md#the-region) | `godot/sim/map/region.gd`, `godot/content/regions/` | `godot:m2:region` |
| Where home is, and the camp that moves it | [docs/15](docs/15-base-building.md#base-siting) | `godot/sim/home.gd`, `godot/sim/modules/camp.gd` | `godot:m2:camp` |
| The ground, and water | [docs/24](docs/24-world-and-scale.md#the-ground) | `godot/sim/map/surface.gd`, `godot/sim/map/tilemap.gd` | `godot:check:water`, `godot:check:road` |
| Vehicles | [docs/25](docs/25-vehicles.md) | `godot/sim/modules/vehicles.gd`, `godot/content/vehicles/` | `godot:m2:vehicles`, `godot:check:wrecks`, `godot:m2:light_burn` (the siphon) |
| Sightlines and memory | [docs/28](docs/28-visibility-and-sightlines.md) | `godot/sim/vision/`, `godot/sim/modules/sightings.gd` (every body remembered with a `kind`; the per-observer `explored` bitset) | `godot:m2:sight`, `godot:check:memory` (`godot/check_memory_look.gd`) for the afterimage and the remembered map it feeds on the presentation side |
| First-person space: the height profile, the body cylinders, the eye, and what is in the way of a blow | [docs/40](docs/40-first-person-spatial-contract.md) | `godot/sim/space/space.gd` (`SimSpace.PROFILE`, `body_of`, `eye_of`, `segment_clear`, `reach_clear`, asked by `godot/sim/modules/melee.gd`'s `_resolve_strike`, `godot/sim/modules/shambler.gd`'s `_clear_contact` and `godot/sim/modules/npc_combat.gd`'s `can_strike`), drawn by `godot/presentation/first_person/district_view.gd` and `godot/presentation/first_person/body_view.gd` | `godot:m2:space` (`godot/check_m2_space.gd`), `godot:check:fp_geometry` (`godot/check_fp_geometry.gd`) | the record |
| Speech: what a body says out loud | [docs/30](docs/30-decisions.md) | `godot/sim/modules/speech.gd`, `godot/content/speech/` | `godot:check:speech` |
| Save and load | [docs/19](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd`, `godot/sim/save.gd` | `godot:m2:save` |
| The overcast day: the finished picture graded by the sky's share of daylight, off at night and under no HUD | [docs/30](docs/30-decisions.md#the-overcast-day-as-a-grade-2026-10-24) | `godot/presentation/day_grade.gd`, `godot/presentation/day_grade.gdshader`, `godot/presentation/main.gd` (`_draw_day_grade`; the world's words, bubbles and pawn tag, painted over the grade by `_paint_world_text`) | `godot:check:grade` (`godot/check_grade_look.gd`; its PIXELS lane runs headed when `DISPLAY` is set) |
| The look | [docs/30](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03) | `godot/presentation/`, `tools/sprites/` | `godot:check:topdown`, `godot:check:appearance`, `godot:check:camera`, `godot:check:motion`, `godot:check:action`, `godot:check:world_bake`, `godot:check:light`, `godot:check:road`, `godot:check:water`, `godot:check:wrecks`, `godot:check:roof`, `godot:check:trees`, `godot:check:worn`, `godot:check:authored`, `godot:check:fx`, `godot:check:grade`, `sprites:check` |
| The screen | [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) | `godot/ui/` (its frames from the UI Field Kit, `godot/art/simplyzombies-ui/`, through `godot/ui/kit.gd`), `godot/presentation/main.gd`, `godot/presentation/input_map.gd` | `godot:check:ui_skin`, `godot:check:hud`, `godot:check:inventory`, `godot:check:respond`, `godot:check:web_look`, `godot:ban:healthbar`, `godot:check:play` (the one gate that executes the scene: `godot/check_play.gd`) |
| Balance and the campaign harness | [docs/22](docs/22-performance.md#measuring) | `godot/check_m2_balance.gd`, `godot/check_m2_harness.gd`, `godot/playtest/ten_day.gd` | `godot:m2:balance`, `godot:m2:harness`, `godot:playtest` (a measurement, not in the chain) |
| Performance | [docs/22](docs/22-performance.md) | `godot/bench/bench.gd`, `bench/` | `godot:bench`, `bench`, `bench:frame` |
| Content loading and validation | [docs/20](docs/20-ecs-and-content.md) | `godot/platform/`, `godot/content/schemas/` | `godot:validate`, `test` |
| The engine, CI and the desk | this file | `scripts/run-godot.mjs`, `.github/workflows/ci.yml`, `.claude/hooks/session-start.sh` | `check:routing`, `check:timing`, `godot:smoke`, `godot:r6:coverage` |
