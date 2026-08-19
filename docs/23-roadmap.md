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
ordinary play because `SimShambler.GRABS_ENABLED` is `false` — see the four entries below: three
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

Three residuals are named, in the order they cost the most, and each is a design call rather than
something to pick unilaterally:

- **A break-away runs into the wall it was released against.** This is the finding, and it is
  measured rather than reasoned: over three days of seed 404 with the flag on, a `breakAway` body
  carries its escape velocity into `movement.integrate` on 1,230 of 1,266 ticks and the integrator
  **zeroes it on 1,124**, because the committed heading is blocked on the X axis on 1,107 ticks, on
  the Y axis on 1,154, and on **both at once on 1,087 — 86%**. Total ground covered is 12.66 m,
  0.010 m per tick against a nominal 0.105. `_break_away` takes its direction once, at the moment of
  release, and never re-derives it (by design — it is a shove-off, not a pursuit solver), and
  `_integrate_movement` zeroes a blocked axis. A colony is grabbed where a colony lives, which is
  against the annex walls, so the shove-off points into masonry and the survivor spends all 26 ticks
  leaning on it. That is why 404's mid-press escapes cover a mean of **0.063 m** before the re-grab
  (4.71 m across 75 windows) while 31337's cover 0.72 m — and why **the re-grab is the same shambler
  in 309 of 309 windows across the three seeds that have any**.
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

**What the flip makes reachable rather than builds:** the located wound with its presentation lie,
armour-reduced transmission and the private `transmitted` flag, the paperdoll's wound ring, and the
bloater's open-wound check — all written against a bite nothing currently produces. Cripple and
stagger remain unwired: `shambler.gd` subscribes to neither `injury.sustained` nor
`entity.staggered`.

**Still open, by system** (condensed from the retired backlog; the spec links in the slice-scope
table above are the authority on each):

- **World & map** — ~15 resource types, the three location loot tables, site depletion, food
  spoilage.
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
  {16, 32, 64, 128} px/m. Screamer and bloater still render as tinted shapes; tile art still
  has no renderer path (`_draw_district` draws flat rects); the art-style *flavour* stays open —
  `.hermes/plans/2026-08-19_topdown-art-brainstorm.md` holds the three candidate directions and
  the overhead re-authoring of the zombie visual language, for the owner to pick from. **Next up,
  in order:** get the flavour pick from the owner (the brainstorm doc's screenshot-fixture
  method is the way to compare them); regenerate the five sprites again only if the pick isn't
  A (the shipped baseline), since B needs rotation support (`draw_set_transform` around the
  blit — the centre anchor was chosen so this stays a contained change) and C needs a rig-sheet
  pass before more sprites exist; then screamer/bloater art and a tile/terrain renderer path,
  both still open regardless of the pick.
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
