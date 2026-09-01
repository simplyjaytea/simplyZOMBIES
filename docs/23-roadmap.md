# 23 — Roadmap

*Why this exists: the other design documents describe a game far larger than a first build. This one
says what gets made, in what order, what proves each stage, and what may still be wrong.*

---

## How to read this document

This roadmap owns **intended scope, order, exit criteria, risks, and design questions**, and — since
the retirement of the per-item checkbox `HANDOFF.md` — the per-milestone status sections below, which say what
has landed and what remains. What is *built* is proven by the Godot gate suite (`CLAUDE.md` lists the
gates), not by any checkbox. [README.md](../README.md) is user-facing and stays at feature level.

The engine rebuild does not replace or renumber these product milestones. Its separate
[Godot rebuild roadmap](31-godot-rebuild-roadmap.md) reproduces the completed behavior behind parity
gates, then returns here to resume Milestone 2 at the same point and in the same order.

The design set is a **backlog, not a promise**. Written down, the vision is several years of work: a
hardcore survival colony sim with tower defense, procedural survivors, affixed items, a classless
skill web, located injury, uncertain infection, weather, factions, vehicles, and world decay. The
response is not to pretend all of that belongs in the first release. It is to prove the thesis with a
vertical slice, then expand only what earns its place.

## The thesis to prove

> **A player managing the [attention field](03-attention.md) — trading comfort for safety, day after
> day, with people they have invested in and can permanently lose — is doing something fun.**

Noise response alone is the Milestone 1 mechanical premise. The full thesis needs a colony, time,
investment, loss, and succession, which is why it cannot be answered before Milestone 2.

## Milestone 0: Foundations (complete)

The [architecture](19-architecture.md) work with no game on top:

- Fixed-timestep tick loop, seeded RNG, and plain serializable state
- Minimal ECS with ordered systems ([ECS and content](20-ecs-and-content.md))
- Event bus and modifier pipeline ([extensibility](21-extensibility.md))
- Validated content registry
- Canvas renderer reading simulation state; input through a command queue
- Versioned save/load
- CI gates for determinism, module isolation, simulation purity, and performance

**Exit criterion:** an entity moves around a tile map deterministically, and the same seed plus input
log reproduces byte-identical state.

**Result:** passed and closed. Implementation evidence lives in the CI gate suite and, for the
retired TypeScript oracle, at tag `ts-oracle-final`.

## Milestone 1: The spine (complete)

The [attention model](03-attention.md) and something that reacts to it:

- Noise propagation and scent diffusion on the coarse attention grid
- Light as a separate, wall-precise shadowcast rather than a coarse field channel
- [Line of sight](28-visibility-and-sightlines.md) shared by light, rendering, and future client views
- Shamblers following gradients with individual bias, contact pursuit, grabs, and bites
- One directly controlled survivor using the five-rung [stance ladder](29-movement-and-stances.md)
- Committed melee swings, stagger, stamina, grabs, and breaking free
- Day/night and findable light sources
- Developer overlays cycling noise, scent, and sight

The shipped grab uses fixed escape power. When attributes arrive, [Strength](#planned-survivor-attributes)
will improve that chance; every additional grabber continues to reduce it.

**Exit criterion:** make noise and zombies converge immediately. Stop emitting noise and the summoned
response disperses, while scent makes stillness only temporarily safe.

**Result:** passed and closed. Scent also gave field memory an observable result the original design
did not predict: a disturbed horde can migrate downwind by following its own residue.

## Milestone 2: The vertical slice

Everything needed to test the thesis, and nothing else. Several foundations were pulled forward
during Milestone 1 — grid inventory, item generation, located body parts and condition presentation,
the melee/grab loop, and the private infection-transmission seam. They are inputs to this slice, not
work to rebuild.

| System | Slice scope |
|---|---|
| **Map** | One hand-authored small district with a defensible building |
| **Survivors** | Generator with a small name, trait, and backstory pool; about three naturally recruitable survivors |
| **Work** | Haul, Construct, Cook, and Doctor, with NPC priority selection |
| **Needs** | Hunger, thirst, rest, and mood. Temperature and hygiene deferred |
| **Health** | Complete slice injury loop: located injuries, continuous conditions, treatment, diagnosis, and permanent consequences |
| **Infection** | Transmission, uncertainty, symptoms, responses, and turning. The Constitution hook uses a neutral baseline until attributes ship |
| **Zombies** | Shamblers only |
| **Combat** | Shipped melee plus complete ranged combat, with the [parity contract](09-combat.md) live |
| **Items** | Keep the shipped item/grid foundation; add ranged bases, armor, attachment behavior, active wear, and repair |
| **Inventory** | World-container search, colony storage, and loadout automation on the shipped grid |
| **Crafting** | Duct Tape and Scrap Kit modification consumables |
| **Web** | A shallow six-region web, about 12–18 nodes, so Fighter, Worker, Medic, and Scout all have valid auto-allocation paths |
| **Building** | Walls, gate, barricades, one trap, and one bait emitter |
| **Decay** | Food spoilage only |
| **Director** | Slice director: pressure/strain, grace period, lulls, recruitment and night events, and minimum siege cadence |
| **Death** | Permadeath, corpses, and [succession](01-hardcore-contract.md#succession-what-happens-when-you-die) |
| **Resources** | About 15 resource types and three location loot tables |
| **UI** | Priority grid, shallow web, diagnosis/condition prose, and legible non-numeric feedback |
| **Balance** | Minimal headless campaign harness for run-length, death, siege, and combat-parity distributions |

The natural slice still targets about three recruits. Risk 1 uses a **seeded six-survivor colony
scenario** so automation can be tested without bloating recruitment content merely to reach the test
population.

The director is intentionally not the full storyteller system. “Nothing Personal” is an internal
balance baseline, not a player-facing preset. Full storyteller presets remain Milestone 4.

**Explicitly not in the slice:** survivor attributes, relationships, weather, factions, full world
decay, mutation waves, temperature, hygiene, unique survivors, named items, the full web, most zombie
types, vehicles, multiplayer, and the escape endgame.

### Build order

1. **Lethality:** finish injury, infection, treatment, turning, and armor interaction on the shipped
   bite/transmission seam.
2. **People and economy:** survivor generation, needs, jobs, the authored district, resources,
   container search, and spoilage.
3. **Ranged parity:** ranged actions, aiming/sway, ammunition, ranged items, and NPC combat.
4. **Automation and progression:** shallow six-region web, Focus auto-allocation, and loadout upkeep.
   This comes after the work and combat sources that earn its points.
5. **Defense and pacing:** building, then the slice director that measures and pressures those systems.
6. **Continuity:** recruitment, death, corpses, grief-independent loss consequences, and succession.
7. **Proof:** automated distribution runs first, then the human ten-day playtest.

**Exit criterion:** survive ten in-game days, become invested in a survivor, lose them permanently,
continue through succession, and still want another run afterward. The slice must be playable end to
end without a developer explaining it.

### Where Milestone 2 stands

This section took over `HANDOFF.md`'s live-status role when the per-item checkbox ledger of that
name was retired (2026-08). A short `HANDOFF.md` came back a commit later and is still in the tree,
but it is a cold-start pointer and an owner-decision list, **not** a status ledger: this section is
the authority, and where the two ever disagree this one is right. Keep it
current **in the same commit** as the work it describes. Every claim of "landed" below is proven by a
named gate (`npm run godot:m2` chains them all); the full done-item history with per-item evidence
lives in git — `git log --diff-filter=D -- HANDOFF.md` finds the retired ledger, and the revision
before its deletion holds the itemised backlog. The section runs in this order: [what's left](#whats-left-in-milestone-2), named
so the name alone says what the work is; the landed summary; the flag record; and
[the record, by system](#the-record-by-system) — everything landed, with its evidence.

#### What's left in Milestone 2

Everything still open, in one place, as small named pieces. The rule for a name here: **the name
alone should say what the work is** — no codenames, no lever letters, no rule numbers. Each piece is
sized to land in one session with its own gate (or an extension of a named one) unless it says
otherwise. This list carries no evidence and no history; when a piece lands, delete it here and
write its record — named, gated, measured — into [the record, by system](#the-record-by-system), in
the same commit. That is the whole discipline: one list of what remains, one record of what landed,
and nothing that has to be ticked.

**Waiting on the owner — decisions, not code.** Each is measured and written up; none may be
decided unilaterally. `HANDOFF.md` carries the same short list for whoever picks the project up.

1. **Can sepsis kill?** Today it is debilitating and permanent-until-treated, deliberately not a
   death path. The `GRABS_ENABLED` flip has landed (the flag record below closes with it), which
   makes sepsis reachable in ordinary play and makes this decision live rather than hypothetical.
   Making it lethal is a balance decision that needs a measurement attached.
2. **Pick the top-down art style.** `.hermes/plans/2026-08-19_topdown-art-brainstorm.md` holds the
   three candidate directions and the overhead re-authoring of the zombie visual language; its
   screenshot-fixture method is the way to compare them. The five shipped sprites need regenerating
   only if the pick isn't A (the shipped baseline): B needs rotation support (`draw_set_transform`
   around the blit — the centre anchor was chosen so that stays a contained change), and C needs a
   rig-sheet pass before more sprites exist. The two art pieces below queue behind this pick.

**World generation — the rich district.** The sandbox arc, authorized by the owner (2026-08-25):
docs/24's "authored templates, procedurally assembled" built for real, still in one district.
**All nine pieces have landed** — the template stamp, the anchors, the generator, the loot pass,
the sited annex, the seeded boot, the wall rule, the ground, the raiders; the record has each.
The district is generated from data now — 51 buildings on the canonical seed, loot and colony
sited per seed, any seed bootable from the command line, a raid band drawable from day 8 — and
the gate boots run on a real miniature district instead of an empty map. Region,
roads-between-districts and streaming stay Milestone 3B; the road seam ships as data the street
pass actually reaches (edge connection points). The owner's scope decisions are recorded in
[docs/30](30-decisions.md#what-the-worldgen-arc-decided). Nothing in this group remains open;
what the arc left behind is named in the debt list (the ground is player-only today, rubble
unplaced) rather than here.

**People — the survivor pipeline:**

- **The six-survivor automation checkpoint.** Risk 1's seeded colony, every NPC on Focus
  automation — the micromanagement-cliff measurement. The colony-shape question it was once
  queued behind is decided (the flag record: a bigger colony, three at boot), so what it measures
  now is the cliff itself.

**Medicine — the back half of treatment:**

- **Supply quality tiers.** The sepsis roll already prices sterile < cloth < dirty dressings; what
  is open is quality as an authored property of medical supplies generally.
- **Diagnosis text that scales with Medicine skill.** A good medic reads a wound better; a novice
  reads it vaguely. Prose only — no numbers arrive with skill. This is also where the condition
  view learns to say a wound has been cleaned or sutured: the ladder writes both, and neither is
  in `sim/condition.gd` yet, deliberately — a field with one possible value is a gate that cannot
  fail, which is the lesson the `bandage` field's arrival taught.
- **The splint, and fracture immobilisation.** `closeKind` declares `splint` and
  `SimTreatment.CLOSE_KINDS` accepts only `suture`, so a kit declaring one is refused rather than
  silently sutured with. `cleanTier`'s `alcohol` grade is priced in `SEPSIS_CLEAN_MUL` and carried
  by no content entry — both are named here rather than left to look wired.
- **Permanent conditions that keep a survivor in play.** A limp, a blind eye, a scar — loss that
  does not remove the person, docs/05's permanent-consequences row.

**Gear — finishing what items started:**

- **The repair economy: station, materials, Craft.** `SimItems.repair_item` already lowers the
  ceiling on every repair; what is open is the cost of invoking it.
- **Attachments wear out.** docs/10's "suppressors wear out fast" — attachments have no condition
  of their own yet.
- **Attachments meet the attention field.** An optic useless in the dark; a weapon light that is a
  real light source and therefore a real emitter.
- **An attachment-fitting screen.** `item.attach` / `item.detach` work and have no surface.
- **Bed quality as an authored property.** `SimNeeds.sleep_quality` reads a bed today as binary —
  in one or not — where docs/04's own list implies a cot beats the ground by less than a proper
  bed beats a cot; content would carry the difference once more than one kind of bed exists.

**Attention:**

- **Carried weight loudens footsteps.** Weight stays simulated and never printed; footstep noise
  is how it is supposed to read.

**Art & renderer — queued behind the style pick, needed whichever way it goes:**

- **Screamer and bloater sprites.** Both still render as tinted shapes.
- **Prop art on the 64×64 canvas.** The props are drawn now (see the record) but as content-tinted
  footprint shapes: a container, a bed, a campfire and the well each take an `appearance.sprite`
  key today and none of them has a file behind it.

**UI:**

- **Condition and stamina readouts in the world, not a corner.** The diegetic half of the prose
  contract — the words move onto the body and the scene.
- **The skill web screen.** **Presentation only, now.** The mechanism underneath it landed with
  [Focus and the Manual learn line](#the-record-by-system) — the `web.buy` command, the
  `SimSkills.web_view` read model and the choice of who manages a survivor, all gated by
  `godot:m2:autonomy`. What remains is a *screen*: the web drawn as a web, with regions and
  adjacency and the shape of a survivor's history visible in it, rather than the one prose line
  the work grid can fit. Nothing in the sim is waiting on it.
- **Prose that names its modifier sources.** "Slow because the leg is splinted", generated from
  the modifier pipeline rather than hand-authored per case.

**Proof — what closes the milestone, in this order:**

- **Distribution assertions.** Quiet nights, sieges, deaths and run lengths asserted as
  distributions in the balance harness, not as single-seed anecdotes.
- **The melee-vs-ranged parity measurement.** Risk 6's checkpoint: melee-only against ranged-only
  colony outcome distributions, before human tuning argues from anecdotes.
- **The full balance grid.** `BALANCE_FULL=1`, ~9 h — an overnight job at measured throughput, not
  a "quick run".
- **The human ten-day playtest.** The exit criterion itself, run by a person.

**Debt — not features, named so it stops being folklore:**

- **The shallow content validator.** `npm run godot:validate` does not recurse, so every nested
  content shape needs its own purpose-built gate, and the frozen oracle's Ajv disagrees with it
  about depth — a content edit is unverified until both have run. `CLAUDE.md`'s traps section
  carries what this has already cost.
- ~~**Bus-only counters in the balance tier.**~~ **Resolved with the flip:** the `grab.started` /
  `grab.broken` counters became assertions — `_assert_grabs_reach_the_campaign` (the floor: at
  least one fast seed records a grab and a named `grab.broken` cause, which is also the flip's
  dead-socket proof) and `_the_grab_counters_can_see_a_grab` (the true negative: one fabricated
  started/broken pair through a real drain must move each counter by exactly one), both in
  `check_m2_balance.gd`'s fast tier.
- **Rubble is never placed.** `SURFACE_RUBBLE` is written by no generator pass and no building
  template — counted over the shipped 256 district: 0 tiles on both measured seeds — so docs/24's
  ×0.7/×1.7 rubble row, its palette colour and its tint are reachable only by hand. Undergrowth
  places at ~0.7% of tiles, sparse for something meant to be a route choice; both are dressing
  authoring, found by the ground slice.
- **NPC and zombie locomotion ignore the ground.** `SimSurface.speed_on` is wired on the
  command-driven path only, which `controlled` entities alone take — `jobs.gd`'s velocity write
  and the nine in `shambler.gd` carry no surface term, so the ground is a player-only mechanic
  today (which is also the mechanical reason the campaign harness could not move when it landed).
  Widening it moves NPC pathing balance, so it wants its own before/after. `Palette.COLOUR_HEX`
  (14 entries, zero readers) and `sim/map/surface.gd`'s unused `SimTileMapRes` preload were
  found in the same sweep — dead sockets of the named shape, one line each when touched next.
- **The Godot build has no enforced budget.** docs/00 pillar 6 says a feature that breaks budget
  does not ship, and every budget CI actually enforces measures the **frozen oracle**: `npm run bench`
  is vitest over `src/`, and `npm run bench:frame` spawns **vite** and drives the TypeScript/Canvas
  build in a browser. `npm run godot:bench` benchmarks a synthetic `{components, field, spatial}`
  dictionary rather than a `SimWorld`, and prints `BENCH_OVER_BUDGET` while exiting 0. So the only
  thing that ships is the only thing nothing measures — which is how a 12.58 ms per-frame
  serialisation lived in `_update_hud` (see the record's **Kernel & review sweep**).

**Defects found by the review sweep, still open.** Every one was read in the shipped code and the
measured ones say what was measured; none is a design question. They are not fixed here because
each wants its own gate and several want a balance re-measurement, which is a slice apiece rather
than a line apiece. Worst first. What the same sweep *did* fix is in
[the record](#the-record-by-system) under **Kernel & review sweep**.

- **Crouching never lowers your eye.** `SimStances.eye_of` is called by nothing and no code ever
  writes `observer["eye"]`, so `Opacity.Low` / `Tile.Low` cover blocks nobody. The frozen oracle
  has this (`stance.eyes`); the port dropped it.
- **A worn-out weapon is lost, not dropped.** `SimItems.apply_wear` unequips at zero condition and
  nothing gives the item a home — no `stored`, no `position`, no slot. `item.detach` has the same
  shape: `SimAttachments.detach` deliberately leaves the attachment homeless and the command does
  nothing about it.
- **Cook has no claim on its ingredient.** Nothing marks the raw item as spoken for and the job
  does not re-check at completion, so two cooks turn one raw item into two meals — or into one meal
  out of nothing. `Bury` has the same hole: `_do_bury` reads "the corpse has no position" as "I am
  carrying it".
- **A lull's opening edge is dead code.** `_begin_lull` guards its only write to `lullFromTick`
  with `world.tick < lullFromTick`, and the field starts at 0 and is never written, so the
  condition can never be true and the window is effectively `[0, lullUntilTick)`. `world.gd`'s
  save comment already treats this field as load-bearing.
- **An unreachable destination costs a full A\* every tick, forever.** `SimPath.find` scans the
  open set linearly with a 4096-pop guard and the caller cannot tell "guard exhausted" from "no
  path", so it re-runs the worst case on the next tick and every tick after.
- **The content tree is re-parsed six times a second while you play.**
  `main.gd::_poll_content_reload` runs every 0.5 s in a debug build and calls
  `ContentValidator.validate_tree` and then `ContentReload.try_reload_world`, which validates again
  and loads again — three full walks of all 27 JSON files, twice a second, with no change
  detection. `ContentReload.poll_content_dir`, written to be that change detection, returns
  `not paths.is_empty()` (always true) and is called by nothing.
- **`write_file_atomic` is not atomic.** `platform/storage.gd` deletes the existing save before
  renaming the temp file over it, which is the window the name, the comment and the module header
  all promise there isn't.
- **A missing schema silently disables validation for a whole content type.**
  `content_validator.gd` treats it as a `push_warning` and a `continue`, and
  `npm run godot:validate` still reports success.
- **`recorded` grows without bound.** `SimCommandQueue.recorded` deep-copies every command ever
  pushed and is read only by `parity_snapshot`. In a played session that is every movement command
  of every tick, kept for the life of the run.
- **`deep_pockets` is computed in the wrong scope.** The suffix adds `carry_capacity` scoped to the
  *item*; encumbrance resolves `carry_capacity` scoped to the *actor*. Rolled, named, saved, read
  by nothing.
- **`_weapon_for_attacker` wears the wrong weapon.** It returns the first of `primary`/`secondary`
  carrying any weapon profile, so a survivor with a knife in `primary` and a pistol in `secondary`
  wears the knife on every gunshot and the pistol never wears at all.
- **`merge_into_stack` reads a failure as a success.** `merge_stacks` returns 0 both for "fully
  merged" and for all five of its give-up paths, so `stow` can report an item stored that it did
  not store.
- **Sightings are recorded on geometry, not on sight.** `sightings.gd::_observe_one` uses
  `line_of_sight` rather than `detail`, so a survivor remembers — and the HUD reports — bodies
  standing in the 170-degree arc behind them. The information-stays-scarce ban is the reason to
  care.
- **Four of the five infection verbs, and six other commands, have no way in.** `item.modify`,
  `item.attach`, `item.detach`, `item.split`, `item.pickUp` and `container.search` are live command
  handlers that nothing — no key, no button, no NPC decision — ever pushes, and the
  attachment-fitting screen above is part of the same hole. `infection.respond` **now has a
  producer** for exactly one of its verbs: the antibiotics word on the body screen
  (`godot:check:respond`, see the record). What is still unreachable, and why each is left that
  way rather than tidied up beside it:
  - **`quarantine`** is a mechanical no-op — it writes a `quarantined` record and publishes an
    event, and nothing reads either. It is deliberately **not** surfaced: a button that does
    nothing is worse than a verb that cannot be reached, because only one of the two is a lie.
    Giving it an effect is the piece of work, and the surface follows it.
  - **`cauterize` and `amputate`** are aimed at a body *part*, and **`put_down`** at a *person*.
    Neither selection exists on any screen — the body screen names one survivor and no part, and
    `treat.context` deliberately picks the wound for you. A patient-and-part selection surface is
    what all three are waiting on, and it is one piece of work for the three of them.
- **More gates that cannot fail.** Four were fixed in the sweep; these are what a read of all
  thirty-odd check scripts turned up and did **not** fix. Assume there are others and go at the
  rest with the same question — *what change would turn this red?*
  - `check_appearance.gd`'s `_all_blocks()` skips every content file whose top level is an Array,
    so **all item** appearance blocks are invisible to the gate. It also calls the uncached
    `ContentLoader.load_tree()` once per content path *inside* its own loop and is itself re-called
    per iteration by two callers, turning a 27-file walk into thousands of full directory scans.
  - `check_r6_mutation.gd`'s "validator not vacuous" lane asserts that a `RegEx` **the gate itself
    just compiled** does not match `"BAD_ID"` — the subject is the gate's own local object, not
    `ContentValidator`, so no change to the validator can turn it red. Its `_mutate_perf` lane
    claims to prove the bench gate is not always PASS and never invokes the bench with a small
    budget; it asserts that 100 iterations of `field.decay()` take more than 0.0001 ms/tick.
  - `check_r6_coverage.gd`'s `_isolation` says it boots "with each non-kernel module disabled" and
    disables nothing; its only guard is `if w == null` on the result of `World.new(...)`.
  - `check_m2_gear.gd`'s `_coverage_composes_by_max_not_sum` discards both `SimInventory.equip`
    return values, so the max-vs-sum claim is satisfied by a world where only the mask was equipped.
  - `check_m2_save.gd`'s `_streams()` and `check_r3_full.gd`'s "seed mismatch: restore should
    assert" block have the same shape as `check_m2_recruits.gd`'s old "transmitted → shambler
    **with kit**" lane (fixed in the survivor-generation slice, see the record) — a condition
    computed and thrown away, and a block that never calls `restore`.
  - `check_hud.gd`'s fixture world lacks the components five of `hud.gd`'s clause builders read, so
    those clauses return `""` and their assertions pass with no data to judge — which CLAUDE.md
    says must skip loudly instead.
  - `check_r6_bench.gd` loads `bench.gd`, prints a "delegating" line and calls `quit(0)` without
    running a benchmark — and no npm script or `run-godot.mjs` path references the file, so it is a
    dead gate that would pass unconditionally if anyone wired it up.
- **Three more dead sockets, on top of the nine now listed in CLAUDE.md.** `sim/spatial/hash.gd`
  in its entirety — nothing in `sim/` or `presentation/` calls it, only `bench/bench.gd` and two
  check scripts, so the headless bench measures a structure the running simulation never touches
  (`melee.gd` says so out loud: "candidates via spatial would be faster but we scan for
  correctness"); `SimThreat.threat_within`, so fast-forward is never interrupted by a zombie the
  way the oracle's is; and `SimDirector.snapshot_of`, which `world.gd` deliberately replaced and
  which is now a second hand-listed copy of the director's save shape.
- **`repair_cost` and `spoilage_rate` are stats nothing resolves.** Both are declared in
  `sim/modifiers/stats.gd` and both are the target of a shipped web node — `craft.tape`,
  `craft.scrap`, `surv.cook` — and no code anywhere calls `resolve` on either, so those three
  nodes are bought, applied, and felt by nobody. Named here because the focus-auto-allocation
  slice made `craft.scrap` ownable for the first time and it would be dishonest to record that as
  a node arriving in play: what arrived is a node that can be owned. Repair already spends a
  fixed scrap cost (`SimJobs.REPAIR_TICKS` and the fortify scrap rules) and cooking already has a
  spoilage clock, so both have an obvious reader waiting.
- **`bloater` contamination fires once per survivor, ever.** `contaminationRolled` is set the first
  time a survivor stands in any cloud and is never removed, so every later cloud in the campaign is
  a no-op for them.
- **A corpse looks exactly like a person.** Presentation has no notion of one: same sprite, same
  tint, same facing pointer — and because `_make_corpse` removes `velocity`, the peripheral-motion
  cull inverts for corpses.

**Parked until Milestone 3A — blocked by missing systems, not by choices:**

- **Warmth and hygiene slots** (undershirt, socks, underwear) — wait for temperature and hygiene.
- **Trait-weighted modification outcomes** — wait for traits; `SimModification.TRAIT_FAILURE_SHIFT`
  is the named seam.

**Landed, gated, and reachable in play:**

- **Lethality** — infection stages, armour-reduced transmission, diagnosis, the five responses
  including amputation, and turning (`godot:m2:lethality`). Stats MVP: STR/CON/DEX
  (`godot:m2:stats`).
- **The district and its inhabitants** — civic-annex overlay (`godot:m2:district`), the
  shambler/screamer/bloater roster (`godot:m2:roster`), NPC combat including the pistol
  fire-and-reload branch (`godot:m2:npc`).
- **Ranged combat** — bow/pistol fire loop, reload, ammunition (`godot:m2:ranged`), aiming
  (`godot:m2:aim`), with wear no longer wiping a weapon's runtime state (`godot:m2:upkeep`).
- **People and economy** — needs (`godot:m2:needs`), jobs (`godot:m2:jobs`), recruits
  (`godot:m2:recruits`), fortification (`godot:m2:fortify`), the slice director
  (`godot:m2:director`), save/load (`godot:m2:save`), the shallow skill web (`godot:m2:web`).
- **The stance ladder, sim-owned** — Z/X/C/V plus the Sprint latch, with the zero-stamina gate in
  the sim (`godot:m2:stance`).

**Survivor generation: appearance, age, backstory, starting kit** — **landed**
(`godot:m2:recruits`, seven new lanes). `SimRecruits.roll` already rolled a name, 2-3 traits, a
backstory label, aptitudes with a backstory nudge, a kit and a feature list; what was missing was
never the pools, it was five dead sockets between the roll and the screen. All five are wired:

- **Age.** `generator.json` gained `ageBands` (young/adult/midlife/elder, each an authored prose
  word and an aptitude nudge); `roll` picks a band, then an integer inside it, and the nudge feeds
  the same clamp-and-rebalance-to-15 loop the backstory nudge already used, applied together
  rather than as two separate passes. The integer lands on `identity.age` and is never printed —
  `person_clause` below is its only other reader, and it reads the word, not the number.
- **Backstory.** Each of the eight backstories gained a `line` (one authored sentence); identity
  now carries `backstoryId` alongside the existing label, and the line is looked up from content
  at read time rather than copied onto `identity`, so editing a line changes what an existing save
  says with no migration.
- **Appearance, visual.** New `godot/content/colony/looks.json`, a **tint-only** array (docs/30
  records why no `sprite` key) that `check_appearance.gd`'s array-topped `_all_blocks()` walk
  already validates for free; `generator.json` gained a `looks` list, `roll` picks one onto
  `identity.look`, and `presentation/main.gd` prefers `identity.look` over `identity.id` for a
  generated colonist's `cid` — a data pass-through, not a branch, so the appearance ban holds. A
  generated colonist no longer renders as an identical role-colour disc.
- **Appearance, prose.** The rolled feature list reaches `identity.features`, unread by anything
  before this slice.
- **Kit.** `survivors.gd::_hold_it`, previously wired for uniques only, is now
  `SimSurvivors.equip_kit(world, ent, kit, x, y)` and both spawn paths call it: a kit weapon lands
  in the hand, a pack item falls back to the pack, and a failed stow still drops at the spawn
  point. Before this, `SimRecruits.spawn_generated` only ever `stow`ed — a generated colonist
  carrying `item.bat.aluminium` had no `meleeWeapon` component, unarmed in the same way the
  pre-armed-kit unique colonist once was (see "A weapon somebody actually holds", above).
- **The surface.** `SimSurvivors.person_clause(world, ent) -> String` turns backstory, age and
  features into one prose sentence — "Asha Chen, a night auditor, settled into adulthood; broad
  shoulders, tired eyes, crooked nose" — with no digit in it anywhere, and `godot/ui/work_panel.gd`
  draws it as a second line under each row's name (`ROW_H` grew from 36 to 52 to fit it, and the
  panel from 320 to 420 tall to keep the same six rows on screen). Mara's own content already
  authored an `age` and `appearance.features` that nothing read; `spawn_unique` now reads both
  onto `identity`, so the one hand-authored survivor gets a clause too, off the same function.

Seven lanes: GEN SHAPE (rolled dict against content, including a bogus look id resolving no
block); READERS (`identity.age/look/backstoryId/features` after `spawn_generated` — the assertion
that would have caught the dropped appearance list); KIT IN HAND (every kit id resolves through
`SimItems.spawn_item`, and `fired_security`'s bat lands as a `meleeWeapon` — **measured red**
against the pre-slice code, where it stowed instead); AGE READS (a forced band rolls
bit-identical twice; two opposite-nudged bands, ±2 dex, diverge by 1.5-1.8 average dex over 24
same-seeded pairs, measured before the 0.5 threshold was written — CLAUDE.md's "measure balance
claims, never theorise them", because the rebalance loop can partly re-absorb a nudge into
whichever stat it makes the new unique max); PROSE (non-empty, contains the backstory line,
no digit — `[0-9]` finds none); LOOK RESOLVES (a rolled look's tint differs from the role colour,
two looks give two tints, a missing id falls back to the role colour); DETERMINISM (same seed
rolls identical, a different seed diverges, with a loud skip if it doesn't rather than a silent
pass). A mutation check dropping the `identity.look` write turned READERS red
(`readers: identity.look is empty`) with every other lane untouched, confirming the lane is
watching the write and not just the shape of the dict. The same slice closed the sweep's
`check_m2_recruits.gd` "with kit" defect (`turned < 1` was the only real check; the `if
w3.components.query(["container"]).has(int(e)) ...: pass` around it did nothing) — the death
lane's turn-to-shambler case now asserts `SimInventory.carried_items` is non-empty on the
shambler, having first asserted it was non-empty on Mara before she turned.

New randomness (age band, age integer, look pick) draws from a new named stream,
`recruitLook`, never from `recruits` — `npm run godot:m2:balance`'s fast tier was not re-run
because nothing about it could have moved: the `recruits` stream's draw order (name, surname,
story, traits, composition, features) and `accept`'s 15% transmit roll are byte-for-byte what
they were, which is exactly what a new stream costs nothing to guarantee.
`godot/content/colony/` stays outside `CONTENT_TYPES` (`src/sim/content/types.ts`), so the
frozen oracle's Ajv never walks it — `npm test`'s 594 passes prove the invisibility rather than
assume it, same as the existing `skill_web.json` in the same directory.

**Trait conflict rules** — **landed** (`godot:m2:recruits`, four new CONFLICTS lanes). Conflicts
are content, not a GDScript constant: `generator.json` gained `traitConflicts`, a list of pairs,
and `SimRecruits.roll`'s trait-bag loop calls the new `_erase_conflicts_of(bag, picked_id,
conflicts)` after every pick — including the backstory `bias` pre-pick, which runs *before* the
loop starts and is the case a naive "erase inside the loop only" implementation misses. `bag`
stays a plain Array end to end (the packed-array-is-a-value trap does not apply; `Array.erase`
matching by value is exactly right for a list of trait-id strings). Of the shipped eight traits,
exactly one pair is a genuine contradiction: `squeamish` vs `iron_stomach`, which
`npc_combat.gd`'s `break_off_state` already reads as opposite ends of the same threshold — the
honest scope is recorded in docs/30 rather than papered over with docs/07's other three named
pairs, none of which are traits the pool actually authors. Four lanes prove the *mechanism*, not
just the one-entry table: TRUE POSITIVE (200 rolls off one fixed seed's `recruits` stream never
co-occur a declared pair, and the lane refuses to pass quietly — it fails loudly if the sample
never drew one of the pair's members at all, which it does not, having drawn both); TRUE NEGATIVE
(a synthetic two-trait fixture pool declared conflicting returns one trait; the same fixture with
the conflict list emptied returns two — the general case docs/07's four-pair sketch would have
needed, proved without adding four unread traits to the pool); BIAS (every roll forced onto
`line_cook`, whose bias is verified against content to be `iron_stomach`, never carries
`squeamish` alongside it, over 60 rolls); DEAD SOCKET (every id `traitConflicts` names resolves
into the `traits` pool, and every id in the pool is either read by sim code or named in the
lane's own INERT allowlist — grep-verified against `sim/`: `steady_hands`, `loud`, `night_blind`
and `fast_healer` are read nowhere, `squeamish`/`iron_stomach`/`optimist`/`light_sleeper` are).
A mutation check dropping both `_erase_conflicts_of` calls turned TRUE POSITIVE, TRUE NEGATIVE
and BIAS all red; restoring only the loop-pick call and leaving the bias pre-pick's call removed
turned BIAS red on its own (TRUE POSITIVE went red too, incidentally, since `line_cook` and
`night_auditor`'s biases feed the same stream the loop draws from) — both runs are in the session
log for this change. Erasing from `bag` changes its size, which is what a plain `int_range(0,
size-1)` draws against, so this is a determinism-affecting change by design and was measured
rather than assumed safe: `godot:m2:balance` (fast tier) and `godot:m2:harness` were run before
and after, same four seeds. Both came back **byte-identical**, line for line — `M2_BALANCE_OK`'s
four `FAST seed=...` lines and `M2_HARNESS_OK`'s TURTLE/NOISY/KD lines matched exactly. The single
recruit each balance seed draws never rolled a `squeamish`/`iron_stomach` pair to begin with (an
eight-trait bag with one conflicting pair rarely draws both in one 2–3-trait pick, and the four
fixed seeds landed on the rarely side this run), so the erase never fired on this measurement —
an honest "did not move," not evidence the mechanism is a no-op, which the gate's own TRUE
POSITIVE lane (200 rolls off the `recruits` stream, not four) is what actually exercises it.

**Landed, gated, and switched ON — the survival loop.** Five slices built it end to end: the
grab → struggle → bite loop (`godot:m2:contact`), wounds with a severity and a bleed clock
(`godot:m2:wounds`), pressure and bandaging plus a command path to the five infection verbs
(`godot:m2:treatment`), and recovery that closes wounds and climbs integrity back, earned only while
fed and not exerting (`godot:m2:recovery`). A bite makes a located wound, it bleeds, you stop it with
your hands or a dressing, and it mends over days you have to earn. All of it is reachable in
ordinary play now: `SimShambler.GRABS_ENABLED` ships `true` — the flag record below walks the
recorded reasons in order, what answered each, and closes with the flip itself (the owner's
2026-09-01 decision, taken together with the bigger colony that unblocked it). The
wound-treat-recover half had already stopped being unreachable when the **swipe** landed (the
basic-combat slice, further down); the flip adds the bite, and with the bite, infection.
Post-flip, `M2_BALANCE_OK`'s `survivors_end >= 1` over the four fast seeds measures the shipped
default with grabs live, which makes it the standing "the colony survives its own contact loop"
assertion.

**Answered: bite lethality during a hold.** The owner's call was to pull four levers together and
conservatively rather than one of them hard, and all four have landed:

- **Where a held bite goes.** New `SimCombat.HELD_HIT_LOCATION_WEIGHTS` — head 0.05 against the
  free-hit table's 0.20, torso 0.30, each arm 0.14, each hand 0.09, each leg 0.07, each foot 0.025.
  A mouth inside a grapple reaches an arm, not a skull. The free-hit table is untouched, and the
  roll stays in one canonical place: `SimMelee._roll_body_part` gained an optional weights argument
  and only the bite site passes it.
- **How often.** `REPEAT_BITE_TICKS` 40 → 80 — four seconds between repeat bites, not two.
  `FIRST_BITE_TICKS` stays 30.
- **How hard, per part.** `maxf(2.0, minf(BITE_DAMAGE, 0.35 × part max))`, so a head takes 5.25
  (three bites to destroy, not two), a torso still takes the full 8, an arm 7, a hand or foot 3.5.
  This moves a severity band on purpose and the gate pins which side: an arm bite was 8 of 20 =
  0.40, exactly the DeepWound boundary; it is now 7 of 20 = 0.35, a Laceration — a fifth of the
  bleed rate — with the old flat 8 kept as the assertion's own control.
- **The struggle.** `STRUGGLE_TICKS` 20 → 16 and `STRUGGLE_STAMINA` 20 → 15: sooner, and six
  attempts on a full tank rather than five. The contest maths is untouched (one shambler is still
  1/1.5 = 0.667, pinned in `check_m2_stats.gd`). The re-grab cooldown became its own constant,
  `REGRAB_COOLDOWN_TICKS = 20`, at its old value — it had been `STRUGGLE_TICKS` doing double duty,
  so the escape lever was quietly shortening it as well.

`godot:m2:contact` grew two assertions for this, each with its true negative: **HELD-AIM** rolls
4,000 held and 4,000 free locations and requires the head share to collapse (measured 0.048 against
0.192) and arms-and-hands to dominate (0.467 against 0.121), with the free-hit table run through the
same counter as the control that must fail; and **BITE-SCALE** pins the per-part arithmetic, the
floor and ceiling on every part, the severity band edge, and that a live hold's `bite.landed` carries
the scaled number for the part it names. HELD-AIM earned its keep immediately: the first draft of the
table summed to 1.05, which `_roll_body_part` would have absorbed silently as extra weight on a foot.

**Answered: the harness colony had no agency.** The three things the previous measurement found
load-bearing were all owner-approved and have all landed, in the game rather than in the harness
wherever the game was the thing that was wrong:

- **Instinct.** A held survivor with nobody answering for them struggles on their own after
  `STRUGGLE_INSTINCT_TICKS` (40 ticks, two seconds), at the same stamina price and through the same
  contest. `F` stays the better answer rather than the only one: it commits the escape on the tick
  it is pressed, two seconds sooner, and resets the clock by arming — so instinct never takes a
  decision away from somebody making one. `godot:m2:contact` grew **INSTINCT**, which times the
  attempts off the `stamina.spent` that pays for them: unattended, the first is at hold-tick 40 and
  none is earlier; played, the first is at hold-tick 1 and there is deliberately **no** attempt at
  40, because arming reset the clock.
- **A weapon somebody actually holds.** `SimSurvivors.spawn_unique` now equips a kit item into the
  slot it belongs to instead of packing it, and Mara's kit gained the annex's other kitchen knife.
  A stowed weapon is not a weapon — `melee.gd` builds the `meleeWeapon` profile off `item.equipped`
  — which is how the second colonist came to boot unarmed while carrying her own kit. The balance
  harness's `mixed` arm became an arm like the other two rather than "whatever the boot left", and
  `godot:m2:balance` grew **ARMED**: no campaign may start with an unarmed colonist, with the
  counter's own true negative (disarm one, the count must move to exactly one).
- **Holder-first targeting.** `npc.combat` now prefers a shambler that has hold of somebody over a
  nearer one that does not. It is safe to be strict about that because the candidate list is
  already bounded by the weapon's own envelope, so a preferred holder is always one this NPC can
  act on. `godot:m2:npc` grew **HOLDER**, with both halves in one arena: with a hold open every
  arrow goes to the far holder and none to the near wanderer, and with no hold open the identical
  placement shoots the near one.

Those show up in the shipped build, where grabs are still off: the fast tier now records the
colony's **first kills at all** — 6 on seed 404 and 1 on 90210, against zero in every previous run
— because there are two armed people in the annex instead of one.

**Answered: the price of an escape, and nobody else being able to pay it.** The owner picked two
levers, both additive and both landed. The escape contest itself is untouched — one shambler is
still 1/1.5 = 0.667, still pinned in `check_m2_stats.gd`.

- **Stamina recovers while held.** `health.recover` stops skipping regeneration for a body carrying
  `grabbed` (the recovery delay still counts down, it just no longer suppresses regen), and
  `world.gd` stops charging a held body the posture ladder's drain. The second half is what makes
  the first half real: the drain publishes `stamina.spent` every tick, every `stamina.spent` re-arms
  the delay, so without it a survivor grabbed mid-jog would regenerate nothing, forever. An empty
  tank is now a pause of about 25 ticks instead of a hold with no exit. `godot:m2:contact` grew
  **REGEN-HELD**: a pinned survivor climbs 0.0 → 18.0 over 30 ticks with zero drain charges, and the
  true negative is a **free** jogging survivor in the identical stamina state who stays at 0.0 —
  proving the exemption is load-bearing and that the delay still does its job everywhere else.
- **Rescue.** A free survivor can break a shambler's hold on somebody else: `H`, or an NPC deciding
  for itself. `SimShambler.try_begin_rescue` is the single precondition list (in reach, hands free,
  no attempt in flight, off cooldown, and `RESCUE_STAMINA` 10.0 — refused below it, and refusal
  charges nothing), `shambler.rescue-intake` is its own system at `input`/8 so the contact gate's
  `_no_struggling` cannot silence it, and the contest resolves `RESCUE_TICKS` 12 later from a new
  `rescue` RNG stream, using the **rescuer's** `grab_escape` power against the same total grip. A win
  frees the victim from *every* hand at once — the measured average is 1.4 holders — and arms the
  ordinary re-grab cooldown and break-away. `npc.combat` prefers it over its own weapon when the
  victim is within `RESCUE_METRES`, on an envelope that widens to 2.6 m only while somebody is held,
  so an archer standing off keeps shooting and an unarmed NPC can still pull. Gates: **RESCUE**
  (16 seeds, both outcomes required, with an empty tank, a 3.0 m victim and a grabbed rescuer as
  three separate refusals) and **RESCUE-FIRST** (the NPC picks the pull over the swing; collinear
  geometry past `RESCUE_METRES` is the negative that makes it swing; attempts spaced ≥ 32 ticks).
- **`grab.broken {victim, by, cause}`**, published at the one point a victim becomes fully free, with
  causes `struggle` / `rescue` / `geometry` / `holder-died` / `victim-died`. It is how a bus-only
  harness can count releases at all. **BROKEN** asserts each cause exactly once, against a
  200-tick unbreakable hold that must publish none.

**Measured, and the flag still does not flip.** The same throwaway driver as last time (rewritten:
`SimBoot.playable`, the harness's own compressed campaign, `GRABS_ENABLED` forced on, `entity.killed`
de-duplicated by entity id), run over the four fast seeds **on the parent commit and on this one**,
so both columns come from one measurement:

| seed | before (same driver, `ab2f3ac`) | after | how it ends |
| --- | --- | --- | --- |
| 20260805 | `2/2`, 0 grabs | `2/2`, 0 grabs | no contact at all in ten days |
| 404 | `0/2`, 115 grabs, 66.9% held, **38.3%** empty-tank | `0/2`, 149 grabs, 64.7% held, **13.3%** empty-tank, 71 escapes won | both by blood loss |
| 31337 | `2/2`, 39 grabs | `2/2`, 60 grabs, 59 escapes won | every grab on the recruit; neither boot colonist is ever held |
| 90210 | `0/2`, 98 grabs, 17.4% held, **48.9%** empty-tank | `0/2`, 149 grabs, 14.1% held, **0.0%** empty-tank, 136 escapes won | both by blood loss |

(The retired driver reported 65% and 69% held for those two seeds; re-measured with the current one
the baseline is 66.9% and 17.4%. The empty-tank figures reproduce almost exactly — 38.3% against 38%,
48.9% against 49% — so the denominators that matter agree and only the older held-tick denominator,
whose driver is gone from the tree, differed.)

The price of an escape is no longer the binding constraint: empty-tank ticks fell by two thirds on
404 and to zero on 90210, and escapes won went from none the instrumentation could see to 71 and 136.
**Two seeds still wipe, so `GRABS_ENABLED` stays `false`**, and the reason is a different one:

- **Rescue cannot reach.** Across 2,610 held ticks on 404 and 2,590 on 90210, the nearest free
  colonist was **never** within `RESCUE_METRES` — never within 6 m, in fact; the closest approach all
  campaign was 6.41 m and 11.17 m. The lever is built, gated and correct; a two-person colony spread
  across a district simply never has a second body standing next to the first. That is the same wall
  holder-first targeting hit one lever earlier, and it will not move until a colony is either bigger
  or posted closer together.
- **A held body cannot treat what is bleeding.** `treatment._can_channel` refuses first aid to a
  `grabbed` survivor — correctly; you cannot press on a wound with a zombie on your arm. On 404 a
  colonist spends 64.7% of their living ticks held across **149 separate grabs**, so two thirds of
  that survivor's life is time they are bleeding and may not answer it. Both wipes are blood loss.

**Answered: a held survivor may answer their own bleeding. Landed, then inverted: the churn.**
Three levers have now been pulled at this blocker and all three are built. Two of them do what they
were picked to do. The third — this slice — does what it was picked to do *and* takes back most of
what the first one bought, and that trade, measured rather than guessed at, is where the flag now
stands.

- **Aid while held (Lever A).** `treatment._can_channel` grants exactly one channel to a `grabbed`
  body: `pressure` with `patient == actor`. The arbitration is seven named rules, written out in
  full at the top of `treatment.gd` and each one gate-asserted, because a hold and a channel now
  meet in places that used to be mutually exclusive — R1 the exemption itself (begin *and* the
  per-tick re-check), R2 `grab.started` sparing only the victim's own self-pressure, R3 a stagger
  still cancelling everything, R4 struggle and press coexisting, R5 becoming fully free cancelling
  your own self-pressure and only that, R6 self-aid deferring while a break-away runs, R7
  `context()` picking `pressure` while held even with a dressing carried. Gates: **AID-HELD** and
  **HELD-CONTEXT** in `godot:m2:treatment` (with the two new refusal rows — `bandage`/grabbed and
  `pressure`/grabbed-other — pinning what the exemption does *not* open), and **PRESS-THROUGH**,
  **STRUGGLE-DURING-PRESS**, **FLIGHT-CANCELS-PRESS**, **BREAKAWAY-DEFER** in `godot:m2:contact`.
  The refusal-table row that used to pin the old behaviour was swapped rather than deleted, so the
  vocabulary is still complete.
- **The churn (Lever B).** `BREAK_AWAY_SPEED` 1.6 → 2.1. The treadmill was a speed bug, not a
  duration one: both bodies are pinned for a hold, so a release starts from at most `GRAB_METRES`,
  and at 1.6 against the 1.68 seek the holder *gained* 0.08 m/s on the person who had just escaped
  it — the gap shrank across the 20-tick cooldown and the re-grab was unconditional. At 2.1 (walk
  speed, not a sprint) the escapee gains 0.42 m/s. **CLEAR-AWAY** measures it and pins the speed
  against the seek so a locomotion retune cannot restore it: 1.057 m between the bodies when the
  cooldown lapses and no re-grab through `BREAK_AWAY_TICKS`, against a re-grab after 19 ticks for
  the same survivor stripped of the break-away. The comment at `shambler.gd` that claimed the
  duration made the separation outlive the cooldown was false and is now speed-backed.
- **R5 inverted, so that flight is flight (Lever C, this slice).** R5 used to say a running press
  outranked a break-away, which made Lever B unreachable for exactly the survivors using Lever A.
  It now says the opposite: `treatment.escape-releases-press` subscribes to `grab.broken` and
  cancels the victim's own self-pressure — that, and nothing else. R2 is deliberately untouched, so
  the two rules are exact mirrors: a *second holder arriving* still never takes your palm off your
  own wound, and only becoming **fully free** does. R6 then re-opens the press once the running is
  done. The drain ordering is design and is asserted rather than worked around: `grab.broken` is
  published inside the escape tick and handlers run at drain, at the end of `world.step()`, so the
  press is still there for that tick's `treatment.pin` and flight begins the tick after — one of
  breakAway's 26 ticks spent standing still, worth about 0.105 m of gap. **FLIGHT-CANCELS-PRESS**
  replaces REGRAB-SPARES-PRESS and walks the whole cycle: the escape tick pinned at 0.0000 m with
  the press cancelled by the end of it, 1.050 m flown by tick 11, the press re-opening at tick 26
  clear of the hold and going on to clot, and the re-grab at tick 29 against a cooldown of 20. Its
  control is the same seed and the same geometry with the subscription lifted off the bus — the
  behaviour that shipped before — which covers no ground at all and is re-taken at 19. Three
  negatives keep a cancel-everything from passing it: a second holder does not cancel (R2), a
  stagger still does (R3), and a `grab.broken` naming a bystander cancels nothing. The treatment
  gate's **INTERRUPTS** gains the mirror row: a free treater's press on a patient who tears free
  *survives*, because that patient has stopped being dragged.
- **Same-file side fix.** `_gather_survivors` skips `corpse` carriers. `identity` survives
  `_make_corpse`, so shamblers pursued and grabbed the dead — a hold nobody could answer, inflating
  every contact counter. **CORPSE**: never taken over 60 ticks, where a living body in the same
  placement is taken on tick 1.

Measured with a throwaway driver rewritten from scratch (`SimBoot.playable`, the balance harness's
own `_compressed_campaign`, `GRABS_ENABLED` forced on, `entity.killed` de-duplicated by entity id),
run on the clean tree and again on this one, so both columns are one measurement. "Living ticks" is
the sum, over the 20,010 ticks a compressed campaign actually steps, of how many colonists were
alive on each — so a two-person colony that lasts the whole run reads 40,020. A mid-press escape
is classified from a snapshot of the victim's `treatment` taken at the **start** of the tick the
`grab.broken` drains on: reading it at drain time would be reading state this slice has already
edited, and would report the phenomenon vanishing whatever had actually happened.

| seed | before (this slice's parent) | after | how it ends |
| --- | --- | --- | --- |
| 20260805 | `2/2`, 0 grabs, 0 bites | `2/2`, 0 grabs, 0 bites | no contact at all in ten days |
| 404 | `0/2`, 214 grabs, 136 bites, 26 presses begun / **25 completed**, 5,863 living ticks | `0/2`, **150** grabs, **88** bites, 76 begun / **0 completed**, 4,959 living ticks | before: 2 head-destroyed + 1 blood loss. after: 1 head-destroyed + 2 blood loss |
| 31337 | `2/2`, 49 grabs, 21 bites, 10 begun / 9 completed, 40,020 living ticks | `2/2`, 46 grabs, 20 bites, 42 begun / **0 completed**, 40,020 living ticks | colony never touched on either tree |
| 90210 | `0/2`, 212 grabs, 122 bites, 27 begun / **26 completed**, 18,844 living ticks | `0/2`, **166** grabs, **65** bites, 144 begun / **0 completed**, 17,102 living ticks | before: 1 head-destroyed + 1 blood loss. after: **3** blood loss |

**The inversion delivers the hold count and pays for it in clotting, and the net is not survival.**
Grabs fall 214 → 150 on 404 and 212 → 166 on 90210, bites fall 136 → 88 and 122 → 65, and the
re-grab window finally comes off the cooldown on two seeds — mid-press windows longer than the
20-tick cooldown go from 0 of 44 to 10 of 41 on 31337 and from 0 of 119 to 10 of 141 on 90210 (404
manages 2 of 75; see the first residual below). But a press cancelled at every escape banks nothing,
and the fragments arithmetic is exactly what it predicted: **presses completed go from 25/9/26 to
zero on every seed**, blood loss becomes the whole of 90210's death list, and 404's colony lives 15%
*fewer* ticks than it did with the press winning. Both hard seeds still end `0/2`, so
**`GRABS_ENABLED` stays `false`** and this is reason six rather than a flip record.
`survivors_end >= 1` was not relaxed; it remains considered and rejected.

Three residuals were named, in the order they cost the most. **The first is now answered** (see
the slice below); the other two stand:

- ~~**A break-away runs into the wall it was released against.**~~ **Answered.** The finding, which
  was measured rather than reasoned: over three days of seed 404 with the flag on, a `breakAway`
  body carried its escape velocity into `movement.integrate` on 1,230 of 1,266 ticks and the
  integrator **zeroed it on 1,124**, because the committed heading was blocked on the X axis on
  1,107 ticks, on the Y axis on 1,154, and on **both at once on 1,087 — 86%**. Total ground covered
  was 12.66 m, 0.010 m per tick against a nominal 0.105. A colony is grabbed where a colony lives,
  which is against the annex walls, so the shove-off pointed into masonry and the survivor spent all
  26 ticks leaning on it — which is why 404's mid-press escapes covered a mean of **0.063 m** before
  the re-grab and why the re-grab was the same shambler in 309 of 309 measured windows.
- **The pinned escape tick.** The cancel lands at drain, so the escapee stands still for one tick
  while the holder keeps closing at 0.084 m. That single tick is worth 0.105 m of gap, which lifts
  `BREAK_AWAY_SPEED`'s own "a release from d0 < 0.58 m can still be inside reach when the cooldown
  lapses" to roughly **0.69 m**. FLIGHT-CANCELS-PRESS releases from 0.85 m for exactly this reason
  and says so.
- **Contact rarity, and what a press is worth in fragments.** With holds arriving every ~50 ticks a
  400-tick deep-wound press has two completion paths: a single unbroken 400-tick hold, or being free
  and clear long enough after the colony kills or sheds the holder. Neither happened once across
  four seeds. A press that is cancelled at every escape still suppresses the bleed while it runs —
  which is most of a cycle — but it never clots, and blood loss is what kills these colonies.

The balance tier is therefore still exactly what it was, plus bus-only `grab.started`/`grab.broken`
counters that report and assert nothing, and `_the_flag_actually_gates_acquisition()` in the contact
gate still exercises both directions.

**Answered: a break-away now has somewhere to go, and one hard seed stops wiping.** The residual
above was a locomotion bug wearing a design call's clothes: the shove-off insisted on going
*straight* away, and straight away from a shambler that has you against a wall is into the wall.
`_break_away` now treats straight-away as the **preference** rather than the commitment. It fans out
in `BREAK_AWAY_FAN_DEGREES` order — 0, ±22.5, ±45 … ±135, stopping short of 180 because a survivor
shoving off does not run through the thing that had hold of them — and commits to the first
candidate with a clear run of `BREAK_AWAY_PROBE_METRES` (1.5 m, sampled every 0.25 m against the
same tile lookup the integrator collides with, through the new `World.body_fits_at`). Falls back to
the longest partial run when nothing is clear, and to straight-away when nothing is clear at all,
which is a body wedged in a corner and has no better answer. It stays a shove-off: one heading,
taken once at release, no per-tick re-derive, no RNG, no pursuit solver.

`godot:m2:contact` grew **AWAY-CLEAR**, with a negative in each direction. Positive: a release with
a wall column directly behind the victim commits 90° off straight-away and flies 2.00 m, against
**0.11 m** for the identical release with the heading forced back to straight-away — the
shipped-before control, which must fail to move, and does. Negative: the identical release in an
empty field must commit to straight-away *exactly* (deviation asserted under 0.001°), so a fan that
quietly re-aimed every escape in the game could not pass.

Measured with the same driver as the previous slice, run on the clean tree and again on this one:

| seed | before | after | how it ends |
| --- | --- | --- | --- |
| 20260805 | `3/2`, 0 grabs, 0 bites | `3/2`, 0 grabs, 0 bites | no contact at all in ten days |
| 404 | `0/2`, 150 grabs, 88 bites, 8,490 living ticks, 50.2% held, **0.0086 m/tick** | `0/2`, 152 grabs, **79** bites, **12,011** living ticks, **31.4%** held, **0.1038 m/tick** | 3 × blood loss |
| 31337 | `3/2`, 46 grabs, 20 bites, 0.0374 m/tick | `3/2`, **6** grabs, **2** bites, 0.1035 m/tick | colony never touched on either tree |
| 90210 | `0/2`, 166 grabs, 65 bites, 0.0169 m/tick | **`1/2`**, **65** grabs, **20** bites, **0.1041 m/tick** | 2 × blood loss |

(The before column reproduces the previous slice's recorded figures exactly — 150/88 and 166/65,
both `0/2` — so the two measurements are comparable.)

**An escape is now worth what the open-field arithmetic always claimed.** Ground covered per
break-away tick goes from a tenth of nominal to 0.104 against a nominal 0.105 on both hard seeds.
90210 is **the first hard seed to stop wiping**; 31337's contact all but disappears; 404's colony
lives 41% longer and spends a third rather than half of its life held.

**The flag stays `false`, and residual three is now the whole of what is left.** 404 still ends
`0/2` with all three deaths blood loss — and **126 presses begun, zero completed**. A press
cancelled at every escape banks nothing, so a 400-tick deep-wound press has no reachable completion
path while holds arrive every ~50 ticks. That is the fragments arithmetic the R5 inversion bought
the hold count with, and it is the single measured thing between this loop and the flip.

**Answered: a press banks the time it has already served (R8).** This reverses a rule that was
deliberate and written down — `check_m2_treatment.gd`'s header said in as many words that a partial
hold must never bank, and named the assertion that would fail if one did. R5's inversion is what
made it untenable, and the reversal is on measurement rather than taste, the same way R5's own was.
`treatment.cancel` now writes the ticks a `pressure` channel served onto the open wounds of the
part it was aimed at (capped at that part's own pressure cost), and `begin` asks for what is left.
The bank lives **on the wound**, not on the presser, so whoever presses next inherits it. Two
exceptions carry the cost: a **stagger** banks nothing — R3 already singles it out as the one thing
that takes your hand off your own arm — and **bandaging never banks**, because a dressing is
applied, not accumulated. No decay, and cleared at completion and at `SimWounds.reopen`.

`godot:m2:treatment`'s `_a_hold_broken_early_buys_nothing` was **renamed and extended** rather than
deleted, so the vocabulary stays complete: it is now
`_a_partial_hold_clots_nothing_and_banks_everything`, and it still fails if a released hold ever
clots by itself. What it gained is the other half — the resumed press asks for 1 tick of 400 and
goes on to clot — plus the true negative that stops R8 making pressure free: the identical hold
ended by a **stagger** pays the full 400 again.

Measured on the same driver, before and after, with one correction carried into both columns: the
previous slice's "presses completed" counter watched `treatment.completed`, which is not an event
this sim publishes. The real signal is `wound.treated`, and both columns below use it.

| seed | before | after | how it ends |
| --- | --- | --- | --- |
| 20260805 | `3/2`, no contact | `3/2`, no contact | never touched |
| 404 | `0/2`, 126 presses begun / **0 completed**, 12,011 living ticks, 152 grabs | `0/2`, 219 begun / **20 completed**, **14,834** living ticks, 197 grabs | 2 × blood loss, 1 × head destroyed |
| 31337 | `3/2`, no presses | `3/2`, no presses | colony never touched |
| 90210 | `1/2`, 121 begun / **0 completed**, 29,825 living ticks, 65 grabs | `1/2`, 327 begun / **21 completed**, **36,573** living ticks, 239 grabs | 1 × blood loss, 1 × head destroyed |

Fragments now add up: ~11 cancelled presses compose into one clot, which is exactly the arithmetic
the rule was picked for. Both hard seeds live about 23% longer, and grabs *rise* on both — a
survivor who is alive longer is a survivor there is more time to grab, which is the counter reading
correctly rather than a regression.

**`GRABS_ENABLED` still stays `false`, and what is left is no longer a bug.** 404 ends `0/2`, and
the remaining constraint is the shape of the colony rather than another contact-loop lever. The
"rescue can never reach" finding from two slices ago has been **re-measured and is now only partly
true**, which is worth stating plainly rather than repeating: with escapees actually covering
ground, a free colonist is within `RESCUE_METRES` (1.6 m) of a held one for 135 ticks on 90210 and
18 on 31337, closest approach 0.52 m and 0.21 m — where the previous measurement found no approach
inside 6 m on any seed. **On 404 it still never reaches**: closest all campaign is 4.40 m, improved
from 6.41 m and still nearly three times the radius. That colony simply never stands together, and
moving it is **People and economy** work — a bigger colony, or one posted closer — rather than
anything left in the contact loop. It is a design call about the shape of the slice, not a
measurement waiting to be taken.

**Flipped: `GRABS_ENABLED` ships `true` — the owner's decision, with the colony that carries it.**
The owner decided both halves of the standing question in one session (2026-09-01): grow the boot
colony rather than reposting it, then flip. What landed, each half gated:

- **A third boot colonist.** `survivor.unique.ellis` — Ellis Okafor, a depot night watchman with a
  steel pipe, STR 6 / DEX 4 / CON 5, Fighter focus, Guard 1 — is pure content under
  `content/survivors/uniques/`, the "drop another JSON, no code change" promise finally cashed.
  Two boot defects stood in the way and were fixed with it: `SimSurvivors.boot_playable` computed
  the same +1.6 m offset for every unique, so a second colonist stacked on the first's point — it
  now takes one fixed offset per unique by index (`BOOT_SPAWN_OFFSETS`, a table, no RNG, the
  blocked-tile mirror fallback kept per spawn), which posts the colony inside `RESCUE_METRES` of
  itself; and `SimBoot.place_stations` made exactly two beds, so somebody would have slept on the
  floor — it makes three now. `check_m2_stats.gd`'s MARA lane still pins `boot_playable`'s return
  (the last unique in id order — Mara), and `godot:m2:balance`'s ARMED lane now counts three armed
  colonists at every boot.
- **The flip itself.** `shambler.gd`'s six-reason rationale block became a pointer at this record;
  the flag stays a `static var` (gates drive it both ways), deliberately not world state and not
  saved. The swipe gate's three swipe-only lanes now pin the flag **off** for themselves with a
  restore-to-previous — at 0.9 m a live grab wins the approach and every swipe assertion would be
  measuring a grapple — and its grapple lane, like the contact gate, pins it on and restores.
  Three campaign gates needed the same isolation, each red diagnosed rather than theorised:
  `check_m2_raiders.gd`'s prey arena measures pursuit and the claw ("closed ≥ 0.8 m") and a
  live grab pins both bodies at arm's length; `check_m2_needs.gd`'s NPC-latrine lane measures
  the seek ladder and the walk, and a probe driver showed a shambler taking hold of Mara
  mid-walk at tick ~1200 of its 4000; `check_m2_npc_combat.gd`'s guard-post lane spawns its
  zombie 0.9 m off — inside `GRAB_METRES` — so "drift off the post" was reading accumulated
  2.1 m/s break-away flights (8.3 m) rather than a chase. Each pins the flag off for the lane
  and restores the previous value. Two more gates assumed a two-person colony rather than a
  flag value: the "solo death ends the run" lanes in `check_m2_jobs.gd` and
  `check_m2_recruits.gd` killed a hard-coded Mara then the player, which left Ellis alive and
  read the run's correct refusal to end as a failure — "solo" now kills every other colonist,
  with a new intermediate assertion that the run must NOT have ended while the player lives.
  No assertion band was widened anywhere in the triage.

Measured with the flag-record driver (the compressed fast-tier campaign, `entity.killed`
de-duplicated by id, closest-rescue-approach instrumented) on this commit's parent and on this
commit, one driver, both columns. "Deaths" counts every person the bus reported dead who was never
named a raider — waiting strangers at the gate included — which is why a seed can end `3/3` and
still carry two:

| seed | before (colony 2, parent) | after (colony 3, this commit) | rescue approach (min) |
| --- | --- | --- | --- |
| 20260805 | `2/2`, 66 grabs, 0 deaths | `1/3`, 83 grabs, 2 deaths (head), **2 rescues** | 2.27 m → **0.10 m** |
| 404 | `2/2`, 24 grabs, 0 deaths | `1/3`, 66 grabs, 3 deaths (head), **1 rescue** | 2.47 m → **1.05 m** |
| 31337 | `1/2`, 16 grabs, 2 deaths (bloodloss, head) | `3/3`, 11 grabs, 0 deaths | 0.53 m → colony never held |
| 90210 | `2/2`, 31 grabs, 2 deaths (head) | `3/3`, 29 grabs, 2 deaths (head) | colony never held on either tree |

Two findings the table forces out loud. First: **the parent commit already ended every seed with a
survivor.** The last recorded measurement (above) had 404 at `0/2` with a 4.40 m closest approach;
the recruit-kit and NPC-focus slices that landed in between moved the balance more than any contact
lever did — an armed recruit is a fourth pair of hands. The bigger colony was the owner's decision
and was executed and measured as decided, not re-litigated against that surprise. Second: **a
third body is not a free win.** Contact rises where the colony stands together (grabs 66 → 83 and
24 → 66 on the two hard seeds), and two seeds that ended `2/2` at colony 2 end `1/3` at colony 3 —
more people near the noise is more people in reach. What the colony buys is exactly what the
flag record said it could not have: **rescue fires in real campaigns now** — three of four seeds
record a `grab.broken` cause of `rescue`, and 404's closest approach falls from three radii out to
1.05 m, inside `RESCUE_METRES` 1.6. No seed wipes; `survivors_end >= 1` was not touched and now
measures the shipped default with grabs live, four seeds green (`M2_BALANCE_OK`).

The balance tier's bus-only `grab.started` / `grab.broken` counters were promoted to assertions in
the same commit — `_assert_grabs_reach_the_campaign` (the floor and the flip's dead-socket proof:
189 grabs and four distinct causes across the fast seeds on this commit) and
`_the_grab_counters_can_see_a_grab` (the true negative: one fabricated pair through a real drain
moves each counter by exactly one) — which closes the debt item that named them.

**What the flip makes reachable rather than builds:** the located wound with its presentation lie,
armour-reduced transmission and the private `transmitted` flag, the paperdoll's wound ring, and the
bloater's open-wound check — all written against a bite nothing currently produces. Cripple and stagger are **no longer
unwired** (`godot:m2:contact`, STAGGER and CRIPPLE). Both were sockets cut and connected to
nothing: `shambler.gd` had a `Staggered` state and a `ticksStaggered` countdown the state machine
already handled and nothing could ever enter, and `crawlFactor` had been on the shambler component
since it was written and read by nobody. docs/09 says what a stagger is for — "landing a solid hit
interrupts the target … a staggered zombie isn't grabbing you" — so `shambler.stagger` now enters
the state *and* breaks the hold, publishing `grab.broken` with a new `staggered` cause and arming
the ordinary re-grab cooldown, so the answer to a grab is not one swing followed by an instant
re-take. Acquisition already required `Pursue`, so a staggered shambler cannot take you again
while it is down. Cripple goes through a new `SimShambler._speed_of`, one accessor rather than a
multiply at each of the four places a stored speed becomes a used one, and it is **derived from
the body every tick** (`SimHealth.is_crawling`) rather than latched off `injury.sustained` — a
flag would have to be kept in step with amputation and save/load, and a derivation cannot drift.
Measured: a legless shambler covers 0.420 m against an intact one's 1.680 m over the same window,
a ratio of 0.250 against `crawlFactor` 0.25.

**Basic combat is live** (`godot:m2:swipe`, plus new assertions in `godot:m2:npc` and rewritten
ones in `godot:m2:district` / `godot:m2:director`) — the owner's four asks of 2026-08-19, landed
as one slice without touching `GRABS_ENABLED`:

- **The swipe.** A Pursuing shambler with a survivor inside `SWIPE_METRES` (1.1 m) lands a clawed
  cuff after one second of windup and every three seconds after, publishing `attack.connected` —
  the survivor swing's own channel — so it costs a located "cut" wound through the one damage
  pipeline and rolls no infection. Part-scaled like a bite at half the fraction
  (`clampf(0.15 × part max, 1.0, 3.0)`): every swipe sits at its part's Scratch/Laceration
  boundary and can never cut a DeepWound or execute a head in five hits, which the flat first cut
  measurably did. Walls refuse it, out-of-reach refuses it, and a grapple takes both bodies off
  the menu — holder and held alike — so the flip's lethality question gains no back door. The
  gate holds cadence exactly, one wound per swipe, the scaling formula per observed hit, the
  no-infection refusal against a live-channel control, and both grapple refusals.
- **What a lethal district did to the harness, measured and answered.** The compressed fast tier
  wiped both hard seeds on day one, and the diagnosis driver attributed every death rather than
  guessing: colonists died kneeling (378 ticks pinned mid-fight — nothing but a grab or a stagger
  could interrupt a first-aid channel), critically injured NPCs fell out of `npc.combat` entirely
  and were ground down at arm's length (41 swipes taken, one swing answered), and succession fed
  each dead player's replacement into the same passivity. Three rules answer those, each the
  smallest that fits: **R9** — a landed hit interrupts a channel, and banks (a claw ripping you
  off a press is not a stagger); **R10** — self-aid will not *start* while a live claw stands in
  `SWIPE_METRES` of a free survivor (fight or run first, kneel when clear; the held stay under
  R1 — and the radius is the claw's strike reach, not contact, because a break-away ends inside
  contact and the press R5 cancels must still re-open, which FLIGHT-CANCELS-PRESS caught when the
  first cut got it wrong); and **break-off is disengagement, not surrender** — a critically injured survivor spends
  no shot and seeks nothing at range but still fights the claw already in melee reach. With all
  three: 404 ends `2/2` with 5 colony kills where the survival loop's whole history had it `0/2`,
  and 90210 ends `1/2` — the one death an unattended player who killed three zombies and bled out
  untreated, which is the harness being honest rather than broken.
- **Instinct defense** (`godot:m2:npc`, INSTINCT). The struggle instinct's twin, with its number
  and its reasoning: an unattended controlled survivor — no command of any kind for
  `DEFEND_INSTINCT_TICKS` (40) — answers a *Pursuing* claw inside melee reach with the swing a
  key press would have started. Any command resets the clock, so a present player is never
  overridden — not aiming, not hiding, not fleeing — and the Pursue requirement means instinct
  can never open a fight or cost a hidden player their silence. This is what lets succession
  promote a colonist into the player seat without promoting them into furniture.
- **Spawning up.** Boot wanderers 12 → 20 (`SimBoot.WANDERERS`, now referenced by the district
  and director gates rather than duplicated as a literal), night packets `[0, 2, 4, 6]` →
  `[0, 3, 6, 9]`, `LIVE_CAP` 24 → 32. The balance fast tier holds all four seeds inside every
  band at the new density.
- **Mouse aim, and one attack button.** The cursor proposes a bearing (`aim` command); the sim
  takes it only for a stationary body — a moving one faces where it goes, so you do not track a
  target over your shoulder at a jog. Left click aims at the cursor and attacks with what is in
  hand: fires if a ranged weapon is equipped (converting itself to a reload on an empty magazine,
  as `ranged.gd` always has), swings if not. G and F stay as the key equivalents, and clicks on
  UI never reach the trigger (`_unhandled_input`, unchanged).
- **A shambler's body is its own** — `shambler.json` now declares `body: {head: 25, torso: 60,
  legs: 40}` explicitly instead of silently inheriting `SimCombat.ZOMBIE_BODY` through an
  `extends` key that no loader has ever resolved. Same numbers; the trap is that retuning
  `base.json` would have moved every type except the one that ships.

#### The record, by system

What landed and what proved it, system by system (condensed from the retired backlog; the spec
links in the slice-scope table above are the authority on each). The open tails that used to end
these bullets moved to [what's left](#whats-left-in-milestone-2), so a bullet here is evidence,
not a to-do list:

- **World & map** — ~~the three location loot tables~~ **landed** (`godot:check:loot`): what a
  place yields is content now, not two hardcoded kits in `boot.gd`. `content/loot/tables.json`
  holds `residential`, `medical` and `military_cache` against a new `loot.schema.json`, each
  declaring location, danger, roll count, tier weights and per-entry quantity ranges — docs/12's
  "a loot table declares location type, resource weights, tier weights, and quantity ranges",
  which that document already claimed was JSON while the code had it in two `const` arrays.
  `SimBoot.place_loot` rolls them off a dedicated `lootTable` RNG stream (new randomness gets its
  own stream, so a table edit cannot shift the tier sequence for everything spawned afterwards),
  and the tier now comes from the *place* — a military cache rolls 1.000 above `scavenged` against
  a kitchen drawer's 0.141, where both used to be flat `scavenged`. The district gained a medical
  site so the third table is reachable in play. **Food spoilage** is now content too
  (`godot:m2:needs`, FOOD CONTENT): `SimNeeds.FOOD` was a hardcoded dictionary of three foods, and
  what a food restores, does to mood, how long it keeps and how likely it is to make you ill is a
  `food` block on the item base — docs/12's "spoilage rules are JSON", the other half of the loot
  move. The retired table is pinned **by value** in the gate, so the move is provably a change of
  where the numbers live and not of what they say. Presence of the block is what makes an item
  edible: `is_food` asks nothing else. Site depletion landed with container search — see Inventory
  below.
  ~~Round out the resources toward ~15 types~~ **landed**. Counting the scavenged raw materials
  and consumables actually placed in a loot table — `class` `material`/`consumable`, docs/12's
  taxonomy classes 1–4, kept apart from the seven currency-grade modification consumables above,
  which are its class 5 and tracked as their own line — put **13** resource types in the ground
  across the four shipped tables. Battery and Bolt of Cloth are the two docs/12 names residential
  and commercial had always promised (batteries, cloth) with no item behind them; adding both, to
  residential and commercial, brings the shipped count to **15**. `check_loot.gd` pins no resource
  count — LOOT SHAPE and LOCATIONS OK only assert every entry resolves and every table is placed —
  so this count is taken by hand off the tables, the honest measure where no gate keeps a number
  honest for you.
  ~~The annex as a stamped template~~ **landed** (`godot:check:buildings`, the chain's 33rd gate)
  — the worldgen arc's first slice. `SimTemplates.stamp` places a template's arrays at a
  handed-in origin through `apply_patch`'s exact clipping; the origin is still (38, 38), and the
  gate's migration lock proves the switch changed **no bytes** on the canonical seed at 64 and
  256 — with a one-tile-east restamp as the true negative that proves the lock can fail. The
  template's rect-relative anchors (gate_a, gate_b, player_start, well) land on the map as
  `map.anchors` with absent-sentinel accessors on `SimTileMap`, and `SimBoot.colony_start` is the
  anchor's first live production reader — the gate's reader lane proves the player boots onto the
  anchor, follows it when the template moves, and falls back only on an anchorless map. A
  `building` content type is registered and schema'd (`building.schema.json`, shallow-validated
  plus the gate's own depth checks) with deliberately **zero shipped entries** — the pool arrives
  with the placer that reads it, in the district-types piece above. `map.schema.json` gained the
  optional `anchors` block, and the edit is proven load-bearing: without it the frozen oracle's
  Ajv fails the content suite 9/9.
  ~~Anchors on the map, constants deleted~~ **landed** (`godot:m2:district`, ANCHORS lane) — the
  arc's second slice. `SimDirector.ANNEX`, `SimFortify.GATE_A/GATE_B` and every literal colony
  coordinate are gone; boot (well, station floors), director (edge legality, annex peak), jobs
  (guard post, corpse dump, the three annex scans), needs (stockpile tiles), fortify (gate scrap
  rules) and recruits (arrival, departure) read `map.anchors` through the `SimTileMap` accessors,
  sentinel-guarded so an anchorless map degrades to a no-op rather than siting the colony at a
  sentinel. Eight coordinate-pinning gates re-derive their windows from the booted world's
  anchors — same band values, different source — and the district gate's new ANCHORS lane pins
  the boot's anchors, their stability across two boots, and that an unstamped district reports
  none; it also asserts a water source stands on the well anchor, so the anchor has a reader
  rather than being a tenth dead socket. Behaviour is **bit-identical, measured**: the balance
  fast tier, director variance and side distribution re-run against a HEAD worktree matched line
  for line. The same slice found and fixed a gate that could not fail: `check_m2_fortify`'s
  scrap-choke probed two tiles off its 24-tile arena, refused as walls whatever the rule did —
  its arena now carries real gate anchors, a true positive and a control tile.
  ~~District types as data, and the generator rebuilt~~ **landed** (`godot:m2:district` lanes
  GENERATOR ROADS ENTERABLE DETERMINISM DISTRICT-DATA RESERVE; `godot:check:buildings`, SHIPPED
  POOL) — the arc's third slice, and the big one. `sim/map/worldgen.gd` replaces the fixed
  64-block lattice: streets drawn from district JSON and terminated at the declared edge
  connection points (the Milestone 3B road seam, live — each a paved opening in the border wall),
  parcels carved, buildings placed by weighted pick from an authored pool of **17 templates**
  (7 residential, 3 sheds, 2 civic, 5 commercial), thinned by density — **51 buildings** on the
  canonical 256 map (40–64 across twelve seeds, band pinned 40–70) and a real miniature district
  at 64 (7 canonical, floor pinned ≥ 4), so the gate boots stopped running on empty maps. Two
  types ship: `district.residential_suburb` (the default) and `district.town_center` (blocks
  12–20, streets 3 wide, commercial-heavy — 148 buildings at 256). Every generation pass draws
  from its own named stream (`worldgen.streets`/`parcels`/`buildings`/`occluders`/`terrain`, via
  `derive_seed` — the XOR salts are gone), and the gate pins byte-identical same-seed
  regeneration, different-seed divergence, and dressing that moves no walls. Every building's
  interior is reachable through its door from the street walk-in — the sandbox goal's "buildings
  are enterable", asserted: six bricked fixture shells report six unreachable rooms.
  `SAVE_VERSION` 16 → 17, because the same seed no longer regenerates the pre-rebuild ground.
  The balance fast tier, director variance, sides and harness pins were captured before and
  re-run after: **no band moved** — pacing is stream-driven; only where bodies stand changed
  (canonical-seed kills 2 → 5, one death, survival intact on all four seeds). The
  attention-field baseline for the wall-attenuation slice, measured on the new 256 map: 0 of
  4,096 cells solid under the all-16 rule, 6 under ≥ 8-of-16. Honest halves: `district.type` is
  read today only by the gate's district-data lane (its real reader is the loot piece), and
  `town_center` is reachable only by gates until the seeded-boot piece ships `--district`.
  ~~Loot sites generated per seed~~ **landed** (`godot:check:loot`, retargeted onto booted
  manifests) — the arc's fourth slice. A `worldgen.sites` pass draws each district's
  `lootProfile` (per-building rolls by tag, per-district counts for the rare tables, scaled by
  area — the 64 miniature honestly carries zero medical or military caches, pinned both
  directions) and records `map.sites`, an array of records the dressing passes protect and
  `SimBoot.place_loot` now reads; the patch-loot path is deleted. The canonical 256 suburb
  stands 71 sites (63 residential, 4 commercial, 1 medical, 1 military cache, the annex's 2);
  town center 176, commercial-heavy; 97–98% indoors by construction, the outdoor exceptions car
  boots on driveways. Most sites stand as containers (finite, searched-once — docs/12's site as
  it was meant to read). The annex's two authored sites became template-relative loot rows that
  `SimTemplates.stamp` converts and merges — the five stale absolute rows are gone.
  `loot.commercial` is authored at last (24 entries over existing items; `industrial` is now the
  one enum slot without a table, stated in the schema rather than implied). `check_loot` walks
  the booted manifests of both shipped district types — every authored location placed, every
  site resolving and standing open, containers counted against the manifest, site determinism
  with the dressing off — each lane sabotage-proven (a wall-buried site, an out-of-bounds roll,
  unstood containers, dropped template rows and a mistagged host each produce their named
  failure). The same slice re-pinned `_playable_boot` (ground ≥ 8 loose, ≥ 1 container, measured
  across six boot seeds) and fixed a jobs-gate haul lane that had silently assumed a district
  with no reachable loot. Balance did not move: the four fast-tier lines are byte-identical.
  ~~The annex sited per seed, survivability validated~~ **landed** (`godot:m2:district`, lanes
  SITING SURVIVABILITY RE-SITE) — the arc's fifth slice, the one that makes a seed a world.
  Siting is a pipeline pass on the `worldgen.annex` stream: ordered candidate lots
  (street-adjacent, border-margined so no wall loses its spawn pool — the worst side across
  eight tested seeds keeps 14 spawn tiles), one stamp site, and the survivability validator as
  the pipeline's final pass — docs/01's "no unwinnable starts" made mechanical: start open, both
  gates open and reachable from a road opening over walkable ground, ≥ 6 indoor station tiles,
  well open, a site of every placed loot table reachable from the gates. A failing clause
  advances to the next candidate, bounded and deterministic; a district failing every candidate
  errors loudly. The canonical seed sites at (21,13) on the 64 miniature and (108,107) at 256;
  eight seeds, eight distinct sites, every clause true. No tested seed re-sites naturally — the
  lane says so loudly, then exercises the path synthetically through a documented reject hook.
  The measured find: once the annex left the map's corner, `SimBoot.playable`'s wanderer scatter
  booted 2–7 shamblers **inside** the colony and wiped three of the four balance seeds by day 3
  — diagnosed with a throwaway driver, not theorised, and fixed by teaching the boot scatter the
  rule the director always had (refuse the annex rect, bounded re-roll). After: zero inside,
  survivors 2/2 on all four seeds, and a boot-lane assertion with a planted true negative.
  Re-pins live in the gates (`SITED_64`/`SITED_256`, the sited anchor expectations,
  `BUILDINGS_64_MIN` 4 → 3 measured across twelve seeds); balance, director and harness
  thresholds held.
  ~~The seeded sandbox boot~~ **landed** (`godot:check:worldgen`, the chain's 34th gate) — the
  arc's sixth slice, the one that hands the sandbox to a player. `--seed=N` and `--district=<id>`
  parse from the user args after `--` (the `--parity` precedent; a malformed value warns and
  boots the default rather than dying), and F2 leaves for another city: a fresh run on a
  presentation-side random seed, same district, through the one `_boot_world` path `_ready`
  itself uses — every per-run read model reset, the sim RNG ban untouched because the roll lives
  in `presentation/` and the chosen seed then determines everything downstream. The seed and
  district print on the M developer sheet only; the HUD digit ban holds unchanged. The gate
  boots **22 worlds** — ten seeds by both shipped types at 64, two at 256 — and judges every one
  sited, survivable, loot-resolving, no wanderer booted into the colony, then steps each 200
  ticks clean. Same-seed regeneration is byte-identical while the dressing stream moves 165
  tiles and no walls; the attention solid-cell count prints per witnessed district (11 counts,
  largest 0 — the wall-attenuation slice's regression witness, still reading the defect); four
  negatives say no (a density-0 district, a planted shambler in the colony, a bricked gate
  failing gates-open alone, an empty district refused loot); and the gate asserts its own
  runtime, 14.1 s of a 90 s budget. Closes slice 3's honest half: `town_center` is reachable in
  play through `--district`.
  ~~Walls attenuate noise: the ≥ 8-of-16 rule~~ **landed** (`godot:m2:district`, lane WALLS) —
  the arc's seventh slice, and the worst defect of the review sweep closed.
  `SimAttentionField.for_map` now marks a 4 m cell solid when at least half its subtiles are —
  `solid_subtiles * 2 >= subtiles`, exactly 8 of 16 on a full cell — and an edge cell judges
  only the tiles it really covers, so the out-of-bounds void no longer votes. On the shipped 256
  district the field goes from **0 solid cells to 9** of 4,096 (the lane prints the exact count;
  a blank floor map still marks none); the threshold is pinned exact — 8 solid marks the cell, 7
  does not, and an edge cell covering 4 real tiles marks at 2 and not at 1; and the dead-socket
  half is asserted live: noise behind a wall arrives at 159.40 against 172.00 across open
  ground, and `_uphill` refuses a solid neighbour its open twin steps into. The lane's own true
  negative was exercised by restoring the all-16 rule — the gate goes red naming the defect — so
  the regression cannot return silently. Balance, harness and director fast tiers re-run after
  the rule change: every pinned band held, no re-pin needed. `godot:check:worldgen`'s solid-cell
  witness now reads 9 at 256 where the slice before it recorded 0.
  ~~The ground drawn, and load-bearing~~ **landed** (`godot:m2:stance` lane GROUND;
  `godot:check:topdown` lane GROUND) — the arc's eighth slice. The surface layer draws as flat
  tints: `Palette.SURFACE_TINTS`, five entries indexed by `SimSurface.Surface` with paved bound
  to the exact floor colour the district already drew, resolved per tile by
  `Appearance.ground_colour` and used by `_draw_district` as the base fill under Floor, the Low
  inset and the Tree canopy — the same rects, different colours, no draw call added, and the
  art-style pick still the owner's. Sim side, `SimSurface.speed_on` stops being a dead socket:
  `SimWorld.surface_speed_at` multiplies into the command-path speed on the line between the
  stance rung and the modifier resolve, re-sampled per tick, returning exactly 1.0 on a world
  with no tilemap so the frozen parity fixtures cannot move (`R1_PARITY_OK`, byte-identical).
  The stance gate asserts metres covered, never mechanism: paved 6.3000 m equals the
  pre-surface arithmetic exactly, undergrowth 3.7800 m (×0.60), ratios compared against
  `speed_on` itself — sabotaged three ways (wiring removed, everybody slowed, table replaced by
  a literal) and each names its own failure. The topdown gate proves the draw path reads the
  surfaces array, that no two tints collide, and that a sixth surface without a colour fails
  rather than reading out of range. Balance and harness are byte-identical before and after —
  measured, with the sharper reason recorded: the wiring sits on the command path only
  `controlled` entities take, so the ground is a **player-only** mechanic today (debt entry
  above), noise deliberately does not follow it, and rubble is never placed by any pass (debt
  entry above).
  ~~Raiders: a hostile band at the gate~~ **landed** (`godot:m2:raiders`, the chain's 35th gate)
  — the arc's ninth slice and its close. Hostility is one component, `allegiance: {faction}`,
  read through `SimAllegiance.hostile`/`enemies_of`; substituting `enemies_of` for the hardcoded
  shambler query in `npc_combat`'s target pick is the whole of it, so colonists shoot raiders,
  raiders shoot colonists, both still fight zombies, and every existing line — range envelope,
  sightline refusal, holder preference — applies unchanged. Unmarked bodies default to `colony`,
  leaving every existing fixture standing. Zombies treat raiders as prey through the shared
  `is_person`, and raiders feed the noise and scent field like anybody. The director draws raids
  on the new `raid` stream: first day 8, 20% a night, bands of 2–4 landing on consecutive legal
  pool tiles, under `RAID_LIVE_CAP` 8 kept apart from the horde's budget, with `director.raid`
  published every night carrying its reason (rule 5). Two archetypes ship as content under
  `content/raiders/` with their own schema (oracle-invisible, the `content/loot/` precedent):
  `scav` — machete, weight 4 — and `gunhand` — pistol, 16 rounds, weight 1 — sharing one tint
  and the survivor glimpse radius, so a peripheral disc cannot say it is not one of yours. A
  dead raider drops its kit and despawns corpse-less (`components.query` does not check alive; a
  corpse would hold the cap forever). The gate runs nine lanes — archetypes, draw, grace,
  approach, blood, prey, seed, death, ledger — each with its true negative; the dead-socket
  proof is BLOOD's: two bodies identical but for the faction trade 0/0 blows. Balance measured,
  not theorised: every pre-existing counter identical on all four fast seeds, two seeds gained a
  raid and held 2/2, harness byte-identical, no re-pin; the worst legal band forced onto day 8
  costs one colonist of two on one seed of four, with three of the four raiders down on every
  seed — a real loss, not a wipe. Honest halves: a band that reaches the gate stands its ground
  — no withdrawal, so survivors accumulate against the cap across a long campaign — and there is
  no looting AI; both named, neither hidden.
- **Art** — the presentation is now **flat top-down** (docs/00 carries the reversal of the
  isometric reversal; docs/30 what it deleted): identity projection at zoom 64 (1 tile = 1 m =
  64×64 px), depth is `y`, walls are flat fills with a bevel rather than extruded, WASD is
  cardinal, and a peripheral glimpse is an anonymous disc with no sprite or facing — all pinned by
  the new `TOPDOWN_OK` gate (`check_topdown.gd`, in the `godot:m2` chain), each assertion of
  which fails against the old isometric maths. The five sprites (`survivor_mara`,
  `zombie_shambler`, three equip overlays, AI-generated) are regenerated on the **64×64
  centre-anchored canvas** — RimWorld proportions on a Zero Sievert palette — landed
  renderer-and-art in one commit, with `APPEARANCE_OK` now failing any sprite off that canvas
  (a stray 64×96 is a build failure, not a footnote). Wheel zoom steps the camera through
  {16, 32, 64, 128} px/m. What remains on this track — the style pick (waiting on the owner) and
  the screamer/bloater sprites and prop art queued behind it — is in
  [what's left](#whats-left-in-milestone-2), including which picks force a sprite regeneration.
  ~~Tiles and props drawn for real~~ **landed** (`godot:check:topdown` lanes BUILDINGS and PROPS,
  `godot:check:appearance` lane PROPS) — and it is the renderer half that landed, not the art half;
  which half is which is spelled out below. A building reads as a building now: `map.indoors` —
  the third array over the same grid, written by the generator and drawn by nothing — pulls an
  interior floor 0.62 of the way towards a board colour **over** the surface it stands on, so a
  shop floored on rubble and a house floored on paving stay two different floors while both read
  as inside from across the street; and the doorways in `map.buildings[].doors`, which are ordinary
  Floor tiles in a wall run with nothing in the tile array to tell them from the street, draw as
  worn boards between whichever jambs the neighbouring tiles actually have (the garage template's
  five-tile mouth therefore reads as a mouth, not as five doors). The door set is derived by a pure
  `Appearance.door_tiles` and cached in `main.gd` against the map object it came from — on the
  drawing node, where a static cache would be shared between the two worlds a gate boots. Props are
  visible: a `prop` content type (`prop.schema.json`, registered in `content_validator.gd`, six
  entries in `content/props/stations.json`) says how a container, a bed, a campfire and the well
  look; `presentation/appearance.gd`'s `PROP_KINDS` is the entire mapping from component to content
  id, including the one boolean per prop that changes the picture (searched, lit — two ids, not one
  entry with two tints); and `_draw_props` culls to the camera bounds **and** to the player's own
  sightline, so a cupboard on the far side of a wall is not visible through it. Content picks from
  four presentation-owned footprint primitives (box, slab, disc, ring) and the gate asserts every
  name the schema's enum allows is a shape `_draw_prop` actually draws; not one tint is in code
  (Palette's `prop` is the drab colour of a content mistake, and an unauthored id degrades to it).
  The load-bearing assertion is the dead-socket one: the PROPS lane boots a real district and fails
  if **anything** standing in it that is neither a body nor a carried item resolves no look — so a
  fifth kind of prop added without a `PROP_KINDS` entry is caught rather than standing there
  invisible, which is exactly the state all four of these were in until this slice. Shown to fail
  by deleting the bed row (entity 2 resolves nothing), by removing the `_draw_props()` call, and by
  setting `INDOOR_MIX` to 0. Measured cost: the prop pass's queries are **~34 µs a frame** over the
  47 containers of a booted 256 district, and everything else is culled to the viewport. **What did
  not ship, deliberately:** no art — every prop is a content-tinted shape, which is the supported
  fallback and not a stopgap, and prop art is now its own named piece in
  [what's left](#whats-left-in-milestone-2); the screamer and bloater sprites are their own piece
  and were not touched; corpses still draw as people, which is its own entry in the defect list.
  Same slice, same commit, a gate that could not fail: `check_appearance.gd`'s `_all_blocks` now
  walks **array-topped** content files, which it never did — so every item's appearance block,
  `equipSprite` and all, was invisible to the shape and key assertions that name it. Fixed, and
  shown to fail: an unknown key added to an item's appearance block now reds `APPEARANCE_OK`.
  Tuning pass on the same slice, `godot:check:topdown` lane WALL: the walls were drawing too big
  against everything else — a wall tile was a full tile of flat `#3b4048`, the brightest and
  largest thing on the screen, while the survivor standing beside it is a fraction of a tile, so a
  one-tile wall read as a block the size of the room behind it. The judgement was to keep the
  footprint and shrink the *bright part* of it rather than inset the fill or show floor at the
  base, because the sim blocks the whole tile and a visual that promises passage the sim refuses is
  worse than chunky walls: the tile is now filled with a darker **cap** (the top of the wall, seen
  from above) and only the edges that meet something walkable carry a lit **face** band 0.17 of a
  tile wide, so a wall run reads as one thick line with a lit edge instead of a row of bright
  blocks, and windows are drawn as masonry with the glass in the pane rather than as a tile of
  glass. The gate measures the thing that could go wrong in the other direction — both faces stay
  clear of the brightest ground the district can put against a wall (lit 0.369 against 0.220, in
  luminance) so every wall/floor boundary is a drawn line — and was shown to fail at a face share
  of 0.5, at a cap no darker than the fill, at a face that sinks into the ground, and with the
  exposed-edge test removed.
- **Survivors** — ~~Focus auto-allocation: NPCs spend their own web points~~ **landed**
  (`godot:m2:web`, lanes NPC / SURPLUS / REACH / DRIFT). What this list used to say — "the shallow
  web is landed; nobody but the player can walk it" — was wrong, and the correction is the
  interesting part. `SimSkills._autospend` has always been entity-agnostic and the gate's FOCUS
  lane has always spent *Mara's* points down the Medic path, so an NPC could walk the web from the
  day the web landed. Three real things were missing, all found by reading the code rather than the
  list:
  **Nobody ever chose.** Every survivor booted on `Auto`, `Auto` is one flat path, and nothing in
  the sim ever called `set_focus` — so six colonists bought the same five nodes in the same order
  whatever they had spent their lives doing, which is the opposite of docs/08's "a survivor's
  position on it is a record of what they survived". `SimSkills.suggest_focus` derives a focus from
  what has actually been earned and a new `skills.drift` system (ai phase, order −1) applies it on
  a day boundary; the rules are in
  [docs/30](30-decisions.md#focus-drift-what-moves-a-survivor-off-auto).
  **Points earned off the path were stranded for life.** `_autospend` walked `focusPaths[focus]`
  and nothing else, so an Auto colonist doing Construct banked Craft points against a path with no
  Craft node in it. A second pass now spends the leftovers on the cheapest affordable node in any
  region, ties by content order, and only ever with points of that node's own region — so it can
  never raid a path's savings, and a survivor drifts outward from the cheap centre the way docs/08
  describes.
  **Two nodes nobody in the game could ever own.** `ranged.calm` and `craft.scrap` appear in no
  `focusPaths` entry, and with no web screen there is no other way to buy a node: dead content
  sockets, the tenth and eleventh of this milestone. The surplus pass is what reaches them, and the
  REACH lane is the assertion that *something reads* every node — it probes all 15 with the focus
  that lists them, or Auto where none does, and names which mechanism bought each. Run against
  pre-slice code it says so out loud: `ranged.calm (Ranged, cost 2) is on no focus path and the
  surplus pass never buys it: nobody in the game can own it`, exit 1. It now prints
  `REACH OK 15 nodes: 13 by path, 2 by surplus ["ranged.calm", "craft.scrap"]`. The two orphans
  were deliberately **not** added to a path, because a path entry would make the lane green without
  the mechanism it exists to prove.
  Provenance is the third piece and it is one field: `set_focus` takes `by`, the `job.focus`
  command intake passes `"player"`, and drift refuses to move anybody whose `focusSetBy` reads
  `player` — docs/07's "never touch anything you've manually locked", made mechanical rather than
  promised. Every lane carries its negative: a Manual NPC given the same six jobs holds all six
  points and buys nothing; a probe with no points owns no nodes; the player-set twin stays on Auto
  through the same five Doctor jobs; one Medicine point plus a history that names medicine drifts
  while the same point with a history that names nothing does not; and the twin who has only ever
  rested stays on Auto, because Endurance votes for no focus. Four mutation runs confirm the lanes
  can fail: deleting the surplus loop reds SURPLUS (`5 Craft points bought no Craft node on a path
  that has none: nodes []`) and REACH (above); deleting the provenance guard reds with
  `drift overrode a player-set focus: Medic`; deleting the cadence guard reds with `drift ran twice
  in one day`; and writing the cadence as `tick % DAY_TICKS != 0` — the compressed-campaign trap —
  reds with `5 Doctor jobs and a day boundary left the NPC on Auto`, which is the whole reason the
  cadence is a day *number* compared against `driftDay` on the component.
  **Before and after, same seeds.** `godot:m2:jobs` is line-for-line identical. `godot:m2:harness`
  is identical on all six lines (turtle packets=3, noisy live=20/avenue=17/peak=45.00, knife 24/3,
  bow 14/3, pistol 20/4). The balance fast tier moved on exactly one of four seeds: **404, kills
  8(m8) → 7(m7) and deaths 1 → 0**; 20260805, 31337 and 90210 are unchanged in every field, and no
  band moved. Diagnosed rather than theorised, with a throwaway driver that replayed 404's
  compressed campaign printing every `job.focus_changed` and `entity.killed`: Mara kills five
  shamblers by day 3, drifts Auto → Fighter on the day-4 boundary, kills two more, and no colonist
  dies. A second balance run with the drift system disabled reproduced 404 = 7 kills, 0 deaths
  *exactly*, which puts the movement on the **surplus pass**, not on drift — Mara now owns
  `melee.tempo` and `melee.reach` (swing_speed ×1.04, melee_reach ×1.05), which under the old path
  pass she could never buy, and that changes her kill timing. Drift fired on 404 and moved no
  counter. The driver was deleted.
  **Honest halves.** `SimSkills.points` is *unspent* points, and treatment (`CLOSE_MEDICINE_FLOOR`)
  and modification (the Craft tier bias) read it as a skill level — so spending points now costs a
  little of that reading. The shift is bounded and one-directional: an Auto survivor reaches the
  same Medicine reading three earned points later than before, and the same Craft bias three later,
  after which every further point banks as it always did. That "unspent doubles as skill" oddity
  predates this slice and is left alone rather than quietly redefined. And `craft.scrap` is now
  ownable while the stat it moves, `repair_cost`, is resolved by nobody — see the defect list.
  The other three pieces on this row (fuller generation, trait conflict rules, the six-survivor
  checkpoint) are still in [what's left](#whats-left-in-milestone-2).
- **Survivors** — ~~Focus and the Manual learn line, on the work grid~~ **landed**
  (`godot:m2:autonomy`, lanes CYCLE / DRIFT / MANUAL HOLDS / BUY / CONTENT / VIEW / SAVE). The half
  above gave a survivor a focus and let them drift into it; this one gives the *player* the say,
  and it is deliberately **not** a new toggle. docs/07 already made the choice: with a Focus set a
  survivor auto-allocates their web, and "setting Focus to Manual gives full control of that one
  survivor's web". So the autonomy choice **is** Focus, and the work grid now draws it — one
  lowercase word at the end of each name, dim for the five self-managing values and amber for
  `manual`, the one that means the learning is in your hands. Clicking cycles it forward and
  right-clicking backward (so Manual is one click from Auto), and the click pushes `job.focus`
  through the command queue rather than calling `SimJobs.set_focus`. That word also closes a dead
  socket: `work_view` has delivered a `focus` field since the grid was written and nothing had ever
  drawn it — the twelfth of this milestone, and the first one found by looking for a place to put a
  feature rather than by a sweep.
  **The manual path is a real path, not a label.** A new `web.buy {entity, node}` command, consumed
  by `skills.intake` (input phase, order **15** — one after `jobs.intake` at 14, so a focus flip and
  a buy pushed in the same frame resolve the flip first and the buy is not refused for a survivor
  who is no longer on auto). Four refusals, each with its own reason on `web.refused`: `auto` (the
  survivor manages their own web), `unknown`, `owned`, `points`. The affordability check, the spend,
  the append and the modifier re-apply moved into one static `_buy` that the focus path, the surplus
  pass and the intake all call — `melee.gd`'s two-intakes argument, applied before the drift rather
  than after it.
  **The screen gets a shape from which a number cannot be computed.** `SimSkills.web_view` returns
  `{known:[prose], learnable:[{node, name}]}` and nothing else: no cost, no point total, no count.
  Affordability is boolean *by construction* — a node the survivor cannot pay for is simply absent
  from `learnable` — which is the condition-view pattern applied to progression, and the VIEW lane
  enforces it with a key allowlist plus a `[0-9]` scan over the serialised view, health-bar-ban
  style. The prose names are **content**: every node in `skill_web.json` gained a `name` ("a surer
  grip", "a healer's hands", "tape and patience"), because an id-to-phrase dictionary in the draw
  loop is exactly the pattern `godot:check:appearance` exists to keep out. Neither validator
  constrains that key — `godot:validate` is shallow and the frozen oracle's `CONTENT_TYPES` does not
  list `colony/` (both re-run here, both green) — so the CONTENT lane carries the assertion itself,
  with a scanner self-test so it can fail.
  **Choosing Auto is a handback.** The `job.focus` intake stamps `"player"` for every focus except
  `Auto`, which it stamps `"auto"`. Without that one exception a player who clicks round to Auto —
  the word that means "you decide" — would have locked that survivor out of drift for the rest of
  the run, irreversibly, with nothing on screen to say so. `set_priority`'s forced flip to Manual
  now writes `"player"` too, because hand-editing a grid cell is a person's choice by any reading.
  **And the UI's last queue bypass is gone.** `work_panel.gd` called `SimJobs.set_priority` directly
  and then re-pulled the view synchronously — the only place in the UI that reached into the sim and
  mutated it, which meant a grid edit never reached `commands.recorded` and R6's replay could not
  reproduce a run the player had steered. It is a `job.priority` command now; `main.gd` re-pulls the
  view every frame anyway, so the row updates on the tick the command lands.
  **Every lane carries its negative,** and two mutation runs confirm they fail. CYCLE asserts the
  command writes `player` *and* that `SimJobs.set_focus` — drift's own path — writes `auto`, so the
  seam is shown to distinguish its callers rather than to stamp one value; breaking the handback so
  Auto writes `"player"` reds it with `CYCLE: choosing Auto left setBy player, so the handback locks
  instead of releasing`. DRIFT proves the positive half first (an auto survivor with five Doctor
  jobs *does* move Auto → Medic) before asserting a player-set Fighter holds on the same evidence,
  because "never overrides the player" is vacuous if drift never fires. BUY provokes each of the
  four refusals and pairs every one with an unchanged component and no `web.learned`; deleting the
  Manual guard in `skills.intake` reds it with `BUY: buying surv.cook expected refusal "auto", got
  [... "reason": "owned"]` — the auto survivor had already spent the points itself, which is the
  interleaving the guard prevents. SAVE is the one that would otherwise fail silently: a player-set
  focus is put through a real `JSON.stringify`/`parse_string` round trip and the drift assertion run
  again on the far side, because `focusSetBy` is a String inside a component and a key lost in JSON
  re-enables drift over a player's choice with nothing to report it.
  **The honest half.** This is the *mechanism* of "the skill web screen", not the screen. What
  ships is one prose line per row — "knows a surer grip · long legs — could learn: tape and
  patience, plain grit" — with the learnable names clickable. The web drawn *as a web*, with regions
  and adjacency, is still in [what's left](#whats-left-in-milestone-2), annotated presentation-only.
  Nothing was measured about balance because nothing in the campaign path changed: the refactor into
  `_buy` is behaviour-identical (same order, same affordability, same modifier set), and the new
  intake consumes a command no headless driver pushes. Confirmed rather than assumed —
  `godot:m2:balance` prints the same four rows as the slice above (404 = 7 kills m7 / 0 deaths,
  20260805 = 5 kills / 1 death) and `godot:m2:harness` the same six lines (knife 24/3, bow 14/3,
  pistol 20/4).
  **One existing lane had to move, and it is worth saying which.** `check_m2_web.gd`'s DRIFT lane
  locked its survivor by pushing `job.focus` with focus `Auto` and asserting `focusSetBy == player` —
  an assertion of exactly the behaviour the handback rule reverses, and it went red here. The lane
  now locks with `Fighter`, which serves it better anyway: the five Doctor jobs it then runs argue
  *against* Fighter, so "did not move" is a refusal rather than a coincidence, where under `Auto`
  the survivor was being asked to stay on the focus drift starts from. The assertion the old line
  was reaching for — that a command stamps provenance — is unchanged and now has both halves in
  `godot:m2:autonomy`'s CYCLE lane.
- **Needs** — ~~raw and spoiled food carrying illness risk~~ **landed** (`godot:m2:needs`,
  ILLNESS). docs/04's food clause is "raw and spoiled food fills the bar but damages mood **and
  carries illness risk**"; only the mood half shipped, so raw food was a mood tax and nothing else
  and there was no mechanical reason to cook anything you were not enjoying. `illnessChance` is
  authored per food and multiplied by `SPOILED_ILLNESS_MUL` when the item has actually gone off, so
  one number moves both cases: measured 0.223 raw, 0.618 spoiled, 0.000 cooked over 400 meals each.
  A bout is bounded and self-limiting — it costs mood and 0.6× work, then passes and restores both
  — and is kept distinct from zombie infection *and* from sepsis, per the slice's own rule that
  bacterial infection stays separate. Nobody dies of it in Milestone 2, which is why it lives in
  `needs.gd` rather than growing a module. `iron_stomach` is full immunity rather than a reduction.
  ~~mood consequences: slower work, mistakes, refusing jobs, arguments~~ **landed**
  (`godot:m2:needs`, MOOD BANDS / MOOD WORK / ARGUMENTS). Mood previously had exactly one
  consequence and it was a cliff: at `-80` the survivor walked out, and everything between "fine"
  and "gone" did nothing — the opposite of docs/04's own summary, "a slow, sour decline where the
  colony stops functioning ... more frightening and more recoverable than a dramatic break".
  There are bands now — content / low / miserable / breaking, read through one canonical
  `SimNeeds.mood_band` so a boundary moves in one place — and each adds a consequence to the one
  below. Measured over a 200-tick window: **200 / 150 / 80** ticks of job progress at
  content / low / miserable, where the slowdown alone would be 100, so the remainder is mistakes.
  Mistakes (`job.mistake`) push progress *backwards* and belong to miserable and worse; sulks
  (`job.refused`) drop the current assignment and idle for 300 ticks. Arguments spread misery to
  the nearest survivor in earshot, accumulate to a **cap** and drain away — the cap is the design,
  because an unbounded source would let two miserable survivors drive each other past the leave
  threshold in minutes, which is the meltdown docs/04 rules out.
  Two findings worth keeping. Job progress ran through **seven copies** of the same two-line
  countdown, so a work-speed consequence had six chances to apply everywhere and quietly miss one;
  it is one `_progress` now. And the refusal was first hooked on `_pick`, where it fired **exactly
  never** in a booted colony — an NPC settles into a standing Guard job (`ticksLeft` 0, no
  completion) and never picks again. It hooks `_tick_one` instead, after the needs-seek branch, so
  a sulking survivor still eats and sleeps: this is a refusal to *work*, not to live.
  ~~the bathroom need, and a latrine to answer it~~ **landed** (`godot:m2:needs`, RELIEF /
  ACCIDENT / NPC RELIEF; `godot:m2:save`, NEEDS-ERA). New scope: the owner authorized it on
  2026-08-28 **against docs/04's own cut list**, which had said latrines were a scent emitter and
  nobody tracked a bladder — that clause is struck through in docs/04 rather than quietly deleted,
  and the need is written up beside the other six there. It is a **pool, not a band**, because
  that is how this file already treats a periodic bodily need: hunger, thirst and rest empty on a
  clock and are refilled by an act, temperature and hygiene are read off the world. Being a pool
  it inherits `pressure`, the seek ladder, the crossing events and the HUD prose for nothing.
  Measured at **1.3889 per 2000 ticks** against hunger's 0.3472 — twice a day at rest — and
  **eating and drinking speed it up** by a named 12 and 18 rather than a fraction of what they
  restore, so rebalancing the diet cannot silently rebalance this. The two literal
  `["hunger", "thirst", "rest"]` arrays in `work_mul` and `_apply_muls` are one `POOLS` constant
  now: a fourth pool would otherwise have joined one of them and missed the other, which is the
  seven-copies-of-the-countdown shape from the slice above.
  The latrine is a station like the well — position, marker component, factory in `needs.gd`,
  sited off the colony anchor by `SimBoot.latrine_tile` (outdoors, ≥ 4 tiles from the well, never
  the gate or the corpse dump, nearest-wins so one seed sites one latrine in one place). It
  carries docs/03's **scent 12**, so building one is comfort paid for in attention; the whole m2
  chain including the balance fast tier and director variance is green with it standing in the
  colony. **Nowhere to go is never damage** — the gate asserts no body part moved — it is one
  hygiene band (which brings its own mood cost and doubles scent) plus capped, decaying shame
  under `mood.soiled`, shaped like grief and arguments for the reason they are shaped that way.
  Measured: mood 0.0 → **−33.6** on one accident, shame capped at 24 and draining, and the same
  survivor relieved in time carries none of it.
  The dead-socket assertion is the one that matters: an NPC at 20 relief **walked itself to the
  latrine in 593 ticks with no player input**, and the same NPC in a colony with no latrine
  relieved nothing — a need only the player could answer would have been the tenth socket, and the
  one every colonist would hit twice a day. Prose is words only ("You need to go." at 80, "You
  badly need to go." below 30, "You're humiliated." after an accident, silent at 90). No new RNG
  stream, deliberately: the clock is deterministic and the accident is what happens when it runs
  out, so there was nothing to roll. The slice was built before the prop renderer landed and
  shipped its latrine undrawn; integration added the `prop.latrine` row to `PROP_KINDS` and
  `content/props/stations.json`, so it stands visible under the same PROPS lane as the well.
  **Not shipped:** nobody can build a *new* latrine, the colony boots with the one it is sited;
  and there is no downwind, because there is no wind until weather lands in Milestone 3.
  ~~a meal's mood never wearing off, a survivor who dies in bed keeping it, and `extremely_cold`
  being unreachable~~ **landed** (`godot:m2:needs`, MEAL MOOD / BED / COLD). Three review-sweep
  defects, one gate lane each; every lane has a true positive, a true negative and the assertion
  that something *reads* the mechanism, and all three lanes were shown to go red with the fix
  reverted before they were trusted green.
  **A meal's mood.** `eat` added a `mood` modifier with the fixed source `need.food` and nothing
  ever removed one, while shame, grief, arguments and illness all pair their `add` with a
  `remove_by_source` — thirty meals were thirty summing, permanent entries. It is bounded twice
  now, in `_fall_ill`'s shape: one modifier from one source, replaced rather than stacked, and
  expiring on `MEAL_MOOD_TICKS` (36000 — three in-game hours, comfortably shorter than the gap
  between meals) through a `need.mealMood` system that publishes `mood.mealFaded`. Measured: one
  cooked meal **8.0**, thirty cooked meals **8.0** where the old code carried 100.0, and nothing
  left once the clock runs out. The read: a spoiled meal drops `mood_band` from `content` to
  `low` — which is what every consequence in jobs.gd matches on — and the band comes back when the
  meal fades.
  **The bed.** `_make_corpse` stripped `sleeping` directly instead of going through
  `SimNeeds._wake`, the one place that clears a bed's `occupiedBy`, so a survivor who died in bed
  held it for the rest of the run and `nearest_bed`'s free-only scan — which is what jobs.gd's
  Rest asks — never offered it to anybody again. Both doors are shut: `_make_corpse`, and
  `_turn_with_kit`, where the despawn takes the sleeper's components and leaves the *bed* pointing
  at a dead id. The lane kills through `entity.killed` + `finish_death` (the funnel starvation
  already uses) rather than `attack.connected`, deliberately: that publishes into `need.wake-hit`,
  which would wake them and free the bed for reasons that have nothing to do with the fix.
  **The deep cold.** `_tick_temperature` could write `comfortable`, `very_cold` and
  `a_little_cold` and nothing else, so `extremely_cold` — the only band `band_pressure` calls
  "hard", with its own HUD line and its own branch in jobs.gd — was unreachable and every branch
  keyed to it was dead. Cold is a **dose** now, which is the order docs/04 lists its consequences
  in: a survivor outdoors at night with no fire keeps a `coldSinceTick`, and `EXPOSURE_TICKS`
  (18000 — an hour and a half, a quarter of the night) later the band deepens. Any warmth clears
  the clock, so the deep band is the price of a sustained night out rather than a moment of one,
  and the cloth wrap's one-band shift is worth a real hour and a half. `work_mul` and
  `_apply_muls` now read the band through `band_pressure` instead of naming `very_cold` in a list
  — a list is exactly where the band went missing — so the hard band costs −20 mood against
  `very_cold`'s −10 rather than the nothing it would otherwise have cost. The HUD line is its own
  words ("You're freezing."); it read identically to `very_cold`, which would have made the band
  invisible in play. The read: an `extremely_cold` NPC drops a job mid-action through jobs.gd's
  `hard` branch and a `very_cold` one works on to the end of it.
  ~~Sleep quality~~ **landed** (`godot:m2:needs`, SLEEP / SLEEP FACTORS / PAIN SLEEP / SLEEP
  MOOD) — the Medicine group's own blocked-on-itself item. docs/05 lists sleep last among what
  pain degrades ("accuracy, work speed, mood, sleep quality") and there was no sleep-quality value
  for it to degrade; `SimNeeds.sleep_quality` is that value now, derived every sleeping tick from
  the same discipline `SimWounds.pain_of` already keeps rather than stored as truth. Of docs/04's
  factor list — "bed quality, warmth, darkness, quiet, and safety" — what the sim already tracks a
  state for is a bed, a temperature band, felt pain and the noise field; darkness and safety are
  not modelled by anything today and are not faked here, so bed quality's own authored property
  moved to what's left (Gear group) rather than being invented alongside this. **The calibration
  constraint:** a survivor in a bed, indoors, comfortable, unwounded, in quiet still restores
  exactly the pre-slice 100 a night — measured, so a typical good night is unchanged and only a
  degraded one moves. A bad night is floored at `SLEEP_QUALITY_FLOOR` (0.2, an arbitrary-looking
  number recorded in docs/30) rather than allowed toward zero — the same "never a dead night"
  shape pain's own floor keeps — so the worst measured night restored 20 against a good night's
  100, never nothing. Each factor moves the number alone, measured in isolation: a rough bed
  0.5000, `very_cold` 0.7500, a deep wound 0.8200, a noise source beside the sleeper 0.8000,
  against a perfect-night baseline of 1.0000; a light-sleeper trait multiplies the *penalties*
  rather than the total, so a light sleeper in a quiet room sleeps exactly as well as anybody
  else and only pays more when something actually disturbs them. Painkillers buy a night back
  through the same suppressed `pain_of` a medic already reads: measured, an unwounded control and
  a dosed Scratch both read 1.0000 against an undosed 0.9680. A bad night costs mood at `_wake`,
  `_apply_grief`'s shape exactly — one modifier from one source (`mood.sleep`, deliberately kept
  out of `NEED_SOURCES` for the reason `SOIL_SOURCE` is, so `_apply_muls` cannot strip a cost it
  did not cause), capped, and drained on the mood tick: measured, one rough night cost 8.00 named
  in `explain`, three in a row capped at 16.00 in exactly one modifier (never three summed ones),
  and decay ticks alone returned mood to baseline. `jobs.gd`'s Rest needed no change — it already
  stops at `rest >= 80`, so a poor night simply keeps a survivor in bed longer rather than needing
  a new stopping rule — and `condition.gd` is untouched, so the health-bar ban's key allowlist did
  not move. The dead-socket half: `hud_clause` reads a quality word grown out of the old
  `slept: "bed"/"rough"` field (now `rested`/`broken`/`barely_slept`, silent on `rested` the way
  every other band in this file already is) and, isolated from the rest pool's own "You're
  exhausted" line, says a different sentence after a bad night than a good one with no digit in
  either; and the smaller rest pool a bad night leaves behind measurably drops `work_mul` the next
  morning (1.000 → 0.850) on the pool alone, temperature band cleared first so it cannot be doing
  that instead. All four lanes were shown to go red with `sleep_quality` reverted to a constant
  1.0 before being trusted green.
- **Attention leftovers** — ~~the sim half of last-known-position memory~~ and
  ~~director-varied nights~~ **both landed** (`godot:m2:sight`, MEMORY / EXPIRY / PROSE;
  `godot:m2:director`, VARIANCE / BOUNDS / SIDES). docs/28 rated this
  "Half": the renderer faded a mark where a body was last drawn and the simulation had no
  per-observer memory at all, so a colonist forgot a shambler the instant a wall intervened and
  no prose could say otherwise. `SimSightings` keeps one record per observer per body — a position
  and a tick, never a track — with a two-minute horizon and three staleness bands. The prose
  degrades in its **counting** as well as its clock ("two of them, east, a moment ago" becomes
  "a few of them, east, a while ago"), which is docs/28's degradation and clause 4's refusal to
  hand out unearned precision in the same table; there is no distance in it, because a remembered
  distance is exactly the number nobody has. Watching something fall erases its record while a
  kill out of sight leaves it standing, and that asymmetry is the model in one line. The renderer
  now reads the sim's memory rather than keeping its own dictionary — a mark on the ground and a
  colonist's decision have to be the same recollection.
  Two findings worth keeping. **Only the player had eyes**: `boot.playable` set one `observer` and
  nothing else got any, so every per-observer question about a colonist was being asked about a
  view that did not exist — the sixth dead socket this milestone, and `SimSurvivors.give_eyes` is
  now the one place a survivor gets a view and a memory. And the memory is stored as an **Array of
  records rather than a Dictionary keyed by entity**, because a component round-trips through JSON
  on every save and JSON has no integer keys.
  **Varied nights** is the other half of the same bullet and a bigger change than it sounds. docs/17
  says "the director doesn't pick a number for the night" — and it was picking a number: `size`
  fell straight out of the day, the live count, colony power and the week's noise peak, none of
  which the seed moves. The balance harness had been reporting **the same 3 sieges and 7 quiet
  nights on every seed**, and check_m2_balance.gd's own comment already said the seed reached
  nothing but the edge pick. A night is **drawn** from a weighted table now, conditioned on
  strain: strain decides how hard the week leans, not what tonight is. Measured over 60 nights at
  one seed: **quiet 21 / probe 16 / press 13 / siege 10**, longest siege run 2, longest quiet run
  3. The shipped fast tier now varies seed to seed — sieges **2 / 1 / 3 / 2** where it was
  3 / 4 / 3 / 3.
  docs/17 rule 4's variance floor and ceiling are mechanical: `MAX_CONSECUTIVE_SIEGE` steps a
  third siege down to a press, and the quiet floor steps a fourth quiet night up to a probe. The
  floor **already existed and was unreachable** — `if size == 0 and nightsSinceQuiet >= …` sat
  after an unconditional `size = BASE_SIZE`, so it was written, gated and dead. Rule 5 ("never
  rubber-band silently") is why every dusk publishes `director.night {shape, drawn, size, side,
  reason}`; `drawn` is what lets a gate tell a bound that fired from a night that never tested it.
  Packets also **arrive where the field points** rather than always from the south: the noise
  along each district edge picks the side, and a silent district gets a seeded pick rather than a
  default. Measured across 60 nights: all four sides, 12 / 10 / 8 / 9.
  Two findings. `entities.despawn` flips an alive bit and `components.query` does not consult it,
  so a harness that despawned bodies without removing the component left every one of them in the
  director's live count — which read as "56 quiet nights in a row". And **`SimDirector.snapshot_of`
  was called by nothing**: `world.gd` hand-listed three director keys, so `lullFromTick` and
  `weekPeakNoise` were written every night and dropped by every save. `world.gd` now copies the
  director's scalars generically, so a future dial is saved without world.gd learning what it is.
- **Health & injury** — ~~the remaining injury types (fracture, sprain, burn, concussion)~~
  **landed** (`godot:m2:wounds`, KINDS and CAUSES). docs/05's injury table has nine rows and three
  shipped, as *severities* of one bleeding wound. The four remaining are structurally different —
  not primarily bleeding, recovery that does not track severity, and two of them impairing far
  beyond their severity band — so `kind` stopped being a label and became a table. Everything a
  kind changes is declared in one `WOUND_KINDS` row rather than as four `if kind == …` branches
  across `append_wound`, the recovery tick, the impairment pass and the sepsis roll, which is how
  the bleed rate and the clot clock would end up disagreeing about what a fracture is.
  Measured: the three closed kinds bleed **0.0000** against a cut's 8.0000 at the same severity;
  recovery is the kind's own figure (sprain 5d < deep cut 16d < fracture **42d**) with kinds that
  declare none still falling through to the severity table; a fractured leg moves at 0.880 against
  a scratched leg's 0.960 *at identical severity*, which is "near-total loss of the part" made
  mechanical; a concussion costs reactions where an ordinary head cut costs nothing; and a closed
  injury cannot go septic at all while a burn (0.432) is twice a cut (0.216).
  **Every kind has one reachable cause**, from docs/05's own Cause column, and none of them is a
  new subsystem: a deep head hit concusses (a graze does not), 21 of 50 deep limb hits fractured
  and 0 of 50 light ones, **cauterisation burns** — `infection.gd` had published
  `injury.sustained/burn` since cauterise was written and nothing listened, so searing a bite left
  no mark on the arm it seared — and 22 of 100 zero-stamina sprint collapses sprained a leg.
  **Named rather than faked:** docs/05's other causes (falls, fence climbs, crush, fire) need
  systems that do not exist, and a concussion's *perception* loss has no stat to attach to — vision
  is a shadowcast with no modifier seam — so only the reaction half is wired. Adding a stat nothing
  reads so the row could list three keys would be a modifier that looks wired and is not.
  ~~Continuous pain and exhaustion~~ **landed** (`godot:m2:wounds`, PAIN / PAINKILLERS /
  EXHAUSTION), which completes docs/05's set of four continuous conditions — blood loss shipped,
  sepsis landed above, and these were the remaining two. **Pain did not exist at all**, and
  `item.painkillers.blister` was in two loot tables and Mara's starting kit with no code reading it
  (the fifth dead socket this run). **Exhaustion was half-wired**: stamina emptiness reached melee
  and nothing else, so an exhausted survivor swung badly and shot, worked and felt exactly as well
  as a rested one — docs/04 lists all four.
  Pain is **derived, never stored**: a pure function of the wounds carried, so it cannot drift from
  them and needs nothing in the save file. It sums (one laceration 0.220, three 0.660), scales with
  severity (deep 0.450) and kind (burn 0.330 against a cut's 0.220), and a septic wound throbs
  (0.330). It costs accuracy, swing speed, mood and work speed. Painkillers **suppress without
  healing** — the felt pain drops while the raw pain, the wound list and the recovery clock are all
  untouched, and it wears back off to exactly what it was, which is docs/05's "way to get someone
  killed because they didn't notice how hurt they were". Exhaustion now reaches all four: swing
  0.400, aim 0.500, mood −8.0 and work 0.652 on an empty tank, with the mood cost deliberately kept
  clear of the miserable band so an ordinary hard day does not start sulks and arguments.
  ~~The full treatment ladder: clean, then close, then rest~~ **landed** (`godot:m2:treatment`,
  CLEAN SEPSIS / CLEAN SUPPLY / CLOSE / CLOSE REFUSALS / SHORTCUT / LADDER SUPPLY / HELD LADDER /
  LADDER KEY / SELF-CLEAN / REOPEN ERASE / LADDER CONTENT, and the extended DETERMINISM).
  **Two rungs were added, not three**: `SimWounds._is_recovering` — fed and not exerting — has been
  the rest rung since Slice 3 and is gated by `godot:m2:recovery`, so the record says so rather than
  claiming a verb for it. `clean` and `close` are two more entries in `CHANNEL_VERBS` and nothing
  else: no second state machine, and every interrupt, the pin, the per-tick re-check and the whole
  R1–R10 arbitration are inherited unchanged. `jobs._do_doctor` still goes through
  `SimWounds.dress_worst` and was not touched.
  **Cleaning was the missing sepsis factor.** `sepsis_chance`'s own comment said "the four factors
  docs/05 names" and docs/05 names five — "whether it was cleaned" had no verb behind it and no
  term in the arithmetic, which is the same socket shape the roll itself was written to close.
  Measured over 240 seeded dusk rolls at fixed hygiene and Medicine 0: **55/240 septic uncleaned
  against 25/240 cleaned with antiseptic**, and the water grade in between at 45/240, so rinsing a
  wound with drinking water is worth something and worth less. Neither end is absolute — the
  uncleaned control goes septic and the cleaned run still does, floored by `SEPSIS_CLEAN_MIN_MUL`
  for the reason `SEPSIS_MIN_MUL` floors the skill term.
  **Closing buys speed and holds it shut**, through the two readers that already existed: a sutured
  wound reached `wound.closed` in **5 earned ticks against an unsutured wound's 10**, and a fresh
  sutured deep wound held under a sprint (0.0000 blood) that tore the identical unsutured one open
  (3.9800). The part's integrity regen carries the same multiplier as the wound's earned tick, so
  suturing cannot leave a limb permanently weaker by closing its own wound early.
  **The shortcut stays legal and stays expensive**: bandaging an uncleaned wound succeeds and stops
  the bleed, at 31/240 septic against clean-then-dress's 17/240 (docs/30 for why refusing it would
  be the wrong rule). `close` refuses a wound that is still bleeding ("still-bleeding") and a deep
  wound below Medicine 2 ("unskilled") while a novice may still close a laceration — the floor is
  deep-wound-only.
  **Two dead sockets closed by assertion rather than by hope.** `treatment.self-aid` and
  `_nearest_bleeding` widened from bleeding-only to "any rung this body wants", so an NPC with a
  dirty wound and antiseptic in their pack opens a clean channel with no player input (0.216000 →
  0.097200 chance) — left as it was, both verbs would have been player-only on the day they landed.
  And `_reopen_from_overwork` now erases `cleaned`/`cleanTier` beside the `pressedTicks` it already
  erased: a torn wound reprices **exactly** as one nobody ever cleaned, which is asserted to seven
  decimals rather than directionally. Reverting either term was checked to turn its row red.
  **Calibration: the uninvested paths are unchanged.** `SEPSIS_CLEAN_MUL["none"]` is 1.0 and an
  unsutured wound's earned tick is still literally `+ 1`, and the gate pins both — an uncleaned
  wound's chance is bit-identical to the pre-change expression, and an unsutured wound still needs
  its full ten earned ticks. So `godot:m2:balance` was the only balance evidence this needed; the
  campaign-scale sepsis-incidence measurement rides with the deferred full balance grid, unchanged
  by this slice because a colony that invests nothing plays exactly as it did.
  Content: `cleanTier` and `closeKind` are flat scalars under enums (the shallow validator only
  checks those), `item.water.bottle` gains `cleanTier: water` — `SimNeeds.use_item` matches on
  `baseId`, so drinking is untouched — and `item.antiseptic.bottle` and `item.suture.kit` are new
  and in the medical table, antiseptic thinly in residential too.
  This system's open tails (supply quality tiers, skill-scaled diagnosis and the condition view's
  words for a cleaned or sutured wound, the splint, permanent conditions, sleep quality) are in
  [what's left](#whats-left-in-milestone-2).
  ~~Bacterial infection kept distinct from zombie infection (sepsis)~~ **landed**
  (`godot:m2:wounds`, SEPSIS and SEPSIS COST). This was a socket, not a gap: `needs.gd` published
  `sepsis.checked` with a hygiene multiplier every dusk and **nothing subscribed to it**, so
  `sepsis_mul` was gated, correct, and reached no wound. The roll now lives in `wounds.gd` (which
  owns the record and the recovery clock sepsis has to block) and takes all four factors docs/05
  names in one expression, so no caller can apply three of them — measured severity 0.018 scratch
  → 0.122 deep, hygiene 0.059 clean → 0.154 filthy, the full dressing chain 0.021 sterile < 0.059
  cloth < 0.094 dirty < 0.111 bare (an undressed wound worse than any dressing, which is what makes
  a bad one better than none), and Medicine 0.171 → 0.090, floored so a good medic never makes a
  dirty wound safe.
  Both consequences docs/05 draws from the separation are real. **Antibiotics are pulled in two
  directions**: `use_antibiotics` now accepts a septic survivor with no bite exposure at all, out
  of the same finite stock and through the same spend path, so every ordinary wound spends the
  infection budget — and a player cannot tell sepsis from a bite by which button lit up. **The
  ambiguity is preserved**: the HUD clause is "You're feverish, and it isn't getting better", which
  is deliberately the same word zombie infection's early stages use and says nothing about which it
  is.
  **Scoped deliberately:** sepsis is debilitating and permanent-until-treated, and **not directly
  lethal**. A septic wound stops healing entirely and clears only to antibiotics. That produces the
  budget pull without adding a death path to a lethality model whose balance was, when this landed,
  the thing standing between `GRABS_ENABLED` and its flip. The flip has since landed (the flag
  record) and the scoping stands unchanged: making sepsis kill is a balance decision with a
  measurement attached, not a detail to slip in beside the mechanic, and it remains the owner's.
  ~~Sepsis's only cure is unreachable in play~~ **half landed** (`godot:check:respond`,
  `RESPOND_OK`). `infection.respond` had been a live command handler nothing pushed, which meant
  antibiotics — the one thing that clears sepsis, and the only answer to a bite that is not a
  saw — could not be reached by a player at the moment the `GRABS_ENABLED` flip made both
  ordinary. **The half that shipped is antibiotics**, as a clickable word under the condition
  readout on the Tab body screen, in work_panel.gd's idiom: the sim owns what is offered
  (`SimTreatment.response_view`, the companion to `options_for`), a response you can afford is
  simply *there* in the accent colour, one you cannot is absent rather than greyed, and a click
  pushes `infection.respond` through the command queue like every other player act. **The half
  that did not** is the other four verbs, each left out for its own reason and named in
  [what's left](#whats-left-in-milestone-2): `quarantine` is a no-op, and `cauterize`, `amputate`
  and `put_down` need a patient-and-part selection surface that does not exist.
  **The presence rule is the honesty core**, and it is two questions the player could already
  answer from their own screen: is there a course in the pack (`SimInfection.carries_course`,
  which goes through the same `_find_course` the spend does, so the word cannot promise what the
  sim would refuse), and is anything showing that a course might answer
  (`SimInfection.symptom_of`). The second reads the diagnosis label and the fever clause — the two
  things the HUD already prints — and never `transmitted`, never `is_septic`: a latent bite reads
  "clear" and is offered nothing, so **suspicion dosing has no surface, deliberately**, and a
  fever from either cause offers the identical word. `use_antibiotics`' own comment is the rule
  being obeyed: the player must not be able to tell sepsis from a bite by which button lights up.
  **The free-course hole closed with it.** `use_antibiotics`' zombie-infection path kept its own
  copy of the spend, fell through a `pass` when the pack was empty ("still allow course without
  item in tests") and recorded the course anyway — so a bitten survivor dosed for free while the
  sepsis path beside it had always refused, and the finite uncraftable supply the whole docs/05
  trade rests on was finite only for whoever had not been bitten. It now spends through the one
  `_spend_one_course` and refuses `no-antibiotics`, which is the word the sepsis path already
  used; a refusal that differed by cause would leak precisely what the button lighting up would
  have leaked. No gate lane had relied on the itemless course (the two that spend one already
  granted the item, and the router lane runs on a world with no exposure at all), so nothing was
  weakened to accommodate the fix.
  Six lanes, each with its true negative: TRUE POSITIVE (a feverish survivor carrying a stack of
  two is offered the word; pushing the command the click builds and stepping once spends exactly
  one, publishes `antibiotics.used`, clears the sepsis, and the word goes with the fever —
  asserted after the step, because handlers run at drain); NO NEED (the same full pack with
  nothing wrong offers nothing, and the same world one fever later offers the word); NO SUPPLY
  (both stocks — a symptomatic bite and a fever — offer nothing with an empty pack, and a forced
  push is refused `no-antibiotics` with nothing spent and **no course recorded**, both with the
  same word, and the same push with a course in the pack doses); NO LEAK (the rows are a function
  of the *stage* alone: two worlds identical but for `transmitted` produce byte-identical views at
  Latent and at Onset, latent offers nothing and onset offers the word); PROSE (no digit in any
  offered row, check_hud.gd's scanner and its three seeded catches); DEAD SOCKET (the reach chain
  read out of `ui/inventory_panel.gd` — `_draw` calls `_draw_responses`, which resolves
  `response_view` and turns its rows into click rects, which `_press_at` reads to push
  `infection.respond` — plus the verb being one the router answers). NO SUPPLY is the fix's own
  true negative and was **run red before the fix and green after**: with the `pass` restored it
  reports "a symptomatic bite with nothing in the pack was dosed anyway".
- **Combat** — ~~firing at a remembered position (and what it costs)~~ **landed**
  (`godot:m2:sight`, SIGHT / NO-EYES / RECALL-FIRE), together with the rule it depends on. docs/09
  says aiming "inherits visibility wholesale" and `_fire_shot` inherited none of it — a shot was a
  cone test against live positions, so a round went through a wall and connected.
  `SimRanged.can_target` is the one refusal, asked by the shot and by
  `npc_combat._nearest_threat`, which is where npc_combat.gd's own note said it should land
  rather than being answered twice. It tests
  **geometry, not the facing arc** (`SimVisibility.line_of_sight`): a wall stops a bullet and
  peripheral vision does not, and an arc test would have left an NPC unable to swing at something
  standing behind it. It is **permissive for a shooter with no `observer` at all**, which is what
  keeps every pre-sightlines ranged fixture honest instead of silently missing — NO-EYES is that
  assertion. Firing at a remembered position then costs exactly what docs/09 prices it at and not
  a tick more, because the noise, the flash and the spent round all precede the hit test already;
  the only thing added is the *decision*, which the player always had by pointing and pressing F
  and an NPC now takes when nothing is visible and the memory is still inside the Recent band.
  **Measured cost to the colony: none, and the measurement is weaker than it looks.** The shipped
  fast tier is unchanged seed for seed (0 / 6 / 0 / 1 kills, 2/2 survivors on all four) after
  giving every colonist eyes and refusing shots through walls — but every one of those kills is
  melee (`m6/r0`), so the tier records that the sightline rule cost nothing, not that it was
  exercised. A ranged reading needs the full grid, which is still deferred.
  ~~Jamming on degraded
  weapons~~ **landed** (`godot:m2:ranged`, JAM and CLEAR). Condition already scaled melee and
  ranged damage, so a pistol at 10% was a slightly weaker pistol rather than one you could not
  trust; docs/09 asks for the other half — "degraded firearms jam, and clearing a jam takes longer
  than a reload". The chance is **not authored**: `SimItems.JAM_CHANCE_BY_BAND` is keyed off
  `condition_band`, the same function that produces the word the inventory screen shows, so a
  weapon the player is told is "failing" cannot be one that never jams. Measured 0.130 over 400
  trigger pulls against the table's 0.120, with a sound pistol at 0.000. `jams` is a **content
  flag** on the ranged block, not inferred from having a magazine — docs/09 and docs/11's Gun Oil
  both say *firearms*, and a bow at 5% condition jams at 0.000, which is the negative that keeps
  the flag load-bearing. A jam costs **time only**: the stuck round is not spent (it comes out
  during the clear), the weapon returns to Idle rather than resuming the shot, and clearing takes
  `CLEAR_JAM_MULTIPLIER` × the weapon's *own* reload — a multiple rather than a constant, so
  "longer than a reload" stays true if a reload time is ever retuned. Measured 80 ticks against a
  40-tick reload.
- **Items** — ~~attachments gaining a reader~~ **landed** (`godot:m2:attach`); the repair economy
  around `SimItems.repair_item` moved to [what's left](#whats-left-in-milestone-2). The previous
  note here was
  **wrong in an instructive way**: it said no content declared `slots` either, and every weapon
  base has declared them since the item pipeline landed — what was missing was anything that fits
  into one and anything that reads one. Five attachment items ship, findable in the residential
  and military-cache tables (docs/10: "found, not crafted"), and `SimAttachments` is the reader.
  **An attachment declares what it multiplies** — `{"noise": 0.22, "cone": 1.2}` is a suppressor —
  so nothing in the module names an optic, a magazine or a suppressor, and a new kind is a data
  edit. Multipliers rather than adders, so two attachments compose the same way in either order.
  Measured: pistol noise **180 → 39.6** against docs/09's "suppressed firearm ~40", the aim cone
  **0.4225 → 0.5070** with the suppressor's accuracy cost and **→ 0.2957** with a red dot, and a
  magazine **8 → 12**. It moves: the same suppressor detached and refitted to a second pistol
  gives the identical 39.6, which is the "your gems come with you" clause the whole mechanism
  exists for. `cone` is a new **weapon** property rather than a use of the `ranged_accuracy`
  stat, because that stat resolves on the entity and an optic is a property of the gun.
  **Deliberately not in this slice**, and named rather than left to look finished: attachments do
  not wear (docs/10's "suppressors wear out fast" is the condition half, and they have no
  condition of their own yet), an optic is not yet useless in the dark, a weapon light is not yet
  an attention emitter, and there is no inventory screen for fitting one — the `item.attach` /
  `item.detach` commands are the reach, on the `item.modify` precedent. All four are named pieces
  in [what's left](#whats-left-in-milestone-2). **Continuous condition-degradation effects** are now essentially closed:
  `condition_factor` already scaled melee damage and speed and ranged damage, and jamming (above)
  was the missing piece docs/10's table called for.
  ~~`spawn_item` draining the whole event queue mid-tick~~ **fixed** (`godot:m2:upkeep`,
  SPAWN-DELIVER) — the worst-first defect on the review sweep's list. The synchrony the drain
  bought is real — a just-spawned pack must carry its container grid before the caller's next
  line stows into it — but `publish()` then `drain()` bought it by flushing every event other
  systems had queued that tick, and since some spawns hang on an RNG roll (`ranged.gd`'s
  recovered arrow, spawned *after* its own `attack.connected` was queued), **which** handlers ran
  early was not stable between two runs differing in an unrelated draw. The bus gained
  `deliver()`: one event, dispatched to its subscribers now, queue untouched, still entering the
  record. The module decoupling stands — items still does not import inventory, and with the
  inventory module unregistered a pack is still simply an item with no grid. The frozen oracle
  keeps its own drain (`items.ts`, frozen); parity is unaffected because the parity snapshot
  carries no event ordering. The gate lane holds a queued sentinel through a spawn, requires the
  grid attached synchronously and the event in the record, and proves its probe can fail by
  firing it with a real `drain()`; the old behaviour was re-applied against the lane and went
  red before the fix went in.
- **Inventory** — ~~searching world containers (a car boot, a cupboard)~~ and ~~site
  depletion~~ **both landed** (`godot:check:loot`, CONTAINER and CONTAINER SITES). A map loot site
  that declares `container` is not scattered at boot: `SimContainers` stands a `searchable` there
  holding the same table, and it rolls when somebody opens it — the same `SimLoot` roller and the
  same `lootTable` stream, so loose tins and the cupboard they were in draw from one distribution.
  Reached through the ordinary `use.context` key, after loose items and before everything else, so
  one key empties the cupboard and then picks the contents up. Depletion is that `searched` is set
  once and cleared by nothing, which is docs/12's cut of respawn timers made mechanical rather
  than merely intended; a second search refuses `already-searched`, distinguished from
  `nothing-here` because those mean different things to somebody deciding whether a building is
  worth the walk. The district ships a cupboard, a car boot and a supply locker. Searching is
  **instant, not a channel** — recorded as a decision in the module header, with fortify's channel
  named as the template if it ever needs to be interruptible. A container is drawn now, searched
  or not — the Art track's tile-and-prop piece, recorded there. The one open tail here, carried
  weight loudening footsteps, is in [what's left](#whats-left-in-milestone-2).
- **Modification** — ~~Duct Tape (reroll an affix), Scrap Kit (add an affix), skill-weighted
  outcomes, failure that consumes and damages~~ **landed** (`godot:check:mods`). Which operation a
  consumable performs and against which item classes is **content** — a `modification:
  {operation, appliesTo}` block on the item base, exactly as docs/11's content-shape section
  describes — while what an operation *does* is code, in `SimModification.OPERATIONS`, which is the
  registry that document points at.
  ~~The other five (Whetstone, Gun Oil, Solvent, Machinist's Gauge, Salvage Rights)~~ **also
  landed** (`godot:check:mods`, the FIVE MORE lane), each as docs/11's table names it. Whetstone
  reuses `reroll` verbatim, restricted to `weapon.melee` — the same gamble Duct Tape runs, just
  narrower, so it needed no new operation at all. Gun Oil is the new `condition_restore`
  operation on `weapon.ranged`: it raises condition toward the ceiling, and docs/11's "small
  jam-chance reduction" needed no second mechanic, because `SimItems.jam_chance` already derives
  jam chance from the condition band. Solvent is the new `strip` operation — every affix gone and
  the tier reset to scavenged, docs/11's "returning the item to Scavenged". Machinist's Gauge is
  the new `reroll_chosen` operation: the same reroll as Duct Tape but on an affix the caller
  names — `item.modify` grew an optional `affix` field, read by nothing else. Salvage Rights is
  the new `upgrade_tier` operation: the item's `itemTier` moves one step up `SimItems.TIERS` and
  every affix is rerolled fresh at the new tier's capacity. All four new operations refuse a wrong
  item class exactly as `add` and `reroll` already did, plus their own true negatives —
  already-at-ceiling, already-max-tier, no-target-affix, no-such-affix — each measured in the
  FIVE MORE lane, not asserted on the function having returned "ok".
  Craft moves both odds in the directions docs/11 names — failure 0.200 → 0.080 over six points
  (floored at 0.05, because a bench that cannot fail is not a gamble), and the mean affix tier
  0.409 → 0.694 under the bias. Injured hands raise failure to 0.230 and cancel the tier bias, so
  a good crafter working hurt is an ordinary one rather than a worse-than-novice one; two
  destroyed hands refuse outright. Failure spends the consumable and costs 0.25 condition, and
  below 0.20 it breaks the item outright with its ceiling, so it is scrap forever — reachable only
  from an already-degraded item, so a fresh find is never one roll from scrap. Every one of the
  seven consumables is findable in a loot table, the same dead-socket check `check_m2_attach.gd`
  runs for attachments — the Scrap Kit in the military cache, Duct Tape in all four, and each of
  the five new ones in at least one.
  Two things fell out of this that were missing rather than new: an item's **tier was rolled at
  spawn and thrown away**, so nothing could afterwards ask how many affix slots an item has — it
  is now an `itemTier` component with `SimItems.tier_of`/`affix_capacity` — and there was no path
  to re-derive an item's modifiers after its affixes change, now `SimItems.reapply_affix_modifiers`
  (removing by affix source rather than clearing the item's scope, which would drop modifiers this
  module never put there). Trait-weighted outcomes are parked for Milestone 3A — the seam is named
  in [what's left](#whats-left-in-milestone-2).
- **UI** — ~~the inventory screen as a fixed sheet~~ **reworked** (presentation-only, so the proof
  is `godot:smoke` plus the screenshots in the session record rather than a sim gate): every
  carried container is now its own **window** — draggable by its title bar, **pinnable** so its
  contents stay on screen during ordinary play — with all drag state owned by one layer
  (`ui/inventory_panel.gd`) because Godot pins mouse focus to the control that took the press, so
  cross-window drops have to be routed somewhere that can see every window at once. A **settings
  sheet on Esc** (`ui/settings_panel.gd`) adjusts inventory and pinned-bag opacity, persisted with
  window positions and pins to `user://ui_prefs.json` (`ui/prefs.gd`) — presentation preferences
  live beside the UI, never in the save. The screens share one skin (`ui/chrome.gd`, olive/gunmetal
  with a single amber accent, in the STALKER-PDA / Zero Sievert register the sprites already sit
  in), the stance paperdoll moved to the **bottom-left** with the HUD key hints taking the freed
  corner, grid item labels are width-fitted rather than cut at six characters, and click-to-fire
  moved to `_unhandled_input` so a click on any UI surface is never also a trigger pull.
  A second pass landed on the owner's direction: the survivor screen is **one view** now (tabs
  gone — slots flank the doll and anything wrong with the body reads as prose beneath it), the
  paperdoll is a **filled capsule silhouette** rather than a stroked stick figure (rounded joints,
  per-part tint blend, armour as a steel outer stroke, a ground shadow — every part still
  individually tintable and nothing numeric), **pinned belt and vest pouches stay fully usable
  during play** while a backpack still needs the inventory open (`ContainerWindow.quick`, the
  owner's cut: what is on your front is reachable, what is on your back is not), and a
  **developer spawn menu on F8** (`ui/debug_panel.gd`) lists every item id and zombie type and
  spawns through a new command-driven `sim/modules/debug.gd` (`debug.spawn`, its randomness on a
  dedicated `debug` stream) — dev tooling in the M-raw-sheet family, not a player surface.
  **The slot taxonomy is landed and gated** (`godot:m2:gear`): five new slots — face, eyes,
  gloves, legs, feet — join the seven shipped ones, each with a findable armor item (cloth mask,
  safety glasses, work gloves, canvas work pants, leather boots) in the loot tables, and a sixth
  item closing a socket the gate found on arrival: **the head slot had shipped with no item that
  could fill it**, so a canvas cap now exists. Layering is basic by decision — independent slots,
  coverage composing by max per part through the one existing reader
  (`SimInfection.armor_coverage_of`), which is what reduces bite transmission and marks the
  paperdoll; the gate pins max-not-sum with two head pieces, findability for every piece, a
  no-dead-slot sweep (every `EQUIP_SLOTS` entry must have at least one shipped item), and the
  slot-mismatch refusal. The schema's `equipSlot` enum grew the five values — verified against
  **both** validators, the shallow one and the frozen oracle's recursing Ajv. The paperdoll was
  also rebuilt as a properly human figure (tapered limbs, A-pose, chest-to-hip taper, elliptical
  head) after the owner rejected the capsule draft.
  **The body screen answers an infection now** (`godot:check:respond`): a clickable word under the
  condition readout, drawn from `SimTreatment.response_view` and pushing `infection.respond`, in
  the same idiom the work grid's learnable node names set — present when it would work, absent
  when it would not, prose and no digits. The rule that decides when it appears, the four verbs
  that deliberately have no surface yet, and the free-course hole it closed are under Health &
  injury above.
  This system's open tails (the diegetic readouts, prose from modifier sources, the skill web
  screen, the attachment-fitting surface, the patient-and-part selection the other infection verbs
  wait on, the parked warmth/hygiene slots) are in [what's left](#whats-left-in-milestone-2).
- **Death & succession** — ~~the colony morale hit on a death~~ **landed** (`godot:m2:needs`,
  GRIEF and ONCE), leaving the balance-grid proof that "the run ends only when the last survivor
  dies". docs/04 lists **grief** and **witnessing a death** as two separate negative mood sources
  and they are two magnitudes here: **18.00** witnessed against **7.00** heard about, on every
  other survivor in the colony. Witnessing could not have been asked before the sightlines slice —
  `world.vision` answered for the player alone until every survivor got eyes, so "did anybody see
  this" had no answer for a colonist; it is the same `line_of_sight` a shot is refused by.
  A **put-down costs more** (×1.6, measured 11.20 against the same death's 7.00), which is the part
  of docs/06 response #5's price that can be paid without relationships — docs/07 scales grief by
  closeness through pairwise opinions and those are Milestone 3A, so this is deliberately the
  colony-wide half and docs/30 says so. Grief **stacks to a cap** (40.0) and drains over about
  thirteen in-game hours, on the argument-cap argument: three deaths in a bad night must not empty
  the colony through LEAVE_AT in one stroke, which is the meltdown docs/04 rules out. The Optimist
  trait halves it, per docs/07's "less grief transmission".
  Worth keeping: `entity.killed` **fires more than once for the same individual** — health.gd on a
  destroyed head, infection.gd on a put-down and again on turning — so the colony would have been
  charged two or three times for one funeral. The dedupe is a `mourned` component on the body
  rather than a module-level set, because a static would be shared between the two worlds a gate
  boots and would not survive a save; ONCE republishes the event twice and asserts the total does
  not move.
- **Kernel & review sweep** — a read of the whole tree looking for defects rather than for the
  next feature. Thirteen fixes landed with seven gate assertions, each with its true negative; the rest
  of what the sweep turned up is named in
  [defects found by the review sweep](#whats-left-in-milestone-2) rather than fixed here, because
  each needs its own gate and two need a balance re-measurement. The last two sub-bullets below
  were worked off that list in a later session; the sweep's own count stays thirteen.

  - **Two worlds no longer share one attention field** (`godot:m2:district`, ISOLATION). `SimBoot`
    kept "the last world that called `attach_kernel`" in a `static var`, and the `noise.emitted` /
    `scent.accumulated` handlers wrote into *that* world's field rather than the field of the world
    that published. Measured on the parent commit: boot A (seed 101) then B (seed 102), publish
    magnitude 500 at (8,8) on A and step A — **A's own field read 0.0000 and B's read 500.0000**.
    On the spine (docs/03), which means every gate that boots a positive and a negative world was
    reading the wrong field for anything about noise or scent, negative controls included; three
    gates carried fixture comments explaining that they stayed off `attach_kernel` to dodge it, and
    those comments are now history rather than instructions. The handlers capture their own world;
    `world` is an object, so the closure captures a reference and CLAUDE.md's lambda-capture trap
    (primitives by value) does not apply. This is the third time docs/30's "a static would be shared
    between the two worlds a gate boots" has been paid for, after `putDown` and `mourned`.
  - **A despawn takes its components and its modifiers with it** (`godot:m2:save`, DESPAWN-CLEAN).
    Two leaks, both writing into every save. `world.despawn` guarded the modifier cleanup on
    `has_method("removeScope")` — the method is `remove_scope`, so the guard was false on every
    despawn that has ever run and the line did nothing; it is the only camelCase `has_method` in the
    tree, and the same shape as the `vel["x"]` trap, a guard naming something that does not exist.
    Separately, five call sites reached past `world.despawn` to `world.entities.despawn`, which
    retires the id and touches no components: eight arrows consumed through the shipped
    `_consume_ammo` path left eight ids that `components.query(["itemBase"])` still returned for
    entities `is_alive` said were dead — CLAUDE.md's trap 9 on the item path rather than the
    population one. The gate's negative is that second failure reproduced deliberately.
  - **A put-down puts them down** (`godot:m2:treatment`, PUT-DOWN). docs/06 response #5 sells
    "certainty, immediately, cheaply" and delivered none of it: `put_down` published
    `survivor.putDown` and `entity.killed` and returned `ok`, and **nothing reaps on that bus** —
    `finish_death` is called by health.gd's own reaper, wounds.gd's, and needs.gd, never by a
    subscription. The survivor walked away from their own mercy kill. The assertion that stood here
    watched the two events go out and stopped, which is the dead-socket pattern exactly. A body the
    colony put down is also now the one body transmission does not raise, since a put-down that let
    them turn anyway delivers the outcome the verb exists to buy your way out of.
  - **You cannot shoot from a sprint** (`godot:m2:ranged`, SPRINT). `SimStances.CAN_AIM` has said
    `false` for Sprint since the ladder landed and was **read by nothing in the repo**; `_capable_of`
    refused Crawl with a hand-written `!= 0`. docs/29's stance table says "Sprint: cannot aim". A
    ninth dead socket. Only the player carries a `posture`, so no NPC behaviour moved. The gate walks
    all five rungs — three must still fire, or "nobody can shoot" would pass just as well.
  - **One command undresses one survivor** (`godot:m2:gear`, UNEQUIP). `item.unequip` looped every
    entity with an `equipment` component with no ownership test, where the three cases beside it all
    had one — and `ui/inventory_panel.gd` pushes it straight off the paperdoll, so one click on your
    own coat stripped that slot from everybody in the colony. A slot name cannot say whose command it
    is, so the command carries the item. `item.pickUp` had the same shape and is now the controlled
    survivor's alone.
  - **The hidden developer sheet stops costing a frame** (`godot:check:hud`, SHEET-COST). Its
    fingerprint is a hash of `world.serialize()` — canonical JSON over every component, the entity
    store, the modifier table and the attention field — recomputed four times a second whether or not
    anybody had pressed **M**. Measured at **12.58 ms per call** on a two-hour-old seed-404 world with
    46 entities: one blown 16.7 ms frame, four times a second, growing with the colony, for a panel
    nobody had opened. docs/00 pillar 6. Two smaller things in the same function went with it: the
    zed counter built and sorted an array to count what `components.count` reads off a size
    (0.0068 ms against 0.0007 ms), and `SimFortify.look_at` was called twice per update with
    identical arguments.
  - **Bleeding reads as English in both voices** (`godot:m2:wounds`, BLEED-VOICE). The third-person
    HUD line was produced by splicing a word into the first-person sentence, which read "Ada looks
    going grey." and "Ada looks bleeding." — two of four ranks ungrammatical on a line every NPC
    survivor produces in ordinary play, since the swipe made bleeding reachable — and fell through to
    a hard-coded "has lost a lot of blood" for anything else. Both voices are authored per rank now,
    the same move `WOUND_KINDS` made on the injury kinds. The unnamed fallback is "Someone", because
    every row's verb agrees with a third-person singular subject and singular "they" does not.
  - **Four gates that could not fail.**
    `check_hud.gd` skipped every line beginning with `day `, and hud.gd emits `"day %d, %s"` — so
    anything numeric appended to that one line passed the digit ban untouched; the exemption is one
    token now, and the gate carries a row of lines it must catch, including `day 3, Dusk, 4 seen`.
    `check_m2_swipe.gd`'s WALL row placed the bodies **1.6 m** apart against `SWIPE_METRES` 1.1, so
    the swipe was refused by reach and the row passed identically with the wall deleted, while its
    comment claimed "Distance 1.0 m, well in reach"; it is 1.07 m now, the distance is asserted
    rather than assumed, and an unwalled control at the same range must land swipes.
    `check_m2_lethality.gd`'s `_bite_trials` returned `-1` when the vest could not be equipped, and
    `-1` satisfied **both** of the ARMOR comparisons — not `>= 500`, and not `> 425.0` — so a
    broken setup printed `ARMOR OK armored=-1` and exited 0; the sentinel is checked before it is
    compared now. And `check_m2_web.gd` asserted the melee-damage modifier had applied with
    `if dmg < 1.0`, against a stat whose **base is 1.0** — so "the modifier applies" was satisfied
    by the modifier not applying; it reads `<= 1.0` now and the real value is 1.040. That gate's
    FOCUS lane was also wrapped in an `if mara >= 0:` with no else, so a fixture that stopped
    producing a unique survivor would have taken the whole claim with it and still printed
    `M2_WEB_OK`; it fails loudly instead.
  - **CI stopped running three gates twice.** `npm run godot:m2` already ends with
    `ban:healthbar`, `check:appearance` and `check:hud`, and the workflow listed all three again as
    separate steps. The step that runs the whole 32-gate chain was also named "M2 lethality", after
    one of them.
  - ~~The DEX noise guardrail is a no-op~~ **fixed** (`godot:m2:stance`, DEX GUARDRAIL).
    `attention_emitter.gd` scaled the DEX-driven `move_speed` multiplier into `magnitude` and then
    threw it away four lines later, recomputing `magnitude = base * SimSurface.noise_on(surf)` from
    the un-scaled `base` — the surface branch runs whenever `speed > 0.0`, so the guardrail landed
    for nobody moving. It reads `magnitude *= SimSurface.noise_on(surf)` now. Measured: two players
    walking the same 40 ticks through undergrowth, one carrying a move_speed ×1.8 modifier, emit
    52.0000 and 93.6000 total noise — a ratio of 1.8000, matching the modifier exactly; with no
    modifier the two runs agree at 52.0000. The new lane was confirmed to fail against the bug it
    targets: reverting the surface line collapses the ratio to 1.0000.
  - ~~A dead colonist still triggers the screamer~~ **fixed** (`godot:m2:roster`, CORPSE).
    `SimAllegiance.is_person` checks `controlled`/`identity`/`raider`, none of which
    `SimRecruits._make_corpse` strips — gear stays on the body per ADR 0013 — so a corpse kept
    setting off the screamer's 300-magnitude alarm on cadence, forever. `screamer.gd`'s survivor
    scan now skips any entity carrying `corpse`, the same exclusion `enemies_of` already applies
    (allegiance.gd) and for the same reason; `is_person` itself is untouched, since shambler.gd
    and bloater.gd share it. Measured: a screamer with the run's one visible "person" turned into
    a corpse via the real `_make_corpse` path stayed silent across 650 ticks, past its own
    600-tick cooldown, while the sibling lane with a living survivor still alarms at magnitude
    300. Confirmed to fail against the bug it targets: reverting the `corpse` skip alarms on the
    corpse exactly like the living-survivor lane does.

- **Proof** — nothing here has run yet; the four proof steps live in
  [what's left](#whats-left-in-milestone-2), in the order they close the milestone. Deferred, not
  cancelled.

## Milestone 3A: Survivor depth

Only if Milestone 2 answers the thesis affirmatively. This track deepens the people and colony before
adding more geography:

1. Full work grid, including Guard/Scout behavior
2. Relationships and grief
3. Full skill web
4. The six survivor attributes below, now that each has a live consumer
5. Weather, temperature, hygiene, full decay, mutation waves, and remaining zombies
6. Named items, unique survivors, remaining modification consumables, traps, and bait

That order is deliberate. WIS lookout needs a lookout job; CHA needs relationships; INT needs the web;
temperature needs weather. CHA trade and WIS raider warnings activate fully when factions arrive in
Milestone 4 rather than existing as dead bonuses in Milestone 3A.

**Exit criterion:** two generated survivors with different aptitudes, histories, relationships, and
web paths solve the same colony problem in observably different ways without either becoming a
mandatory template.

### Planned survivor attributes

Survivors eventually carry **STR, DEX, CON, INT, CHA, and WIS**. These are bounded aptitudes, not
classes or prebuilt identities. Generation uses a fixed budget with tradeoffs: no survivor can be high
in all six, and backstory, age, and traits produce modest, explainable shifts rather than perfect
rolls. A survivor's base values are permanent after generation.

The skill web may contain rare, late, opportunity-costly nodes that permanently raise an attribute.
Equipped items and affixes may provide conditional bonuses. Repetition never raises base attributes,
and removing an item removes only its conditional bonus. Rerolling the starting survivor creates a
different person; it never edits an existing person's attributes.

| Attribute | Benefit and guardrail |
|---|---|
| **STR — Strength** | Raises the hidden carried-mass threshold before encumbrance slows the survivor and raises escape power against grabs. More grabbers still diminish escape chance independently. |
| **DEX — Dexterity** | Raises movement speed across every stance without replacing stance tradeoffs. It cannot ship until footstep attention is normalized by distance or equivalently scaled, so speed does not silently become a second stealth bonus. |
| **CON — Constitution** | Raises effective body-part durability through a bounded injury-tolerance modifier to incoming integrity loss. Baseline maxima remain properties of the body kind; there is never a global HP pool or health bar. CON may also lengthen infection progression, but never changes the wound-time transmission result. |
| **INT — Intelligence** | Increases activity-earned, region-tagged skill progress. It never grants retroactive progress, generic levels, or permission to buy an unrelated region; INT-raising nodes cannot accelerate their own acquisition. |
| **CHA — Charisma** | In Milestone 3A, increases positive relationship gains and negotiation outcomes without erasing grievances. Better faction trade activates with Milestone 4. |
| **WIS — Wisdom** | Notices that an item or location merits inspection and gives earlier approximate warnings about sensed danger. It never reveals exact quality, affixes, counts, positions, or anything through walls; Scavenger's Eye retains exact loot-quality and roll benefits. |

Attribute benefits stay within roughly one competence band. Injury, equipment, position, and learned
skills must remain more important than a favorable roll. Known aptitude does not automatically violate
the uncertainty contract, but exact numbers versus descriptive bands is a UI decision that must be
made before implementation.

## Milestone 3B: World range

This is a separate completion track rather than a requirement bundled into survivor depth:

1. **World scale:** continuous region, district types, road graph, authored-template procedural
   assembly, district-tier simulation, and streaming.
2. **Drive benchmark:** synthetic streaming-at-speed load before a drivable vehicle exists.
3. **Vehicles:** bases, slots, affixes, driving, fuel, breakdowns, route trails, and attention output.
4. **Mobile bases:** interior modules, volume budgeting, convoys, relocation, and nomad play.

**Exit criterion:** travel across multiple streamed districts at the target speed without breaking the
frame budget, then prove fixed, nomad, and hybrid colonies all have distinct viable failure modes.

## Milestone 3C: Multiplayer

Multiplayer is independent of world range: authoritative host, survivor-versus-survivor play in one
district, filtered client views, recovery runs, and voice as an emitter. The visibility primitive now
exists; what remains unproven is per-client filtering, leakage, synchronization, and host cost.

**Exit criterion:** two clients can play one district without receiving hidden entity or attention
information, while the host remains deterministic and inside the single-player frame budget.

## Milestone 4: Breadth

Factions and trade · the escape endgame · storyteller presets and the full sandbox layer · expanded
large-scale balance campaigns · content volume.

## Deferred: z-levels

Multi-floor buildings, stairs, and standable rooftops remain deliberately undesigned. Every spatial
assumption is planar:

| Assumption | Current shape |
|---|---|
| Map | One planar tile layer with Floor, Wall, Window, Screen, Low, and Tree classes |
| Ground | A separate planar surface layer |
| Attention | One 64 × 64 coarse grid carrying noise and scent; light is separate |
| Rendering | One planar tile/surface raster with no floor ownership |
| Visibility | Two-dimensional shadowcasting |

Z-levels add a dimension to all of them at once. They are not revisited before Milestone 2 proves the
thesis and Milestone 3B establishes the streaming and memory budget. Any future attempt begins with a
throwaway field/visibility cost spike.

---

## Risks

All live risks stay together here. Exact task state and measurements belong in the milestone status
sections above, or in the gate output that produced them.

### 1. The micromanagement cliff — open, highest design risk

Unlimited survivors × affixed gear × a web can become spreadsheet management. **Checkpoint:** the
seeded six-survivor Milestone 2 scenario, every NPC on Focus automation. If full auto is not viable,
shrink item/web complexity rather than adding more required UI labor.

### 2. Unlimited survivors may undercut permadeath — open

If players treat recruits as ammunition, infection loses its teeth. **Checkpoint:** Milestone 2;
observe whether players quarantine and treat people or execute every uncertain case.

### 3. Unscheduled hordes may starve tower defense — open

No wave timer may leave building untested. **Checkpoint:** Milestone 2; if sieges are too rare to
justify defenses, the slice director guarantees a minimum cadence without changing attention rules.

### 4. ECS and modifiers may be over-engineering — retired after Milestone 1

The risk was architectural cost, not whether the noise prototype was fun. Milestones 0–1 repeatedly
changed movement, visibility, items, combat, infection seams, and content while preserving
determinism and module isolation. The minimum architecture has earned its current footprint; future
abstraction still needs a concrete second consumer.

### 5. Attention-field performance — closed

Continuous scent and 500-body convergence passed named CI benchmark scenarios within their budgets,
including saturated-field cost. Exact machine-dependent timings stay in the benchmark
output rather than becoming permanent roadmap promises. Reopen only for a larger field, a real new
continuous channel, or a failing budget.

### 6. Melee/ranged parity may not survive contact — open

**Checkpoint:** the Milestone 2 campaign harness compares melee-only and ranged-only colony outcome
distributions before human tuning argues from anecdotes.

### 7. Streaming at driving speed — open, highest engineering risk

**Checkpoint:** Milestone 3B runs the drive benchmark against synthetic load before vehicles. Failure
means smaller regions or abstracted travel are still affordable decisions.

### 8. Nomad viability doubles the balance surface — open

**Checkpoint:** compare fixed-only, nomad-only, and hybrid campaigns. Fixed colonies should fail to
siege/mutation pressure; nomads should fail to fuel/attrition, with neither strictly dominant.

### 9. What a multiplayer client may know — narrowed

Visibility, occlusion, and filtered rendering primitives exist, so the prerequisite is satisfied.
**Checkpoint:** before transport code, validate per-channel attention filtering, audible-but-unseen
leakage, host-only developer overlays, and the cost of per-client views.

### 10. A host in the loop may miss the frame budget — open

**Checkpoint:** synthetic clients attached to the single-player benchmark, held to the same budget.

### 11. Attributes may create mandatory builds or reroll fishing — open

Familiar RPG stats invite optimization even when the game says “blank slate.” **Checkpoint:** generate
large seeded cohorts, verify the fixed budget prevents universally superior survivors, then playtest
whether one stat becomes mandatory or starting-survivor rerolling dominates actual play.

## Spike findings: attention field

This is historical evidence. The disposable pre-Milestone prototype tested the narrower mechanical
premise “make noise and they come.” It did not test the full colony/permadeath thesis. Its findings
are retained as history; the linked specifications and the milestone status sections above are the
authority.

| Finding at spike time | Final resolution |
|---|---|
| Gradient ascent produced conga lines | Persistent seeded individual bias fans convergence into a crowd |
| Noise seemed uncalibrated | The missing fact was the unit; the district became 256 m without changing the magnitude table |
| Noise-based residue did nothing | Field memory was always a scent mechanic. Milestone 1 built and verified it; hordes migrate downwind on their residue |
| Rendering dominated simulation | Frame budgets and real-browser gates were added alongside tick budgets |
| Scent cost was unknown | Milestone 1 measured and closed the performance risk |
| Quiet was completely safe in the noise-only spike | Shipped scent makes quiet slow rather than safe; whether that feels tense remains a playtest question |

## Open questions

This is the canonical design and playtest question register. Other documents should link here rather
than copying it; engineering blockers belong beside the work they block, in the milestone status
sections above.

### Milestone 2 questions

- Is being quiet tense, or merely slow?
- Does a district-wide shout crowd out quieter attention verbs?
- Does a migrating horde feel legible from the wind, or arbitrary?
- Is the current scent lifetime right?
- Does limited visibility feel dangerous, or merely empty and opaque?
- Do surfaces visibly change route choice without a numeric readout?
- Are the focal and peripheral sight arcs readable and fair?
- Should a stationary body in peripheral vision disappear completely?
- How long should a day feel in actual play?
- Is night tense once light counterplay exists, or just an inconvenience?
- Is the grid inventory a decision or a chore?
- Is invisible weight legible through gait, breathing, stamina, and footsteps?
- How lethal is too lethal?
- Does succession feel like continuity rather than a consolation prize?
- How rare should recruits be?
- How small can the skill web remain while still earning its complexity?

### Milestone 3+ questions

- Does the authored-slice/procedural-region hybrid hold up?
- Do attributes need exact visible values or descriptive bands?
- Does the generation budget prevent dump stats, mandatory stats, and reroll fishing?
- Does a mobile base make a fixed colony feel like a burden?
- Does PVP preserve the meaning of permadeath?
- Does voice-as-emitter create tension or simply encourage silence?
- Is real-time multiplayer without pause still this game?

## Settled decisions: do not relitigate

These were each decided explicitly by the repo owner. They moved here from the retired checkbox
`HANDOFF.md`.
If you're about to "improve" one, don't:

- **Hardcore is the thesis, not a difficulty slider.** Permadeath with succession into another
  survivor; no win condition plus an optional expensive escape.
- **No wave timer.** Horde pacing is attention-driven and director-paced.
- **Blank slates mean no classes or predetermined builds, not identical biology.** Every survivor
  eventually gets bounded, budgeted STR/DEX/CON/INT/CHA/WIS aptitudes. The build still lives
  primarily in found gear plus a classless skill web earned by doing, and the same rules apply to
  the controlled survivor and every recruit.
- **Survivors are unlimited and procedurally generated.** Recruits arrive as unskilled nobodies —
  that is the counterweight that keeps permadeath meaningful.
- **Melee and ranged both good**, spending non-convertible currencies (body/bite-risk vs.
  ammo/attention).
- **Fully drivable continuous region**, no abstracted travel legs. **Full nomad play viable.**
- **Performance is pillar 6**, with CI budget gates that fail the build.
- **Engine transition:** rebuilt in Godot behind parity gates while the TypeScript/Canvas/Vite
  version remained the executable oracle — complete, with the oracle archived at `ts-oracle-final`.
  Typed GDScript on Godot 4.7.1, Compatibility, Web + Windows. **Saves may break pre-1.0** — stable
  IDs and a version stamp, but no cross-engine migration framework.
- **The inventory is a grid, and weight is invisible.** Tarkov/DayZ-shaped: cells, footprints,
  rotation, nesting, and containers you have to wear to get. This *replaced* the weight-and-capacity
  model [docs/10](10-items.md) originally specified — a capacity bar is a number about your
  capacity, which [clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable)
  prohibits outright, and a grid is the same information as shape. Weight is still simulated and
  never printed: you find out you are overloaded by walking slower. **There is no kilogram on the
  inventory screen** and adding one is a contract violation, not a UX improvement.
- **Vehicles were un-cut** after initially being cut at the vision level. [docs/00](00-vision.md)
  records the reversal and why the original objection was half right.
- **A district is 256 m, falloff stays linear.** Decided against re-authoring the magnitude table,
  because its ratios are load-bearing in six documents and only the unit was ever missing.
- **Field memory is scent, never noise.** Kept rather than cut, on the condition that Milestone 1
  proved it did something. **It did** — though not the something that was written down. See
  [what scent changed](30-decisions.md#what-scent-changed-and-what-it-corrected).

## Roadmap cut list

- **Per-item checkbox bookkeeping.** Retired with the checkbox `HANDOFF.md`; the milestone status sections carry
  condensed state, gates carry the proof, and git history carries the itemised record.
- **Milestone 3 breadth inside the vertical slice.** The slice proves the thesis before expansion.
- **Full storyteller presets in Milestone 2.** Only the slice director and an internal neutral baseline.
- **Z-level implementation before the thesis and streaming budgets are proven.**
- **A second progression system beside attributes and the skill web.** Attributes are aptitude; the web
  is learned history.

## Definition of done for the doc set

1. Every system document has substantive content and a cut list. This roadmap is the cut authority for
   sequencing and therefore carries its own roadmap-level cut list rather than repeating every doc's.
2. Every cross-document link resolves.
3. The [cookbook examples](21-extensibility.md#the-cookbook) are achievable using only defined mechanisms.
4. No document contradicts the [vision](00-vision.md) or [hardcore contract](01-hardcore-contract.md).
5. README and the roadmap keep their separate audiences and do not duplicate volatile status.

---

**Previous:** [27 — Multiplayer](27-multiplayer.md) · **Next:** [30 — Decision Records](30-decisions.md) ·
[Doc index](../README.md#documentation)
