# AGENTS.md

Environment, tooling, and the routing table. `CLAUDE.md` covers what the project *is*, how a unit
of work runs, and what must not be broken — read that one for the workflow, the standing bans, the
conventions, and the traps. The [routing table](#routing-table) below is the index: what to read,
where the code is, and which gate judges it, by kind of work and by system.

This repo is the game **simplyZOMBIES**.

- **Godot 4.7.1 build** (`godot/`, typed GDScript) — the canonical, playable product. Every
  `godot:*` npm script and `npm run build` targets this. New behaviour goes here.
- **TypeScript/Canvas "oracle"** (`src/`, `test/`, `bench/`) — the pre-rebuild implementation,
  kept as a **frozen reference**. It is not the shipped product and must not gain features, but
  it is still in the tree and **still gated by CI**: the `check` job runs `npm test`,
  `npm run typecheck`, `npm run lint` and `npm run format:check` against it, and `performance`
  runs `npm run bench` / `npm run bench:frame`. All of it is currently green (45 files, 594
  tests). `npm run dev` serves it via Vite on `127.0.0.1:5174` if you need to look at it.

Standard commands live in `package.json` scripts, `README.md`, and `.github/workflows/ci.yml`;
use those as the source of truth.

## Current work

This file does not carry status — a copy of it here drifted while docs/23 moved on, which is
exactly the failure the project keeps re-learning. The pointers:

- [docs/23's Milestone 2 status section](docs/23-roadmap.md#where-milestone-2-stands) is the
  authority on implemented reality — each claim there names the gate that proves it. Its
  [what's left](docs/23-roadmap.md#whats-left-in-milestone-2) section names every open piece as a
  small named item, and [the record, by system](docs/23-roadmap.md#the-record-by-system) holds the
  evidence for what landed.
- `CLAUDE.md`'s **workflow** section is how a unit of work runs, start to finish; its "Where the
  work is" section carries the three state facts worth repeating (the survival loop, on since
  2026-09-01; the top-down presentation track, whose art direction is the Dungeon Settlers look
  of 2026-09-03; the dead-socket pattern).
- `HANDOFF.md` names what is waiting on the owner. Those items — sepsis lethality, whether a roof
  covers a known building's unseen walls, whether the one-handed weapons need their own
  silhouettes at 32 px, and how dense a forest stand may get — are **decisions, never picked
  unilaterally**. Read the list there rather than trusting a count here. (The `GRABS_ENABLED` flip
  and the colony-shape call it waited on were decided by the owner 2026-09-01 and are landed; the
  flag record in docs/23 closes with them. The art-style pick was decided 2026-09-01 and
  re-decided 2026-09-03; docs/30 carries both.)
- The active design record is `.hermes/plans/2026-08-17_065300-vertical-slice-design.md`; it is
  **not** implementation evidence. `CONTEXT.md` holds the slice vocabulary — what to call needs,
  jobs, stances, and their states — so prose and code stay in one language.
- New NPCs and adjacent feature scope stay paused. The boot colony is **three** by the owner's
  2026-09-01 decision — the player, Mara, and Ellis (`survivor.unique.ellis`); further roster
  growth stays paused.

## Routing table

Where a unit of work goes: what to read before touching it, where the code lives, the gate that
can fail it, and where its record is written. `npm run check:routing` judges this table -- every
path, script and link in this section must resolve, and every `godot/check_*.gd` must be reachable
from an npm script -- so a route here is a claim the build checks, not a note that drifts. Add a
row when a system gains a home; the gate goes red when a route stops being true.

**By the kind of work:**

| If the work is... | Read first | It lives in | The gate | Record it in |
|---|---|---|---|---|
| Starting a session cold | [CLAUDE.md](CLAUDE.md), then [HANDOFF.md](HANDOFF.md), then [what's left](docs/23-roadmap.md#whats-left-in-milestone-2) | -- | `npm run godot:smoke` proves the engine | -- |
| A decision named in [HANDOFF.md](HANDOFF.md) as the owner's | that entry, and [docs/30](docs/30-decisions.md) | nowhere: stop and ask | -- | -- |
| A sim mechanic (a need, a wound, a job, the weather) | the system's spec in the table below, [docs/30](docs/30-decisions.md), and the traps in [CLAUDE.md](CLAUDE.md#traps-that-have-already-cost-someone-a-session) | `godot/sim/modules/`, `godot/sim/` | its `godot:m2:<name>` gate while iterating; `npm run godot:m2` before the commit | [the record, by system](docs/23-roadmap.md#the-record-by-system); a call taken goes in [docs/30](docs/30-decisions.md) |
| Content (an item, a zombie, a loot table, a weather kind) | [docs/20 Part 2](docs/20-ecs-and-content.md#part-2-content) and the schema under `godot/content/schemas/` | `godot/content/` | `npm run godot:validate` **and** `npm test` (only the oracle's Ajv recurses), plus the nested-shape gate for that block | the record |
| How a thing looks | [the Dungeon Settlers look](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03), `godot/assets/sprites/README.md` | `godot/presentation/`, `godot/assets/sprites/`, `tools/sprites/` | the `godot:check:<look>` gate for that layer; `npm run sprites:check` after touching `tools/sprites/` | the record, with a screenshot under `.hermes/plans/` for the owner to judge |
| What the screen says | [hardcore contract clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable), the vocabulary in [CONTEXT.md](CONTEXT.md) | `godot/ui/`, the read models `godot/sim/condition.gd` and `godot/sim/attention_read.gd` | `npm run godot:check:hud`, `npm run godot:ban:healthbar`, `npm run godot:check:respond` | the record |
| A claim about balance | [the workflow's step 5](CLAUDE.md#the-workflow), [docs/22 on measuring](docs/22-performance.md#measuring) | a throwaway driver, deleted afterwards | `npm run godot:m2:balance` and `npm run godot:m2:harness`; the before/after numbers | the record, numbers included |
| The save format | [docs/19's save model](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd` (`SAVE_VERSION`), `godot/sim/save.gd` | `npm run godot:m2:save` | the record |
| A gate, new or fixed | [a gate that cannot fail](CLAUDE.md#conventions), the dead-socket rule in [CLAUDE.md](CLAUDE.md#where-the-work-is) | `godot/check_*.gd`, a mode in `scripts/run-godot.mjs`, a script in `package.json`, a link in the `godot:m2` chain | `npm run check:routing` proves it is reachable | the record |
| The frozen TypeScript oracle | the top of this file | `src/`, `test/`, `bench/` | `npm run typecheck`, `npm run lint`, `npm run format:check`, `npm test`, `npm run bench` | nothing: it gains no features |
| CI, scripts, hooks, this table | [CLAUDE.md's verifying section](CLAUDE.md#verifying-a-change) | `.github/workflows/`, `scripts/`, `.claude/` | `npm run check:routing`, `npm run format:check`; the engine pin in `scripts/run-godot.mjs` | the record's Kernel & tooling entry |
| Driving a pull request | `.claude/skills/steward/SKILL.md` | -- | whatever CI reports; `npm run godot:m2` before every push | the PR itself |
| Playing it, or a screenshot | [Running the game](#running-the-game-gui) below | `godot/presentation/main.tscn` | `npm run godot:run` | -- |

**By system** -- the spec, the code, and the gate that proves it. Where a row names several
gates, the first is the one to iterate on:

| System | Spec | Sim | Gate |
|---|---|---|---|
| Attention: noise, scent, light | [docs/03](docs/03-attention.md) | `godot/sim/field/attention.gd`, `godot/sim/modules/attention_emitter.gd`, `godot/sim/attention_read.gd` | `godot:m2:district` |
| Needs | [docs/04](docs/04-survival-needs.md) | `godot/sim/modules/needs.gd` | `godot:m2:needs` |
| Health, wounds, recovery | [docs/05](docs/05-health-injury.md) | `godot/sim/modules/health.gd`, `godot/sim/modules/wounds.gd`, `godot/sim/condition.gd` | `godot:m2:wounds`, `godot:m2:recovery`, `godot:m2:splint`, `godot:ban:healthbar` |
| Infection and treatment | [docs/06](docs/06-infection.md) | `godot/sim/modules/infection.gd`, `godot/sim/modules/treatment.gd` | `godot:m2:treatment`, `godot:m2:lethality`, `godot:check:respond` |
| Survivors, recruits, the roster | [docs/07](docs/07-survivors.md) | `godot/sim/modules/survivors.gd`, `godot/sim/modules/recruits.gd`, `godot/sim/modules/roster.gd`, `godot/sim/modules/aptitudes.gd` | `godot:m2:roster`, `godot:m2:recruits`, `godot:m2:stats` |
| The skill web, Focus, jobs | [docs/08](docs/08-skill-web.md) | `godot/sim/modules/skills.gd`, `godot/sim/modules/jobs.gd` | `godot:m2:web`, `godot:m2:autonomy`, `godot:m2:jobs`, `godot:m2:upkeep` |
| Combat, stances, aim | [docs/09](docs/09-combat.md), [docs/29](docs/29-movement-and-stances.md) | `godot/sim/modules/melee.gd`, `godot/sim/modules/ranged.gd`, `godot/sim/modules/npc_combat.gd`, `godot/sim/stances.gd`, `godot/sim/combat.gd` | `godot:m2:swipe`, `godot:m2:ranged`, `godot:m2:aim`, `godot:m2:stance`, `godot:m2:npc`, `godot:m2:contact` |
| Items, inventory, attachments, modification | [docs/10](docs/10-items.md), [docs/11](docs/11-crafting.md) | `godot/sim/modules/items.gd`, `godot/sim/modules/inventory.gd`, `godot/sim/inventory/grid.gd`, `godot/sim/modules/attachments.gd`, `godot/sim/modules/modification.gd`, `godot/sim/modules/containers.gd` | `godot:m2:gear`, `godot:m2:attach`, `godot:check:mods` |
| Loot and resources | [docs/12](docs/12-resources.md) | `godot/sim/loot.gd`, `godot/content/loot/` | `godot:check:loot` |
| Zombies | [docs/14](docs/14-zombies.md) | `godot/sim/modules/shambler.gd`, `godot/sim/modules/bloater.gd`, `godot/sim/modules/screamer.gd` | `godot:m2:contact`, `godot:m2:swipe`, `godot:m2:lethality` |
| Fortification | [docs/15](docs/15-base-building.md) | `godot/sim/modules/fortify.gd` | `godot:m2:fortify` |
| Weather | [docs/16](docs/16-weather.md) | `godot/sim/modules/weather.gd`, `godot/content/weather/`, `godot/content/climate/` | `godot:m2:weather`, `godot:m2:storm`, `godot:m2:cold`, `godot:m2:heat`, `godot:check:weather` |
| The director and the raiders | [docs/17](docs/17-director.md), [docs/18](docs/18-factions.md) | `godot/sim/modules/director.gd`, `godot/sim/modules/raiders.gd`, `godot/sim/modules/allegiance.gd` | `godot:m2:director`, `godot:m2:raiders` |
| The district and world generation | [docs/24](docs/24-world-and-scale.md) | `godot/sim/map/`, `godot/content/districts/`, `godot/content/buildings/` | `godot:check:worldgen`, `godot:check:buildings`, `godot:m2:district` |
| Vehicles | [docs/25](docs/25-vehicles.md) | `godot/sim/modules/vehicles.gd`, `godot/content/vehicles/` | `godot:m2:vehicles`, `godot:check:wrecks` |
| Sightlines and memory | [docs/28](docs/28-visibility-and-sightlines.md) | `godot/sim/vision/`, `godot/sim/modules/sightings.gd` | `godot:m2:sight` |
| Save and load | [docs/19](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd`, `godot/sim/save.gd` | `godot:m2:save` |
| The look | [docs/30](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03) | `godot/presentation/`, `tools/sprites/` | `godot:check:topdown`, `godot:check:appearance`, `godot:check:camera`, `godot:check:light`, `godot:check:road`, `godot:check:wrecks`, `godot:check:roof`, `godot:check:trees`, `godot:check:worn`, `sprites:check` |
| The screen | [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) | `godot/ui/` | `godot:check:hud`, `godot:check:respond`, `godot:ban:healthbar` |
| Balance and the campaign harness | [docs/22](docs/22-performance.md#measuring) | `godot/check_m2_balance.gd`, `godot/check_m2_harness.gd` | `godot:m2:balance`, `godot:m2:harness` |
| Performance | [docs/22](docs/22-performance.md) | `godot/bench/bench.gd`, `bench/` | `godot:bench`, `bench`, `bench:frame` |
| Content loading and validation | [docs/20](docs/20-ecs-and-content.md) | `godot/platform/`, `godot/content/schemas/` | `godot:validate`, `test` |
| The engine, CI and the desk | this file | `scripts/run-godot.mjs`, `.github/workflows/ci.yml`, `.claude/hooks/session-start.sh` | `check:routing`, `godot:smoke`, `godot:r6:coverage` |

## Two different containers, two different starting states

Which one you are in changes the first thing you have to do.

| | Cursor Cloud VM | Claude Code on the web |
|---|---|---|
| Godot 4.7.1 | preinstalled at `/usr/local/bin/godot` | **absent** until `.claude/hooks/session-start.sh` installs it (or `bash scripts/setup-web-session.sh` by hand) |
| Export templates | preinstalled at `~/.local/share/godot/export_templates/4.7.1.stable/` | **not installed** — set `SETUP_EXPORT_TEMPLATES=1` if you need `godot:export` or `godot:smoke:exports` |
| Display | VNC desktop already on `DISPLAY=:1` | none — start one: `Xvfb :1 -screen 0 1920x1080x24 &` |
| Playwright Chromium | preinstalled | at `/opt/pw-browsers`; never run `playwright install` |

`scripts/run-godot.mjs` auto-discovers the engine (and honours `GODOT_BIN`) and hard-rejects any
build whose `--version` does not start with `4.7.1`. Keep that pin exact — the same version and
SHA-512 appear in `.github/workflows/ci.yml`, `pages.yml`, and `scripts/setup-web-session.sh`, so
changing one means changing all of them.

## Headless verification (no display needed)

Every correctness and performance gate runs headless through `scripts/run-godot.mjs`. The one to
run before a commit is **`npm run godot:m2`**, which chains every Milestone 2 gate (count them off
the script in `package.json`; every number written here has drifted); `npm run godot:r6` adds
parity, coverage, mutation and soak on top. `CLAUDE.md` names the gates worth knowing by name; the
authoritative list is the `godot:m2` script in `package.json`, and every gate has a
`godot:m2:<name>` script of its own for iterating.

Expected output that is **not** a failure:

- `ObjectDB ... leaked at exit` and `resources still in use` printed *after* a gate reports its
  `_OK` line. Engine shutdown noise. Check the `_OK` line and the exit code.
- `BENCH_OVER_BUDGET` from `npm run godot:bench`, which still exits 0. The budgets are calibrated
  against compiled TypeScript; headless GDScript is an interpreter. See docs/22.

Long-running gates, so you can plan: `godot:m2:balance` is ~4.5 min and is part of `godot:m2`.
`BALANCE_FULL=1 npm run godot:m2:balance:full` is a **~9 hour** grid and is opt-in for that
reason — `BALANCE_DAYS` and `BALANCE_SEEDS` scale it down to exercise the code path.

## Running the game (GUI)

```bash
Xvfb :1 -screen 0 1920x1080x24 &     # skip on the Cursor VM, which already has :1
DISPLAY=:1 npm run godot:run          # or npm run godot:editor
```

- Rendering is the Mesa `llvmpipe` software renderer. `Could not set V-Sync mode`, the ALSA
  errors, `libpulse.so.0: cannot open shared object file` and `All audio drivers failed, falling
  back to the dummy driver` are all expected here and harmless.
- **It starts on day 1 in daylight** — `SimBoot` boots the clock at `Clock.DAY_BEGINS`, which is
  the first tick of the Day phase. (This file used to say it starts at night and that you should
  wait for dawn. That was wrong, whenever it stopped being true.) A day is four hours at 1×, so
  press `3` for 10× and wait if you want to see dark.
- The HUD is **prose only** — no numbers except the day counter, enforced by
  `npm run godot:check:hud`. Do not go looking for a `light` value on it; the numeric developer
  sheet lives behind the `M` toggle. `F1` shows the key list, which is up by default on a fresh
  run and will sit over the middle of the screen until dismissed.

### Screenshots

A warning on checking whether a display already exists: `pgrep -f Xvfb` matches **your own shell
command** (the pattern is in its argv), so it reports a running server when there is none. Test the
display, not the process list — run the capture and read the error, or pick a fresh number
(`Xvfb :2 …`) and pass it explicitly.

There is no `scrot`, `imagemagick`, `xwd` or `ffmpeg` in these containers. Capture through Godot
instead: write a throwaway `SceneTree` script that instantiates `res://presentation/main.tscn`
into `root` — `godot/test/project_smoke.gd` is the pattern — drives it, and calls
`root.get_texture().get_image().save_png(path)`. Run it with
`DISPLAY=:1 godot --path godot --script res://<name>.gd`. This is also how you set a scenario up
before capturing it (spawn a shambler next to a survivor, then watch). Delete the script when you
are done — it is a driver, not a fixture, and it has no gate keeping it honest once it is
committed.

## When something looks broken

Check it against `main` before treating it as environment breakage — but note that this file
previously listed three "known pre-existing" failures (`npm test` content-id and handoff-count
drift, and `format:check` flagging `.scratch/*.html`) that have all since been **fixed**. Verified
2026-08-25 on this container: `npm test` (45 files / 594 tests), `npm run typecheck`,
`npm run lint`, `npm run format:check`, `npm run godot:validate`, `npm run godot:test`,
`npm run godot:smoke` and the full `npm run godot:m2` chain all pass. A red one is a real
regression, most likely yours.

One thing that is *not* environment breakage and is not yours either: `npm run godot:m2` takes
about **twelve minutes** here (measured 2026-09-04; `CLAUDE.md` carries the figure).
`godot:m2:balance` (~4.5 min) and `godot:m2:lethality` are most of it.
Run the single `godot:m2:<name>` gate you are iterating on and save the chain for the commit.
