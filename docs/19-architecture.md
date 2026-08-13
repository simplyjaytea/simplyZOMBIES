# 19 — Architecture

*Why this exists: this design changed substantially four times before a line of code existed, and it
will change again. The architecture's primary job is not performance or elegance — it's absorbing
change cheaply.*

---

## Stack

**Current playable reference: TypeScript, HTML canvas, Vite, no engine.** Chosen because:

- The simulation is the hard part, and it's engine-agnostic either way.
- Browser output means it's runnable and screenshottable during development without a build/install
  cycle.
- Vitest runs the sim headlessly, which the [director](17-director.md) and balance work depend on.
- **The Godot door stayed open** — and the rebuild through it is now planned in
  [docs/31](31-godot-rebuild-roadmap.md).

This document describes the architecture that earned the pivot and remains authoritative while the
TypeScript build is the oracle. The rebuild roadmap owns transition order and parity gates. At
cutover, this document is rewritten around the final Godot project rather than retaining two stacks
as permanent architecture.

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
│  godot/content/ JSON: items, zombies, affixes…   │  ← data, engine-agnostic
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

### `godot/content/`
JSON with stable string IDs. Fully engine-agnostic; see [ECS & content](20-ecs-and-content.md).

### `platform/`
Thin adapters behind interfaces: input, audio, persistence, timing. The only layer that knows what
platform it's on.

### The host/client boundary

[Multiplayer](27-multiplayer.md) adds a networked host, and it adds **no layer**. Networking is a
`platform/` adapter like input or storage; the host runs the same `sim/` kernel headless, and `sim/`
stays unaware it is being hosted.

| Rule | Why |
|---|---|
| **Networking lives in `platform/`** | Same reason the clock does — `sim/` must stay pure and portable |
| **`sim/` never learns it is networked** | A networked run and a local run are the same function of seed and commands |
| **Commands cross the wire; state does not** | Keeps the deterministic record the wire format, and the replay honest |
| **The host filters state per client before sending** | [Clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable): a client that never receives a position cannot render one |

Ordering is the part that is easy to get wrong: merged commands are sorted by `(tick, playerId, seq)`
before the tick, for the same reason the [modifier pipeline](21-extensibility.md) sorts its fold — a
result that depends on arrival order is not deterministic.

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

The pivot to Godot 4 is approved. The contract below now governs a controlled rebuild rather than a
hypothetical escape hatch; [docs/31](31-godot-rebuild-roadmap.md) owns its execution.

| Layer | On a pivot |
|---|---|
| `godot/content/` | **Transferred verbatim.** It is the one canonical tree both engines read during overlap. |
| `sim/` | Clean typed-GDScript reimplementation against deterministic fixtures and behavior tests |
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
├── godot/             Godot 4.7.1 project root
│   ├── sim/           typed, fixed-tick authoritative state and systems
│   ├── presentation/  scenes that read state and submit commands
│   ├── platform/      content now; persistence, input, and timing adapters as they port
│   ├── content/       the canonical JSON + schemas, read by both engines during transition
│   ├── parity/        shared seed/command fixtures and TypeScript oracle snapshots
│   └── test/          headless parity and project-load gates
└── test/
    ├── unit/
    ├── integration/
    └── balance/       headless multi-run harness
```

## Cut list

- **A third-party ECS or framework inside the simulation.** Godot will host and present the game, but
  the [ECS we need](20-ecs-and-content.md) remains small and bespoke; Nodes, physics, or an add-on
  becoming authoritative simulation state would break the determinism boundary.
- **Save migrations.** Deferred to 1.0 by explicit decision.
- **Hot module reloading of game logic.** Content hot-reload is worth having; code hot-reload isn't.

---

**Previous:** [26 — Mobile Bases](26-mobile-bases.md) ·
**Next:** [20 — ECS & Content](20-ecs-and-content.md) · [Doc index](../README.md#documentation)
