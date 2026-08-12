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

**Playable, and early.** Milestones 0 and 1 are complete. Make noise and the district converges;
stay quiet and scent still brings danger eventually. Walls block sight, surfaces change speed and
footstep noise, and midnight closes bare-eyed vision to only a few metres unless you find a light.
Five movement stances trade time, stamina, visibility, and noise. Melee commits you to a swing, while
contact can pin, bite, and force a stamina-paid struggle. Gear already rolls affixes and fits into a
rotatable, nested grid inventory, and wounds appear on a descriptive body-part view rather than a
health bar.

Milestone 2 is the colony-sized vertical slice: generated survivors, needs and work, the complete
injury and uncertain-infection loops, ranged combat, building, pacing, death, and succession.

**[Play the latest main build](https://simplyjaytea.github.io/simplyZOMBIES/).** Every push to `main`
that passes the correctness and performance checks automatically replaces this playable build;
failed checks are never published.

```bash
npm install && npm run dev     # http://127.0.0.1:5174
```

`WASD` move · `Shift` sprint · `F` swing or struggle · `Space` **shout** · `E` pick up · `Tab` **inventory**
(drag to move, right-click or `R` to rotate) · `O` cycles the attention overlay (noise, scent, sight)
· `1`/`2`/`3` speed · `P` pause · `F5`/`F9` save and load.

A day is four hours at 1×, so press `3` and wait for dark.

**Stack:** TypeScript, HTML canvas, Vite, no engine — with a
[portability contract](docs/19-architecture.md#the-portability-contract) that keeps a pivot to Godot 4
cheap.

## Working on it?

**[HANDOFF.md](HANDOFF.md) is the engineer's document and the place to start.** It carries current
implementation state, verification, the task backlog, and what to pick up next.
[docs/23-roadmap.md](docs/23-roadmap.md) owns product scope, milestone order, risks, and playtest
questions; [docs/30-decisions.md](docs/30-decisions.md) records what each completed chunk made
structural and is worth reading before changing something that looks arbitrary.

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

## Reading order

New to the project? **[00](docs/00-vision.md) → [01](docs/01-hardcore-contract.md) →
[03](docs/03-attention.md) → [23](docs/23-roadmap.md)** covers the thesis, the tone, the central
mechanic, and what actually gets built.

Building it? Add **[19](docs/19-architecture.md) → [20](docs/20-ecs-and-content.md) →
[21](docs/21-extensibility.md)**, then **[HANDOFF.md](HANDOFF.md)** for where the code actually is and
**[30](docs/30-decisions.md)** for why it is shaped that way.
