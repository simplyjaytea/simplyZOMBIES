# PLAYBOOK.md

The one entry point for anyone changing this repository, agent or person. It says what the
project is, who works on it and how the work is dispatched, where the work is, how a unit of work
runs, how to verify and push it, what must not be broken, how the project around
the repository runs (who decides what, how a pull request reaches `main`, the shared folder, what
is open), what the last session did and left, and where every system lives. `README.md` is for
players; this file is for builders. Other assistants read it too: it is the project's rules, not
a Claude-only file (`CLAUDE.md` imports it so Claude Code loads it, and `AGENTS.md` points here).
Where it states a fact about the build, it names the file or gate that proves it. Where it says
how the owner works, it records the owner's standing instructions.

`CLAUDE.md`, `AGENTS.md` and docs/38 are stubs that point here (docs/30, "The playbook, one file").

## Start here

**Coordinators resuming the project:** go first to [Where we are](#where-we-are) and the newest entry of
[the session log](docs/43-session-log.md), then [the dispatch workflow](#the-dispatch-workflow).

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
   of the systems it touches ([briefing a worker](#the-dispatch-workflow)).
3. [Waiting on the owner](docs/33-owner-decisions.md#waiting-on-the-owner): decisions that are
   not yours to make.
4. [docs/37, the traps](docs/37-traps.md), before touching the sim.
5. [docs/30, the decisions](docs/30-decisions.md), before changing anything that looks
   arbitrary. It usually is not. Read the entries for the system you touch (search by its name),
   not the whole file.

## The team

**Linux, since 2026-11-04; this roster since 2026-11-05.** The owner's machine runs six terminals in
herdr, not Orca, in two workspaces: "simplyZOMBIES / Main Code" (the coordinator, the advisor, the two
workers) and "simplyZOMBIES / Modeling and Art" (the art lead and its QA). The owner decides and gives
tasks to the coordinator directly. Agents do the rest, each on its own model.

| Role | Agent | Does | Does not |
|---|---|---|---|
| Coordinator | Claude Code, Sonnet 5.5 | The lead: everything routes through it. Reads the state, plans, writes every spec, dispatches to the workers and the art lead, verifies every report against the diff, renders and gates, opens PRs, runs the merge train, merges | Write the work itself, beyond small fixes to docs and records |
| Advisor | Claude Code, Fable 5.1 | Advises the coordinator: a second opinion, a harder judgement call, a plan or design review, and the questions the coordinator cannot settle. Talks to the art QA for anything that crosses the two workspaces | Dispatch, merge, or write the work; relay the owner's tasks (the owner talks to the coordinator) |
| Art lead | Kimi Code, K3.1 Pro, thinking high, in "Never Ask" mode | Every 3D model, rig, clip, UV layout and painted texture | Edit another worker's worktree |
| Art QA | Claude Code, Opus 5.5, a standing terminal beside Kimi | Plans Kimi's rounds, reviews every art batch independently and writes the verdict to `sz-shared/reviews/<piece>/`; the strong tier for a piece that needs higher thinking (a new gate, a shared sim module, the save format) when the coordinator asks | Merge; routine work, which stays with the workers |
| Workers (two) | Claude Code, Haiku 5.5 | Every piece of work that is not art: code, gates, docs, keeping pull requests current with main, and independent reviews of code they did not make | Merge |

The roster may name models, because it says who runs what. Authorship never does: a commit, PR
title or body, code comment or doc does not say which model wrote it (the owner's call, 2026-11-01,
docs/30).

Kimi has priority for models; if Kimi runs out of usage, a worker takes over its worktree from its
HANDOFF.md (see [When a worker runs out](#when-a-worker-runs-out)).

## The dispatch workflow

One coordinator dispatches work into live terminals, and each worker reports back in a file. Workers
never share a worktree at the same time, and nobody switches branches in the main checkout.

1. **Orient.** Read the state: open PRs (`gh pr list`), `origin/main` against the local checkout, the
   worktrees, and the owner's request. Render the current asset before judging it.
2. **Specs live in the shared folder.** Each task is a markdown spec,
   `/home/jtf/sz-shared/<piece>/task-<who>.md`: worktree and branch, the change, constraints,
   ownership, acceptance. Workers sharing a piece also get a `BRIEF.md` with the owner's words verbatim.
3. **One worktree per worker.** `git worktree add -b <agent>/<piece> .claude/worktrees/<piece> origin/main`
   (or off the PR it stacks on). Worktrees sit under `.claude/worktrees/`, on branches named
   `<agent>/<piece>`. Symlink `node_modules` from the main checkout; the symlink is excluded in
   `.git/info/exclude`.
4. **Dispatch.** `hc ls` lists the terminals in both workspaces, "simplyZOMBIES / Main Code" and
   "simplyZOMBIES / Modeling and Art". Addresses such as `t1p` change between runs: Kimi is the `kimi-code`
   row, the art QA is the Claude row beside it, and the workers are the Haiku rows (`hc read <t>` shows
   the model on each screen). Start one
   with `hc run --bg --name <n> --cwd <worktree> --outlive-parent <cmd>`, then
   `hc send <t> "Read <spec> and WORKER_RULES.md, then do the task without stopping"`. `hc send` wraps
   its text in `<hc>` tags, so a slash command sent that way becomes a chat message. Kimi asks before
   each shell command unless it is in "Never Ask" mode: `hc keys <t> / y o l o enter` turns that on.
5. **Wait.** `hc wait <t>` returns on every status change. Loop it until `REPORT.md` appears or the
   terminal goes idle, then `hc read <t>`. A worker that runs out writes `HANDOFF.md` instead.
6. **Verify.** Read the diff yourself, and the manifest or map where there is one, and rerun the gates
   the spec names. Workers have reported work as done when it was not, three times in one session.
7. **Settle.** Reuse the terminal for the next task once the report is verified. Subagents cannot write
   under `sz-shared`, so the coordinator writes their `REPORT.md` from the hand-back.

### Art in rounds

- The art lead publishes the UV layout early (`uv_layout.png` + `.json` with island rects, orientation,
  landmarks, mirroring and a position bake), so the paint starts in parallel.
- Every round renders the same views beside the owner's concept: Blender clay and textured, and the
  in-engine sheet from `npm run godot:shots:survivor -- --glb=<path> --out=<dir>`. The coordinator judges
  the in-engine sheet, not only Blender.
- Each round gets an independent review by the art QA, which writes the review and a ranked verdict
  (`OPUS_VERDICT.md`) under `sz-shared/reviews/<piece>/` and sends both to the art lead. The coordinator
  reads the verdict before opening the PR and merges on it. Geometry is locked before final paint, and
  paint is locked last. The owner sees the accepted model before any pull request.

### Independent review and the merge train

- **Art and placement review** (the owner's call, 2026-10-27). An art or placement PR merges only after
  an independent read-only reviewer checks it, and after fixes, a confirmation pass by the same reviewer
  against its first report. A push after a verdict voids it.
  - The art QA is the reviewer, never the worker that made the art. The brief is the PR, its head and
    base commits, and `/home/jtf/sz-shared/reviews/<piece>/` for the report. A confirmation pass also
    gets the previous report. The reviewer is not told the worker's account of what changed. An art PR
    merges on the art QA's written sign-off; the coordinator merges it, the art QA never does.
  - The reviewer makes its own shots of base and head with `godot:shots`, measures the noise floor
    (base against base) before calling a difference, and names both commits in the report.
  - Round 3 is the last full round. Later passes check only the previous findings and raise only
    blockers. Minor findings in a clear round go into docs/23. Docs-only, gate-only and 1 to 2 px
    gate-verified follow-ups need no review.
- **The merge train** (the owner's call, 2026-10-27). Pieces built side by side merge one by one, each as
  it goes green. The next merges `main` in (never rebase, never force-push), waits for CI on its new head,
  and merges in turn. Conflicts in the tails of docs/23 and docs/30 are settled by keeping both entries.
  A piece that waits on another names it in its body.
- After each merge the coordinator tells the open workers the new `main`. A worker keeps the queue
  current: it merges `main` into the next PR, reruns the touched gates, and reports a table (number,
  head, CI, local gates, preconditions, risk).
- A bundle of pieces that conflict in code goes into one integration PR that names the PRs it closes
  (#289 closed twelve). Docs-only PRs merge after a clean local merge and `check:routing`.

### When a worker runs out

1. Tell it to stop. It commits a WIP checkpoint even if checks fail, and writes `HANDOFF.md` (method,
   what works, what fails and why, next steps, traps).
2. Wait for it to go idle before anything else touches the worktree.
3. Start the replacement in the same worktree (`hc run ... --cwd <worktree>`), its spec pointing at the
   handoff and the original task.

A worker revived after days can wake with stale context, so brief it on the current `main` first. Push
at a clean point before a long run.

**Briefing a worker.** docs/23 and docs/30 are too large to read whole. A brief names the parts that
bear on the piece: its entry in docs/23's what's left, its row in the [routing table](#routing-table),
the record entries of the systems it touches, and the docs/30 entries for those systems. The worker reads
this file, docs/37 and those parts. A worker that needs more reads more; the brief is a floor, not a fence.

## Rules for every worker

Every worker reads `/home/jtf/sz-shared/WORKER_RULES.md` with its spec. The coordinator maintains that
file; this section is the same rules as the repository holds them.

- Read this file in your worktree first: Standing bans, Conventions, Traps and Verifying a change. It
  is the project's rules.
- Work only in the worktree your spec names, on its branch. Never switch branches in the main checkout.
- Never push to `main`, never merge a pull request, never force-push, never rebase a pushed branch,
  and never skip or loosen a gate.
- **No OS-level input and no desktop screenshots, ever.** Drive Godot from inside (the gate harness,
  `Input.parse_input_event`, a throwaway GDScript driver) and capture only the game viewport, or render
  through Blender. A worker's synthetic keys once landed in the owner's browser.
- Run every Godot gate, capture and Blender job under `xvfb-run -a` (or `env -u WAYLAND_DISPLAY DISPLAY=`).
  Never let a window open on the owner's display `:0`.
- Commits use the repository's local git identity, `worker`, and carry no attribution trailer: no
  Co-Authored-By line and no session link. Commits, PR text, code comments and docs never name the model
  or agent that wrote them.
- Spin up your own subagents when it helps.
- Stuck on a design question (anything a player would notice that the spec does not settle)? Build the
  most conservative default, note it in your report, and keep going.
- Ask the coordinator in your `REPORT.md`. Never open a question prompt nobody can answer.
- When done, or blocked, or out of usage: commit, push your branch (`git push -u origin <branch>`),
  write `REPORT.md` in your piece's folder (what changed, the gates run with their exact OK or FAIL
  lines, the head SHA, anything left or doubtful), then end your turn. Out of usage mid-task: commit a
  WIP checkpoint and write `HANDOFF.md` instead (method, what works, what fails and why, next steps,
  traps).
- Do not open the pull request. The coordinator does.

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

**Setting.** The game is set in Japan, in the Kagase valley in the mountains west of Tokyo (docs/30).
The valley is fictional and inspired by the real Ome–Okutama valley; its layout, towns and districts
are in [docs/42](docs/42-ome-okutama-setting.md) (the map in section 3, the renames in section 5).
Place names, businesses and brands are fictional. The renames are on their pull requests: R1 #333
(the districts and region), R3 #334 (the building templates), R5 #335 (food and drink), R6 #341
(cartridges and brass), R7 #337 (tools, comfort and melee), R8 #339 (vehicles), R9 #342 (the
people) and R10 #340 (the descriptions). R2, the region's cell order, is #344 (it bumps the save
format to v34). The real layout, landscape and architecture are the inspiration. The re-theme
is planned work, listed in docs/23.

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

- **First person is the game; top-down is legacy** (2026-11-04, docs/30): first person is the
  default boot and every new piece is first person; the top-down game stays, boots with
  `npm run godot:run:topdown`, and keeps its gates, but gets no new features or UI slices unless
  the owner asks. Shared sim modules serve both. The top-down rules in docs/30 and docs/32 govern
  only the legacy build.
- **The setting is Japan (Ome–Okutama), 2026-11-04** (docs/30): inspired by the real Ome–Okutama
  valley in western Tokyo; names are fictional. The re-theme is planned work, listed in docs/23.
- **The survival loop is built, gated and on.** `SimShambler.GRABS_ENABLED` ships `true`. Any
  gate that pins the flag restores the previous value.
- **The alpha stopped at a balance wall on 2026-10-21.** The target was a colony alive on day 10
  on 2 of 3 seeds, and it was not met. The numbers, the traces and the next measurement are in
  docs/23's "Balance after the alpha" (under what's left). The next measurement is ten seeds and
  a median wipe day, on `main` and on each candidate. No lever is judged on three seeds again.
- **A day is one real hour** (`Clock.DAY_SECONDS`, the owner's 2026-10-19 call). The speed
  ladder is 1x and 3x; 10x waits on the tick budget.
- **The boot colony is three**, the player, Mara and Ellis, by the owner's 2026-09-01 decision.
- **Dead sockets.** Complete, correct, gated code that nothing reads has turned up many times. A
  mechanism needs an assertion that something reaches it.
- **For the current `main`,** run `git log origin/main -1` and look at its CI. This file carries
  no commit hash on purpose, because a hash written here is out of date after the next merge.

The longer state notes, the art history and the full dead-socket list are in
[the state of the build](docs/36-state-of-the-build.md). What the last session did and left is in [the session log](docs/43-session-log.md).
The open items are under [Where we are](#where-we-are).

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

- **One piece, one branch, one pull request,** opened from a fresh branch off `main` and based on
  `main`. A worker pushes only its own branch. Never push to `main`.
- **A fix to someone else's open pull request** is a pull request onto its branch. Branch off that
  pull request's head, push your own branch, and open a pull request whose base is its branch. CI
  runs on it, because `ci.yml` runs on every pull request whatever its base. It merges into that
  branch under the same rules as a merge into `main`. #230 onto #228's branch was the first.
- **Follow-ups start fresh.** A merged pull request is finished. New work goes on a fresh branch from
  `main`, with a new pull request, never on top of merged history.
- **Fill in the PR template** (`.github/pull_request_template.md`): the piece, the gate, the
  measurement, the record, what was verified.
- **Drive it green** by the steward skill (`.claude/skills/steward/SKILL.md`). Never skip, disable or
  loosen a gate to get there.
- **Merge with a merge commit,** after re-checking the head and CI right before merging. The worker
  that wrote a pull request never merges it. The coordinator merges, and only with the owner's
  go-ahead (`gh pr merge <n> --merge --match-head-commit <sha>`). The merge train, above, sets the
  order.
- **Merged head branches come back** after each merge unless "Automatically delete head branches" is
  on in the repository settings. Name the branches that should go, and the owner deletes them.

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
- **The open calls are listed in [docs/33](docs/33-owner-decisions.md#waiting-on-the-owner)**, the only
  list. Each has a default already built, so none of them blocks a piece.
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

## The release plan

Decided by the owner on 2026-10-26 ([docs/30](docs/30-decisions.md#the-release-plan-and-the-content-arcs-2026-10-26)).
The pieces of each stage are in [docs/23's what's left](docs/23-roadmap.md#whats-left-in-milestone-2).

1. **Alpha closed: it loops.** Milestone 2's exit criterion in code, not balance. In flight at the last
   check: colonist self-care, the buildables, the floodlight take-down.
2. **Alpha open: it survives.** The balance wall, judged only by ten seeds and a median wipe day.
3. **The art pass: it looks finished.** Runs beside stage 2, on the art tier.
4. **Beta: people and the world.** The save format freezes here and migrates from then on.
5. **1.0: breadth.** Multiplayer (3C) is 1.x unless the owner pulls it forward.

## The content arcs

Opened by the owner on 2026-10-26 ([docs/30](docs/30-decisions.md#the-release-plan-and-the-content-arcs-2026-10-26)).
Each arc is a group in [docs/23's what's left](docs/23-roadmap.md#whats-left-in-milestone-2), one piece
per line. The rule that binds all four: **readers before content, pictures a stage behind.** A stat
nothing resolves is not authored; a kind, part or frame gets its picture in the stage after its sim piece.

The four arcs are zombies (seven to fourteen kinds), raiders (four to nine archetypes and a doctrine on
the band), firearms (every number a sum of its parts) and melee (frames rather than weapons; finished
2026-10-27). The open calls from the arcs are in [docs/33](docs/33-owner-decisions.md#waiting-on-the-owner).

## The shared folder

The shared folder is `/home/jtf/sz-shared/`, outside the repository. It holds one folder per piece:

| Path | What is in it |
|---|---|
| `<piece>/task-<who>.md` | The spec for one worker: target worktree and branch, the change, constraints, acceptance |
| `<piece>/BRIEF.md` | Where several workers share a piece: the owner's words verbatim and the technical contract |
| `<piece>/REPORT.md` or `HANDOFF.md` | What a worker did and gated, or what it leaves when it runs out |
| `reviews/<piece>/` | Independent art and placement reviews (`review_round-N.md`, `OPUS_VERDICT.md`) |
| `backups/` | Branch bundles, taken before a remote branch is deleted |
| `concept/` | The owner's concept art, for likeness checks |
| `WORKER_RULES.md` | The rules every worker reads, held by the coordinator (see Rules for every worker) |

Never cite a shared-folder path inside the routing table. `npm run check:routing` resolves every
backticked path in that section against the repository, so such a path turns the gate red.

## Art and animation conventions

The first-person art is the current direction (docs/39, docs/41).

- **Kit shape.** Every kit is a reproducible Blender builder with `-- --check` and planted-error
  modes, a `<kit>.manifest.json` in `godot/assets/first_person/`, and an independent in-engine review
  before merge. The reviews keep finding the same faults (camouflage-like noise, paint that follows
  atlas cells, density claims the check did not measure, bodies that float or sink), so a new kit's
  builder checks those from the start.
- **Texel density:** 128 px/m for bodies and arms, 256 px/m for heads, measured on the exported GLB.
- **Every Blender and Godot job runs under `xvfb-run -a`.**
- **Compare pixels, not bytes.** This machine's Blender links zlib-ng, so a rebuilt PNG or GLB can
  differ in bytes from a Windows-built one. Before calling a rebuilt file a change, compare its pixels.

### Legacy top-down art

These rules govern only the legacy build (docs/30, 2026-11-04). The sprite brief is
`godot/assets/sprites/README.md`.

- A tile is 32 art px, drawn at 2x on the boot zoom (`godot/project.godot`).
- A body canvas is 32x40 with the soles on row 39; the heavy's is 40x48 with the soles on row 47.
- A clothing sheet has one row per view (S, E, N, W): column 0 is the rest picture, columns 1 to 8
  the walk, column 9 the breath (`godot/art/simplyzombies/clothing/README.md`).
- `npm run godot:check:action` holds every fall, lunge and stagger to the bounds in the header of
  `godot/check_action.gd`.
- Review exports in the shared folder: survivor reload strips use 48x56 cells (sole on row 43, head
  top on row 16); zombie action strips use 112x60 cells at 4x (sole on row 55).

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

## Where we are

First person is the game; top-down is legacy (docs/30). Setting: the Kagase valley, inspired by
Ome–Okutama (brief docs/42, on `main`; the owner took every card's default on 2026-11-04, PR #332).
For what is open, `gh pr list`; for the last session's handoff, the newest entry in
[docs/43](docs/43-session-log.md).

**Team** (the owner's call, 2026-11-05). Claude Sonnet is the lead: it plans, dispatches, verifies and
merges, and the owner gives it tasks directly. Claude Fable advises Sonnet and talks to the art QA. Kimi
does all 3D and art; a standing Claude Opus terminal beside it plans Kimi's rounds and signs every art
batch off before its PR. Two Claude Code Haiku workers do everything else. On 2026-11-04 Fable
coordinated and Opus was a subagent; the OpenCode workers were retired that day.

**Merged this session (evening of 2026-11-04):** #318, #319, #320, #323 (docs/42), #324, #325 (this
trimmed playbook), #326 (the organic survivor). Their branches and worktrees are gone.

**The merge train.** A PR merges only when its head contains `origin/main` and CI is green on that
head; after each merge the next PR merges `main` in and waits for CI again. CI is the bottleneck
(nine runs queued at once this session), so the eleven renames go in as one integration PR. Order:
#346, the renames integration (closes #332, #333, #334, #335, #337, #339, #340, #341, #342, #343, #344),
then #338 (arms art), then #331 (arms view, retargeted to `main` **before** the arms branch is
deleted: GitHub closes a PR whose base branch goes), then #327 (purifier refill), #329 (crawler),
#336 (bloodhound), #328 (clothing note). #322 is a no-op (its rule is already on `main`): close it.
The merge-train spec is `sz-shared/merge-train/task-opencode.md`; its rows are in `REPORT.md` there.

**Open pull requests, all with local gates green at hand-off** (CI state moves: `gh pr checks <n>`):

- The renames R1 to R11 (`claude/rename-r*`, one PR each) and the setting calls (#332): names change,
  ids stay; R2 bumped `SAVE_VERSION` to 34 (every v33 save refused, docs/30). The integration branch
  `claude/renames-integration` was being built by a Haiku worker when the owner paused; read
  `sz-shared/renames-integration/REPORT.md` or `HANDOFF.md`. R4 (the kawara and siding look retag)
  waits on Kimi's materials.
- #338 the arms art (`claude/fp-arms`, review round 2 FIX-THEN-MERGE, its one major fixed on the view,
  confirmation pass CLEAR; `sz-shared/reviews/fp-arms/`), #331 the arms in the game
  (`claude/fp-arms-view`, contains #338; six owner defaults built, docs/30).
- #327 the purifier refill, #329 the crawler, #336 the bloodhound's scent-led Seek (all touch shared
  sim modules; each ran the full chain locally), #328 the clothing layers design note (docs/44, five
  owner cards 28 to 32 in docs/33).

**Art line.** The hunting rifle (`kimi/fp-rifle`, `c77c938a`) is BLOCKED by its independent review
(`sz-shared/reviews/fp-rifle/review_round-1.md`: the receiver reads as a scope, its pieces float, no
bolt handle, the barrel tapers backwards, the stock's comb is 91 mm low, a dropped rifle draws as a
pipe); Kimi's round 2 spec is `sz-shared/fp-rifle/task-kimi-round2.md`, to send after the buildings.
Japanese buildings batch A (`kimi/fp-buildings-jp`: kawara and siding materials, the small wooden house
and the tiled-roof house) was in progress at the pause: read `sz-shared/fp-buildings-jp/HANDOFF.md` or
`REPORT.md`. Batch B (shotengai fronts, sawmill shed, station, konbini, kōban, shrine) and prop kit A
follow its review.

**In flight at the pause, with a checkpoint each:** the alarm and noisemaker priced
(`claude/alarm-priced`, `sz-shared/alarm-priced/`) and the buildings batch.

**Waiting on the owner:** the six arms-view defaults (#331); docs/33's firearms card (default rare);
docs/44's five clothing cards; the survivor concept image for `/home/jtf/sz-shared/concept/`; whether
the alarm's wire and the noisemaker's scrap metal are the right prices (the piece measures before and
after). Every one has a default built.

**Next session, start here**, in order:

1. `hc ls`; read every `HANDOFF.md` or `REPORT.md` under `sz-shared/` for the three in-flight pieces
   and resume them (a Haiku for the alarm, Kimi for the buildings).
2. `gh pr list` and CI; run the merge train in the order above. Retarget #331 to `main` before
   deleting `claude/fp-arms`.
3. After the integration merges: R4 waits on Kimi's materials; then the rifle round 2 to Kimi after
   batch A's report, and an independent review of batch A by the art QA (the Opus terminal).
4. Then from the to-do: zombie kinds on the organic base (sim kinds first: the gassed bloater, the
   lurker, the juggernaut, the feigner; pictures a stage behind), the arms polish minors (docs/23),
   the owed ten-seed re-baseline (stage 2) for the crawler and the bloodhound, the sedan's name
   (`check_vehicles.gd` MOUNT pin), a crawler picture.

**To do:** crossbow bolt, fuel, oil and canteen bottles (Kimi); the shambler and six zombie kinds on
the organic base, with a lighter horde version; the clothing layers' first cut after the cards; the
wider world by rail (a design note, docs/30 "The setting cards").

**Known bugs**

- In the third-person testing view the held weapon is not drawn in the body's hand. The view
  model hides there (`claude/fp-arms-view`), which ends it floating beside the body (#313's
  capture), but nothing draws it on the body yet.
- `godot:check:fp_geometry` takes about 13 s; its real-worldgen lane is most of it. The next speed-up
  is caching the four worldgen districts.
- The survivor review scene's light is flat grey, so colour judgements there run dark.
- No presentation code draws a lowered weapon yet (`SimAim.holds`, `FireState` have no reader).
- R2's save bump refuses every v33 save, district saves included, because a save carries only its seed.

## The docs map

| Need | Read |
|---|---|
| First-person conversion: approved direction, phases, spatial contracts and archive | [docs/39](docs/39-first-person-pivot.md) |
| The setting: the fictional valley, the building types, the renames and their order | [docs/42](docs/42-ome-okutama-setting.md) |
| What is open, what landed, with evidence | [docs/23, the roadmap](docs/23-roadmap.md) |
| What each session did and left, newest first | [docs/43, the session log](docs/43-session-log.md) |
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
| The first-person loot-item kit: world-pose models for the things a player picks up | [the item kit's README](tools/blender/first_person_items/README.md) | `tools/blender/first_person_items/build_items.py`, `godot/assets/first_person/items/`, `godot/assets/first_person/items.manifest.json` | `blender --background --factory-startup --python tools/blender/first_person_items/build_items.py -- --check` proves bounds, origins, bodies resting on the floor, item ids and coverage, every item within 2x of its expected size, no laddered item drawn as another item's own model, one single-sided closed material per model, no coplanar faces, texel density per face and byte reproducibility; each check has a `--plant` that turns it red | the record |
| The first-person view-model arms: hands, sleeves, rig and clips for every hold class | [the arms kit's README](tools/blender/first_person_arms/README.md), which carries the contract | `tools/blender/first_person_arms/build_arms.py`, `godot/assets/first_person/arms/`; `godot/assets/first_person/arms/arms.json` stays in that directory so `Models.manifests()` does not register it as loot | `blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --check` prints `ARMS_CHECK_OK` (bytes, names, anchor, bone-length, grip-land, wrap, sight-line, near-plane, stump, in-frame, chain, smooth, weights, cuff, density, background, paint-match, body-match, budget, measured on the exported GLB); `-- --plant <name>` turns each check red | the record |
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
| First-person space: the height profile, the body cylinders, the eye, and what is in the way of a blow | [docs/40](docs/40-first-person-spatial-contract.md) | `godot/sim/space/space.gd` (`SimSpace.PROFILE`, `body_of`, `eye_of`, `segment_clear`, `reach_clear`, asked by `godot/sim/modules/melee.gd`'s `_resolve_strike`, `godot/sim/modules/shambler.gd`'s `_clear_contact` and `_contact_target`, and `godot/sim/modules/npc_combat.gd`'s `_in_reach`, which `can_strike`, `_engage` and the instinct defence share), drawn by `godot/presentation/first_person/district_view.gd` and `godot/presentation/first_person/body_view.gd` | `godot:m2:space` (`godot/check_m2_space.gd`), `godot:check:fp_geometry` (`godot/check_fp_geometry.gd`) | the record |
| Speech: what a body says out loud | [docs/30](docs/30-decisions.md) | `godot/sim/modules/speech.gd`, `godot/content/speech/` | `godot:check:speech` |
| Save and load | [docs/19](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd`, `godot/sim/save.gd` | `godot:m2:save` |
| The overcast day: the finished picture graded by the sky's share of daylight, off at night and under no HUD | [docs/30](docs/30-decisions.md#the-overcast-day-as-a-grade-2026-10-24) | `godot/presentation/day_grade.gd`, `godot/presentation/day_grade.gdshader`, `godot/presentation/main.gd` (`_draw_day_grade`; the world's words, bubbles and pawn tag, painted over the grade by `_paint_world_text`) | `godot:check:grade` (`godot/check_grade_look.gd`; its PIXELS lane runs headed when `DISPLAY` is set) |
| The look | [docs/30](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03) | `godot/presentation/`, `tools/sprites/` | `godot:check:topdown`, `godot:check:appearance`, `godot:check:camera`, `godot:check:motion`, `godot:check:action`, `godot:check:world_bake`, `godot:check:light`, `godot:check:road`, `godot:check:water`, `godot:check:wrecks`, `godot:check:roof`, `godot:check:trees`, `godot:check:worn`, `godot:check:authored`, `godot:check:fx`, `godot:check:grade`, `sprites:check` |
| The screen | [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) | `godot/ui/` (its frames from the UI Field Kit, `godot/art/simplyzombies-ui/`, through `godot/ui/kit.gd`), `godot/presentation/main.gd`, `godot/presentation/input_map.gd` | `godot:check:ui_skin`, `godot:check:hud`, `godot:check:inventory`, `godot:check:respond`, `godot:check:web_look`, `godot:ban:healthbar`, `godot:check:play` (the one gate that executes the scene: `godot/check_play.gd`) |
| Balance and the campaign harness | [docs/22](docs/22-performance.md#measuring) | `godot/check_m2_balance.gd`, `godot/check_m2_harness.gd`, `godot/playtest/ten_day.gd` | `godot:m2:balance`, `godot:m2:harness`, `godot:playtest` (a measurement, not in the chain) |
| Performance | [docs/22](docs/22-performance.md) | `godot/bench/bench.gd`, `bench/` | `godot:bench`, `bench`, `bench:frame` |
| Content loading and validation | [docs/20](docs/20-ecs-and-content.md) | `godot/platform/`, `godot/content/schemas/` | `godot:validate`, `test` |
| The engine, CI and the desk | this file | `scripts/run-godot.mjs`, `.github/workflows/ci.yml`, `.claude/hooks/session-start.sh` | `check:routing`, `check:timing`, `godot:smoke`, `godot:r6:coverage` |
