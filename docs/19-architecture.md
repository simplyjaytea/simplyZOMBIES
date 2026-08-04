# 19 — Architecture

*Why this exists: this design changed substantially four times before a line of code existed, and it
will change again. The architecture's primary job is not performance or elegance — it's absorbing
change cheaply.*

---

## Stack

**TypeScript, HTML canvas, Vite, no engine.** Chosen because:

- The simulation is the hard part, and it's engine-agnostic either way.
- Browser output means it's runnable and screenshottable during development without a build/install
  cycle.
- Vitest runs the sim headlessly, which the [director](17-director.md) and balance work depend on.
- **The Godot door stays open** — see the portability contract below.

## One spine, many optional limbs

The single most important structural rule:

> **Kernel:** the tick loop, the entity store, the event bus, and the
> [attention field](03-attention.md).
> **Everything else is a module.**

[Weather](16-weather.md), the [director](17-director.md), [factions](18-factions.md), the
[skill web](08-skill-web.md), [crafting](11-crafting.md), [infection](06-infection.md),
[needs](04-survival-needs.md) — all modules. Each registers itself, subscribes to events, and
contributes [modifiers](21-extensibility.md).

**Testable property:** the game must boot and run with any non-kernel module disabled. This is checked
in CI by booting with each module individually switched off. It's also how the
[sandbox presets](01-hardcore-contract.md#sandbox-settings) and the
["Nothing Personal" storyteller](17-director.md#storytellers) are implemented — they're not special
cases, they're module configuration.

## Layers

```
┌──────────────────────────────────────────────────┐
│  platform/     input · audio · storage · timing  │  ← interfaces, swappable
├──────────────────────────────────────────────────┤
│  render/       canvas drawing · camera · UI      │  ← reads sim, never writes
├──────────────────────────────────────────────────┤
│  sim/          THE GAME                          │  ← pure TS, no engine types
│                kernel + modules                  │
├──────────────────────────────────────────────────┤
│  content/      JSON: items, zombies, affixes…    │  ← data, engine-agnostic
└──────────────────────────────────────────────────┘
```

### `sim/` — the hard rules

These are enforced by lint rules and CI, not by good intentions:

| Rule | Why |
|---|---|
| **No DOM, no canvas, no browser globals** | Portability and headless testing |
| **No `Math.random`** — seeded RNG only | Determinism |
| **No `Date.now()`** — tick counter only | Determinism |
| **No engine or renderer types cross the boundary** | The expensive rule to retrofit |
| **All state plain and serializable** | Saves, replays, and the port |
| **Fixed timestep** | Determinism |

`sim/` is most of the game by volume and complexity, and it can be run, tested, and reasoned about
with no browser present.

### `render/`
Reads simulation state and draws it. **Never writes to the simulation.** Player input goes through
`platform/` into a command queue that the sim consumes on its own tick — so input is part of the
deterministic record.

### `content/`
JSON with stable string IDs. Fully engine-agnostic; see [ECS & content](20-ecs-and-content.md).

### `platform/`
Thin adapters behind interfaces: input, audio, persistence, timing. The only layer that knows what
platform it's on.

## Determinism

Fixed timestep, seeded RNG per subsystem, plain state, and an input command log. Consequences:

- **A seed plus an input log reproduces a run exactly.** Every death is reconstructible, which is what
  the [fairness rules](01-hardcore-contract.md#fairness-rules) promise.
- **Bug reports become seeds.** "It crashed on night 12" is reproducible rather than anecdotal.
- **Balance becomes measurable.** A thousand headless colonies across seeds produce a distribution, so
  a tuning change's effect is a number that moved. This is how the [director](17-director.md) gets
  validated and it is not optional for a simulation this size.
- **Regression testing works.** Same seed and inputs before and after a refactor should produce
  identical state; divergence localizes the change.

**Rule:** any nondeterminism introduced into `sim/` is a bug of the same severity as a crash.

## The portability contract

TypeScript now, with a cheap pivot to Godot 4 if the browser stops being the right target.

| Layer | On a pivot |
|---|---|
| `content/` | **Transfers verbatim.** JSON is JSON. |
| `sim/` | Mechanical TS→GDScript translation, *or* keep it as-is behind WASM/GDExtension |
| `render/` | Rewritten — but it would be rewritten anyway; that's the point of switching engines |
| `platform/` | Rewritten — small, and it's an interface implementation |

**The one rule that makes this true: no engine type ever crosses into `sim/`.** No `Vector2` from a
graphics library, no node references, no framework base classes. Vectors and shapes are plain data
structures owned by `sim/`.

This rule is cheap to hold from day one and expensive to retrofit later, which is exactly the kind of
decision that belongs in an architecture document written before any code exists. It is also the same
rule that enables headless CI simulation — so it pays for itself immediately, not just on a
hypothetical port.

## Save model

Per the user's decision, **saves may break pre-1.0**:

- Stable string IDs throughout, never array indices.
- A schema version stamp in every save.
- **Old saves are detected and rejected cleanly** with a clear message. No silent corruption.
- **No migration framework**, because writing migrations against a design that's still moving is
  wasted work. Revisit at 1.0.

The [hardcore contract](01-hardcore-contract.md#6-death-is-permanent-the-save-is-single-slot) requires
single-slot, continuously-written saves with no save-scumming — so saving is frequent and must be fast
and atomic. Plain serializable state makes both achievable.

## Testing strategy

| Level | What |
|---|---|
| **Unit** | Pure functions: modifier resolution, affix rolling, attention propagation, pathing |
| **System** | One module in isolation against a synthetic world |
| **Integration** | Boot the sim headless, run N days, assert invariants (nobody starves in a stocked colony; the field decays; nothing NaNs) |
| **Module isolation** | Boot with each module disabled; assert no crash |
| **Determinism** | Same seed and inputs twice → byte-identical state |
| **Balance** | Thousands of headless runs; assert distributions are in range |

The balance tier is the unusual one and the most valuable. It's only possible because of the `sim/`
purity rules.

## Repository layout

```
simplyZOMBIES/
├── docs/              this document set
├── src/
│   ├── sim/
│   │   ├── kernel/    tick · entities · events · attention field
│   │   ├── modules/   needs · health · infection · combat · weather · director · …
│   │   └── rng/       seeded generators
│   ├── render/
│   ├── platform/
│   └── ui/
├── content/           JSON + schemas
└── test/
    ├── unit/
    ├── integration/
    └── balance/       headless multi-run harness
```

## Cut list

- **A third-party ECS or game framework.** The [ECS we need](20-ecs-and-content.md) is small and
  bespoke; a dependency would import engine types into `sim/` and break the portability rule.
- **Networking / multiplayer scaffolding.** Cut at the [vision](00-vision.md) level.
- **Save migrations.** Deferred to 1.0 by explicit decision.
- **Hot module reloading of game logic.** Content hot-reload is worth having; code hot-reload isn't.

---

**Previous:** [18 — Factions](18-factions.md) ·
**Next:** [20 — ECS & Content](20-ecs-and-content.md) · [Doc index](../README.md#documentation)
