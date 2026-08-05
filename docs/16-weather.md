# 16 — Weather

*Why this exists: weather in survival games is usually decoration with a temperature modifier. Here
it's a modifier on the [attention field](03-attention.md) — which makes it a tactical input the player
plans around rather than a visual effect.*

---

## Design rule

**Every weather state must change at least two systems in opposing directions.** If a state is purely
good or purely bad, it's a difficulty knob, not weather. The player should look at the sky and have a
genuine decision.

## Wind — the persistent variable

Not a weather *state* but a continuous property, and the most tactically important one.

- **Scent drifts downwind.** Your base's scent plume goes somewhere, and where it goes determines which
  direction the [drift](14-zombies.md) arrives from.
- Wind direction shifts over days. A base that was safe becomes a base that's upwind of the whole
  district.
- **Bait must be placed downwind** to work ([base building](15-base-building.md)). Getting this wrong
  wastes the resources and pulls pressure toward you instead.
- Strong wind carries noise further in one direction and masks it in others.

Base siting relative to prevailing wind is a decision with permanent consequences, and it's the one
new players never think about.

## Weather states

### Clear

| Effect | Direction |
|---|---|
| Normal visibility, both ways | — |
| Best ranged accuracy | Good |
| Full solar/laundry/drying and construction efficiency | Good |
| **Nothing masks your scent or noise** | Bad |
| Clear nights: moonlight makes light discipline harder to maintain | Bad |

The baseline. Good for work, bad for hiding — clear stretches are when the field accumulates fastest.

### Rain

The best and most complicated weather in the game.

| Effect | Direction |
|---|---|
| **Masks scent heavily** — the strongest attention relief available | Very good |
| Dampens noise propagation | Good |
| Fills water collection — often the difference between drinking and not | Very good |
| Suppresses fire risk | Good |
| **Ranged accuracy penalty** | Bad |
| Survivors get wet → [cold](04-survival-needs.md), hypothermia risk | Bad |
| Rots wooden [structures](15-base-building.md) faster | Bad |
| Mood penalty for working outdoors | Bad |
| Reduces visibility both ways | Neutral |

**Rain is the scavenging window.** You are quieter, harder to smell, and refilling your water — and
you're a worse shot, getting cold, and your walls are decaying while you're away. Experienced play
means running the risky expedition in the rain and accepting you'll be fighting with melee.

### Fog

| Effect | Direction |
|---|---|
| **Zombie sight range collapses** | Good |
| Muffles and disperses scent somewhat | Good |
| **Your sight range collapses too** | Bad |
| Ranged combat becomes nearly useless | Bad |
| Contact happens at melee distance with no warning | Very bad |
| Navigation and returning home become genuinely hard | Bad |

Fog is symmetric and therefore terrifying: it favors whoever is more willing to be surprised, and
zombies are always willing. Fog nights are when melee colonies feel confident and get punished anyway.

### Storm

| Effect | Direction |
|---|---|
| **Extreme noise masking** — the loudest cover in the game | Very good |
| Heavy scent dispersal | Good |
| Structural damage to [barricades](15-base-building.md) | Bad |
| Lightning: fire risk, and a massive light event you don't control | Bad |
| Severe cold and wetness | Bad |
| Outdoor work near-impossible | Bad |
| **You can't hear them coming either** | Very bad |

A storm is the one time you can run a generator, fire guns, and do loud construction with relative
impunity. It's also the one time a [horde](14-zombies.md) can be at your wall before anyone notices.
Storms are the highest-variance nights in the game.

### Heat wave

| Effect | Direction |
|---|---|
| Longer daylight for scavenging | Good |
| **Corpse rot accelerates** → sharp scent increase | Very bad |
| **Food spoils much faster** ([world decay](13-world-decay.md)) | Bad |
| Thirst consumption way up | Bad |
| Heatstroke risk; armor becomes punishing | Bad |
| Fire risk from any flame | Bad |

Heat is the [scent](03-attention.md) event. Corpse disposal stops being housekeeping and becomes
urgent, and a colony that got sloppy about burials during a cool spell finds out during the first hot
week.

### Cold snap / winter

| Effect | Direction |
|---|---|
| **Zombies slow measurably** — the only state that weakens them directly | Very good |
| Scent propagation drops sharply | Good |
| Food spoils far more slowly | Good |
| **Fuel and firewood consumption soars** | Very bad |
| Fires and heaters mandatory → light, smoke, noise | Bad |
| Crops fail; forage disappears | Bad |
| Hypothermia; frostbite as a permanent [injury](05-health-injury.md) | Bad |
| Longer nights, shorter working days | Bad |

Winter is the design's best expression of its own thesis: **the enemy is weaker and staying alive is
much harder.** The zombies aren't the problem in winter — the fuel bill is, and burning fuel is exactly
what brings them back.

### Snow

Stacks on cold with two additions: movement penalties for everyone (survivors more than zombies), and
**tracks** — footprints in snow that [trackers](14-zombies.md) follow straight home. Snow is when
sloppy return routes get a base found.

## Seasons

Weather is drawn from a seasonal distribution rather than uniformly, so the run has a shape:

| Season | Character |
|---|---|
| **Spring** | Rain-heavy. The best scavenging season. Planting. |
| **Summer** | Clear and hot. Productive, loud, and the scent economy gets ugly. |
| **Autumn** | Mixed, foggy. Harvest and preparation. The last easy season. |
| **Winter** | Cold, snow, long nights. Fuel is everything. Attrition. |

Seasons change phase lengths ([core loop](02-core-loop.md)) but never the four-phase structure.

## Forecasting

Per the [imperfect information rule](01-hardcore-contract.md#4-information-is-scarce-and-unreliable),
there is no weather UI panel with a 5-day forecast.

You read the sky. Survivors with the relevant background or [Survival web](08-skill-web.md) nodes
comment: *"that's coming in by evening"*, *"smells like rain"*, *"clear night — keep the lamps down."*
A working radio ([factions](18-factions.md)) can give real forecasts, which is one of the better
reasons to get one running.

## Content shape

Each state is a JSON entry ([content](20-ecs-and-content.md)) declaring a duration range, a seasonal
weight, and a list of [modifiers](21-extensibility.md) — attention channel multipliers, accuracy,
temperature, spoilage rate, structure decay, mood.

**Adding a weather state is one JSON entry plus its modifier list, with no code change.** This is
worked example #2 in the [cookbook](21-extensibility.md).

## Cut list

- **Weather forecasting UI with percentages.** Violates the information rule.
- **Tornadoes, floods, and other terrain-changing catastrophes.** Post-slice; large map-mutation cost.
- **Per-tile microclimate.** Weather is regional; temperature is per-survivor from exposure and
  shelter. That's enough resolution.
- **Weather-driven zombie migration events** as a separate system. The [director](17-director.md)
  handles migration; weather modulates it through the field.

---

**Previous:** [15 — Base Building](15-base-building.md) · **Next:** [17 — The Director](17-director.md) ·
[Doc index](../README.md#documentation)
