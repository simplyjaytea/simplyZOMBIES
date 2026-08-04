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

- **One field ties four genres together.** Noise, light, and scent form a map-wide gradient the horde
  walks up. Cooking, warmth, electricity, gunfire, and every extra person feed it. Survival and tower
  defense are the same system read from two directions.
- **Nobody has a class.** Your survivor is a blank slate, and so is everyone you recruit. Your build
  is the gear you found and modified, plus a classless skill web earned by doing.
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

## Status

**Design phase.** No code yet — this repository currently contains the design document set below. The
[roadmap](docs/23-roadmap.md) defines the vertical slice that gets built first and the risks that
might sink it, and [TODO.md](TODO.md) breaks that into an executable backlog.

**Planned stack:** TypeScript, HTML canvas, Vite, no engine — with a
[portability contract](docs/19-architecture.md#the-portability-contract) that keeps a pivot to Godot 4
cheap.

## Documentation

### Foundations
| | |
|---|---|
| [00 — Vision](docs/00-vision.md) | Pillars, genre influences, what this game is *not* |
| [01 — The Hardcore Contract](docs/01-hardcore-contract.md) | Lethality, permadeath, succession, imperfect information, no win state |
| [02 — Core Loop](docs/02-core-loop.md) | The dawn/day/dusk/night ratchet |
| [03 — The Attention Field](docs/03-attention.md) | **The spine.** Noise, light, scent, and how the horde reads them |

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
| [09 — Combat](docs/09-combat.md) | The melee/ranged parity contract |
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

### Technical
| | |
|---|---|
| [19 — Architecture](docs/19-architecture.md) | Layers, determinism, the kernel-vs-module rule, the Godot port path |
| [20 — ECS & Content](docs/20-ecs-and-content.md) | Component model, data-driven content, mod-ready loading |
| [21 — Extensibility](docs/21-extensibility.md) | Event bus, modifier pipeline, and the add-a-feature cookbook |
| [22 — Performance](docs/22-performance.md) | Tiered simulation, field propagation, scaling to a horde |
| [23 — Roadmap](docs/23-roadmap.md) | The vertical slice, milestones, risks, open questions |

## Reading order

New to the project? **[00](docs/00-vision.md) → [01](docs/01-hardcore-contract.md) →
[03](docs/03-attention.md) → [23](docs/23-roadmap.md)** covers the thesis, the tone, the central
mechanic, and what actually gets built.

Building it? Add **[19](docs/19-architecture.md) → [20](docs/20-ecs-and-content.md) →
[21](docs/21-extensibility.md)**.
