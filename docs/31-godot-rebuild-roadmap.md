# 31 — Godot Rebuild Roadmap

*Why this exists: simplyZOMBIES is moving from its TypeScript/Canvas reference implementation to
Godot. This plan says how to rebuild without reopening settled game design, losing deterministic
behavior, or mistaking a screen that looks similar for a verified replacement.*

---

## Relationship to the product roadmap

[The product roadmap](23-roadmap.md) remains the authority on **what game gets built and in what
order**. Milestones 0 and 1 stay complete because their behavior and exit criteria were proven; the
engine change does not erase that product evidence. Milestone 2 keeps its existing scope and resumes
at lethality after the rebuild cuts over.

This document owns the **transition sequence, parity gates, and cutover criteria**. It does not add
features to the product roadmap. The transition is complete (R0–R7); live product status lives in
[docs/23's milestone status sections](23-roadmap.md#where-milestone-2-stands).

The TypeScript build remains the playable reference and executable specification until the final
cutover gate passes. It is not discarded early, and Godot does not become authoritative merely
because it can draw the district.

## Gate R0: decisions and baseline — complete

The owner approved this baseline on 2026-08-13:

| Decision | Recommended answer | Why |
|---|---|---|
| Engine | **Godot 4.7.1**, pinned in local setup and CI | Current stable patch; one exact version keeps imports and exports reproducible |
| Language | **Typed GDScript** | Godot 4 C# still cannot export to the web; GDScript preserves the public browser build |
| First targets | **Web and Windows desktop** | Web keeps one-click playtesting; Windows provides the native shipping path |
| Renderer | **Compatibility renderer** for the rebuild baseline | It is the safest common denominator for desktop and WebGL |
| Repository | **Same repository; `godot/` is the Godot project root** | Keeps the oracle, fixtures, CI, and review history together without making Godot scan the Node workspace |
| Public preview | Current TypeScript game at `/`; Godot candidate at `/godot/` | Testers can compare the same commit without replacing the known-good build |
| Save compatibility | **No player-save migration before 1.0** | Existing policy already permits pre-1.0 breaks; test fixtures still cross engines |
| Feature policy | **Parity work only until cutover** | Prevents two implementations from moving underneath the comparison |

R0 is closed. A later change to one of these choices requires an explicit decision update because it
changes parity, delivery, or both; it does not quietly reopen the baseline during implementation.

## Rebuild contracts

These survive the engine change:

1. **The simulation owns the game.** Godot scenes render state and submit commands; they never become
   the authoritative location for health, inventory, combat, attention, or AI.
2. **Fixed ticks and named seeded RNG streams remain.** No engine frame delta, global RNG, physics
   callback order, wall clock, or scene-tree order may decide a simulation outcome.
3. **Simulation state stays plain and serializable.** Scalars, arrays, dictionaries, and stable IDs
   cross the boundary; Nodes, Resources, RIDs, Callables, and scene references do not.
4. **Commands are the input record.** Local input, replay input, and eventual network input enter the
   same ordered command queue.
5. **Content remains data.** The existing JSON and stable string IDs transfer before editor-native
   resources are considered. Schema validation remains a build gate.
6. **Information boundaries remain mechanical.** The condition view still receives prose and states,
   never hidden integrity or infection truth. An engine inspector is not permission to leak it into
   player UI.
7. **Performance remains a shipping gate.** Headless tick budgets and rendered-frame budgets must fail
   CI on regression. New engine overhead does not relax the product budgets by default.
8. **Parity is behavioral, not architectural.** Godot should use native presentation tools, but the
   same seed and command fixture must resolve to the same canonical simulation snapshot wherever the
   mechanic is intended to be unchanged.

## What transfers and what is rebuilt

| Area | Treatment |
|---|---|
| `content/` JSON and schemas | Move verbatim to `godot/content/` as the one canonical source; point the TypeScript oracle there during overlap |
| `src/sim/` | Reimplement cleanly in typed GDScript, module by module, against fixtures and behavior tests |
| Renderer and camera | Rebuild with Godot 2D nodes, draw APIs, viewports, and camera tools |
| Inventory, paperdoll, and HUD | Rebuild with Control nodes while preserving information and interaction contracts |
| Input, storage, timing, and content reload | Replace with Godot platform adapters |
| Tests | Port the contract, not the TypeScript syntax; retain paired cross-engine fixtures until cutover |
| Benchmarks | Recreate headless simulation scenarios and native/web rendered-frame scenarios |
| Existing art and generated models | Import or reproduce for parity first; visual redesign is separate work |

## Phase R1: walking skeleton

**Target: 2–3 focused days after R0.**

**Live status (2026-08-13): closed and verified.** The Godot project, canonical content move, paired TypeScript/Godot fixture, fixed-tick
simulation, main-scene smoke, Windows and web exports, local boot checks, and CI jobs exist. Verified on `main` `1ff2725` (run `31661872270` — `check` + `godot-exports` + `performance` green); artifact `godot-r1-windows-web` (`9166512125`, 49 MiB) boots locally (`R1_PARITY_OK`, `GODOT_PROJECT_SMOKE_OK`, `GODOT_WEB_EXPORT_SMOKE_OK`). No longer awaiting a first green run — the closing evidence already exists.

- Create `godot/project.godot`, pin the engine version, and establish `sim/`, `presentation/`,
  `platform/`, `ui/`, `content/`, and `test/` boundaries.
- Move the existing content tree verbatim under the project and update the TypeScript oracle to read
  that same tree; do not maintain a generated or checked-in duplicate.
- Add a headless test entry point and CI smoke job.
- Implement the fixed tick, ordered command queue, named RNG stream, entity identity, one component
  store, content loading, and canonical snapshot writer.
- Render one controllable entity on one tile through a presentation adapter.
- Export Windows and web smoke builds.

**Exit criterion:** the Milestone 0 seed-and-command fixture moves the same entity to the same
canonical state in TypeScript and Godot, and both Godot exports boot from CI artifacts.

## Phase R2: world and attention spine

**Target: 3–5 focused days.**

- Port grid, spatial indexing, surfaces, stance locomotion, stamina, and deterministic movement.
- Port the attention grid, bounded noise propagation, scent diffusion and decay, wind, and residue.
- Port time of day, light ranges, visibility, sight arcs, shadowcasting, and cache invalidation.
- Port shambler gradient following, individual bias, contact pursuit, and threat checks.
- Use debug geometry for presentation until behavior passes; native art is not on this phase's critical
  path.

**Exit criterion:** the current noise, scent, visibility, stance, pursuit, and Milestone 1 acceptance
fixtures match canonical outcomes across engines, and the headless quiet/crowded budgets are within
the existing thresholds or have a measured, approved replacement.

## Phase R3: danger, bodies, and belongings

**Target: 4–6 focused days.**

- Port committed melee, stagger, stamina costs, grabs, diminishing escape, and bite cadence.
- Port six-part bodies, located injury state, visible presentation, and private wound-time infection
  truth without adding the unbuilt disease progression game.
- Port item generation, affixes, condition effects, containers, grid placement, rotation, nesting,
  equipment slots, and inventory commands.
- Recreate save/load for the Godot state version and test round trips. Do not build a player-save
  migrator for the pre-1.0 TypeScript format.

**Exit criterion:** the present five-minute playable loop—move, change stance, make noise, attract a
zombie, swing, get grabbed, struggle, receive a located wound, loot, equip, save, and load—resolves
correctly and deterministically in a headless Godot run.

## Phase R4: native presentation

**Target: 4–7 focused days.**

- Rebuild the district presentation, isometric projection, camera, Y ordering, surface treatment,
  day/night wash, light, visibility masking, and last-known marks with Godot-native 2D tools.
- Recreate survivor and zombie poses, stance animation, movement phase, and developer overlays.
- Rebuild the grid inventory and the shared **Equipment / Injuries** paperdoll panel with Control
  nodes and the same non-numeric information boundary.
- Recreate keyboard, pointer, pause, speed, save/load, debug, and viewport-resize behavior.
- Establish screenshot fixtures at representative daylight, night, combat, inventory, equipment, and
  injury states. They judge legibility and layout, not pixel identity with Canvas.

**Exit criterion:** a player can follow the README quick start without developer help on
both Windows and web, and the approved screenshot deck has no blocking presentation differences.

## Phase R5: platform and delivery

**Target: 2–4 focused days.**

- Implement desktop and browser persistence adapters with atomic-or-equivalent save behavior.
- Restore JSON validation and development content reload without putting Resources into simulation
  state.
- Promote the R1 headless/export jobs into delivery gates; add Godot benchmark jobs and candidate
  packaging without duplicating their engine/template setup.
- During transition, publish the existing TypeScript build at `/` and the Godot candidate at
  `/godot/` from the same green `main` commit. Disable web threads unless the host is deliberately
  configured for the isolation headers they require.
- Keep automatic Pages deployment gated on the complete correctness and performance workflow.

**Exit criterion:** every green push to `main` publishes comparable TypeScript and Godot builds from
the exact passing commit, while a failed gate publishes neither candidate.

## Phase R6: parity and hardening

**Target: 5–10 focused days.**

- Build a parity ledger mapping every existing test file to an exact Godot test, a paired fixture, an
  engine-specific replacement, or an explicit obsolete rationale. “Not ported” is not a category.
- Run shared seeds and command logs through both engines and compare canonical snapshots after every
  relevant tick, not only at the end.
- Recreate module-isolation, save/load, content, determinism, and acceptance coverage.
- Recreate quiet, crowded, attention, and frame benchmark scenarios on headless, Windows, and web
  paths where their cost shapes differ.
- Mutation-test the new determinism, content, deployment, and performance gates at least once.
- Run long soak tests for memory growth, save corruption, input loss, pause/resume, and tab focus.

**Exit criterion:** no unexplained parity difference, no open severity-one or severity-two migration
defect, all required gates green twice consecutively from clean checkouts, and the Godot candidate
meets the same five-minute smoke script and Milestone 0/1 exit criteria as the reference.

## Phase R7: cutover

**Target: 2–3 focused days.**

- Make Godot the root playable build and the default local development path.
- Tag the final TypeScript oracle commit. Keep the tag, parity fixtures, and history; do not carry two
  production implementations afterward.
- Remove TypeScript runtime, Canvas renderer, Vite deployment, and obsolete dependencies only after
  the Godot replacement is live and rollback has been rehearsed.
- Rewrite [the architecture document](19-architecture.md), HANDOFF commands/file map, and CI/Pages
  documentation around the final Godot project rather than leaving transition prose as permanent
  architecture.
- Resume [Milestone 2](23-roadmap.md#milestone-2-the-vertical-slice) at **lethality**, exactly where
  product work paused.

**Exit criterion:** the public URL and Windows artifact run the Godot build from a green commit,
rollback to the tagged TypeScript build is documented and tested, and no active workflow depends on
the old runtime.

## Schedule and critical path

| Phase | Expected focused time | Cumulative |
|---|---:|---:|
| R0 — decisions and baseline | 1–2 days | 1–2 days |
| R1 — walking skeleton | 2–3 days | 3–5 days |
| R2 — world and attention | 3–5 days | 6–10 days |
| R3 — danger, bodies, belongings | 4–6 days | 10–16 days |
| R4 — native presentation | 4–7 days | 14–23 days |
| R5 — platform and delivery | 2–4 days | 16–27 days |
| R6 — parity and hardening | 5–10 days | 21–37 days |
| R7 — cutover | 2–3 days | **23–40 focused days** |

The best case is just under **five focused weeks**. Plan around **six weeks** and reserve **eight** for
design review latency, parity defects, and web-export surprises. R4 presentation work can overlap late
R2/R3 behavior work when contributors are available, but R6 cannot be shortened by parallel
appearance work: parity evidence is the cutover gate.

## Risks specific to the rebuild

| Risk | Control |
|---|---|
| Scene-tree behavior leaks into the simulation | Ban Nodes, physics callbacks, engine delta, and global RNG from authoritative state changes; test headlessly |
| Float or iteration-order differences break replay | Canonical ordering, explicit numeric rules, per-tick paired snapshots, and named fixture seeds |
| Web becomes a second-class target | Boot a web artifact in R1 and keep it in CI through cutover, rather than discovering export limits in R5 |
| A native rewrite quietly changes game balance | Freeze feature work and compare outcomes, not merely APIs or screenshots |
| Tests are declared “too TypeScript-specific” and dropped | Require every existing test file to appear in the parity ledger with a disposition |
| Godot convenience types enter saves | Validate serialized snapshots and forbid Resources, Nodes, RIDs, and Callables in state |
| The transition lasts indefinitely | One active implementation after R7; no feature development in both engines |

## Rebuild cut list

- **No new Milestone 2 mechanics during parity work.** Lethality resumes after R7.
- **No art-direction overhaul.** Import/reproduce current intent first; new assets are a separate
  product decision after parity.
- **No third-party ECS, navigation behavior, or physics authority.** Godot is the host and
  presentation layer; the game's deterministic rules remain bespoke.
- **No C#, GDExtension, or native plugin in the baseline.** Reconsider only against a measured blocker
  after web parity is proven.
- **No TypeScript player-save migration before 1.0.** Cross-engine fixtures are test infrastructure,
  not a promise to preserve development saves.
- **No z-levels, streaming world, vehicles, multiplayer, attributes, or expanded content as “port
  cleanup.”** Their place in the product roadmap does not change.
- **No permanent dual-runtime architecture.** The TypeScript version is an oracle and rollback point,
  not a second shipping implementation.

---

**Previous:** [30 — Decision Records](30-decisions.md) ·
[Doc index](../README.md#documentation)
