# CLAUDE.md

The one entry point for anyone changing this repository, agent or person. It says what the
project is, where the work is, how a unit of work runs, how to verify and push it, what must not
be broken, and where every system lives. `README.md` is for players; this file is for builders.
Other assistants read it too: it is the project's rules, not a Claude-only file (`AGENTS.md`
points here). How the project around the repository runs (who decides what, how a pull request
reaches `main`, the shared folder, what is open) is [docs/38, the playbook](docs/38-playbook.md).

## Start here

```bash
bash scripts/setup-web-session.sh   # verify or install the pinned engine and npm packages
npm run godot:smoke                 # the project boots
npm run check:routing               # the routing table below, and every gate reachable
npm run godot:run                   # play it (DISPLAY=:1 on a headless VM; docs/34)
npm run godot:m2:needs              # one gate while iterating: any godot:m2:<name> or godot:check:<name>
npm run godot:m2 -- --shard=1/4     # one of CI's four shards of the full chain
npx vitest run test/unit/<file>     # one test file of the frozen oracle
```

Then read, in order:

1. This file, top to bottom.
2. [What's left in Milestone 2](docs/23-roadmap.md#whats-left-in-milestone-2), the open work, and
   [the record, by system](docs/23-roadmap.md#the-record-by-system) for how the neighbouring
   systems landed.
3. [Waiting on the owner](docs/33-owner-decisions.md#waiting-on-the-owner): decisions that are
   not yours to make.
4. [docs/37, the traps](docs/37-traps.md), before touching the sim.
5. [docs/30, the decisions](docs/30-decisions.md), before changing anything that looks
   arbitrary. It usually is not.

## What the project is

A hardcore zombie survival colony sim: RimWorld's colony management, Project Zomboid's survival,
Zero Sievert's top-down pixel art. One attention system (noise, scent, light) ties survival to
the pressure the dead put on the colony. [docs/00](docs/00-vision.md) is the vision and
[docs/01](docs/01-hardcore-contract.md) the hardcore contract.

**Godot is the only implementation that ships.** The game is `godot/`: Godot 4.7.1
(Compatibility), typed GDScript. New behaviour goes there and nowhere else. `npm run build` is
`godot:export`, and Pages publishes the Godot build at `/`.

**The TypeScript oracle is frozen, not gone.** `src/`, `test/`, `bench/` and the Vite and vitest
configs are on `main`, and CI's `check` job runs `npm test`, `typecheck`, `lint`, `format:check`
and `bench` against them. It is a reference, not a second product: add no features to it, port
no Godot change into it, and do not delete it or let it go red. Its frozen parity fixtures under
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
succession, and still wanting another run. The alpha plan's pieces (A0 to A24) have all landed;
what remains is the post-alpha balance wall (docs/23's "Balance after the alpha"), the UI
overhaul's later slices, and the rest of [what's left](docs/23-roadmap.md#whats-left-in-milestone-2).
[docs/23](docs/23-roadmap.md) is the authority on what is built and what remains. Facts that
matter every session:

- **The survival loop is built, gated and on.** `SimShambler.GRABS_ENABLED` ships `true`. Any
  gate that pins the flag restores the previous value.
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

The longer state notes, the art history and the full dead-socket list are in
[the state of the build](docs/36-state-of-the-build.md).

## The docs map

| Need | Read |
|---|---|
| How the project runs: the owner, threads, merging, the shared folder, open calls | [docs/38, the playbook](docs/38-playbook.md) |
| What is open, what landed, with evidence | [docs/23, the roadmap](docs/23-roadmap.md) |
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
| Architecture, content, extensibility | [docs/19](docs/19-architecture.md), [docs/20](docs/20-ecs-and-content.md), [docs/21](docs/21-extensibility.md) |
| The UI overhaul's brief | [docs/32](docs/32-ui-overhaul.md) |
| Post-slice designs: the wider region, mobile bases, multiplayer | [docs/24](docs/24-world-and-scale.md), [docs/26](docs/26-mobile-bases.md), [docs/27](docs/27-multiplayer.md) |
| History: the engine move, the early need ADRs | [docs/31](docs/31-godot-rebuild-roadmap.md), `docs/adr/` |
| Screenshots and plans from past pieces (evidence, not instructions) | `.hermes/plans/` |

The design specs are numbered in the order they were written, not reading order. New to the
design? Read docs/00, 01, 03, then 23.

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

Correctness for a Godot change is the Godot gates. **Policy (the owner's call, 2026-10-19,
docs/30):** before a commit, run the gates for what the change touched: its `godot:m2:<name>`
lane, `godot:smoke` and `godot:validate` for a boot or content change, `godot:check:play` for a
scene or input change, and `npm test` for anything under `godot/content/` (the oracle's Ajv
recurses where `godot:validate` does not). Touching a `.ts` file or a prettier-covered path adds
`typecheck`, `lint` and `format:check`; touching a script, a runner mode, a `check_*.gd` or the
routing table adds `check:routing`. **A change to a shared sim module or the save format runs the
full `npm run godot:m2` chain locally before its commit.** CI runs the full chain on every pull
request and every push to main, split across four shards, and nothing merges red.

The commands, timings and CI jobs are in [the gate list](docs/35-gates.md).

## Pushing and pull requests

- **One piece, one branch, one pull request,** opened from a fresh branch off `main` and based
  on `main`. A session pushes only its own branch. Never push to `main`.
- **No model identifiers in anything pushed.** Commit messages, PR titles and bodies, code
  comments and docs never name the model that wrote them. That includes a `Co-Authored-By`
  trailer naming a model: leave it out and keep the session link (`Claude-Session:`).
- **Fill in the PR template** (`.github/pull_request_template.md`): the piece, the gate, the
  measurement, the record, what was verified.
- **Drive it green** by the steward skill. Never skip, disable or loosen a gate to get there.
- **Merge with a merge commit,** after re-checking the head and CI right before merging.
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
predicate, `check_inventory.gd`'s `_name_is_allowed`, is called by both lanes that scan a name
(STRIP and INSPECT) and still refuses a name that is *nothing but* a quantity. **Nothing else
moved**: `description`, every other value in the inspect pane, and every line `check_hud.gd` reads
are under the full ban, and the lane proves it by refusing the identical string the moment it is a
description instead. Do not widen this to a second field without the owner — the whole reason it
is written down here is that a ban amended once is a ban that gets amended again.

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
before touching the sim. Each one was found the expensive way.

## Routing table

Where a unit of work goes: what to read before touching it, where the code lives, the gate that
can fail it, and where its record is written. `npm run check:routing` judges this table -- every
path, script and link in this section must resolve, and every `godot/check_*.gd` must be reachable
from an npm script -- so a route here is a claim the build checks, not a note that drifts. Add a
row when a system gains a home; the gate goes red when a route stops being true.

**By the kind of work:**

| If the work is... | Read first | It lives in | The gate | Record it in |
|---|---|---|---|---|
| Starting a session cold | [CLAUDE.md](CLAUDE.md), then [what's left](docs/23-roadmap.md#whats-left-in-milestone-2) | -- | `npm run godot:smoke` proves the engine | -- |
| A decision named under [Waiting on the owner](docs/33-owner-decisions.md#waiting-on-the-owner) as the owner's | that entry, and [docs/30](docs/30-decisions.md) | nowhere: stop and ask | -- | -- |
| A sim mechanic (a need, a wound, a job, the weather) | the system's spec in the table below, [docs/30](docs/30-decisions.md), and the traps in [CLAUDE.md](docs/37-traps.md#traps-that-have-already-cost-someone-a-session) | `godot/sim/modules/`, `godot/sim/` | its `godot:m2:<name>` gate while iterating; `npm run godot:m2` before the commit | [the record, by system](docs/23-roadmap.md#the-record-by-system); a call taken goes in [docs/30](docs/30-decisions.md) |
| Content (an item, a zombie, a loot table, a weather kind) | [docs/20 Part 2](docs/20-ecs-and-content.md#part-2-content) and the schema under `godot/content/schemas/` | `godot/content/` | `npm run godot:validate` **and** `npm test` (only the oracle's Ajv recurses), plus the nested-shape gate for that block | the record |
| How a thing looks | [the Dungeon Settlers look](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03), `godot/assets/sprites/README.md` | `godot/presentation/`, `godot/assets/sprites/`, `tools/sprites/` | the `godot:check:<look>` gate for that layer; `npm run sprites:check` after touching `tools/sprites/` | the record, with a screenshot under `.hermes/plans/` for the owner to judge |
| Art somebody drew for us | [the brief](godot/assets/sprites/README.md), [art we did not generate](docs/30-decisions.md#art-we-did-not-generate-2026-09-09) | `godot/assets/sprites/authored.json` declares it; the PNG sits beside it | `npm run godot:check:authored` holds it to the published bounds and refuses art nothing reads; `npm run sprites:check` proves it is present at the canvas it declares | the record |
| Art from the outpost pack | [the pack's own README](godot/art/simplyzombies/README.md), [the outpost pack, adopted](docs/30-decisions.md#the-outpost-pack-adopted-2026-09-17) | `godot/assets/sprites/authored.json` declares it, with a `source` (a path, optional `crop`/`pad`) under `godot/art/simplyzombies/`, or as a member of a `source`-carrying `members` family | `npm run sprites:check` reproduces the committed PNG from its source and compares decoded pixels; `npm run godot:check:authored`'s MANIFEST, TIER and SOURCE lanes hold the declaration to shape and the READS lane to a real reader; the look gate of whichever family it lands in (`godot:check:<look>`) once that piece exists | the record |
| The screens' frames, glyphs, cursors and motion: the UI Field Kit | [the kit's own README](godot/art/simplyzombies-ui/README.md), [the UI Field Kit, live](docs/30-decisions.md#the-ui-field-kit-live-2026-09-25) | the approved kit under `godot/art/simplyzombies-ui/` (`godot/art/simplyzombies-ui/manifest.json` and `godot/art/simplyzombies-ui/styles/*.tres` are the spec, read as text; the game never loads a kit `.tres`), resolved by `godot/ui/kit.gd` and worn through `godot/ui/chrome.gd`'s helpers | `npm run godot:check:ui_skin` (`godot/check_ui_skin.gd`): KIT holds `Kit.NINE` to the manifest and the `.tres`, RESOLVE proves every consumed PNG loads headless, PANEL follows `Chrome.panel` to the kit, HELPERS refuses a chrome helper nothing calls, FONT holds every screen to `Chrome.font()` (the kit's VT323, `godot/art/simplyzombies-ui/fonts/VT323-Pixel.res`) and every text size to `Chrome.LADDER` | the record |
| What the screen says | [hardcore contract clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable), the vocabulary in [CONTEXT.md](CONTEXT.md) | `godot/ui/`, the read models `godot/sim/condition.gd`, `godot/sim/attention_read.gd`, `godot/sim/modules/chronicle.gd` and `SimSkills.web_map` in `godot/sim/modules/skills.gd`; the click that picks a colonist, `godot/presentation/pick.gd`, whose `Pick.pick_at` is also what is under a right-click; what you may do about it, `godot/sim/context.gd`'s `SimContext.verbs_at`, drawn by `godot/ui/context_menu.gd`; the keys that reach any of it, `godot/presentation/input_map.gd`; the run's four states and the three screens that are not the game, `godot/presentation/session.gd` and `godot/ui/shell.gd`; the afterimage and the dimmed remembered map, `godot/presentation/main.gd`'s `_draw_afterimages`/`_draw_district` and `godot/presentation/palette.gd`'s `remembered`; speech bubbles, `godot/sim/modules/speech.gd`'s `saying` component and `godot/presentation/main.gd`'s `_draw_bubbles`, drawn over a Focal body only (`_focal_drawn`) and never a name; the one bar over Survivor, Colony and Skills, `godot/ui/nav_bar.gd`, switched by `godot/presentation/main.gd`'s `_show_screen`; a picked body part's condition and care, `godot/ui/care_pane.gd`, offering only what `SimTreatment.options_for` in `godot/sim/modules/treatment.gd` allows; the Colony screen, `godot/ui/work_panel.gd`, its "now" line from `godot/sim/work_read.gd` | `npm run godot:check:hud`, `npm run godot:check:inventory`, `npm run godot:ban:healthbar`, `npm run godot:check:respond`, `npm run godot:check:web_look`; and `npm run godot:check:play`, which boots `godot/presentation/main.tscn` and presses the keys; `npm run godot:check:memory` (`godot/check_memory_look.gd`) for the afterimage and the remembered map; `npm run godot:check:context` (`godot/check_context.gd`) for the menu's rows, their dispatch, walk-here's speed and the scene that opens and closes it; `npm run godot:check:speech` (`godot/check_speech.gd`) for a bubble's content, its triggers and the draw path that reads it; the bar's keys, clicks and Escape in `godot:check:play`'s NAV lane, the Colony screen in its COLONY lane, and the care pane in `godot:check:inventory`'s CARE lane | the record |
| A claim about balance | [the workflow's step 5](CLAUDE.md#the-workflow), [docs/22 on measuring](docs/22-performance.md#measuring) | a throwaway driver, deleted afterwards; a claim about a whole run starts from the standing scripted survivor, `godot/playtest/ten_day.gd` (`npm run godot:playtest`, one seed, ten days, a line per day; `PLAYTEST_SEED`, `PLAYTEST_DAYS`, `PLAYTEST_LOG`) | `npm run godot:m2:balance` and `npm run godot:m2:harness`; the before/after numbers | the record, numbers included |
| The save format | [docs/19's save model](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd` (`SAVE_VERSION`), `godot/sim/save.gd` | `npm run godot:m2:save` | the record |
| A gate, new or fixed | [a gate that cannot fail](CLAUDE.md#conventions), the dead-socket rule in [CLAUDE.md](CLAUDE.md#where-the-work-is) | `godot/check_*.gd`, a mode in `scripts/run-godot.mjs`, a script in `package.json`, a link in the `godot:m2` chain, a shard in `scripts/m2-shards.mjs` | `npm run check:routing` proves it is reachable; `npm run check:shards` proves CI runs it | the record |
| The frozen TypeScript oracle | the top of this file | `src/`, `test/`, `bench/` | `npm run typecheck`, `npm run lint`, `npm run format:check`, `npm test`, `npm run bench` | nothing: it gains no features |
| CI, scripts, hooks, this table | [CLAUDE.md's verifying section](CLAUDE.md#verifying-a-change) | `.github/workflows/` (`.github/workflows/ci.yml` the gates, `.github/workflows/pages.yml` the web build, `.github/workflows/release.yml` the downloadable build, run by hand with a version or by a pushed `v` tag), `scripts/`, `.claude/` | `npm run check:routing`, `npm run check:timing`, `npm run format:check`; the engine pin in `scripts/run-godot.mjs` | the record's Kernel & tooling entry |
| Shipped runtime performance | [docs/22](docs/22-performance.md#shipped-godot-runtime-measurements) | `godot/bench/runtime_tick.gd`, `godot/bench/runtime_frame.gd`, `godot/bench/measured_main.gd`, `scripts/runtime-budget.mjs`, `scripts/run-godot.mjs` | `npm run check:runtime-budget` judges the production runner contract; `npm run godot:m2:tick` (`godot/check_m2_tick.gd`) holds each tick speed-up to the slow answer it replaced; `npm run godot:bench:runtime` and `npm run godot:bench:frame` measure actual timing on a quiet machine (frame needs a display). Existing overruns remain product debt; the real timing commands are not yet CI shipping gates. | docs/22's dated measurements and the record |
| Driving a pull request | `.claude/skills/steward/SKILL.md`, then [Pushing and pull requests](CLAUDE.md#pushing-and-pull-requests) | -- | whatever CI reports; the touched gates before every push, per [Verifying a change](CLAUDE.md#verifying-a-change) | the PR itself |
| Playing it, or a screenshot | [Running the game](docs/34-agents-and-environment.md#running-the-game-gui) below | `godot/presentation/main.tscn` | `npm run godot:run` | -- |
| Art review: before and after screenshots of fixed scenes at both windows | the header of `godot/review/shots.gd`, then `godot/review/scenes.gd` | `godot/review/scenes.gd` (each scene and its verify), `godot/review/shots.gd` (the capture driver, run with `DISPLAY=:1 npm run godot:shots`) | `npm run godot:check:shots` (`godot/check_shots.gd`); its PIXELS lane skips without a display | the record |

**By system** -- the spec, the code, and the gate that proves it. Where a row names several
gates, the first is the one to iterate on:

| System | Spec | Sim | Gate |
|---|---|---|---|
| Attention: noise, scent, light | [docs/03](docs/03-attention.md) | `godot/sim/field/attention.gd`, `godot/sim/modules/attention_emitter.gd`, `godot/sim/attention_read.gd` | `godot:m2:district` |
| Carried light, what burns it down and what feeds it | [docs/03](docs/03-attention.md), [docs/12](docs/12-resources.md) | `godot/sim/modules/light.gd`, `godot/sim/vision/light.gd`, `godot/content/items/lights.json` | `godot:m2:light_burn`, `godot:m2:torch`, `godot:check:light` |
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
| Combat, stances, aim | [docs/09](docs/09-combat.md), [docs/29](docs/29-movement-and-stances.md) | `godot/sim/modules/melee.gd`, `godot/sim/modules/ranged.gd`, `godot/sim/modules/npc_combat.gd`, `godot/sim/stances.gd`, `godot/sim/combat.gd` | `godot:m2:swipe`, `godot:m2:hands`, `godot:m2:ranged`, `godot:m2:ammo`, `godot:m2:aim`, `godot:m2:stance`, `godot:m2:npc`, `godot:m2:contact` |
| Items, inventory, attachments, gunsmithing, modification | [docs/10](docs/10-items.md), [docs/11](docs/11-crafting.md) | `godot/sim/modules/items.gd`, `godot/sim/modules/inventory.gd`, `godot/sim/inventory/grid.gd`, `godot/sim/modules/attachments.gd`, `godot/sim/modules/gunsmith.gd`, `godot/sim/modules/modification.gd`, `godot/sim/modules/containers.gd` | `godot:m2:attach`, `godot:m2:armor`, `godot:m2:ammo`, `godot:m2:bench`, `godot:m2:gear`, `godot:m2:filter`, `godot:check:mods`, `godot:check:inventory` |
| Loot and resources | [docs/12](docs/12-resources.md) | `godot/sim/loot.gd`, `godot/content/loot/` | `godot:check:loot` |
| Stockpile: where the colony keeps things | [docs/12](docs/12-resources.md#storage-and-spoilage) | `godot/sim/modules/stockpile.gd` (the zone and its mark command), `godot/sim/modules/needs.gd` (`is_stockpile_tile`) | `godot:m2:stockpile`, `godot:m2:jobs` |
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
| Speech: what a body says out loud | [docs/30](docs/30-decisions.md) | `godot/sim/modules/speech.gd`, `godot/content/speech/` | `godot:check:speech` |
| Save and load | [docs/19](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd`, `godot/sim/save.gd` | `godot:m2:save` |
| The look | [docs/30](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03) | `godot/presentation/`, `tools/sprites/` | `godot:check:topdown`, `godot:check:appearance`, `godot:check:camera`, `godot:check:motion`, `godot:check:action`, `godot:check:world_bake`, `godot:check:light`, `godot:check:road`, `godot:check:water`, `godot:check:wrecks`, `godot:check:roof`, `godot:check:trees`, `godot:check:worn`, `godot:check:authored`, `godot:check:fx`, `sprites:check` |
| The screen | [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) | `godot/ui/` (its frames from the UI Field Kit, `godot/art/simplyzombies-ui/`, through `godot/ui/kit.gd`), `godot/presentation/main.gd`, `godot/presentation/input_map.gd` | `godot:check:ui_skin`, `godot:check:hud`, `godot:check:inventory`, `godot:check:respond`, `godot:check:web_look`, `godot:ban:healthbar`, `godot:check:play` (the one gate that executes the scene: `godot/check_play.gd`) |
| Balance and the campaign harness | [docs/22](docs/22-performance.md#measuring) | `godot/check_m2_balance.gd`, `godot/check_m2_harness.gd`, `godot/playtest/ten_day.gd` | `godot:m2:balance`, `godot:m2:harness`, `godot:playtest` (a measurement, not in the chain) |
| Performance | [docs/22](docs/22-performance.md) | `godot/bench/bench.gd`, `bench/` | `godot:bench`, `bench`, `bench:frame` |
| Content loading and validation | [docs/20](docs/20-ecs-and-content.md) | `godot/platform/`, `godot/content/schemas/` | `godot:validate`, `test` |
| The engine, CI and the desk | this file | `scripts/run-godot.mjs`, `.github/workflows/ci.yml`, `.claude/hooks/session-start.sh` | `check:routing`, `check:timing`, `godot:smoke`, `godot:r6:coverage` |
