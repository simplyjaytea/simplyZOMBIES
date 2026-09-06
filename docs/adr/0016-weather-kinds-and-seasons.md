# Weather kinds and seasons

Widens [0015](0015-rain-as-sim-state.md)'s one rain flag into the rest of docs/16: the owner
opened it on 2026-09-06 (the weather session) and decided the shape in four answers — storm,
cold snap with snow, heat wave and a shifting wind, in that order; the sky modelled as **weather
kinds as content**; a **simple calendar** of seasons weighting the draw; and, for the look, snow
that lies on the ground as well as falls.

**Status:** accepted

## What is state

`world.weather = {kind, untilTick, spans, windX, windY, windUntilTick, appliedMoveMul,
snowCover, nextLightningTick}`, scalars saved and restored like the director's
(`SAVE_VERSION` 21). At any tick the world is under exactly one kind — `clear`, `rain`,
`storm`, `cold_snap`, `snow`, `heat_wave` — and a kind is one JSON entry,
`content/weather/<kind>.json`, declaring its duration range, its draw weight per season, and
the modifiers it carries; `clear` is an entry with a range and weights and nothing else. The
globals every kind shares — the calendar, the drying timings, the wind, what snow on the ground
does — are one `climate` entry, `content/climate/temperate.json`, a new content type rather
than a second `calibration` file because the frozen oracle validates `calibration/` with Ajv
against the attention schema and would refuse it, while it does not know `weather/` or
`climate/` and ignores both.

The schedule: the first span is always clear; a non-clear span is always followed by clear; a
clear span rolls the next kind among the non-clear kinds by the **current season's** weights,
on the sim's own `weather` stream, then that kind's duration. The season is
`seasonOrder[(day − 1) / seasonDays]` from `startSeason` — five days a season, so a ten-day run
sees spring and summer. `SimWeather.set_kind` is the one path a flip and a gate's forcing both
take, so the modifier and the wind can never be skipped by writing the dictionary. Nothing
subscribes to a kind change; every reader polls `kind`, one dictionary get.

Wind is docs/16's persistent variable, not a kind: a direction re-rolled every `windDriftDays`
at `windStrength`, wandering within `windDriftDeg` (45°) of the field's calibrated lean — the
*prevailing* wind docs/16 describes, and the direction every district siting was measured
under; a free daily direction was the first cut and the harness read it as a coin toss per
seed — times the kind's `windMul` (no shipped kind declares one — the storm's
first cut of 2.0 was the difference between a colony and none on one harness seed, so the
mechanism stays, gate-exercised, and waits for a kind that earns it), handed to the attention
field's four diffusion weights through a new `set_wind`. The field remembers what it was handed
and the weather tick re-applies on any mismatch, every tick — the field's `restore` copies only
noise and scent, `adopt_map` builds a fresh field, and `world.restore` must not call a module,
so self-healing is the only honest shape. The calibration's `windX`/`windY` remain the boot
value (the field's own `default_calibration`; the JSON mirror of them is read by nothing, as
before).

## What reads it

Every reader gated, the spine's by `godot:m2:weather` and each kind's effects by its own gate
(`godot:m2:storm`, `godot:m2:cold`, `godot:m2:heat`), docs/16's two-directions rule met kind by
kind:

| Kind | Good | Bad |
|---|---|---|
| rain | scent half-life ×0.5 | wet, one band colder |
| storm | scent ×0.35, **noise half-life ×0.4** | wet and cold; outdoor work refused; lightning as a noise nobody made (60, under any gun) |
| cold_snap | shamblers ×0.7, food keeps ×2, scent ×0.7 | one band colder day and night, indoors too, unless by a lit fire |
| snow | shamblers ×0.9, food keeps ×2, scent ×0.6 | the cold, and the living ×0.8 once the cover is half laid |
| heat_wave | — (a longer day is docs/02's, not built) | one band hotter by day outdoors, thirst ×1.5, food spoils ×2, corpse scent ×2 |

The spine wires: `needs._tick_temperature` (the shift, between the night/fire/roof base and
the wet), `SimBoot._diffuse` (scent), `shambler._speed_of` (the dead), a **global** `move_speed`
modifier under source `weather` (the living — global so a recruit who arrives mid-snow is
covered and raiders slow with everyone), and `SimJobs._walk`, which had never read
`move_speed` at all — the limp, encumbrance and blood loss slowed the player and never Mara or
Ellis. That defect is closed by the spine and measured in docs/23's record.

The HUD's world column says one sentence a kind and nothing under clear; wind has no sentence
— you read it off the plume (docs/16's forecasting rule).

## Considered and not taken

- **Additive flags** (`storming`, `cold`, `hot` each on its own timer) — simpler a slice, and
  the states would overlap in ways nobody designed; the owner chose kinds.
- **No calendar** — the owner chose one; five days a season is a content number.
- **A sim light pulse per lightning strike** — the owner chose noise plus a screen flash;
  `light.changed` has no transient positional precedent.
- Fog, a ranged accuracy penalty, thirst relief from rain, barricade damage in a storm,
  firewood consumption, frostbite, tracks in snow, seasons changing the day's phase lengths —
  each named in docs/23's what's left, none built here.

## Consequences

- `weather` and `climate` are registered content types with schemas; the shallow validator
  sees a stray key in either; `npm test` ignores both directories.
- The balance harness's fast tier runs under the seasonal schedule, so a summer heat wave is in
  every ten-day run from day 6; docs/23's record carries the before/after lines.
- `rain_look.gd`'s layer is keyed to `SimWeather.raining`, which is content (`wets`), so a
  storm draws rain; snow has its own layer and a ground regrade (the look slice).
