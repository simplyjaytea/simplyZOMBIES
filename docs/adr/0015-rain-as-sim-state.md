# Rain as sim state

Supersedes, in part, [0002](0002-temperature-hygiene-sources.md)'s "weather-lite rain flag —
rejected; weather is a second game": the owner re-decided it on 2026-09-06, in the survival
session, as the smallest weather that is not a toggle.

**Status:** accepted

## What is state

`world.weather = {raining, untilTick, spans}`, saved and restored like the director's scalars
(`SAVE_VERSION` 20). Spans are drawn on the sim's own `weather` RNG stream from
`content/weather/rain.json`: dry 144000..432000 ticks (12–36 h), wet 24000..72000 (2–6 h) —
roughly a spell every day or two, first cuts for the owner. The first span is always dry, so
every gate world boots under a clear sky. `SimWeather` (`sim/modules/weather.gd`) owns all of it
and keeps no static state.

## What reads it

Exactly three readers, each gated by `godot:m2:weather`:

| Reader | Effect | Direction |
|---|---|---|
| `needs._tick_temperature` | a body outdoors in the rain is wet after 200 ticks, stays wet 12000 once dry-skied or roofed, 2400 by a lit fire; a wet body reads **one band colder** before the wrap shift | bad |
| `SimBoot._diffuse` → `attention.diffuse_scent(half_life_mul)` | the scent half-life is halved while it rains (0.5); 1.0 dry | good |
| `main._draw_rain` | the streak layer draws only while it rains; `rain_look.gd` stays pure | look |

The HUD's world column says "It's raining." and the self column says "You're soaked." — words,
no forecast, no digits (`check_hud.gd`). docs/16's rule that a state must move two systems in
opposing directions is met by the first two rows.

## Considered and not taken

- Wind, fog, seasons, an accuracy penalty, thirst relief from rain — docs/16's Milestone 3, each
  its own slice; wind in particular stays the four calibration weights and is not save state.
- Rain as a `noise_propagation` modifier — the stat exists and nothing resolves it; a direct
  factor on the scent step is one line and one reader, and noise is untouched on purpose.
- A wetness pool — a single `wetUntilTick` on the needs component is enough resolution for one
  band's shift, and a pool would want a HUD row of its own.

## Consequences

- `weather` is a registered content type with a schema; the shallow validator sees a stray key.
- The rain layer's `INTENSITY_MIN` now means "within a span the sky is never empty".
- The balance harness's fast tier runs under this schedule; the record in docs/23 carries the
  before/after lines and the throwaway driver's numbers.
