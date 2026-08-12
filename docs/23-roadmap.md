# 23 — Roadmap

*Why this exists: the other design documents describe a game far larger than a first build. This one
says what gets made, in what order, what proves each stage, and what may still be wrong.*

---

## How to read this document

This roadmap owns **intended scope, order, exit criteria, risks, and design questions**. It does not
own implementation bookkeeping: [HANDOFF.md](../HANDOFF.md) is the engineer-facing authority on what
is built, in flight, or next. [README.md](../README.md) is user-facing and stays at feature level.

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

**Result:** passed and closed. Exact implementation evidence lives in [HANDOFF.md](../HANDOFF.md).

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

All live risks stay together here. Exact task state and measurements belong in HANDOFF.

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
including saturated-field cost. Exact machine-dependent timings stay in HANDOFF and the benchmark
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
are retained as history; the linked specifications and current HANDOFF are the authority.

| Finding at spike time | Final resolution |
|---|---|
| Gradient ascent produced conga lines | Persistent seeded individual bias fans convergence into a crowd |
| Noise seemed uncalibrated | The missing fact was the unit; the district became 256 m without changing the magnitude table |
| Noise-based residue did nothing | Field memory was always a scent mechanic. Milestone 1 built and verified it; hordes migrate downwind on their residue |
| Rendering dominated simulation | Frame budgets and real-browser gates were added alongside tick budgets |
| Scent cost was unknown | Milestone 1 measured and closed the performance risk |
| Quiet was completely safe in the noise-only spike | Shipped scent makes quiet slow rather than safe; whether that feels tense remains a playtest question |

## Open questions

This is the canonical design and playtest question register. HANDOFF should link here rather than
copying it; engineering blockers belong in HANDOFF beside the task they block.

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

## Roadmap cut list

- **Detailed checkbox status and implementation notes.** HANDOFF owns them.
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
5. README, roadmap, and HANDOFF keep their separate audiences and do not duplicate volatile status.

---

**Previous:** [27 — Multiplayer](27-multiplayer.md) · **Next:** [30 — Decision Records](30-decisions.md) ·
[Doc index](../README.md#documentation)
