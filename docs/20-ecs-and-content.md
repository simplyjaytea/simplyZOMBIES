# 20 — ECS & Content

*Why this exists: two mechanisms carry most of the "easily changeable" mandate. ECS makes new
behavior additive rather than invasive; data-driven content makes new **things** a JSON edit with no
code at all.*

---

## Part 1: ECS

### Why

The alternative — a `Survivor` class with fields for needs, injuries, infection, skills, inventory,
relationships, and mood — has a specific failure mode: every new system edits that class, every system
knows about every other system, and adding "survivors can catch a cold" means touching code that has
nothing to do with colds.

With ECS, that feature is a new component and a new system. **Nothing existing is edited.** That's the
mandate, expressed structurally.

It's also the answer to scale — component arrays iterate fast, which matters at a thousand entities
([performance](22-performance.md)).

### The model

- **Entity** — an integer ID. No data, no behavior.
- **Component** — plain serializable data attached to an entity. No methods.
- **System** — a function over entities matching a component query, run each tick in a defined order.

Survivors, zombies, items, structures, and corpses are all entities. What distinguishes them is which
components they carry.

### Component inventory

Grouped by owning module. Kernel components are the only ones every entity may rely on.

| Module | Components |
|---|---|
| **Kernel** | `Position` · `Velocity` · `Facing` · `Solid` · `AttentionEmitter` · `Tags` |
| **Actor** | `Actor` · `Faction` · `Perception` · `Locomotion` · `Inventory` · `Equipment` |
| **Survivor** | `Identity` · `Traits` · `Backstory` · `Skills` · `WebNodes` · `Focus` · `WorkPriorities` · `Relationships` |
| **Needs** | `Hunger` · `Thirst` · `Rest` · `Temperature` · `Hygiene` · `Mood` |
| **Health** | `Body` (parts) · `Injuries` · `BloodLoss` · `Pain` · `Stamina` · `BacterialInfection` |
| **Infection** | `ZombieInfection` (stage, private transmitted flag, observation record) |
| **Zombie** | `Zombie` · `SensoryProfile` · `GrabState` · `MutationType` |
| **Item** | `Item` · `ItemBase` · `Affixes` · `Attachments` · `Condition` · `Stackable` |
| **Structure** | `Structure` · `Durability` · `BuildProgress` · `Powered` · `Trap` |
| **Horde** | `Horde` (coarse-sim aggregate) · `Bearing` |

`Facing` is kernel rather than module-owned for the reason the rule below implies: two systems that
do not own each other read it — [sightlines](28-visibility-and-sightlines.md#what-an-observer-is) and
[aiming](09-combat.md#aiming) — so a module-owned heading would mean one of them reaching into the
other's data, or a second heading drifting out of agreement with the first.

**Rule:** a module may define components and read others', but only its owning module writes to a
component. Cross-module effects go through [events and modifiers](21-extensibility.md), never by
reaching into another module's data.

### System ordering

Systems run in a fixed, declared order each tick — determinism requires it
([architecture](19-architecture.md)). Ordering is data, not code:

```
input → ai/decision → movement → combat → attention-emit → attention-propagate
      → needs → health → infection → structures → director → cleanup
```

A module declares where it inserts. Adding a system doesn't require editing a hardcoded list.

### What ECS is *not* used for

Singletons — the [attention field](03-attention.md), [weather](16-weather.md) state, the
[director](17-director.md), the world clock — are plain serializable state on the world object, not
entities. Forcing them into ECS would be dogma without benefit.

---

## Part 2: Content

### The rule

> **If it's a *thing* in the game, it's a JSON entry.**

Zombie types · item bases · affixes · attachments · named items · injuries · web nodes · traits ·
backstories · name pools · recipes · modification consumables · resources · loot tables · structures ·
traps · weather states · decay events · director events · storyteller presets · factions.

None of these require code to add.

### Stable string IDs

Every content entry has a namespaced string ID, permanent once shipped:

```
zombie.screamer · item.axe.fire · affix.prefix.serrated
web.melee.reach_control · injury.fracture · weather.storm
```

Never array indices. Saves, cross-references, and modifier sources all use these, so content can be
reordered, inserted, and removed without breaking anything that survives a restart.

Renaming an ID is a breaking change. Removing one is a breaking change. Both are acceptable pre-1.0
per the [save policy](19-architecture.md#save-model), and neither is acceptable after.

### Example: a zombie type

```json
{
  "id": "zombie.screamer",
  "extends": "zombie.base",
  "introducedInWave": 1,
  "sensory": { "noise": 0.4, "light": 0.9, "scent": 0.2 },
  "locomotion": { "speed": 1.1 },
  "body": { "head": 20, "torso": 40, "legs": 30 },
  "grab": { "strength": 0.3 },
  "emits": [ { "channel": "noise", "magnitude": 4 } ],
  "behaviors": [ "shamble", "pursue", "alarm_on_sight" ],
  "alarm": { "magnitude": 300, "relay": true, "cooldownTicks": 600 }
}
```

Adding this file is the entire cost of adding a screamer, because every behavior tag it references
already exists. This is [cookbook](21-extensibility.md) example #1.

### Example: an affix

```json
{
  "id": "affix.suffix.quiet_hand",
  "name": "of the Quiet Hand",
  "slot": "suffix",
  "appliesTo": [ "weapon.melee", "weapon.ranged" ],
  "tiers": [
    { "weight": 100, "modifiers": [ { "stat": "noise_emission", "op": "mul", "value": 0.85 } ] },
    { "weight": 40,  "modifiers": [ { "stat": "noise_emission", "op": "mul", "value": 0.75 } ] },
    { "weight": 10,  "modifiers": [ { "stat": "noise_emission", "op": "mul", "value": 0.60 } ] }
  ]
}
```

Note that the effect is a [modifier](21-extensibility.md), the same structure a web node, a weather
state, and an injury use. One resolver serves all of them.

### Schemas and validation

Every content type has a JSON Schema. Content is validated **at build time and at load time**, with
failures naming the file, the entry, and the field.

Additional load-time checks beyond schema shape:

- Every referenced ID resolves (no affix pointing at a nonexistent stat)
- No duplicate IDs
- No circular `extends` chains
- Every modifier's `stat` exists in the stat registry
- Every behavior tag is implemented

**Content errors must fail loudly at load, never silently at hour thirty.**

### The registry

Content loads through a registry that walks content directories, parses, validates, resolves
`extends`, and indexes by ID. Systems query the registry; nothing hardcodes content.

### Mod-ready, not mod-complete

Per the user's decision:

**Now:**
- The registry loads *directories*, not a fixed file list
- **The project's own content ships through that exact path** — so the loading mechanism is exercised
  on every single run and cannot quietly rot
- Stable IDs and namespacing already support third-party content
- `extends` allows overriding a base without copying it

**Deferred to post-1.0:**
- A public scripting API for behavior that isn't expressible as data
- Sandboxing untrusted mod code
- Load-order and conflict resolution
- Mod-facing documentation and tooling

The cost today is close to zero — build content loading properly and mod support is mostly a
distribution problem later. The cost of retrofitting it onto hardcoded content is enormous.

### Hot reload

Content reloads without restarting during development. Given [determinism](19-architecture.md), the
workflow is: tweak a JSON value, reload, re-run the seed, compare outcomes. That loop is what makes
balancing a system this large tractable.

## Cut list

- **A third-party ECS library.** Would import foreign types into `sim/` and break the
  [portability rule](19-architecture.md).
- **Archetype-based storage optimization.** Premature; revisit against real
  [performance](22-performance.md) numbers.
- **Content authored in a custom DSL or a visual editor.** JSON plus schemas plus editor
  autocompletion is enough, and JSON ports to any engine.
- **Runtime component addition by mods.** Post-1.0, with the scripting API.
- **Save migrations.** Deferred to 1.0 by explicit decision.

---

**Previous:** [19 — Architecture](19-architecture.md) ·
**Next:** [21 — Extensibility](21-extensibility.md) · [Doc index](../README.md#documentation)
