# CLAUDE.md

Read this before touching anything. It is the one entry point: what the project is, how a unit of work
runs, the routing table, the environment, the owner's open decisions, and what must not be broken.

## Start here

- **Where the work is:** [what's left in Milestone 2](docs/23-roadmap.md#whats-left-in-milestone-2)
  names every open piece. [Where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands) is
  the status, each claim naming its gate. [The record, by system](docs/23-roadmap.md#the-record-by-system)
  holds what landed.
- **Why it is shaped this way:** [docs/30](docs/30-decisions.md). `CONTEXT.md` holds the slice vocabulary.
- **Owner decisions:** [Waiting on the owner](#waiting-on-the-owner) lists what only the owner decides.
- **Commands:** standard commands live in `package.json`, `README.md` and `.github/workflows/ci.yml`;
  those are the source of truth. The frozen TypeScript oracle serves on `127.0.0.1:5174` via `npm run dev`.

Cold start:

```bash
bash scripts/setup-web-session.sh   # verify or install the pinned engine
npm run godot:smoke                 # the project boots
npm run check:routing               # the routing table, and every gate reachable
npm run godot:run                   # play it (DISPLAY=:1 on a headless VM)
```

## Godot is the only implementation that ships

The game is `godot/` — Godot 4.7.1 (Compatibility), typed GDScript. New behaviour goes here and
nowhere else. `npm run build` is `godot:export`, and Pages publishes the Godot build at `/`.

**But the TypeScript oracle is still in the tree and still runs in CI, which this file used to
deny.** `src/`, `test/`, `bench/` and the Vite/vitest configs are all present on `main`, and the
`check` job runs `npm test`, `npm run typecheck`, `npm run lint`, `npm run format:check` and
`npm run bench` against them alongside the Godot gates. As of this writing all of it is green:
**45 files / 594 tests** (one file, `handoff.test.ts`, retired with the checkbox ledger it
counted — see the note under Conventions). It is a
*frozen reference*, not a second product — do not add features
to it, do not port Godot changes into it — but do not delete it or let it go red either, because
CI will stop you. Its frozen parity fixtures under `godot/parity/` are what `npm run godot:test`
compares against, and tag `ts-oracle-final` is the rollback point.

The engine pin is exact. `scripts/run-godot.mjs` rejects any engine whose `--version` does not
start with `4.7.1`, and the same version and SHA-512 appear in `.github/workflows/ci.yml`,
`pages.yml`, and `scripts/setup-web-session.sh`. Changing one means changing all of them.

## The workflow

How a unit of work goes through this repo — the same loop for a human, an agent, or both. The
pattern that works here is the **slice**: one named piece, built together with the gate that can
fail it, measured if it claims anything about balance, recorded in the same commit. The sessions
that followed this loop landed six slices in a run; the sessions that did not are where the traps
section came from.

1. **Orient before touching anything.** This file top to bottom, then the
   [routing table](#routing-table) for where each kind of work lives and which gate
   judges it, then
   [what's left](docs/23-roadmap.md#whats-left-in-milestone-2) for what is open and
   [the record, by system](docs/23-roadmap.md#the-record-by-system) for how the neighbouring
   systems landed. The owner list under [Waiting on the owner](#waiting-on-the-owner) names what is waiting on the owner. Read
   [docs/30](docs/30-decisions.md) before changing anything that looks arbitrary — it usually
   is not.
2. **Pick one named piece from what's left.** They are sized to land in a session. The "waiting
   on the owner" group is not pickable — those are decisions, and deciding one unilaterally is
   the one mistake at this stage no gate will catch. Work that is not on the list gets named and
   added there first (or asked about), never smuggled in beside a slice.
3. **Design inside the seams.** Effects are sim-owned and command-driven; `godot/sim/` never
   reads presentation state; how a thing looks is content; new randomness gets its own named RNG
   stream. Anything player-facing goes through the standing bans *before* it is built, not after.
4. **Build the gate with the thing.** Every assertion wants a true positive *and* a true
   negative, and every mechanism wants the assertion that something **reads** it — the
   dead-socket rule, paid for eight times this milestone. An assertion with no data to judge says
   so and skips; it never passes quietly.
5. **Measure balance claims; never theorise them.** A claim about campaign outcomes comes from a
   throwaway driver, run before and after on the same driver — two consecutive guesses at the
   harness each cost a full run to disprove. Check the throughput arithmetic first (the shipped
   world runs at ~34 ticks/s: a game day is ~2 h 21 min, a ten-day campaign ~23 h; see
   Throughput below). Drivers are deleted
   afterwards; anything that stays behind gets a gate keeping it honest.
6. **Verify before committing.** Run the gates for what the change touched; the policy is under
   [Verifying a change](#verifying-a-change). A content edit is not verified until `npm test` has also run — the frozen oracle's Ajv recurses where `godot:validate` does not.
   Touching a `.ts` file or any prettier-covered path adds `typecheck`, `lint`, `format:check`.
7. **Record in the same commit.** Delete the piece from what's left; write its record — named,
   gated, measured — into the record, by system. Update the owner list under [Waiting on the owner](#waiting-on-the-owner) only when what is waiting on the owner changed. Prose is hand-wrapped.
8. **Leave it honest.** No checkbox ledgers anywhere; every claim names the gate that proves it;
   where only half a thing shipped, the record says which half.

## Verifying a change

Correctness for a Godot change is the Godot gates. **Policy (decided 2026-10-19, docs/30):** before a commit, run the gates for what the change touched:
its `godot:m2:<name>` lanes, `godot:smoke` and `godot:validate` for a boot or content change, `godot:check:play`
for a scene or input change, `npm test` for anything under `godot/content/`. The full `npm run godot:m2`
chain runs in CI's `godot-m2` job on every pull request and every push to main, and nothing merges red.
A change to a shared sim module or the save format still runs the full chain locally before its commit. The
latest full cloud run took **47m16s for 85 gates** (2026-10-03,
`GATE_TIME_TABLE` total 2835.79 seconds), including **15m29s** for the fast balance tier.
Timings depend on the machine: 30m06s for 84 gates was
measured 2026-09-27 on a four-core Windows desktop, with two worker slices running beside it;
31m29s for 83 gates the day before; 26m45s for 69 gates on a project container on 2026-09-12. It
said twelve here for eight days, measured 2026-09-04 when the chain was 51 gates; the alpha-roster
arc added four gates and took the roster from 152 bases to 362, and a catalogue gate's cost scales
with the roster. Budget for the real
number — an instruction to run a twelve-minute command that actually takes twenty-seven is how a
pre-commit check quietly stops being run:

```bash
npm run godot:smoke      # project boots            → GODOT_PROJECT_SMOKE_OK
npm run godot:validate   # content registry
npm run godot:test       # R1 parity vs the frozen fixture
npm run godot:m2         # all Milestone 2 gates    → M2_LETHALITY_OK et al
npm run godot:m2:balance # the balance harness, fast tier → M2_BALANCE_OK (~15 min here, in godot:m2)
npm run godot:m2:sight   # sightlines and memory     → M2_SIGHT_OK
npm run godot:m2:attach  # attachment slots          → M2_ATTACH_OK
npm run godot:m2:ammo    # calibers, and what a round changes → M2_AMMO_OK
npm run godot:m2:hands   # bare hands, never actually empty  → M2_HANDS_OK
npm run godot:m2:wounds  # severity, the bleed clock  → M2_WOUNDS_OK
npm run godot:m2:treatment # pressure and bandaging   → M2_TREATMENT_OK
npm run godot:m2:medicine  # supply grades: antibiotics, painkillers, a cure for illness → M2_MEDICINE_OK
npm run godot:m2:filter    # what a mask keeps out of a bloater's cloud → M2_FILTER_OK
npm run godot:m2:materials # what a recipe is made of, by kind → M2_MATERIALS_OK
npm run godot:m2:transform # what a thing cooks, boils or purifies into → M2_TRANSFORM_OK
npm run godot:m2:noise     # a device you wind up, put down and pick back up → M2_NOISE_OK
npm run godot:m2:comfort   # something for your own morale that is not a meal → M2_COMFORT_OK
npm run godot:m2:teach     # a book, read once, bounded by what practice pays → M2_TEACH_OK
npm run godot:m2:warmth    # insulation per part, wet, cooling, and what sheds rain → M2_WARMTH_OK
npm run godot:m2:light_burn # a lamp runs out, a headlamp lights, a floodlight stands → M2_LIGHT_BURN_OK
npm run godot:m2:armor     # armour slots, and coverage that stops a blow → M2_ARMOR_OK
npm run godot:m2:recovery  # healing, and what is permanent → M2_RECOVERY_OK
npm run godot:m2:splint    # the splint, and the limp a bad fracture leaves → M2_SPLINT_OK
npm run godot:m2:raiders   # the band at the gate       → M2_RAIDERS_OK
npm run godot:m2:vehicles  # the parked cars and bikes, driven → M2_VEHICLES_OK
npm run godot:m2:weather   # the sky has kinds: seasons, wind, the shift → M2_WEATHER_OK
npm run godot:m2:storm     # noise masked, lightning, outdoor work refused → M2_STORM_OK
npm run godot:m2:cold      # the cold snap's pantry, the snow's cover     → M2_COLD_OK
npm run godot:m2:heat      # the hot clock, heatstroke, thirst, rot       → M2_HEAT_OK
npm run godot:m2:fog       # sight collapsed both ways, one content number → M2_FOG_OK
npm run godot:m2:tick      # the tick's memos agree with the scans they replaced → M2_TICK_OK
npm run godot:ban:healthbar  # the health-bar ban   → BAN_HEALTH_BAR_OK
npm run godot:check:appearance # the sprite pipeline → APPEARANCE_OK
npm run godot:check:hud      # HUD speaks in prose   → HUD_OK
npm run godot:check:play     # the gate that plays it: boots the scene, presses keys → PLAY_OK
npm run godot:check:context  # the right-click menu, and walk-here → CONTEXT_OK
npm run godot:check:speech   # speech bubbles: a line said, and who says it → SPEECH_OK
npm run godot:check:respond  # the antibiotics word  → RESPOND_OK
npm run godot:check:camera   # smoothed follow, shake → CAMERA_OK
npm run godot:check:light    # sight-derived wash, lit ∩ seen pools → LIGHT_LOOK_OK
npm run godot:check:memory   # the afterimage, and the remembered map dimmed → MEMORY_LOOK_OK
npm run godot:check:road     # street manifest, paint, palette, rubble → ROAD_LOOK_OK
npm run godot:check:water    # deep water solid and clear, the ford slow and loud → WATER_OK
npm run godot:m2:region      # four districts in one space, each identical to itself → M2_REGION_OK
npm run godot:check:wrecks   # parked vehicles, heaps, debris art → WRECKS_OK
npm run godot:check:weather  # the sky per kind, snow cover, the flash → WEATHER_OK
npm run godot:check:roof     # wall caps and faces, roofs cut out where seen → ROOF_LOOK_OK
npm run godot:check:trees    # tall trees in the entity sort, the fade → TREES_OK
npm run godot:check:worn     # gear layers, order and skeleton fit → WORN_LOOK_OK
npm run godot:check:web_look # the skill web drawn as a web, words only → WEB_LOOK_OK
npm run godot:check:ui_skin  # the UI Field Kit, worn → UI_SKIN_OK
npm run godot:check:fx       # the shot is seen: flash, casing, blood, flame, only where seen → FX_OK
npm run godot:r6         # parity, coverage, mutation, soak, bench, validate
npm run godot:run        # play it (DISPLAY=:1 on a headless VM)
npm run sprites:check    # generated art still matches tools/sprites/ → SPRITES_OK
npm run check:routing    # the routing table resolves; every check_*.gd is reachable → ROUTING_OK
npm run check:timing     # the per-gate timing table names every mode the chain ran → TIMING_OK
```

Those are the ones worth naming, not all of them: `godot:m2` chains **86**, and the authoritative
list is the `godot:m2:chain` script in `package.json` (`godot:m2` itself is
`node scripts/m2-chain.mjs`, which reads that list and runs it) — read it there rather than
trusting a copy here, because a copy here is one more thing that drifts. Run an individual gate
with the `godot:m2:<name>` script beside it when you are iterating; run the chain before you
commit. `godot:m2` prints a `GATE_TIME_TABLE` at the end — every gate it ran, slowest first, with
a total — built from the `GATE_TIME` line `scripts/run-godot.mjs` prints after every mode, success
or failure; `npm run check:timing` is the gate that proves the table cannot come up short.

`sprites:check` is the one gate deliberately **outside** `godot:m2`: it needs Pillow
(`pip install pillow==12.3.0`) and that chain stays engine-only and pip-free, so it runs as its
own step in CI's `check` job. Run it after editing anything under `tools/sprites/` or any PNG
that package generates — it re-renders every registry key and compares decoded pixels against
the committed file, so a palette edited without regenerating is a red build.

`check:routing` is the other gate outside `godot:m2`, and the one that judges the desk rather
than the game: it reads the routing table in CLAUDE.md and fails on any path, npm script or
doc anchor that no longer resolves, then asks the dead-socket question of the gates themselves
(every `godot/check_*.gd` reachable from `scripts/run-godot.mjs`, every runner mode reachable
from `package.json`, every `godot:m2:*` / `godot:check:*` / `godot:ban:*` script inside the
`godot:m2` chain or excused by name). Run it after touching any of those four things. Node only,
about a second.

`check:timing` is a third gate outside `godot:m2`, beside it rather than in it: it self-tests
`scripts/m2-chain.mjs`'s per-gate timing table against fabricated `GATE_TIME` lines (never the
real engine) and checks that `godot:m2` still delegates to it and that `run-godot.mjs` still
prints the line the table is built from. Run it after touching `scripts/run-godot.mjs`,
`scripts/m2-chain.mjs` or the `godot:m2:chain` list. Node only, about a second.

`godot:m2` prints `ObjectDB ... leaked at exit` and `resources still in use` *after* it reports
success. That is engine shutdown noise, not a failure — check the `_OK` line and the exit code.

CI runs `godot:m2` as four parallel `godot-m2-shard` jobs, one per shard, and the `godot-m2`
job gathers them as the required check (it passes only when every shard did). The shard layout is
`scripts/m2-shards.mjs`: every chained gate is in exactly one shard, shard 4 is `godot:m2:balance`
alone (791 s, the floor on wall time), and the gates that write the per-machine `user://` store
share shard 3. `npm run godot:m2 -- --shard=<i>/4` runs one shard; a gate added to the chain must
also be added to a shard in the same commit, or `check:shards` (in the `check` job) goes red. The
unsharded `npm run godot:m2` is unchanged. Measured 2026-10-19 on one runner: 40m45s for 85 gates.
The `check` job (25 min) runs the TypeScript side (`npm test`, `typecheck`, `lint`,
`format:check`), `sprites:check`, `check:routing`, `check:timing`, `check:shards`,
`check:runtime-budget`, the smoke, the validator and the R6 gates.
The `performance` job runs `npm run bench` and `npm run bench:frame`.
Touching a `.ts` file or any prettier-covered path means running those too. Legacy
`npm run godot:bench` prints `BENCH_OVER_BUDGET` and still exits 0 on a synthetic workload.
`npm run godot:bench:runtime` measures the real playable world's tick and
`npm run godot:bench:frame` measures the real scene's world-draw CPU work (a display is required).
These commands fail on overruns or invalid evidence. CI enforces their deterministic runner
contract; actual Godot timing enforcement remains open because the product exceeds its targets.
See docs/22. `npm run bench` is the separate, enforced TypeScript benchmark.

A fresh Claude Code on the web container has no engine; `.claude/hooks/session-start.sh`
installs it. To do it by hand: `bash scripts/setup-web-session.sh`. It does **not** install export
templates, so `godot:export` / `godot:smoke:exports` need `SETUP_EXPORT_TEMPLATES=1`.

## Jev delegation

Use the `jev` MCP tools for cheap, bounded judgments. Jev is advisory: it never replaces a gate,
never makes a decision that belongs to the owner, and never relaxes a rule in this file. If the
server is down, say so once and carry on without it.

**Before reading**
- The orient reads (workflow step 1): read them in full.
- More than 5 candidate files: rank them with `jev_rerank` or `jev_find`, then read only the top
  matches. Ranking never proves absence; the dead-socket question ("does anything read this?")
  is answered by grep.
- Outside content (web pages, docs, API payloads, pasted text): run `jev_screen` first. `block` =
  don't use it; `review` = show the user the flagged part.

**Deciding**
- Yes/no checks over text you already have: `jev_noul`, or `jev_verify` for strict evidence.
  Anything grep, a gate or the engine can settle, settle that way.
- Picking from 2–6 known options: call `jev_decide` once, and do what it says if it returns
  `ask_user` or `investigate`. Never use it on "waiting on the owner" items, the standing bans,
  or docs/30 decisions.
- Docs vs. code drift (a docs/23 record against the gate or code it describes): `jev_compare`.

**Before commit / PR / "done"**
1. Run the gates from workflow step 6. Red = stop.
2. Call `jev_gate` (with claims from the docs/23 record, and gate output as evidence) or
   `jev_review` on the diff. `auto_accept`: **0.75** if the diff touches only `*.md` / `docs/`,
   otherwise **0.85**.
3. `auto`: proceed, but commit only when asked. `review`/`escalate`, a non-empty
   `limiting_rubrics`, or a contradicted claim: stop, quote the concern, ask the user. If they
   override, record it in the commit message.
4. Report the Jev result next to the gate results, never instead of them.

Scores vary about ±0.06 between runs. Don't re-run the review hoping for a pass, and don't tune
the threshold to fit a result.

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

## Where the work is

Milestone 2, the vertical slice — one district, a handful of survivors, enough of every system to
find out whether the loop is fun. Its exit criterion is ten in-game days, permanent loss,
succession, and still wanting another run.

The whole-interface redesign is a proposal, not a shipped change. Read [docs/32](docs/32-ui-overhaul.md)
and [the owner's 2026-10-03 decision](docs/30-decisions.md#the-whole-interface-2026-10-03) before
applying older kit, font or chart requirements. Its work list is [docs/23's UI overhaul group](docs/23-roadmap.md#ui-overhaul).

The boot colony is **three by the owner's 2026-09-01 decision** — the player, Mara, and Ellis
(`survivor.unique.ellis`), and further roster growth *at boot* stays there. The pause that
decision put on new NPCs and roster growth was **lifted by the owner on 2026-09-14**
([docs/30](docs/30-decisions.md), "The pause lifted"): generated people, raiders and zombies are
the thirteen-piece population arc landed on 2026-09-15/16. Generated people, individual raiders,
dormant zombies and settler camps are recorded with their gates in docs/23. The three-person
boot colony remains fixed; later recruitment grows it. The **captives arc** (docs/30's "One web,
and the captives", the same
day; docs/23's what's-left names its slices) is named work under that lift rather than the lone
exception to a pause its own entry was written against — a held raider who can be recruited or
put to work, with a recruited captive mid-game growth either way. The design record is
[`.hermes/plans/2026-08-17_065300-vertical-slice-design.md`](.hermes/plans/2026-08-17_065300-vertical-slice-design.md).
It captures decisions, not shipped behavior: nothing counts as done until code and a focused Godot
check prove it.

[docs/23](docs/23-roadmap.md) is the authority on what is intended **and**, in its milestone status
sections, on what is built and what remains (the old per-item checkbox `HANDOFF.md` was retired
into it and its itemised history lives in git; there is no `HANDOFF.md` any more (retired 2026-10-19), and the owner list lives under
[Waiting on the owner](#waiting-on-the-owner), which is not a status ledger). Its
[what's left](docs/23-roadmap.md#whats-left-in-milestone-2) section names every
remaining Milestone 2 piece — small, modular, named so the name alone says the work — and its
[record, by system](docs/23-roadmap.md#the-record-by-system) holds the evidence for what landed;
a landing moves its piece from the first to the second in the same commit.
[docs/30](docs/30-decisions.md) is the authority on why something that looks arbitrary is shaped
that way. Read 30 before changing something that looks arbitrary. This file does not restate their
contents — the one copy of the status lives in docs/23, because every duplicated copy of it has
drifted. Three things about the current state matter enough to repeat anyway:

- **The survival loop is built end to end, gated, and ON.** Grabs, bites, located bleeding
  wounds, pressure and bandaging, rescue, recovery, infection — `SimShambler.GRABS_ENABLED`
  ships `true` since the owner's 2026-09-01 decision (a bigger colony, then the flip; docs/23's
  flag record is the seed-by-seed history and closes with it). The flag stays a gate-drivable
  static: any gate lane that pins it must **restore the previous value**, because one gate
  process shares it across every world it boots. Relaxing `survivors_end >= 1` has been
  considered and rejected — post-flip it is the standing assertion that the shipped default
  survives its own contact loop. Sepsis lethality was decided 2026-09-06 (lethal untreated,
  docs/30's "The playable state") and landed 2026-09-07 with the cold and the heat — three
  dusks septic and the body dies; docs/23's lethality record in the playable-state group.
- **The presentation is flat top-down, not isometric** — an independent track that touched nothing
  under `godot/sim/`. `docs/00-vision.md` carries the reversal, docs/30 what it made structural,
  and the art entries in what's left the ordered next steps. The style is **the Dungeon Settlers
  read, decided by the owner 2026-09-03**: a warm dark-fantasy palette, walls drawn with a lit cap
  and a south face, roofs cut out where the sim sees, three-quarter props and vehicles, 32 px a
  tile at 2×. **Its face-on pawn and its "nobody rotates" clause were reversed by the owner on
  2026-09-11** — docs/30's "The decoupled paperdoll" — and that proposed rotating rig was
  subsequently superseded by the adopted outpost pack. Since 2026-09-26 ("The bodies turn and
  walk", the outpost pack) humans draw the pack's four-direction body; the 2026-10-02 zombie
  pose set replaces its shared shambler with seven animated families and settled corpses.
  Only the screamer and the bloater are still the face-on pawn described below. The 2026-09-03 entry itself
  superseded the 2026-09-01 style-B pick (the rotating player, the overcast mood) and records the
  twelve decisions and what each earlier clause becomes; the 2026-09-11 entry does the same for
  it, which is the third time the bodies have been re-decided — read docs/30 in date order rather
  than trusting any one entry alone. **Decided lands slice by slice, and [docs/23's
  record](docs/23-roadmap.md#the-record-by-system) is the one copy of which ones have.** This file
  deliberately does not list them: that list has now drifted three times, each time a slice landed
  without its copy here being updated, which is the same reason the milestone status lives in one
  place. What the style *is* **as shipped today**: the table is warm; humans use the outpost body and
  zombies use their content-selected families (32×40, the heavy 40×48), four views and a walk keyed to
  `world.tick`, never mirrored, while the screamer and the bloater are squat face-on pawns that
  flip through a negative-width rect; walls draw their
  material's cap or south face and roofs cover what the sim cannot see; the darker ground draws a
  boundary once onto the lighter tile; a tree is a 32×96 picture standing in the entity sort; a
  parked car is a manifest record the layout wrote, drawn as one three-quarter picture per class,
  variant and axis in that same sort; and equipment draws on the body in one order -- the
  pack's four wearables per view and supported held weapons; the old face-on clothing overlays
  are retired. Where a piece has not landed yet, its code comments say so on purpose. The reference's
  HUD — portraits, bars, numbers, name plates — is explicitly not adopted.
- **The dead-socket pattern.** This milestone has turned up **eleven** pieces of code that were
  complete, correct, often gated, and read by nothing: `crawlFactor`, the `Staggered` state,
  `sepsis.checked`, `injury.sustained`, `item.painkillers.blister`, `SimVisibility` for everybody
  but the player, rule 4's variance floor behind an `if size == 0` that could never be true,
  `SimDirector.snapshot_of`, `SimStances.CAN_AIM` (found by the review sweep — it had said "a
  sprint cannot aim" since the ladder landed while `SimRanged` let a sprinting survivor fire),
  the `move_speed` stat itself for every NPC (found by the weather spine: `SimJobs._walk` never
  resolved it, so the limp, encumbrance and blood loss had only ever slowed the player), and
  `item.appearance.sprite` — in the schema since the appearance pipeline landed, read by nothing,
  so every dropped item was the same ten-pixel square until the 2026-09-08 glyph slice gave it a
  reader.
  **A gate asserting that a helper returns the right number does not assert that anything reads
  it** — and the textual assertion that says something *does* read it has to be able to find the
  reader after a refactor. The inventory overhaul turned two such gates red without breaking
  anything: `check_respond` looked for a call in `_draw` that had moved into `_draw_body`, and
  `check_weather` looked for the ground-item colour in `_draw_entities` after it moved into
  `Appearance.item_look`. Both were fixed by following the call a link further, never by dropping
  the needle. **A third instance, 2026-09-12, a different shape:** `check_m2_comfort.gd` asserted
  its key was in `check_m2_gear.gd`'s `READ_KEYS` by searching for the *tail* of that list,
  `"noise", "comfort"]` — deliberately, because the bare word appears in that file's prose too and a
  needle a comment can satisfy cannot fail. The reasoning was right and the needle was still wrong:
  the books slice appended `"teaches"` an hour later and the lane went red against a gear gate that
  was correct. Isolate the line first (`begins_with("const READ_KEYS")`) and ask for membership
  inside it — no comment can satisfy that and no later key can displace it; `check_m2_teach.gd` is
  the precedent. When you add a mechanism, add the assertion that something reaches it —
  `check_m2_attach.gd`'s "is this findable in any loot table" is the cheapest example, and
  `npm run check:routing` applies the same rule to the gates themselves (a check script no npm
  script reaches is red, which retired `check_r6_bench.gd`). The sweep
  left four sockets named but unfixed; one closed 2026-09-16 — `SimStances.eye_of` now has a
  reader, `SimVisibility.refresh` writing `observer["eye"]` from it every tick
  (`godot:m2:sight`'s EYE and EYE-READER lanes; the record's Attention leftovers entry) — and
  three remain (`sim/spatial/hash.gd` entire, `SimThreat.threat_within`, and
  `SimDirector.snapshot_of` — found, replaced by `world.gd`, and still defined); they are in
  [docs/23's defect list](docs/23-roadmap.md#whats-left-in-milestone-2).

Keep all effects sim-owned and command-driven; player-facing state remains prose/diegetic and must
not weaken the condition-view health-bar ban. The full balance grid and human ten-day playtest are
still required Milestone 2 proof, deferred rather than cancelled.

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
  same commit as the work it describes (workflow step 7). There is no `HANDOFF.md` any more; its owner list is under [Waiting on the owner](#waiting-on-the-owner). **Never** put per-item checkboxes in any status file.
  Its checkbox predecessor drifted four times, most recently by ~34 shipped-but-unticked items,
  which is why status is condensed prose with each claim naming the gate that proves it. No gate
  enforces this any more (`godot:check:handoff` retired with the old file), so the discipline is
  the convention. Where only half an item shipped, say which half.

## Traps that have already cost someone a session

Each of these was found the expensive way. They are not style opinions.

- **Packed arrays are values in GDScript.** `(dict["key"] as PackedStringArray).append(x)` appends
  to a *copy* and silently does nothing. This made a four-seed harness report four identical runs.
  Use a plain `Array` for anything you mutate through a Dictionary.
- **A survivor's body parts do not share a scale.** A healthy head is 15, a hand 10, a torso 40 —
  so `body[part] < 15` means "critically injured" on a torso and "perfectly fine" on a head. There
  is exactly one place that normalises: `SimHealth.part_state`, which returns
  Unhurt/Hurt/BadlyHurt/Unusable. Compare states, never raw integrity.
- **`entity.killed` fires more than once for the same individual** — `health.gd` on a destroyed
  head, `infection.gd` on a put-down and again on turning. Counting events counts one death three
  times. De-duplicate by entity id.
- **The content validator will not catch a nested key.** It checks top-level types only. A wrong
  key inside an `armor` block sat in `item.wrap.cloth` for weeks giving zero arm protection, and
  only a purpose-built gate found it. **Reproduced deliberately on 2026-09-12** by the warmth
  slice's sabotage pass, in a brand-new block: a `warmth` map naming a body part that does not exist
  passed `npm run godot:validate` with `GODOT_CONTENT_OK`, and only `check_m2_warmth.gd` refused it.
  That is the whole argument for a purpose-built gate per nested shape, demonstrated rather than
  asserted.
- **But the frozen TypeScript oracle validates the same content with Ajv, and Ajv *does* recurse.**
  The two validators read one shared tree under `godot/content/`, and they disagree about depth:
  `npm run godot:validate` passes a nested violation that `npm test` rejects with a hard
  `ContentError`. So a content edit is not verified until **both** have run — a new enum value, a
  new nested key, anything under `content/schemas/`. This cost a red CI on a change where
  `godot:validate`, `godot:m2` and a purpose-built gate were all green: the map schema's
  `loot[].table` enum still listed two locations and the oracle refused the third.
- **`velocity` uses `dx`/`dy`; `position` uses `x`/`y`.** Writing `vel["x"] = 0.0` adds a key
  nothing reads and raises nothing — a pin that silently does not pin. `shambler.pin` and
  `treatment.pin` are the precedent for both the phase slot (`movement`, order −1) and the names.
- **`events.publish()` only queues; handlers run at `drain()`, at the *end* of `world.step()`.**
  So a fixture that publishes an event and then reads the result without stepping sees nothing
  ("2 hits, 0 wounds" cost a while), and an event published *into* a tick lands after that tick's
  systems have already run — a stagger arriving on the tick a channel completes is genuinely too
  late to stop it. Both are correct behaviour; write the test around them rather than tolerating a
  fudge factor inside the measurement.
- **GDScript lambdas capture primitives by value.** A closure assigning to an outer `int` or
  `bool` mutates its own copy, so an accumulator written inside an event handler reads back
  unchanged. Use an `Array` or `Dictionary` — reference types — for anything a handler accumulates.
  Same family as the packed-array trap above. This one keeps being paid for: it most recently made
  a jam gate report "never cleared" for a jam that had cleared exactly on schedule, because the
  `cleared_at` an event handler assigned to was a captured `int`. The failure mode is the worst
  kind — the gate goes red and blames the code under test.
- **Diagnose the balance harness, do not theorise at it.** Two consecutive guesses at why a flag
  flip wiped colonies (blood loss; then NPCs having no way to treat themselves) were both wrong,
  and each cost a full harness run to disprove. A throwaway `SceneTree` driver that boots
  `SimBoot.playable(seed, …)`, runs the same day count and prints `entity.killed` causes answers it
  in one run. Delete the driver afterwards.
- **A Dictionary keyed by an entity id does not survive a save.** Components round-trip through
  JSON, and JSON has no integer keys — a `{entity: record}` component comes back with String keys
  and the very first `seen[entity]` after a load misses silently, with no error and no wrong
  number, just a memory that is empty for reasons nothing reports. Store per-entity collections
  as an **Array of records** (`{"e": id, …}`) and scan; `sim/modules/sightings.gd` is the
  precedent. Same family as the packed-array and lambda-capture traps above: a value that is
  quietly not what you stored.
- **`entities.despawn` does not remove components, and `components.query` does not check alive.**
  Despawning a body leaves every one of its components in place, so anything counting a population
  by `query` still counts it. This made a director harness report "56 quiet nights in a row" --
  the culled bodies still filled `LIVE_CAP`, so every night after the fourth was refused rather
  than drawn. Remove the component you are counting, not just the entity.
- **`Array.erase()` and `Array.find()` on Dictionaries match by *value*, not by reference.**
  Measured in 4.7.1: with `a` and `b` two different Dictionaries holding identical content and
  `arr = [a, c, b]`, `arr.find(b)` returns **0** and `arr.erase(b)` removes **`a`**. So an array of
  records — a wound list, a sighting list, anything keyed by content rather than by id — cannot be
  edited by handing the element back. Find the index yourself on a field that is unique, or give
  the records an id. `wounds.gd`'s closing loop is safe only because two value-identical wounds
  necessarily close on the same tick; one added field away, it would not be.
- **A `has_method()` guard naming a method that does not exist is silently false forever.** It
  raises nothing, logs nothing, and quietly turns the whole branch into a no-op — `world.despawn`
  guarded its modifier cleanup on `has_method("removeScope")` against a method called
  `remove_scope`, so no despawned entity ever had its modifiers cleared and every save carried
  them. GDScript's `has_method` does **not** convert between snake_case and camelCase for script
  methods. Same family as `vel["x"]`: a name that looks right and reaches nothing. If you write
  one, grep for `func <name>(` before you trust it.
- **A `static var` is shared between the two worlds a gate boots.** docs/30 records this twice for
  components (`putDown`, `mourned`) and it was still live in the kernel: `SimBoot` kept "the last
  world that called `attach_kernel`" in a static, and the attention handlers wrote into *that*
  world's field rather than the publisher's. World A published magnitude 500 and A's own field read
  0.0000 while world B's read 500.0000 — on the spine, under every two-world assertion about noise
  or scent. Per-world state belongs on the world or in a closure over it; a closure over an object
  is safe, because the lambda-capture trap above is about primitives.
- **`main.gd` matches on the tile class twice, and a textual gate that reads the first arm judges
  the wrong one.** `_draw_district` has a `match tile:` that picks a *colour* and a second one that
  *draws*, each with its own `SimTileMap.Tile.Low:` arm. A gate slicing from the first label found
  four lines of colour arithmetic and reported that the draw loop never asks whether a vehicle
  covers the tile — red, and blaming code that was correct, which is the worst thing a gate can do.
  Enumerate every arm and pick the one calling the draw helper; `check_wrecks.gd`'s `_low_arms` is
  the precedent. Same family as proving a scanner on a fabricated body before trusting it: a
  textual assertion needs to be shown it is reading what it thinks it is.
  The 2026-10-03 water repair is the stronger boundary precedent: `check_water.gd` isolates
  `_draw_district`, its two tile matches and each Water arm by indentation, ignoring comments.
  A fixed 4,000-character window broke when valid wall code grew before the water fill; merely
  scanning farther would let another branch's fill hide a missing one. Its positive and negative
  scanner fixtures exercise both failure modes.
- **`sum()` of floats is not the same number on every CPython.** 3.12 sums floats with
  compensated (Neumaier) summation and 3.11 does not, so `sum((0.10, 0.45, 0.30))` is exactly
  `0.85` on one and `0.8500000000000001` on the other. Multiply either by an integer count and a
  result that lands on a **half** goes opposite ways, because `round()` breaks a true half *to
  even* and only one of the two inputs is a true half. This turned `sprites:check` — a byte
  comparison — red on CI over one pixel of a raider's boot, against art that was correct on the
  machine that drew it, and it cost two wrong hypotheses (reach near-ties; hash-order
  dependence, `PYTHONHASHSEED` swept) before the third was found by rendering under both
  interpreters side by side. Anything whose output is compared byte for byte must not decide a
  boundary with float arithmetic: use whole percents and integer division, as
  `palette.tone_ceiling` now does. These containers ship Python 3.11 and CI takes whatever the
  runner image has (3.12 when this was found) — the engine is pinned exactly and Pillow is
  pinned to 12.3.0, but the interpreter is not, so this class of divergence is invisible locally
  until CI says so. Pinning Python was considered and not taken: a generator that renders the
  same bytes on any interpreter is worth more than one that is only ever run on one.
- **A CRLF checkout turns textual gates red against correct code.** With `core.autocrlf true`
  (the Windows default) every working file ends its lines in a carriage return, and a gate that
  matches a whole source line exactly never finds it: on 2026-09-26 `godot:m2:dormant` failed on
  a clean `main` with "the isolator found no Seek arm". The repository's `.gitattributes` now pins
  `* text=auto eol=lf`, so a fresh clone is LF everywhere; an older checkout needs
  `git config core.autocrlf false` and a fresh checkout (`git rm -rq --cached . && git reset
  --hard`, with any work stashed first).
- **A clean git merge can leave a content object with the same key twice.** On 2026-09-26 one
  branch added `"appearance": {"sprite": …}` above an item's `equipSlot` and another added
  `"appearance": {"equipSprite": …}` below it; git saw two different hunks and merged both without
  a conflict. Every JSON reader here, Godot's and Ajv's alike, keeps the *last* duplicate without a
  word, so `godot:validate` and `npm test` were green while the item had silently lost its icon —
  only `godot:check:authored`'s READS lane noticed, because the art it declared was now read by
  nothing. After merging branches that both touched `godot/content/`, scan for duplicate keys
  (Python's `json.load(..., object_pairs_hook=...)` sees them) before trusting a green validator.
- **Throughput, measured:** the shipped world measured **34 ticks/second** headless (docs/22,
  "Remaining milestone evidence", 2026-10-03), so a game day (288,000 ticks) is about 2 h 21 min
  and a no-wipe ten-day campaign (2,772,000 ticks) about 22.6 hours. The ~1,085 ticks/second figure
  is the 64-tile district harness, not the world; do not use it for world estimates. Anything
  phrased as "run a few campaigns" is an overnight job — check the arithmetic before promising a
  grid.

## Working alongside other agents

More than one assistant works on this repository — Claude, ChatGPT, Astra, Sol, or a person —
sometimes at the same time. Nothing in this section is specific to any of them; where a tool's
own wrapper exists it is named as a wrapper around the plain command, never as the command.

- **Orient the same way regardless of who you are.** `CLAUDE.md` top to bottom (it is the
  project's rules, not a Claude-only file), then docs/23's
  [what's left](docs/23-roadmap.md#whats-left-in-milestone-2). The [routing table](#routing-table)
  below is the map of which files belong to which system and which gate judges them; `npm run
  check:routing` keeps it true.
- **Claim a piece by branch name and separate checkout.** `<agent>/<piece-slug>` — `astra/dev-menu-raiders`,
  `sol/per-gate-timing`, `claude/<anything>` — pushed early, so `git branch -r` is the live list
  of who is on what. There is deliberately **no claim ledger in any file**: a list of who holds
  what is status, this file carries none, and the checkbox ledger this project retired drifted
  four times for exactly that reason. A pushed branch cannot drift. Use `git worktree add -b
  <agent>/<piece-slug> <path> <base>` for each simultaneous worker and inspect `git worktree list`
  as well as remote branches. A local worktree does not imply its branch has been pushed.
- **Share tools, isolate runtime state.** `GODOT_BIN` may point to the same pinned executable
  across worktrees; dependencies may share an unchanged `node_modules`. Each checkout keeps its
  own `godot/.godot` imports. Give workers separate `XDG_DATA_HOME` and `XDG_CACHE_HOME` directories
  and separate displays so captures and save/load checks cannot overwrite another worker's
  state. Reserve quiet machine time for performance measurements. One coordinator owns shared
  roadmap/README/handoff edits and integrates disjoint code patches before final verification;
  worker evidence is a handoff to that coordinator, not a second status ledger.
- **Stay on disjoint files.** Pick a piece whose *files* line (each entry in the alpha-shell
  group names its files; other groups name their system, and the routing table names the system's
  files) does not overlap a branch already pushed. Some tracks are serial by construction — the
  alpha shell's pieces two to five all edit `godot/presentation/main.gd` and land one after
  another on one branch — and a second agent takes a piece beside them rather than one of them.
- **The gates are the same for everyone.** Before any commit: the gates for what you touched, as [Verifying a change](#verifying-a-change) lists them; the full `npm run godot:m2` chain runs in CI on every pull request; `npm test` as
  well for anything under `godot/content/`; `npm run check:routing` for anything touching
  `package.json` scripts, `scripts/run-godot.mjs`, a `godot/check_*.gd` or this table;
  `npm run sprites:check` after touching `tools/sprites/` or a PNG it generates. The engine
  install is `bash scripts/setup-web-session.sh` — `.claude/hooks/session-start.sh` is only the
  wrapper Claude Code on the web runs around it. Expected-noise notes are in
  [Headless verification](#headless-verification-no-display-needed).
- **The record discipline is the same for everyone.** A piece lands with its record: deleted from
  what's left and written into [the record, by
  system](docs/23-roadmap.md#the-record-by-system) in the same commit, named, gated, measured.
  Nothing under [Waiting on the owner](#waiting-on-the-owner) is decided by any agent; a piece that needs one of those
  decisions stops and asks.
- **Handing a piece over mid-flight.** Push the branch. Say in the last commit message whether
  the gate is red or green and which lane. Put the next step in the pull request body, not in a
  status file. The next agent starts from the branch and that body, and from nothing else.

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
| A decision named under [Waiting on the owner](#waiting-on-the-owner) as the owner's | that entry, and [docs/30](docs/30-decisions.md) | nowhere: stop and ask | -- | -- |
| A sim mechanic (a need, a wound, a job, the weather) | the system's spec in the table below, [docs/30](docs/30-decisions.md), and the traps in [CLAUDE.md](CLAUDE.md#traps-that-have-already-cost-someone-a-session) | `godot/sim/modules/`, `godot/sim/` | its `godot:m2:<name>` gate while iterating; `npm run godot:m2` before the commit | [the record, by system](docs/23-roadmap.md#the-record-by-system); a call taken goes in [docs/30](docs/30-decisions.md) |
| Content (an item, a zombie, a loot table, a weather kind) | [docs/20 Part 2](docs/20-ecs-and-content.md#part-2-content) and the schema under `godot/content/schemas/` | `godot/content/` | `npm run godot:validate` **and** `npm test` (only the oracle's Ajv recurses), plus the nested-shape gate for that block | the record |
| How a thing looks | [the Dungeon Settlers look](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03), `godot/assets/sprites/README.md` | `godot/presentation/`, `godot/assets/sprites/`, `tools/sprites/` | the `godot:check:<look>` gate for that layer; `npm run sprites:check` after touching `tools/sprites/` | the record, with a screenshot under `.hermes/plans/` for the owner to judge |
| Art somebody drew for us | [the brief](godot/assets/sprites/README.md), [art we did not generate](docs/30-decisions.md#art-we-did-not-generate-2026-09-09) | `godot/assets/sprites/authored.json` declares it; the PNG sits beside it | `npm run godot:check:authored` holds it to the published bounds and refuses art nothing reads; `npm run sprites:check` proves it is present at the canvas it declares | the record |
| Art from the outpost pack | [the pack's own README](godot/art/simplyzombies/README.md), [the outpost pack, adopted](docs/30-decisions.md#the-outpost-pack-adopted-2026-09-17) | `godot/assets/sprites/authored.json` declares it, with a `source` (a path, optional `crop`/`pad`) under `godot/art/simplyzombies/`, or as a member of a `source`-carrying `members` family | `npm run sprites:check` reproduces the committed PNG from its source and compares decoded pixels; `npm run godot:check:authored`'s MANIFEST, TIER and SOURCE lanes hold the declaration to shape and the READS lane to a real reader; the look gate of whichever family it lands in (`godot:check:<look>`) once that piece exists | the record |
| The screens' frames, glyphs, cursors and motion: the UI Field Kit | [the kit's own README](godot/art/simplyzombies-ui/README.md), [the UI Field Kit, live](docs/30-decisions.md#the-ui-field-kit-live-2026-09-25) | the approved kit under `godot/art/simplyzombies-ui/` (`godot/art/simplyzombies-ui/manifest.json` and `godot/art/simplyzombies-ui/styles/*.tres` are the spec, read as text; the game never loads a kit `.tres`), resolved by `godot/ui/kit.gd` and worn through `godot/ui/chrome.gd`'s helpers | `npm run godot:check:ui_skin` (`godot/check_ui_skin.gd`): KIT holds `Kit.NINE` to the manifest and the `.tres`, RESOLVE proves every consumed PNG loads headless, PANEL follows `Chrome.panel` to the kit, HELPERS refuses a chrome helper nothing calls, FONT holds every screen to `Chrome.font()` (the kit's VT323, `godot/art/simplyzombies-ui/fonts/VT323-Pixel.res`) and every text size to `Chrome.LADDER` | the record |
| What the screen says | [hardcore contract clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable), the vocabulary in [CONTEXT.md](CONTEXT.md) | `godot/ui/`, the read models `godot/sim/condition.gd`, `godot/sim/attention_read.gd`, `godot/sim/modules/chronicle.gd` and `SimSkills.web_map` in `godot/sim/modules/skills.gd`; the click that picks a colonist, `godot/presentation/pick.gd`, whose `Pick.pick_at` is also what is under a right-click; what you may do about it, `godot/sim/context.gd`'s `SimContext.verbs_at`, drawn by `godot/ui/context_menu.gd`; the keys that reach any of it, `godot/presentation/input_map.gd`; the run's four states and the three screens that are not the game, `godot/presentation/session.gd` and `godot/ui/shell.gd`; the afterimage and the dimmed remembered map, `godot/presentation/main.gd`'s `_draw_afterimages`/`_draw_district` and `godot/presentation/palette.gd`'s `remembered`; speech bubbles, `godot/sim/modules/speech.gd`'s `saying` component and `godot/presentation/main.gd`'s `_draw_bubbles`, drawn over a Focal body only (`_focal_drawn`) and never a name | `npm run godot:check:hud`, `npm run godot:check:inventory`, `npm run godot:ban:healthbar`, `npm run godot:check:respond`, `npm run godot:check:web_look`; and `npm run godot:check:play`, which boots `godot/presentation/main.tscn` and presses the keys; `npm run godot:check:memory` (`godot/check_memory_look.gd`) for the afterimage and the remembered map; `npm run godot:check:context` (`godot/check_context.gd`) for the menu's rows, their dispatch, walk-here's speed and the scene that opens and closes it; `npm run godot:check:speech` (`godot/check_speech.gd`) for a bubble's content, its triggers and the draw path that reads it | the record |
| A claim about balance | [the workflow's step 5](CLAUDE.md#the-workflow), [docs/22 on measuring](docs/22-performance.md#measuring) | a throwaway driver, deleted afterwards | `npm run godot:m2:balance` and `npm run godot:m2:harness`; the before/after numbers | the record, numbers included |
| The save format | [docs/19's save model](docs/19-architecture.md#save-model) | `godot/sim/kernel/serialize.gd` (`SAVE_VERSION`), `godot/sim/save.gd` | `npm run godot:m2:save` | the record |
| A gate, new or fixed | [a gate that cannot fail](CLAUDE.md#conventions), the dead-socket rule in [CLAUDE.md](CLAUDE.md#where-the-work-is) | `godot/check_*.gd`, a mode in `scripts/run-godot.mjs`, a script in `package.json`, a link in the `godot:m2` chain | `npm run check:routing` proves it is reachable | the record |
| The frozen TypeScript oracle | the top of this file | `src/`, `test/`, `bench/` | `npm run typecheck`, `npm run lint`, `npm run format:check`, `npm test`, `npm run bench` | nothing: it gains no features |
| CI, scripts, hooks, this table | [CLAUDE.md's verifying section](CLAUDE.md#verifying-a-change) | `.github/workflows/` (`.github/workflows/ci.yml` the gates, `.github/workflows/pages.yml` the web build, `.github/workflows/release.yml` the downloadable build, run by hand with a version or by a pushed `v` tag), `scripts/`, `.claude/` | `npm run check:routing`, `npm run check:timing`, `npm run format:check`; the engine pin in `scripts/run-godot.mjs` | the record's Kernel & tooling entry |
| Shipped runtime performance | [docs/22](docs/22-performance.md#shipped-godot-runtime-measurements) | `godot/bench/runtime_tick.gd`, `godot/bench/runtime_frame.gd`, `godot/bench/measured_main.gd`, `scripts/runtime-budget.mjs`, `scripts/run-godot.mjs` | `npm run check:runtime-budget` judges the production runner contract; `npm run godot:m2:tick` (`godot/check_m2_tick.gd`) holds each tick speed-up to the slow answer it replaced; `npm run godot:bench:runtime` and `npm run godot:bench:frame` measure actual timing on a quiet machine (frame needs a display). Existing overruns remain product debt; the real timing commands are not yet CI shipping gates. | docs/22's dated measurements and the record |
| Driving a pull request | `.claude/skills/steward/SKILL.md` | -- | whatever CI reports; `npm run godot:m2` before every push | the PR itself |
| Playing it, or a screenshot | [Running the game](#running-the-game-gui) below | `godot/presentation/main.tscn` | `npm run godot:run` | -- |

**By system** -- the spec, the code, and the gate that proves it. Where a row names several
gates, the first is the one to iterate on:

| System | Spec | Sim | Gate |
|---|---|---|---|
| Attention: noise, scent, light | [docs/03](docs/03-attention.md) | `godot/sim/field/attention.gd`, `godot/sim/modules/attention_emitter.gd`, `godot/sim/attention_read.gd` | `godot:m2:district` |
| Carried light, what burns it down and what feeds it | [docs/03](docs/03-attention.md), [docs/12](docs/12-resources.md) | `godot/sim/modules/light.gd`, `godot/sim/vision/light.gd`, `godot/content/items/lights.json` | `godot:m2:light_burn`, `godot:check:light` |
| Bait: noise you place, wind up and take back up | [docs/03](docs/03-attention.md#playing-the-field) | `godot/sim/modules/noise_device.gd`, `godot/sim/modules/fortify.gd`, `godot/content/items/noise.json` | `godot:m2:noise`, `godot:m2:fortify` |
| Needs | [docs/04](docs/04-survival-needs.md) | `godot/sim/modules/needs.gd` | `godot:m2:needs` |
| Clothing: warmth, wet and cooling | [docs/04](docs/04-survival-needs.md) | `godot/sim/modules/needs.gd`, `godot/content/items/clothing.json` | `godot:m2:warmth` |
| Comfort: something for your morale that is not a meal | [docs/04](docs/04-survival-needs.md) | `godot/sim/modules/needs.gd`, `godot/content/items/comfort.json` | `godot:m2:comfort` |
| Camping and utility gear: what you sleep on, what you wash with | [docs/04](docs/04-survival-needs.md), [docs/10](docs/10-items.md) | `godot/sim/modules/needs.gd` (`furnish_bed`, `_spend_soap`), `godot/content/items/camping.json` | `godot:m2:needs`, `godot:m2:gear` |
| Health, wounds, recovery | [docs/05](docs/05-health-injury.md) | `godot/sim/modules/health.gd`, `godot/sim/modules/wounds.gd`, `godot/sim/condition.gd` | `godot:m2:wounds`, `godot:m2:armor`, `godot:m2:recovery`, `godot:m2:splint`, `godot:ban:healthbar` |
| Infection and treatment | [docs/06](docs/06-infection.md) | `godot/sim/modules/infection.gd`, `godot/sim/modules/treatment.gd` | `godot:m2:treatment`, `godot:m2:medicine`, `godot:m2:lethality`, `godot:check:respond` |
| Survivors, recruits, the roster | [docs/07](docs/07-survivors.md) | `godot/sim/modules/survivors.gd`, `godot/sim/modules/recruits.gd`, `godot/sim/modules/roster.gd`, `godot/sim/modules/aptitudes.gd` | `godot:m2:roster`, `godot:m2:recruits`, `godot:m2:stats` |
| The skill web, Focus, jobs | [docs/08](docs/08-skill-web.md) | `godot/sim/modules/skills.gd`, `godot/sim/modules/jobs.gd` | `godot:m2:web`, `godot:m2:autonomy`, `godot:m2:jobs`, `godot:m2:upkeep` |
| Books that teach: an item that pays into the web | [docs/08](docs/08-skill-web.md) | `godot/sim/modules/skills.gd` (`teach`, `PRACTICE_POINTS`), `godot/sim/modules/needs.gd` (`read_book`), `godot/content/items/books.json` | `godot:m2:teach` |
| Combat, stances, aim | [docs/09](docs/09-combat.md), [docs/29](docs/29-movement-and-stances.md) | `godot/sim/modules/melee.gd`, `godot/sim/modules/ranged.gd`, `godot/sim/modules/npc_combat.gd`, `godot/sim/stances.gd`, `godot/sim/combat.gd` | `godot:m2:swipe`, `godot:m2:hands`, `godot:m2:ranged`, `godot:m2:ammo`, `godot:m2:aim`, `godot:m2:stance`, `godot:m2:npc`, `godot:m2:contact` |
| Items, inventory, attachments, gunsmithing, modification | [docs/10](docs/10-items.md), [docs/11](docs/11-crafting.md) | `godot/sim/modules/items.gd`, `godot/sim/modules/inventory.gd`, `godot/sim/inventory/grid.gd`, `godot/sim/modules/attachments.gd`, `godot/sim/modules/gunsmith.gd`, `godot/sim/modules/modification.gd`, `godot/sim/modules/containers.gd` | `godot:m2:attach`, `godot:m2:armor`, `godot:m2:ammo`, `godot:m2:bench`, `godot:m2:gear`, `godot:m2:filter`, `godot:check:mods`, `godot:check:inventory` |
| Loot and resources | [docs/12](docs/12-resources.md) | `godot/sim/loot.gd`, `godot/content/loot/` | `godot:check:loot` |
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
| The look | [docs/30](docs/30-decisions.md#the-dungeon-settlers-look-2026-09-03) | `godot/presentation/`, `tools/sprites/` | `godot:check:topdown`, `godot:check:appearance`, `godot:check:camera`, `godot:check:light`, `godot:check:road`, `godot:check:water`, `godot:check:wrecks`, `godot:check:roof`, `godot:check:trees`, `godot:check:worn`, `godot:check:authored`, `godot:check:fx`, `sprites:check` |
| The screen | [docs/01](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) | `godot/ui/` (its frames from the UI Field Kit, `godot/art/simplyzombies-ui/`, through `godot/ui/kit.gd`), `godot/presentation/main.gd`, `godot/presentation/input_map.gd` | `godot:check:ui_skin`, `godot:check:hud`, `godot:check:inventory`, `godot:check:respond`, `godot:check:web_look`, `godot:ban:healthbar`, `godot:check:play` (the one gate that executes the scene: `godot/check_play.gd`) |
| Balance and the campaign harness | [docs/22](docs/22-performance.md#measuring) | `godot/check_m2_balance.gd`, `godot/check_m2_harness.gd` | `godot:m2:balance`, `godot:m2:harness` |
| Performance | [docs/22](docs/22-performance.md) | `godot/bench/bench.gd`, `bench/` | `godot:bench`, `bench`, `bench:frame` |
| Content loading and validation | [docs/20](docs/20-ecs-and-content.md) | `godot/platform/`, `godot/content/schemas/` | `godot:validate`, `test` |
| The engine, CI and the desk | this file | `scripts/run-godot.mjs`, `.github/workflows/ci.yml`, `.claude/hooks/session-start.sh` | `check:routing`, `check:timing`, `godot:smoke`, `godot:r6:coverage` |

## Two different containers, two different starting states

Which one you are in changes the first thing you have to do.

For another managed cloud environment, inspect what is actually installed first. The 2026-10-03
Codex workspace had Godot 4.6.3 on `PATH`, so it still needed the pinned 4.7.1 install. Run
`bash scripts/setup-web-session.sh`; if it cannot write `/usr/local/bin`, set `GODOT_BIN` to the
absolute `.ci-tools/godot/Godot_v4.7.1-stable_linux.x86_64` path it prints. The runner does not
discover that checkout-local path automatically. Headless gates need no X server; play and
runtime captures need a working display. Check for Xvfb instead of assuming it is installed.

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

## MCP servers

`.mcp.json` declares the project-scoped MCP servers. Today that is **pixellab**
(`https://api.pixellab.ai/mcp`, reached through `npx mcp-remote@latest`), the pixel-art generation
service — a companion to `tools/sprites/`, not a replacement for it: generated art still has to be
committed and still has to pass `npm run sprites:check`.

Its token is **not** in the repo. The config interpolates `${PIXELLAB_API_KEY}`, so export it
before starting a session:

```bash
export PIXELLAB_API_KEY=<your-pixellab-token>
```

On Claude Code on the web, set it as an environment variable on the environment instead. If it is
unset the server fails to start and every other gate is unaffected — nothing in `npm run godot:m2`
or CI touches it. Never paste the literal token into `.mcp.json`; a committed key is a leaked key.

## Headless verification (no display needed)

Correctness gates run headless through `scripts/run-godot.mjs`; the runtime frame benchmark
needs a real display and renderer. The full chain is **`npm run godot:m2`**, which CI runs on every pull request and which chains every Milestone 2 gate (count them off
the script in `package.json`; every number written here has drifted); `npm run godot:r6` adds
parity, coverage, mutation and soak on top. `CLAUDE.md` names the gates worth knowing by name; the
authoritative list is the `godot:m2` script in `package.json`, and every gate has a
`godot:m2:<name>` script of its own for iterating.

Expected output that is **not** a failure:

- `ObjectDB ... leaked at exit` and `resources still in use` printed *after* a gate reports its
  `_OK` line. Engine shutdown noise. Check the `_OK` line and the exit code.
- `BENCH_OVER_BUDGET` from legacy `npm run godot:bench`, which still exits 0 and measures a
  synthetic dictionary. This exception does not apply to `godot:bench:runtime` or
  `godot:bench:frame`: they exit 1 on overruns or invalid evidence. See docs/22.

Long-running gates, so you can plan: `godot:m2:balance` took **15m29s** within the **47m16s**,
85-gate cloud run on 2026-10-03. Read the current run's `GATE_TIME_TABLE`; older measurements
describe different machines and workloads. `BALANCE_TILES=256 npm run godot:m2:balance:full` is
the opt-in shipped-size grid; the full-tier command otherwise still defaults to 64 tiles.
Measure throughput at its actual district size before estimating the grid; the old
nine-hour figure is not a safe estimate for the current 256-tile campaign. `BALANCE_DAYS` and
`BALANCE_SEEDS` can exercise the full-tier code path at smaller scope, but that is not the full
milestone proof.

## Running the game (GUI)

```bash
Xvfb :1 -screen 0 1920x1080x24 &     # skip on the Cursor VM, which already has :1
DISPLAY=:1 npm run godot:run          # or npm run godot:editor
```

- Rendering is the Mesa `llvmpipe` software renderer. `Could not set V-Sync mode`, the ALSA
  errors, `libpulse.so.0: cannot open shared object file` and `All audio drivers failed, falling
  back to the dummy driver` are all expected here and harmless.
- **It starts on day 1 in daylight** — `SimBoot` boots the clock at `Clock.DAY_BEGINS`, which is
  the first tick of the Day phase. (AGENTS.md used to say it starts at night and that you should
  wait for dawn. That was wrong, whenever it stopped being true.) A day is four hours at 1× (one hour is decided and not yet built: see docs/30), so
  press `=` twice for 10× and wait if you want to see dark.
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

Check it against `main` before treating it as environment breakage — but note that AGENTS.md previously listed three "known pre-existing" failures (`npm test` content-id and handoff-count
drift, and `format:check` flagging `.scratch/*.html`) that have all since been **fixed**. Verified
2026-08-25 on this container: `npm test` (45 files / 594 tests), `npm run typecheck`,
`npm run lint`, `npm run format:check`, `npm run godot:validate`, `npm run godot:test`,
`npm run godot:smoke` and the full `npm run godot:m2` chain all pass. A red one is a real
regression, most likely yours.

Long runs are not by themselves environment breakage: `npm run godot:m2` took **47m16s** for
85 gates in the 2026-10-03 cloud run. `godot:m2:balance` took 15m29s and `godot:m2:storm` 6m09s.
The emitted `GATE_TIME_TABLE` is the current timing evidence; the 26m45s/69-gate figure from
2026-09-12 is historical.
Run the single `godot:m2:<name>` gate you are iterating on and save the chain for the commit.

## Waiting on the owner

This is what only the owner decides. Never pick one of these up unilaterally. Items keep the
numbers they had in the retired `HANDOFF.md` (removed 2026-10-19, see docs/30), so a record that
says "HANDOFF item N" means item N here.

**Does hot reload swap content under a live world, or re-run the seed?** docs/30's "What hot reload
made structural" decides the second — four things capture content at spawn, equip and boot, so a
live swap leaves a world disagreeing with its own content — and `ContentReload.try_reload_world`
has done the first since R5. The 2026-09-13 reload fix kept the swap and added change detection,
by your call for that session; whether the swap stays, or the poll becomes validate-and-report
with a fresh boot to take an edit, is the decision. Nothing measured: it is a question of what
"reload" means, not of a number.

**Should a wash require soap?** docs/04 says washing needs water *and* soap; only the water half is
enforced. The camping slice shipped `hygiene` as banked charges a dirtying spends, and deliberately
did not make soap mandatory: that is a rebalance of a need every colonist has rather than an
addition, and a district that rolled no soap would have no way back from `filthy`, which
`sepsis_mul` reads. Deciding it means deciding what a soapless colony is supposed to do.

**Is the arc's difficulty increase the difficulty you want?** The re-baseline measured it precisely
(see docs/23): the content is innocent, the armour-acquisition rule costs two of four seeds their
colonists. The ten-day playtest is the right judge, and the lever is one static.

These are design calls. They have been measured, written up, and deliberately **not** decided.
(Sepsis came off this list on 2026-09-06 — **lethal untreated**, one of the owner's twelve
playable-state decisions in docs/30's "The playable state" entry; it lands as the lethality piece
in docs/23's playable-state group. Three long-standing items came off on 2026-09-01, decided by
the owner: colony shape
— a bigger colony, three at boot — and the `GRABS_ENABLED` flip, both landed together and closed
in docs/23's flag record; and the top-down art style, picked 2026-09-01 as **B, the rotating
player** and **superseded 2026-09-03 by the Dungeon Settlers look** — upright face-on pawns
that flip, nobody rotates, a warm dark-fantasy palette, walls with a lit cap and a south face,
roofs cut out where seen. docs/30's "The Dungeon Settlers look" entry records the twelve
decisions and what each earlier clause becomes; the work it forces is docs/23's Dungeon
Settlers arc, whose plan is `.hermes/plans/2026-09-03_dungeon-settlers-arc.md`. **Which of its
slices have landed is docs/23's record, not this section** -- a list here went stale twice in two
days, which is the same drift that took the equivalent list out of `CLAUDE.md` in `e2b94e7`.)

0f. **The camp's four first cuts** (2026-09-10). The seam slice landed home as relocatable
   (`godot:m2:camp`, nine lanes) and took four calls without asking, each one line if re-decided.
   **The key** — **decided 2026-09-16**: camp keeps **C**, shift+C to strike, and the stance
   ladder that had shared the letter (the audit found both arms firing on every press) moves onto
   Ctrl — docs/30's "The alpha shell" and docs/23's group of that name; the fix **landed** with
   the play gate on 2026-09-16 (`npm run godot:check:play`, the CAMP-KEY lane; docs/23's record).
   E-with-a-confirm was offered again and not taken. **The clock**: establishing costs fortify's
   ordinary 40-tick channel, because the labour cost is the deferred slice; it is currently
   cheaper than boarding a window and louder than one, which is half of the commitment Task 8
   asks for. **The footprint**: a camp's rect is
   radius 1 — the tile and everything touching it — which is what the director's quiet floor reads
   as "how loud is it at home"; the 32 m keep-off is `GATE_EXCLUSION`'s and is unchanged.
   **Abandonment reverts home to the annex** rather than to the previous camp, which is the simplest
   reading of "camps are temporary" and not the only one.

0e. **Whether a camp should be assignable, and whether an outpost should draw raiders**
   (2026-09-10). Two questions the seam slice deliberately did not answer. The later outpost
   slice extended where colonists will work, so an outpost is already useful. Assignment and
   raid targeting remain separate: nothing is assigned to a particular outpost, and
   `raiders._objective` walks to *home*, so a colony with three outposts is raided exactly like a
   colony with none. Both remaining design calls are named in docs/23's what's left; the owner
   chose work reach before danger.

0b. **Whether a region becomes the default boot** (2026-09-10). Everything is built and gated;
   `--region=region.main_area` reaches it and the default is still a single district. The reason it
   is not flipped is measured: the region runs at **1.48× real time** against a district's **4.15×**,
   which is above the 20 Hz clock but with far less room, and this container has measured the same
   district at 55 and 83 ticks/s on different days — so the margin is real and not comfortable, and
   rendering sits on top of it. Two dials if it needs one: `cellTiles` in
   `content/regions/main_area.json` (already 256 → 192 once, for exactly this reason), and how much
   of a region's population a region boots. **Worth playing before deciding**, which is the one
   thing a table cannot answer.

0c. **The remaining water mechanics** (first cuts 2026-09-09; colour decision superseded by
   the adopted pack). The ford's ×0.45 speed and ×1.8 noise remain first cuts. The old
   `#424f5c` tint/saturation question was settled by the owner's pack-grade decision: the ford
   now uses the pack's measured `#244e56`, proved by `godot:check:water`'s PACK lane. Do not
   reopen that colour question. **The ground is still a player-only mechanic.** `SimJobs._walk`
   resolves `move_speed` but NPC and zombie locomotion do not read `SimSurface`, so today a river
   slows the player and nobody else — half a mechanic in exactly the way noise-only ground was
   before the worldgen arc. Widening it moves NPC pathing balance and is its own measured slice
   (it is in the debt list); until then a ford is a decision only the player makes.

0b. **The idle breath** (2026-09-09). One pixel of pelvis at a quarter of the walk's rate,
   drawn in the fixture round and deliberately left out of the four answers the owner gave that
   day. Small, independent of every other piece, and named in docs/23's character-overhaul group
   rather than decided there.

0a. **The picture on select** (2026-09-08). The owner's answer on the pawn — *"when selecting
   the character, sprite art will appear. However, weapons, clothing, gear will be shown"* —
   names a picture the colony panel does not have. A portrait was refused with the Dungeon
   Settlers HUD on 2026-09-03; a larger picture of the selected pawn, kitted, in the panel is
   not a portrait. Which was meant is the call; docs/30's "Overcast or torchlight" and docs/23's
   what's left name it and do not decide it.

0. **The driving slice's first-cut calls**, each recorded in docs/30's "Driving" entry and each
   a small change if re-decided (the key is decided: the owner chose **E** on 2026-09-05 and it
   landed as a rung of fortify's ladder): four headings with the opposite
   key turning the car round; a moving car passing through bodies (nothing run over); a body at
   the wheel unreachable by shamblers; and the engine's numbers (sedan 24 under way, 4 idling,
   against a sprint's 6) — never measured against the director, because the 64-tile harness
   parks no car. **Added by the second goal of the same day:** the fuel numbers (a sedan's
   40 L, 12 000 m of range, 90 minutes of idle), the crash curve (55 at full speed on the
   square of the speed, a wreck after four runs at a wall), one in ten cars spawning wrecked,
   and the reading of "define the interact key" as *name E once* rather than *add a key for
   the hood* — docs/30's "Fuel and hitpoints" and "One interact key" clauses. **And by the
   third:** a gauge may show a machine's state and never a body's, which is how a dashboard
   with two needles sits beside a HUD that forbids gauges — docs/30's "The dashboard". **And by
   the fourth, the light vehicles:** the five classes and their numbers (bicycle 6.5 / e-bike
   7.5 / e-scooter 6.0 / skateboard 4.5 / kick scooter 4.0, noise 3..5 against a sprint's 6);
   the trade being exposure rather than a speed nerf (a rider is on the shambler's menu, a grab
   or a crash unseats them, the body takes no injury from it); a flat battery riding on at
   `unpowered`; legs costing no stamina; the dash layouts (handlebar, board) and their words;
   parking in the cars' pass on 4-wide spans only, weighted sedan 10 / van 3 / truck 1 /
   bicycle 4 / e-bike 2 / e-scooter 2 / kick scooter 1 / skateboard 1; the car shells as the
   bike paint; and `SAVE_VERSION` 19 — docs/30's "Light vehicles" clause, each a content edit
   or a line. **And by the gear catalogue (2026-09-06):** the pump shotgun (30 damage, 15 m, noise
   220) and the hunting rifle (34, 60 m, 200) against a pistol's 18 / 25 m / 180; the energy
   drink's loan (thirst 15, rest 20 now, 25 back three in-game hours later, chaining
   compounding rather than resetting); a jerry can as ten litres poured whole with the rest
   spilt; and the fuel bottle on a residential shelf until an industrial table exists — docs/30's
   "The gear catalogue", each a content number. **And by the survival session (2026-09-06):**
   the limp at ten percent a leg (owner-picked from three offers), well water's 0.15 illness
   chance a bottle and an instant boil at a lit fire, and NPCs drinking it raw only below soft
   thirst — docs/30's splint and well-water entries; and the rain's numbers (dry 12–36 h, wet
   2–6 h, the scent half-life halved, 200 / 12000 / 2400 ticks to wet, to dry, to dry by a fire) —
   docs/30's "Rain as sim state" and `content/weather/rain.json`, every one a content number.
   **And by the weather spine (2026-09-06):** every duration range and seasonal weight in the
   six kind entries (storm 1–3 h, cold snap and heat wave 1–3 days, snow 4–10 h; rain spring 5
   / summer 2 / autumn 3 / winter 1, and so on), the multipliers (storm scent ×0.35 and noise
   ×0.4, cold shamblers ×0.7 and snow ×0.9, settled snow ×0.8 on the living at half cover,
   heat thirst ×1.5 and spoilage and corpse scent ×2), the wind's daily drift at 0.6 (a
   storm's ×2 and a 240 lightning were the first cuts, and the integration re-measured both:
   docs/23's Weather record), five days a season from spring, and the hot seek walking to a
   roof — docs/30's
   "The sky has kinds", `content/weather/*.json` and `content/climate/temperate.json`. **And by
   its four slices:** body armour for the heat as torso coverage ≥ 0.4 (the jacket and the
   scrap vest, not the wrap) and heatstroke at two exposures in it; snow cover melting under a
   cold snap too (only `snow.json` lays any); lightning's sixteen tries at an open tile; the
   look's `SNOW_COVER_MAX` 0.55, the snow and lightning palette keys, and the flake's fall,
   lean and length — docs/30's per-slice bullets, and two screenshots to judge. **And by fog
   (2026-09-08):** `sightMul` 0.25, two to eight hours, weights spring 2 / summer 1 / autumn 4 /
   winter 1, scent half-life ×0.8, and the veil's alpha (`#c8cdd64d`) — `content/weather/fog.json`
   and one palette key, every one a content number; the season and the veil were the owner's
   calls this session, the numbers were offered and accepted as first cuts.
1. **Whether the wind should be free.** The weather spine's first cut drew each day's wind
   direction anywhere, and the balance harness's four-seed survival floor read that as a coin
   toss: every re-measurement wiped a different seed (docs/23's Weather record has the table).
   Shipped: a prevailing wind — the attention field's calibrated lean, which every district
   siting was measured under — that wanders within `windDriftDeg` (45°) of it, content in
   `climate/temperate.json`; 180° is the free wind back. docs/16's "a base that was safe
   becomes a base that's upwind of the whole district" and a per-seed survival floor pull
   against each other, and which gives is a design call, not a number.
2. **Whether a roof covers a known building's unseen walls too.** The wall-and-roof slice roofs
   the unseen *indoor* tiles of a building the survivor can see part of, as approved, so the
   unseen perimeter walls stay black and the roof reads as a mass inside a black ring
   (`slice5-front-64.png` in the plan's shots). Roofing every unseen tile of the footprint is
   one condition in `RoofLook.roof_tiles` and leaks nothing the footprint does not already;
   the look is arbitrated by screenshot, so it is the owner's.
3. **Whether the one-handed weapons need their own silhouettes at 32 px.** The worn slice found
   that the bat, machete, pipe and kitchen knife share a fist, an angle and a value range: they
   are distinguishable side by side and would not be at a glance mid-fight. The cheapest fix
   gives each primary weapon its own lean rather than sharing the bat's, which re-authors the
   shipped bat -- so it is recorded rather than taken in passing. The service pistol is the
   weakest single key for the same reason of size. Sharper since the second gear catalogue
   (2026-09-09): the weapon hand now holds fifteen melee bases and seven ranged, each new one
   given its own lean and length so none of them added to the pile, but the shipped four are
   still the shipped four and the two rifles are now a pair as well.
4. **Whether a forest stand should ever be as dense as the generator can make it.** In the
   densest one measured -- 44 Tree tiles in a 9x9 -- the player is very nearly invisible: trees
   are Opaque, so sight collapses to a few tiles, and the fade rule cannot help much because
   several trunks overlap the body at once (`slice9-stand-64.png`). That is the forest's
   character rather than a defect in the fade, but the density is content: the knobs are the
   terrain block's `standsMax`, `treesMax` and `treeSpread`.
5. **The two playable-state flips against the compressed tier's survival floor.** Two of the
   owner's own 2026-09-06 decisions are built, gated at both values and shipped at the old
   one: sight as a stimulus (`SimShambler.SIGHT_ENABLED`, decision 3 — since flipped, see the
   end of this item) and the strain table from night 3 (`SimDirector.GRACE_NIGHTS`, decision
   4, ships 7 rather than 2).
   Measured on the FAST tier with each on, a seed or two in four **wiped**, and
   `survivors_end >= 1` is the assertion CLAUDE.md records as considered and rejected for
   relaxing. The eyes and director records in docs/23 carry the diagnostics: a shambler that
   can see re-takes the colonist it just released, and three early packets finish a colony
   that cannot kill a shambler with a knife. The trade is between the owner's pacing and a
   floor measured on a 64-tile district sixteen times the shipped density with the player's
   body unattended. The options, each one line: (a) flip both after the torso slice lands and
   re-measure — the plan's order, and the record's recommendation; (b) let the compressed
   floor be "three seeds of four" and flip now; (c) run the FULL tier at 256 overnight
   (`BALANCE_FULL=1 BALANCE_TILES=256`) before deciding, ~8 hours at the measured rate.
   **Re-measured after the torso slice landed** (docs/23's Lethality record): with both flips
   on, three seeds hold at 3 of 3 and seed 20260805 still wipes (186 grabs, the crowd that saw
   the annex on night one never left), and the harness's over-cap invariant trips on two seeds
   (live 35 / 34 against a cap of 32 for a few hundred ticks — something places past the
   clamp once the table opens on night 3, to be found before the flip). **Sight alone,
   re-measured after the torso slice, holds the floor**: survivors 1 / 2 / 3 / 3 of 3, every
   band green — so sight ships on (decision 3 executed under the standing assertion, the
   commit after the torso slice's) and this item is now the table alone: flip `GRACE_NIGHTS`
   to 2 once the over-cap placement is found and seed 20260805 is re-read with sight already
   on. **The population arc found what it is, 2026-09-15, and did not act on it**, because the
   flip is yours: *nothing places past the clamp*. `SimDirector` refuses a spawn past
   `live_cap_for(world)` with reason `cap` and always has — but `infection.gd` and
   `SimRecruits._turn_with_kit` create a shambler from a body that dies infected with **no cap
   check at all**, so a colony that loses people to bites grows the horde past a budget the
   director is still honouring. Three separate slices hit it independently (the dormant, the
   camp and the settlers' day, each diagnosing it from the same signature: no identity, no
   allegiance, no corpse). It is in docs/23's defect list. Whether the turn should be clamped,
   or the cap should exclude turned bodies, is a balance call and therefore this item's.
6. **The playable-state slices' first-cut calls**, 2026-09-07, each inside one of the owner's
   twelve decisions, each recorded in docs/30's entry for its slice, and each a one-constant
   change if re-decided. The eyes: a zombie's sight reach is `range × sqrt(lightSense)` scaled
   by the light *at the target* (a lit survivor is seen from the dark), the shadowcast recast
   only after two tiles of movement, and a screamer's own groan raises its own noise threshold
   so it does not chase itself. The field: every zombie's base scent is **1**, chosen off
   docs/03's migration drift (6–7 m of centre-of-mass drift in an hour against 19 m at the
   plan's 8, which dominated the field). The doors: a door swings shut sixty ticks after its
   tile empties, breaks at stage four, and zombies never open one; the press: pressure
   `n × (1 + 0.5 × (n − 1))` against stage costs of 40 (board), 160 (door) and 90 (scrap).
   The band: raiders withdraw after 6,000 ticks at the objective with nobody in reach, or at
   once when below half their size. The lethality doses: frostbite at two exposures and death
   at three in the cold, heatstroke at three and death at four in the heat and only in armour,
   sepsis lethal at the third untreated dusk. The screen: a chronicle line stays two game
   hours, three at most; a click selects and never orders; a thin ring marks the selection.
   None of these was asked about, because the session was autonomous; each is the kind of
   number the ten-day playtest is for.

7. **Does a raid that can actually connect get to wipe the colony?** The melee-reach fix
   (docs/23's defect list, "A melee raider band cannot reach a body that does not move", built
   2026-09-16 on branch `claude/raider-reach-halt` and deliberately not landed) is a correctness
   fix, not a difficulty dial — a raider closes to its own weapon's reach instead of standing a
   metre short of everything — but `npm run godot:m2:balance`'s FAST tier measured what it
   costs: seed 404's `mixed` arm was already down to its last colonist before the fix, and after
   it that colonist dies too (`survivors_end` 1→0, `run_over` true). That fails `_assert_bands`'s
   standing `survivors_end >= 1`, the assertion CLAUDE.md says was considered and rejected to
   relax after the `GRABS_ENABLED` flip, so the fix cannot land green as the tree stands. Three
   ways out, none taken unilaterally: the shipped default is meant to absorb a raid this lethal
   (permanent loss is Milestone 2's own exit criterion) and the assertion changes; the assertion
   was unknowingly grading the reach bug rather than the difficulty and the FAST seed set or its
   floor changes; or a raider first-cut number (band size, `HALT_METRES` itself, the withdraw
   rule) moves and is re-measured. The branch carries its gate, its record and both measurement
   tables, and merges the moment one of the three is picked.

8. **The four asks' first-cut numbers** (2026-09-17, docs/30's "What the owner asked for after
   the shell"). The owner picked the shape of each piece; the numbers inside were taken in the
   session and are each one line if re-decided. **Bare hands** (`SimCombat.BARE_HANDS`): reach
   1.0 m, weight 0.6, damage 4 (three to a shambler's head, fifteen to its torso), stagger 6,
   speed 1.3, recovery 0.8, stamina 0.7, the ordinary connect noise. **The afterimage** fades
   over the sim's `FRESH_TICKS` (ten seconds) and the mark over `RECENT_TICKS` (a minute) — those
   are the prose's own bands, deliberately not new constants; if the picture should linger
   longer, the band moves and the HUD's "a moment ago" moves with it. **The mutters**
   (`SimSpeech.MUTTER_EVERY` 400 ticks, `MUTTER_P` 0.15): a colonist in a need band speaks about
   once every two minutes; a line's horizon is `SAY_TICKS` 60 (three seconds), a scream 40.

9. **The needs-assets report's remaining questions**
   (2026-09-25, docs/23's record, "Art — the outpost pack's needs-assets report"). The report the
   outpost-pack arc named for held weapons, utilities, decals and the extra UI icons is done; none
   of its remaining scope should be assumed approved. **Two questions were subsequently
   settled:** container pictures by loot table and held weapons on the pack's bodies were
   approved and shipped (docs/30's "The whole outpost pack", docs/23's corresponding records).
   Containers show closed/searched states; the supplies-visible state remains deferred because
   it would reveal contents at a distance.
   **Do the pack's utilities become new mechanics, or stay decoration?** A generator, a rain
   collector, a stove distinct from the campfire, and a spike trap a raider or a zombie can
   trigger are none of them systems the sim has today; building the art is the smaller half of
   giving any of them a socket, and whether that arc is worth opening at all is the owner's call.
   **Do fences and gates become their own tile kind?** Slice 5's own prose counts all thirteen of
   the pack's wall states, but a fence and a gate have no counterpart in `SimTileMap.Tile` today —
   only a wall, a window and a door do — so landing those five states in full means new sim
   content, not only a renderer change; whether that is worth doing now, or the slice ships its
   other eight and leaves fence and gate for a later piece, is the owner's to pick.
   **Is a footprint decal a certainty the player should have?** A trail rendered where an actor
   walked, unseen by the player, is the kind of information clause 4 refuses; whether the whole
   decal group (`fx-blood-pool-*`, `fx-bullet-hole-*`, `fx-scorch-mark`, `fx-wood-chips`,
   `fx-shell-pile`, `fx-footprint`) is worth a persisted-mark sim fact at all, and whether
   `fx-footprint` specifically would be scoped to ground the player's own sightline has already
   swept, are both open.

10. **The UI's type sizes** (2026-09-25, docs/23's record, "UI — one typeface"). The ladder is
   20 / 25 / 30 / 50 in VT323; the HUD cards, action bar, shell rows and panel titles took 30,
   which keeps their old capital height but is not pixel-exact (strokes land 1 and 2 px wide) —
   crisp 25 reads smaller, 50 reads loud. One line per file if re-decided; the FONT lane holds
   whatever is picked to the ladder.
