# 23 — Roadmap

*Why this exists: the other design documents describe a game far larger than a first build. This one
says what gets made, in what order, what proves each stage, and what may still be wrong.*

---

## How to read this document

This roadmap owns **intended scope, order, exit criteria, risks, and design questions**, and — since
the retirement of the separate `HANDOFF.md` — the per-milestone status sections below, which say what
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

This section replaced `HANDOFF.md`'s live-status role when that file was retired (2026-08). Keep it
current **in the same commit** as the work it describes. Every claim of "landed" below is proven by a
named gate (`npm run godot:m2` chains them all); the full done-item history with per-item evidence
lives in git — `git log -- HANDOFF.md` finds the retired file, and its final revision holds the
itemised backlog.

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

**Landed, gated, and switched off — the survival loop.** Five slices built it end to end: the
grab → struggle → bite loop (`godot:m2:contact`), wounds with a severity and a bleed clock
(`godot:m2:wounds`), pressure and bandaging plus a command path to the five infection verbs
(`godot:m2:treatment`), and recovery that closes wounds and climbs integrity back, earned only while
fed and not exerting (`godot:m2:recovery`). A bite makes a located wound, it bleeds, you stop it with
your hands or a dressing, and it mends over days you have to earn. None of it is reachable in
ordinary play because `SimShambler.GRABS_ENABLED` is `false` — see the three entries below: two
blockers that have been answered, and the one measurement that now stands between the loop and the
flip.

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

**The blocker that replaced it, measured: an escape costs stamina, and a survivor held over and over
cannot afford one.** A throwaway driver (`SimBoot.playable`, the harness's own compressed campaign,
`GRABS_ENABLED` forced on, `entity.killed` de-duplicated by entity id) over the same four fast seeds:

| seed | before this work | after | how it ends |
| --- | --- | --- | --- |
| 20260805 | `2/2` | `2/2` | no contact at all — 0 grabs in ten days |
| 404 | `0/2`, 111 bites, **0** struggles | `0/2`, 57 bites, **73** struggles | both by blood loss, first death day 1 |
| 31337 | `2/2` | `2/2` | 39 grabs, all on the recruit; neither boot colonist is ever held |
| 90210 | `0/2`, 45 bites, 2 grabs, **0** struggles | `0/2`, 57 bites, 72 grabs, **92** struggles | both by blood loss, first death day 4 |

Every number moved except the one that decides. What the instrumentation says about why:

- The two colonies that die spend **65% and 69% of their living ticks held**, by **1.4 holders** on
  average, and **38% and 49% of those held ticks with a tank too empty to pay `STRUGGLE_STAMINA`**.
  Instinct fires, wins, is re-grabbed inside the cooldown, fires again, and runs the tank down; an
  empty tank is a hold with no exit, because nothing in the build lets anybody else break one.
- It is **not** the missing player either. A driver mashing `F` on every single tick of the campaign
  leaves seed 404 at `0/2`, the played survivor connecting **once** in ten days (a grabbed body is
  refused its swing, and a freed one is mid-break-away), and empty-tank ticks roughly doubled,
  because pressing F spends the same stamina sooner.
- Holder-first targeting has little to bite on at this loadout: two kitchen knives reach 1.25 m, and
  the holder is at arm's length of its victim, not of the other colonist. It is written for the arms
  that can answer across a room, and the fast tier is not one of them.

So the flag stays `false`. The levers left are the **price of an escape** (`STRUGGLE_STAMINA`, or
stamina that recovers while held), **somebody else being able to break a hold**, or **making contact
rarer** — all three are calls about how being grabbed should feel, of the same kind as the
bite-lethality one, and not to be picked unilaterally. Relaxing `survivors_end >= 1` is not among
them: that has been considered and rejected. The balance tier is therefore still exactly what it
was, and `_the_flag_actually_gates_acquisition()` in the contact gate still exercises both
directions.

**What the flip makes reachable rather than builds:** the located wound with its presentation lie,
armour-reduced transmission and the private `transmitted` flag, the paperdoll's wound ring, and the
bloater's open-wound check — all written against a bite nothing currently produces. Cripple and
stagger remain unwired: `shambler.gd` subscribes to neither `injury.sustained` nor
`entity.staggered`.

**Still open, by system** (condensed from the retired backlog; the spec links in the slice-scope
table above are the authority on each):

- **World & map** — ~15 resource types, the three location loot tables, site depletion, food
  spoilage.
- **Survivors** — the fuller generator (appearance, age, backstory, starting kit), trait conflict
  rules, Focus auto-allocation, and the risk-1 checkpoint (a seeded six-survivor colony on auto).
- **Needs** — mood consequences: slower work, mistakes, refusing jobs, arguments.
- **Attention leftovers** — the sim half of last-known-position memory, and director-varied nights.
- **Health & injury** — the remaining injury types (fracture, sprain, burn, concussion), continuous
  pain and exhaustion, bacterial infection kept distinct from zombie infection (sepsis), the full
  treatment ladder (clean → close → rest), supply quality tiers, skill-scaled diagnosis text,
  permanent conditions that don't remove a survivor from play, and diegetic readouts for the
  continuous conditions.
- **Combat** — firing at a remembered position (and what it costs), jamming on degraded weapons.
- **Items** — attachments gaining a reader (content declares slots nothing reads), repair that never
  restores the full ceiling, and finishing continuous condition-degradation effects.
- **Inventory** — searching world containers (a car boot, a cupboard), weight affecting footstep
  noise.
- **Modification** — Duct Tape (reroll an affix), Scrap Kit (add an affix), skill- and
  trait-weighted outcomes, failure that consumes and damages.
- **UI** — the diegetic condition and stamina readouts (in the world, not a corner), prose generated
  from modifier sources, the priority grid and skill web screens.
- **Death & succession** — the colony morale hit on a death, and proving "the run ends only when the
  last survivor dies" in the balance grid.
- **Proof** — distribution assertions (quiet nights, sieges, deaths, run lengths), the risk-6
  melee-vs-ranged parity measurement, the full balance grid (`BALANCE_FULL=1`, ~9 h), and the human
  ten-day playtest. Deferred, not cancelled.

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

These were each decided explicitly by the repo owner. They moved here from the retired `HANDOFF.md`.
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

- **Per-item checkbox bookkeeping.** Retired with `HANDOFF.md`; the milestone status sections carry
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
