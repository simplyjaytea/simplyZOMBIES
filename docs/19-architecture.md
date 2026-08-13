# 19 — Architecture

*Why this exists: this design changed substantially four times before a line of code existed, and it
will change again. The architecture's primary job is not performance or elegance — it's absorbing
change cheaply.*

---

## Stack

**Godot 4.7.1 (Compatibility, typed GDScript) — the playable build and default development path.**

- The Godot project lives in `godot/` and is the authority for `sim/`, `presentation/`, and `platform/`.
- Web and Windows Desktop exports share one head (`Godot 4.7.1-stable`, `variant/thread_support=false`).
- The TypeScript / Canvas / Vite oracle is archived at tag **`ts-oracle-final`** — parity fixtures,
  oracle snapshots, and history are preserved; production no longer depends on that runtime.

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
│  godot/platform/ input · audio · storage · timing │  ← interfaces, swappable
├──────────────────────────────────────────────────┤
│  godot/presentation/ scenes · camera · Controls   │  ← reads sim, never writes
├──────────────────────────────────────────────────┤
│  godot/sim/      THE GAME                          │  ← typed GDScript, no engine types in state
│                  kernel + modules                  │
├──────────────────────────────────────────────────┤
│  godot/content/  JSON: items, zombies, affixes…   │  ← data, engine-agnostic
└──────────────────────────────────────────────────┘
```

`src/` (TypeScript sim/render/platform) is retained only under the oracle tag for reference and
parity. New work targets `godot/` (see also [31 — Rebuild](31-godot-rebuild-roadmap.md) for transition
history — this document is the final architecture, not a transition diary).

### `godot/sim/` — the hard rules

These are enforced by review and CI, not by good intentions:

| Rule | Why |
|---|---|
| **No Nodes, no scene-tree behavior, no physics callbacks in state** | Determinism and parity |
| **No `randf` / `randi` — seeded `RngStream` only** | Determinism |
| **No `Time.get_ticks_*` / `OS.get_*` in simulation logic** — tick counter only | Determinism |
| **No engine type crosses the state boundary** (`Vector2`, `RID`, `Resource`, `Callable`, `Node`) | Headless and cross-target replay |
| **All state plain and serializable** (`Dictionary`/`Array` scalars) | Saves, replays, parity |
| **Fixed timestep** (`tick_hz = 20`) | Determinism |

`godot/sim/` is most of the game by volume and complexity, and it can be run, tested, and reasoned about
with no window present.

### `godot/presentation/`

Reads simulation state and draws it. **Never writes to the simulation.** Player input goes through
`platform/` into a command queue that the sim consumes on its own tick — so input is part of the
deterministic record.

### `godot/content/`

JSON with stable string IDs. Fully engine-agnostic; see [ECS & content](20-ecs-and-content.md).

### `godot/platform/`

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

Godot is now the host; the contract below is retained as the state boundary that made parity
checkable:

| Layer | On a pivot |
|---|---|
| `godot/content/` | **Transferred verbatim.** The one canonical tree both engines read during overlap. |
| `sim/` | Typed-GDScript reimplementation against deterministic fixtures and behavior tests |
| `render/` / `presentation/` | Engine-owned presentation; sim never owns a renderer |
| `platform/` | Small interface implementations |

**The one rule that makes this true: no engine type ever crosses into `sim/`.** No `Vector2` from a
graphics library, no node references, no framework base classes. Vectors and shapes are plain data
structures owned by `sim/`.

This rule is cheap to hold from day one and expensive to retrofit later, which is exactly the kind of
decision that belongs in an architecture document written before any code exists. It is also the same
rule that enables headless CI simulation — so it pays for itself immediately.

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

Persistence adapters live in `godot/platform/storage.gd` (desktop atomic temp+flush+rename; web
double-buffer). No `Resource` or engine type crosses into save state.

## Testing strategy

| Level | What |
|---|---|
| **Unit** | Pure functions: modifier resolution, affix rolling, attention propagation, pathing |
| **System** | One module in isolation against a synthetic world |
| **Integration** | Boot the sim headless, run N days, assert invariants |
| **Module isolation** | Boot with each module disabled; assert no crash |
| **Determinism** | Same seed and inputs twice → byte-identical state |
| **Parity** | Shared seed + command log through reference → canonical snapshots each tick (ledger: `godot/parity/ledger.md`) |
| **Gates** | Content, determinism, deploy, perf — mutation-tested |
| **Soak** | Memory, save corruption, input loss, pause/resume, tab focus (5k ticks) |
| **Balance** | Thousands of headless runs; assert distributions are in range |

The parity ledger is the cutover gate: every prior test file maps to an exact Godot test, a paired
fixture, a replacement, or an explicit obsolete rationale — "not ported" is not a category.

## Repository layout

```
simplyZOMBIES/
├── docs/              this document set
├── godot/             Godot 4.7.1 project — the playable build
│   ├── sim/           typed, fixed-tick authoritative state and systems
│   ├── presentation/  scenes that read state and submit commands
│   ├── platform/      content, persistence, input, and timing adapters
│   ├── content/       the canonical JSON + schemas
│   ├── parity/        shared seed/command fixtures and oracle snapshots + ledger
│   ├── bench/         headless tick budgets (Web/Windows multi-target; see below)
│   ├── export_presets.cfg  Web + Windows Desktop (thread_support=false)
│   └── ...            check_r6_*.gd gates
├── scripts/           run-godot, export smoke, oracle tooling
├── src/               TypeScript oracle — archived at tag ts-oracle-final (not built by default)
├── test/              TypeScript test suite (reference; Godot suite is under godot/)
└── bench/             TypeScript bench configs (reference; headless Godot bench is godot/bench/)
```

## Cut list

- **A third-party ECS or framework inside the simulation.** Godot hosts and presents the game, but
  the [ECS we need](20-ecs-and-content.md) remains small and bespoke; Nodes, physics, or an add-on
  becoming authoritative simulation state would break the determinism boundary.
- **Save migrations.** Deferred to 1.0 by explicit decision.
- **Hot module reloading of game logic.** Content hot-reload is worth having; code hot-reload isn't.
- **TypeScript runtime as a shipping build.** Archived as oracle; rollback is to the tag, not to a
  second production implementation.

---

**Previous:** [26 — Mobile Bases](26-mobile-bases.md) ·
**Next:** [20 — ECS & Content](20-ecs-and-content.md) · [Doc index](../README.md#documentation)
