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

## Where it stands

**The spine is built and playable. There is no game on top of it yet.**

```bash
npm install
npm run dev        # http://127.0.0.1:5174
```

`WASD` move · `Shift` sprint · `Space` swing, or struggle if something has hold of you · `P` pause ·
`F5`/`F9` save and load · `F3` state fingerprint · `F4` attention overlay *(developer-only)*

What that gets you today: a procedurally generated district you can walk around, an attention field
you can make noise into, shamblers that walk up its gradient and arrive where you were loud, and a
melee loop that decides whether you survive them arriving. Turn the overlay on and you can watch the
thing the whole game is built around — noise blooming out of a fight and the crowd turning toward it.

| Milestone | State |
|---|---|
| **0 — The kernel** | ✅ Deterministic tick loop, ECS, modifier pipeline, content registry, renderer, input, save/load, CI budget gates |
| **1 — The spine** | Field, spatial hash, shamblers, and combat done. **The day/night cycle is the last piece.** |
| **2 — The vertical slice** | Not started. Survivors, needs, injury, infection, base building, the director |

### Working now

- **The attention field.** Three channels on a 4 m grid: noise floods *around* buildings, light is
  occluded by them, scent diffuses downwind over hours. Make noise and they come; go quiet and they
  genuinely don't — both halves are asserted, because a horde that converges regardless of what you
  do would pass any test that only checked the loud half.
- **A horde, not a queue.** Every zombie carries a permanent angular bias on its gradient reading,
  which is the difference between a crowd and a conga line. They investigate, mill, and leave scent
  behind, so a place you made a mistake stays a bad neighbourhood afterwards.
- **Melee.** Wind-up → connect → recovery, all interruptible. Stamina scaled by weapon weight,
  stagger, reach, grabs, bite risk. Weapons are JSON. Let three of them get hold of you and you do
  not get back up.
- **Determinism.** Same seed plus the same inputs reproduces byte-identically, saves included.

### Not built yet

- **The clock** — dawn/day/dusk/night and speed controls. Last of Milestone 1, and the point at
  which the loop above becomes a *day* rather than a sandbox.
- **People** — survivors are one controlled body. No generator, traits, needs, work priorities, or
  succession, so permadeath currently means the run stops rather than continues.
- **Consequences** — a bite is recorded and nothing happens next. Injury, infection and turning are
  Milestone 2.
- **Everything you'd build** — no resources, loot, crafting, walls, or director.

[TODO.md](TODO.md) is the executable version of this, task by task, with all eight roadmap risks
pinned to the task that answers each. **[HANDOFF.md](HANDOFF.md) is where to start if you're picking
this up cold**, or if you're an agent.

**Stack:** TypeScript, HTML canvas, Vite, no engine — with a
[portability contract](docs/19-architecture.md#the-portability-contract) that keeps a pivot to Godot 4
cheap.

## How it's being built

The order is deliberate, and it is not the order that feels productive.

**Documents first, then a throwaway.** All 27 design documents existed before a line of production
code, and the first code written was a [prototype in `spike/`](spike/README.md) built to be deleted —
one screen, no architecture, testing only whether "make noise and they come" is fun before anything
expensive was built on the assumption that it is. It found three problems, one of which (gradient
ascent produces conga lines) would have been an expensive thing to discover in Milestone 2.

**Rules are enforced, not intended.** A convention that lives in a review comment is a convention
that erodes. So: `sim/` compiles with no DOM library at all, which makes browser access a type error
rather than a note; `step(world)` takes no time argument, so the simulation *cannot* read a clock;
every iteration order is sorted, because registration order is import order and bundlers reorder
that; content fails at load with the file, entry and field named, never silently at hour thirty; and
performance budgets fail the build at the same severity as a failing test.

**Nothing is a special case.** Every system outside the kernel is a module that can be switched off,
and CI boots the game with each one disabled and with all of them disabled. That is not a robustness
exercise — it is how sandbox presets and storyteller settings get implemented later, so the mechanism
is being exercised now rather than retrofitted.

**Assume nothing; measure it.** This has repeatedly been the difference between a feature and a
decoration. Field memory was specified, implemented, and *still* had to prove that switching it off
changed where the horde ended up — the earlier prototype's version existed and did nothing. Three
performance budgets have now reported comfortable numbers while measuring nothing at all: a frame
budget that excluded the most expensive thing in the frame, a horde benchmark where 498 of 500
zombies stood still, and a combat benchmark where 460 of them never moved. Each was found by
checking that the scenario was doing the thing, not by the number looking wrong.

**Every guard gets broken on purpose.** New protections are mutation-tested — break the thing, confirm
something goes red, put it back — and the results go in the commit message. It has caught guards that
looked rigorous and tested nothing. A green suite says nothing about whether it *can* go red.

## Documentation

The tables below are the authority on **reading order**. File numbers reflect the order documents were
written, so 24–26 sit under "The world" rather than at the end.

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
| [23 — Roadmap](docs/23-roadmap.md) | The vertical slice, milestones, risks, open questions |

## Reading order

New to the project? **[00](docs/00-vision.md) → [01](docs/01-hardcore-contract.md) →
[03](docs/03-attention.md) → [23](docs/23-roadmap.md)** covers the thesis, the tone, the central
mechanic, and what actually gets built.

Building it? Add **[19](docs/19-architecture.md) → [20](docs/20-ecs-and-content.md) →
[21](docs/21-extensibility.md)**.
