# 21 — Extensibility

*Why this exists: "modular" is a claim until you can show what adding a feature costs. This document
defines the two mechanisms that make modules independent — the event bus and the modifier pipeline —
and then proves the claim with worked examples.*

---

## Mechanism 1 — The event bus

### The problem it solves

Without it, systems call each other. Combat calls infection when a bite lands. Infection calls mood
when someone is quarantined. Mood calls the work scheduler. Within a month every system imports every
other system, and removing one breaks six.

With a bus, **systems publish facts and never name their consumers.** Adding a feature means
subscribing to something that already fires.

### The model

- Events are plain serializable data with a stable string type.
- Publishing is fire-and-forget; publishers never learn who listened.
- Events are queued and drained in a deterministic order within a tick.
- Events are part of the replay record ([architecture](19-architecture.md)).

```ts
bus.publish({ type: "bite.landed", victim: 41, source: 512, bodyPart: "arm.left" });
```

### Core events

| Domain | Events |
|---|---|
| **Time** | `phase.changed` · `day.started` · `night.fell` · `week.elapsed` |
| **Combat** | `attack.connected` · `bite.landed` · `grab.started` · `entity.staggered` · `entity.killed` |
| **Health** | `injury.sustained` · `injury.treated` · `bleeding.started` · `infection.staged` · `survivor.turned` |
| **Attention** | `noise.emitted` · `light.changed` · `scent.accumulated` |
| **Colony** | `survivor.joined` · `survivor.died` · `survivor.left` · `mood.threshold` · `relationship.changed` |
| **Structure** | `structure.built` · `structure.damaged` · `structure.breached` · `trap.triggered` |
| **World** | `weather.changed` · `decay.event` · `site.depleted` · `mutation.wave` |
| **Items** | `item.equipped` · `item.broke` · `modification.applied` · `modification.failed` |

**Rule:** an event states *what happened*, never *what should happen next*. `bite.landed`, not
`apply_infection`. The moment an event carries an imperative, it's a function call wearing a costume.

---

## Mechanism 2 — The modifier pipeline

### The problem it solves

Four genres' systems all touch the same numbers. Accuracy is affected by weather, injury, exhaustion,
stance, weapon condition, affixes, attachments, web nodes, mood, light, and traits. Hardcoding that is
an n² explosion, and every new system makes it worse.

### The model

Everything that changes a number emits a **modifier** into one resolver:

```ts
{ stat: "ranged_accuracy", op: "mul", value: 0.8, source: "weather.rain" }
```

| Field | Purpose |
|---|---|
| `stat` | A registered stat ID |
| `op` | `add` · `mul` · `min` · `max` · `set` |
| `value` | The magnitude |
| `source` | **A stable content ID** — required |

Resolution order is fixed: `add` → `mul` → clamps. Deterministic and order-independent within each op
class.

### Why `source` is mandatory

1. **Debuggability.** Any stat can be asked "why are you this number?" and answer with a full list of
   contributions — indispensable in a system where a dozen sources stack.
2. **Removal.** When rain stops, drop every modifier with source `weather.rain`. No bookkeeping, no
   leaks, no "why is he still inaccurate."
3. **Player-facing description.** The prose descriptions the
   [information rules](01-hardcore-contract.md) require are generated from sources — *"cold, tired,
   and that arm isn't right"* — without any system knowing about the others.

### Who emits modifiers

[Weather](16-weather.md) · [injuries](05-health-injury.md) · [needs and mood](04-survival-needs.md) ·
[traits](07-survivors.md) · [affixes and attachments](10-items.md) ·
[web nodes](08-skill-web.md) · [item condition](10-items.md) · [structures](15-base-building.md) ·
[infection stages](06-infection.md) · [sandbox settings](01-hardcore-contract.md).

**All through one pipeline.** None of them knows the others exist.

---

## The cookbook

Four worked examples, in increasing difficulty. Each is achievable using only mechanisms defined in
these documents — that's the verification criterion in the [roadmap](23-roadmap.md).

### Example 1 — A new zombie type (data only, zero code)

*Add a "Crawler": slow, low to the ground, easy to miss in a breach.*

1. Add `content/zombies/crawler.json` with sensory weights, locomotion, body values, and behavior tags
   drawn from the existing set (`shamble`, `pursue`, `grab_low`).
2. Set `introducedInWave`.
3. Add it to the relevant spawn weight tables.

**Code changes: none.** Provided every behavior tag already exists, this is the entire cost. See
[ECS & content](20-ecs-and-content.md).

### Example 2 — A new weather state (data only, zero code)

*Add "Hail": brief, violent, damaging.*

1. Add `content/weather/hail.json`: duration range, seasonal weights, and a modifier list —
   `noise_propagation ×1.4`, `ranged_accuracy ×0.6`, `structure_decay ×3.0`, `mood -8`,
   `temperature -4`.
2. Add it to the season distribution table.

**Code changes: none.** Every stat it references already exists, and
[weather](16-weather.md) already publishes `weather.changed` and manages modifier lifetime by source.

### Example 3 — A cross-system rule (one small subscriber)

*"Cold makes wounds heal slower."*

This touches [temperature](04-survival-needs.md) and [healing](05-health-injury.md) — two modules that
must not import each other.

1. Add a small rule in the health module subscribing to the existing temperature state.
2. It emits `{ stat: "healing_rate", op: "mul", value: 0.7, source: "rule.cold_healing" }` while cold.

**Code changes: one subscriber, ~10 lines.** Nothing in the temperature module changes; it doesn't
learn that healing exists. Nothing in the wound treatment code changes; it reads `healing_rate` as it
already did.

This is the shape most new mechanics take, and it's the real test of the architecture.

### Example 4 — A whole new subsystem (new module, nothing existing edited)

*Add electricity: wiring, load, brownouts, appliances competing for a generator's output.*

1. **New components:** `PowerProducer`, `PowerConsumer`, `PowerGrid`.
2. **New system:** `powerSystem`, declaring its slot in the [ordering](20-ecs-and-content.md) after
   structures.
3. **Subscribes to:** `structure.built`, `structure.damaged`, `decay.event` (grid failure).
4. **Publishes:** `power.available`, `power.lost`, `brownout.started`.
5. **Emits modifiers:** unpowered lights stop contributing to
   [light attention](03-attention.md); unpowered refrigeration raises the
   [spoilage rate](12-resources.md).
6. **New content:** `content/structures/*.json` gains power fields; schema extended.

**Code changes: entirely additive.** No existing system is edited. The lighting system doesn't learn
about electricity — it reads a stat that something else now modifies. Refrigeration doesn't check for
power — spoilage rate is a stat, and the power module moves it.

**And it's removable.** Disable the module and lights and refrigeration revert to unmodified stats.
The game still runs — which is the [kernel-vs-module rule](19-architecture.md) holding.

---

## Save and versioning policy

Per the user's decision, restated here because extensibility and save stability trade against each
other:

| | Decision |
|---|---|
| **Now (pre-1.0)** | Stable string IDs, schema version stamp, clean rejection of stale saves, **no migrations** |
| **At 1.0** | Revisit. Migrations become necessary once players have runs worth protecting. |

The reasoning: the [hardcore contract](01-hardcore-contract.md) means a run can be dozens of hours, so
saves matter *eventually*. But writing migrations against a design that gained three pillars during its
own design review is work that gets thrown away. Stable IDs are the part that makes migrations
*possible later*, and that part we do now.

## What "modular" is verified against

Not a claim — a CI check:

1. **Boot with each module disabled.** No crash, no NaN, no missing-stat errors.
2. **No cross-module imports** except through kernel, bus, and modifier pipeline. Enforced by lint.
3. **Every modifier has a resolvable source ID.**
4. **Every content reference resolves at load.**
5. **The cookbook examples stay true** — if example 4 stops being purely additive, the architecture
   has regressed.

## Cut list

- **A public mod scripting API.** Post-1.0, per the [content decision](20-ecs-and-content.md).
- **Dynamic event types registered at runtime.** Events are a fixed, versioned vocabulary; ad-hoc
  types would defeat the replay record.
- **Modifier conditions expressed in content** (a small DSL for "only at night"). Tempting; conditions
  live in code that emits and retracts modifiers instead. Revisit if the pattern recurs.
- **Save migrations.** Deferred to 1.0.

---

**Previous:** [20 — ECS & Content](20-ecs-and-content.md) ·
**Next:** [22 — Performance](22-performance.md) · [Doc index](../README.md#documentation)
