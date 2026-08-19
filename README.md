# simplyZOMBIES

A hardcore survival colony sim about the cost of living well during the end of the world.

You control one survivor in a dead town. You can recruit others, and together you fortify a place to
sleep. Every comfort you build — a fire, a light, a generator, a gunshot — is a signal, and the dead
follow signals.

**The better you live, the harder they come.**

---

## The loop, in five lines

1. **Dawn** — count what last night cost. Treat wounds, repair walls, burn the bodies.
2. **Day** — you lead a scavenging run while the colony works. The people who fight best also build
   best, so you can't have both.
3. **Dusk** — barricade, post the watch, decide whether tonight is worth a lamp.
4. **Night** — there's no wave timer. What arrives is what your week's noise, light, and scent earned
   you.
5. **Repeat** until something goes wrong, because it will. There is no winning, only lasting.

## What makes it different

- **One attention system ties four genres together.** Noise and scent spread across the district;
  light changes what can see and be seen. Cooking, warmth, electricity, gunfire, and every extra
  person leave signals. Survival and tower defense are the same system read from two directions.
- **Nobody has a class.** Survivors will have bounded natural aptitudes, but no predetermined build.
  Who they become comes from the gear they find and modify plus a classless skill web earned by doing.
- **Bodies are cheap; people are expensive.** Survivors are unlimited and procedurally generated, and
  they arrive knowing nothing and eating immediately. What infection takes from you isn't a headcount,
  it's two months of investment.
- **A bite can present as a scratch.** You will not always know whether the person sleeping inside
  your walls is infected. Amputate, quarantine, spend the last antibiotics, or put them down — on a
  guess.
- **Melee and ranged are both good, permanently.** Melee spends your body and your infection risk.
  Ranged spends finite ammo and tonight's difficulty. Neither converts into the other.
- **The world decays on a clock you don't control.** The grid fails, food expires, sites empty out,
  the virus mutates. Every equilibrium you build has an expiry date.
- **A vehicle is the loudest thing you own.** An engine emits more noise than a rifle, continuously,
  for as long as it runs — so driving is announcing yourself to a whole district. Vehicles are found
  and customized like any other gear, and a fitted-out van is a
  [home you can drive away from a siege](docs/26-mobile-bases.md).

## Status

**Playable, and early — most of the vertical slice has landed.** Make noise and the district
converges; stay quiet and scent still brings danger eventually. Walls block sight, surfaces change
speed and footstep noise, and midnight closes bare-eyed vision to only a few metres unless you find
a light. Five movement stances trade time, stamina, visibility, and noise. Melee commits you to a
swing; ranged — a bow and a pistol — spends finite ammo and announces you to the district, and both
weapons wear with use and repair imperfectly. Shamblers, screamers, and bloaters walk a 256 m
district with a civic annex. Survivors have STR/CON/DEX aptitudes; they get hungry, thirsty, and
tired, their mood matters, and they work jobs — hauling, building, cooking, doctoring — you steer
through a priority grid. Recruits arrive, gear rolls affixes into a rotatable, nested grid
inventory, a director paces the nights, and you can fortify, save, and load. Wounds appear on a
descriptive body-part view rather than a health bar.

The full injury loop — grabs that pin, bites that make located bleeding wounds, pressure and
bandaging, recovery over days you have to earn — is **built and gated but switched off** for one
more turn. Five of the reasons it was off have been answered. A bite during a hold now aims where
the hands already are, comes four seconds apart rather than two, and takes a share of the part it
lands on, so a held survivor is no longer two rolls from a destroyed head; and the colony fights for
itself now — anyone held struggles on instinct if nobody answers for them, everybody starts with
something in their hands rather than in their pack, and a survivor with a weapon shoots whatever has
hold of a neighbour before whatever is merely nearest. An escape is no longer something you can
run out of money for: you get your breath back while you are held, and somebody standing next to you
can haul you out of a grip with their bare hands (`H`). And you are no longer forbidden from doing
anything about the blood — you can clamp your own hand over your own wound while somebody has hold
of you (`T`), badly, and go on fighting to get free at the same time. Tearing loose takes that hand
off the wound, so an escape is a real run rather than a pause, and the hand goes back on once you
are clear.

What is left is one question nobody should answer alone. Running instead of pressing does mean fewer
hands on you and fewer bites — but nobody ever finishes holding a wound closed that way, and on the
hard seeds the colony still bleeds out. And a shove-off is aimed once, at the moment somebody lets go
of you, which most of the time turns out to be straight at the wall you were pinned against. It is
recorded in full in [where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands).

**Godot 4.7.1 is the playable build.** The web export runs at `/` and the Windows artifact comes
from the same green commit; a failed CI publishes nothing. The TypeScript/Canvas oracle is
archived at tag `ts-oracle-final` for parity reference and rollback. See
[Godot rebuild](docs/31-godot-rebuild-roadmap.md) for transition history.

**[Play the latest main build](https://simplyjaytea.github.io/simplyZOMBIES/).** Every push to `main`
that passes the correctness and performance checks automatically replaces this playable build;
failed checks are never published.

```bash
npm install
npm run godot:run    # Godot — the game (also: godot:editor)
# npm run dev        # TypeScript oracle via Vite (archived, reference only)
```

## Controls

**`F1` shows the keys in game**, and they appear once on a fresh run — this list is the same thing
in text.

| | |
|---|---|
| **Move** | `WASD` walk · `Shift` sprint (fast, and loud — latches while held) · `Z`/`X`/`C`/`V` crawl, crouch, walk, jog |
| **Act** | `F` swing, or struggle out of a grab · `H` pull someone out of a grab · `G` or click — fire · `R` reload · `E` pick up · `T` first aid (bandage if you have one, bare hands if not; again to stop — and while something has hold of you, your own bare hands on your own wound is still allowed) · `Space` shout — heard across the district |
| **Look** | `Tab` gear and injuries (drag to move, right-click or `R` to rotate) · `J` work priorities · `O` attention overlay: noise, scent, sight, light · `M` raw developer sheets · scroll wheel zoom |
| **Run** | `1`/`2`/`3` speed (1×, 3×, 10×) · `P` pause · `F5`/`F9` save and load · `F1` the key list |

A day is four hours at 1×, so press `3` and wait for dark.

The view is flat top-down — RimWorld and Zero Sievert are the closest comparisons — and the
wheel zooms between a close-in read on your survivor and a wide look at the colony. The HUD reads
in words rather than bars: what the district can sense of you sits in the top right, and a
survivor with nothing wrong takes up almost no screen.

**Current playable stack:** Godot 4.7.1 (Compatibility), typed GDScript. The archived
TypeScript oracle remains at tag `ts-oracle-final` with parity fixtures under `godot/parity/`.

## Roadmap

Tentative — [docs/23](docs/23-roadmap.md) is the authority on scope, order, risks, and current
status. Milestones close on their exit criterion, never on a feature count.

- ✅ **Milestone 0 — Foundations.** Deterministic tick loop, ECS, events and modifiers, validated
  content, versioned save/load, CI gates for determinism and performance.
- ✅ **Milestone 1 — The spine.** Noise, scent, and light/sight live in one attention field;
  shamblers follow gradients; stances, committed melee, grabs and breaking free; day/night.
- ✅ **Engine rebuild.** The game moved from TypeScript/Canvas to Godot 4.7.1 behind per-tick
  parity gates ([docs/31](docs/31-godot-rebuild-roadmap.md)), then cut over. Web and Windows builds
  ship from every green commit.
- ◐ **Milestone 2 — The vertical slice** *(underway — most systems landed)*: one district, generated
  survivors, needs and jobs, ranged parity, fortification, a pacing director, permadeath and
  succession, and the complete injury/uncertain-infection loop. Landed so far: lethality and
  turning, the zombie roster, ranged combat, needs/jobs/recruits, building, the director, save/load,
  the shallow skill web, and the full wound-treatment-recovery loop (currently switched off pending
  a design decision about how a survivor holding their own wound closed should be able to run — see
  [where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands)). Still open: loot tables
  and resource variety, the fuller survivor generator, mood consequences, the remaining injury
  types and treatments, world-container search, crafting consumables, and the balance grid plus a
  human ten-day playtest. **Exit criterion:** survive ten in-game days, lose a survivor you cared
  about, continue through succession, and still want another run.
- ☐ **Milestone 3A — Survivor depth.** Relationships and grief, the full skill web, all six
  attributes, weather and temperature, full world decay, and the remaining zombie types.
- ☐ **Milestone 3B — World range.** The continuous drivable region and streaming, vehicles, mobile
  bases, and viable nomad play.
- ☐ **Milestone 3C — Multiplayer.** Authoritative host, filtered client views, voice as an emitter.
- ☐ **Milestone 4 — Breadth.** Factions and trade, storyteller presets, the escape endgame, and
  content volume.

## Working on it?

**`CLAUDE.md` is the engineer's entry point** — what the project is, the standing bans, how to
verify a change, and the traps. `AGENTS.md` covers environment setup.
[docs/23-roadmap.md](docs/23-roadmap.md) owns product scope, milestone order, risks, playtest
questions, and current implementation status; [docs/30-decisions.md](docs/30-decisions.md) records
what each completed chunk made structural, and [docs/31](docs/31-godot-rebuild-roadmap.md) owns the
(completed) engine transition.

## Documentation

The tables below are the authority on **reading order**. File numbers reflect the order documents were
written, so 24–26 sit under "The world", 28 sits next to the spine it serves, 29 sits next to combat,
and 30 sits with the technical set rather than all of them landing at the end.

### Foundations
| | |
|---|---|
| [00 — Vision](docs/00-vision.md) | Pillars, genre influences, what this game is *not* |
| [01 — The Hardcore Contract](docs/01-hardcore-contract.md) | Lethality, permadeath, succession, imperfect information, no win state |
| [02 — Core Loop](docs/02-core-loop.md) | The dawn/day/dusk/night ratchet |
| [03 — The Attention Field](docs/03-attention.md) | **The spine.** Noise, light, scent, and how the horde reads them |
| [28 — Visibility & Sightlines](docs/28-visibility-and-sightlines.md) | Sight, darkness, cover, and what the world may reveal |

### Survival & people
| | |
|---|---|
| [04 — Survival Needs](docs/04-survival-needs.md) | Hunger, thirst, rest, temperature, hygiene, mood |
| [05 — Health & Injury](docs/05-health-injury.md) | Located injuries, blood loss, bacterial infection, treatment |
| [06 — Infection & Turning](docs/06-infection.md) | Diagnostic uncertainty and the five responses |
| [07 — Survivors](docs/07-survivors.md) | The generator, traits, recruitment, work priorities, Focus |
| [08 — The Skill Web](docs/08-skill-web.md) | Classless progression earned by doing |

### Combat & gear
| | |
|---|---|
| [09 — Combat](docs/09-combat.md) | The melee/ranged parity contract, and aiming |
| [29 — Movement & Stances](docs/29-movement-and-stances.md) | Crawl to sprint: speed as a decision about the attention field |
| [10 — Items](docs/10-items.md) | Bases, affixes, tiers, named items, attachments, decay |
| [11 — Crafting & Modification](docs/11-crafting.md) | Materials as currency; the gamble at the workbench |

### The world
| | |
|---|---|
| [12 — Resources](docs/12-resources.md) | The taxonomy, and the three resources that carry the economy |
| [13 — World Decay](docs/13-world-decay.md) | The clock that ensures nothing stays solved |
| [14 — Zombies](docs/14-zombies.md) | Behavior, types, hordes, mutation waves |
| [15 — Base Building](docs/15-base-building.md) | Steering the horde instead of blocking it |
| [16 — Weather](docs/16-weather.md) | Weather as an attention modifier |
| [17 — The Director](docs/17-director.md) | Pacing, lulls, storytellers |
| [18 — Factions](docs/18-factions.md) | Human raiders as a different threat shape *(post-slice)* |
| [24 — World & Scale](docs/24-world-and-scale.md) | The continuous region, districts, roads, route trails *(post-slice)* |
| [25 — Vehicles](docs/25-vehicles.md) | Found, customizable, and the loudest thing in the game *(post-slice)* |
| [26 — Mobile Bases](docs/26-mobile-bases.md) | Interior modules, convoys, and viable nomad play *(post-slice)* |

### Technical
| | |
|---|---|
| [19 — Architecture](docs/19-architecture.md) | Layers, determinism, the kernel-vs-module rule, the Godot port path |
| [20 — ECS & Content](docs/20-ecs-and-content.md) | Component model, data-driven content, mod-ready loading |
| [21 — Extensibility](docs/21-extensibility.md) | Event bus, modifier pipeline, and the add-a-feature cookbook |
| [22 — Performance](docs/22-performance.md) | Tiered simulation, field propagation, scaling to a horde |
| [27 — Multiplayer](docs/27-multiplayer.md) | Authoritative host, survivor-vs-survivor PVP, voice as an emitter *(post-slice)* |
| [23 — Roadmap](docs/23-roadmap.md) | The vertical slice, milestones, risks, open questions |
| [30 — Decision Records](docs/30-decisions.md) | What each chunk of work made structural, oldest first |
| [31 — Godot Rebuild Roadmap](docs/31-godot-rebuild-roadmap.md) | Transition phases, parity gates, delivery, and cutover |

## Reading order

New to the project? **[00](docs/00-vision.md) → [01](docs/01-hardcore-contract.md) →
[03](docs/03-attention.md) → [23](docs/23-roadmap.md)** covers the thesis, the tone, the central
mechanic, and what actually gets built.

Building it? Add **[19](docs/19-architecture.md) → [20](docs/20-ecs-and-content.md) →
[21](docs/21-extensibility.md)**, then **`CLAUDE.md`** and
**[where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands)** for where the code
actually is, and **[30](docs/30-decisions.md)** for why it is shaped that way.
