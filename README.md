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
- **A vehicle is the loudest thing you own.** An engine emits more noise than a rifle, continuously,
  for as long as it runs — so driving is announcing yourself to a whole district. Vehicles are found
  and customized like any other gear, and a fitted-out van is a
  [home you can drive away from a siege](docs/26-mobile-bases.md).

## Status

**Milestone 1, in progress — and it is playable.** Milestone 0 built the architecture; two channels of
the [attention field](docs/03-attention.md) now sit on top of it, with shamblers that climb them. Make
a noise and the district walks toward you in a minute; make none and scent still finds you, in an
hour. And as of the [visibility primitive](docs/28-visibility-and-sightlines.md), **you only see what
you can see** — walls, windows, foliage and low cover are four different answers to that, and a body
you lose behind a building leaves a fading mark rather than vanishing.

The [ground](docs/24-world-and-scale.md#the-ground) decides the rest: pavement, dirt, grass,
undergrowth and rubble each change how fast you cross them and how far your footsteps carry. The
street is the quick way and it announces you; the yards are slow and quiet; the brambles are the only
cover on open ground and they are slow *and* loud.

And there is a [clock](docs/02-core-loop.md). Four phases, a sun that rises and sets, and a night
that takes your sight from 48 metres down to 12 — night is a smaller view, not a darker screen.
The melee loop is built — wind-up, connect or miss, recovery, stamina, stagger, reach, and a
zombie damage model where the head and the legs are what matter. Light emitters and **grabs**
are the rest of the milestone; without grabs there is no bite risk, so melee does not yet pay
the currency the parity contract says it must.

```bash
npm install && npm run dev     # http://127.0.0.1:5174
```

`WASD` move · `Shift` sprint · `Space` **shout** · `O` cycles the attention overlay (noise, scent,
sight) · `1`/`2`/`3` speed · `P` pause · `F5`/`F9` save and load.

A day is four hours at 1×, so press `3` and wait for dark.

The [roadmap](docs/23-roadmap.md) defines the vertical slice that gets built first and the risks that
might sink it, [TODO.md](TODO.md) breaks that into an executable backlog, and
**[HANDOFF.md](HANDOFF.md) is where to start if you're picking this up cold.**

**Stack:** TypeScript, HTML canvas, Vite, no engine — with a
[portability contract](docs/19-architecture.md#the-portability-contract) that keeps a pivot to Godot 4
cheap.

## Documentation

The tables below are the authority on **reading order**. File numbers reflect the order documents were
written, so 24–26 sit under "The world", 28 sits next to the spine it serves, and 29 sits next to
combat rather than all four landing at the end.

### Foundations
| | |
|---|---|
| [00 — Vision](docs/00-vision.md) | Pillars, genre influences, what this game is *not* |
| [01 — The Hardcore Contract](docs/01-hardcore-contract.md) | Lethality, permadeath, succession, imperfect information, no win state |
| [02 — Core Loop](docs/02-core-loop.md) | The dawn/day/dusk/night ratchet |
| [03 — The Attention Field](docs/03-attention.md) | **The spine.** Noise, light, scent, and how the horde reads them |
| [28 — Visibility & Sightlines](docs/28-visibility-and-sightlines.md) | One line-of-sight primitive: the light channel, what the renderer may draw, what a client may know |

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

## Reading order

New to the project? **[00](docs/00-vision.md) → [01](docs/01-hardcore-contract.md) →
[03](docs/03-attention.md) → [23](docs/23-roadmap.md)** covers the thesis, the tone, the central
mechanic, and what actually gets built.

Building it? Add **[19](docs/19-architecture.md) → [20](docs/20-ecs-and-content.md) →
[21](docs/21-extensibility.md)**.
