# Need pools, bands, and hold-max

Milestone 2 ships six Needs on every survivor, including the player and Mara. Hunger, thirst, and rest are 0–100 Need pools; mood stays the existing modifier total; temperature and hygiene are Need bands (not depleting stores). Systems exist for real; Need hold (`needs.holdMax`) freezes them full for debug without unregistering modules. Presentation is a separate ticket.

This is the lock for [How do the five need meters scale, tick, and threshold (soft vs hard)?](https://github.com/simplyjaytea/simplyZOMBIES/issues/33) (GitHub issue writes were blocked from the grilling session; paste the Answer there and close it).

**Status:** accepted

## Shape

| Need | Kind | Sim |
|---|---|---|
| Hunger, thirst, rest | Need pool | `0–100` float, `100` = full, start `100` |
| Mood | Modifier total | Existing `mood` stat, −100..100, base 0 |
| Temperature | Need band | `comfortable` · `a_little_cold` · `very_cold` · `extremely_cold` · `a_little_hot` · `very_hot` · `extremely_hot` |
| Hygiene | Need band | `clean` · `a_little_dirty` · `dirty` · `filthy` |

Combat exhaustion (stamina) stays distinct from rest. “Uncomfortable” is the UI word for `a_little_*` / `a_little_dirty`, not an extra sim state.

## Component

One `needs` Dictionary on the survivor, like `aptitudes`: `hunger` / `thirst` / `rest` (0–100), `temperature` / `hygiene` (bands), `crisis` (`none` · `starving` · `dehydrating` · `passed_out`), plus `starvingSinceTick` / `dehydratingSinceTick` while the matching Need crisis is set. Mood does not live here. Extreme temperature becomes the existing hypothermia/heatstroke injury, not a `crisis` value.

## Modules and Need hold

Each Need is its own module id (`need.hunger`, `need.thirst`, `need.rest`, `need.mood`, `need.temperature`, `need.hygiene`). Boot/sandbox flag `needs.holdMax` (default off on Standard) keeps pools at 100, bands at `comfortable`/`clean`, `crisis` at `none`, and strips Need-sourced mood modifiers. Grief/death mood still applies. NPCs never seek under hold. Isolation `disabled: [...]` remains a separate knob.

## Drain and cadence

Idle time-to-empty: hunger 2.0 game-days, thirst 1.0 game-day, rest one wake window (dawn+day+dusk). A full night in a bed refills rest; sleeping rough refills half; staying up does not. Labor / cold-band / injury-recovery are reserved drain muls; food, water, and sleep refill wait on later tickets.

Drain every sim tick (20 Hz). Modifier writes, threshold events, and job-pressure updates only on band or 30/40/0 crosses. Permitted downgrade: if a `needs-colony` bench (20 survivors) shows up in the 8 ms tick, swap drain to every 1 s without changing rates.

## Soft cascade and hard crisis

Pools: soft at **30** remaining (work speed, melee/ranged accuracy, named mood source). Hard at **0**: hunger → `starving`, crawl, no jobs, death after 1 more day at 0; thirst → `dehydrating`, death after 0.25 day; rest → `passed_out`, forced sleep in place (sleeping-rough recovery unless already on a bed), not death.

Mood: soft at **−25**; hard at **−80** fires `mood.threshold` (leave-with-gear). Leave behavior can wait on continuity/director.

Bands: `a_little_*` / `a_little_dirty` = uncomfortable (soft warning). `very_*` / `dirty` = soft cascade. `extremely_*` / `filthy` = hard. What flips a band, and the numeric muls, wait on [What are temperature and hygiene sources and sinks in the slice?](https://github.com/simplyjaytea/simplyZOMBIES/issues/34).

## NPC seek

Pressure levels only: `ok` / `seek` / `soft` / `hard`. Seek starts at **40**, continues until **80**, never starts above 50. Reevaluate on threshold-cross and ~1 s, never every tick. Needs systems do not pathfind. Finish the **current action**, then seek. Soft/seek never interrupt mid-action; hard interrupts now. The player is not under this rule. Job choice stays on [How do NPCs pick Haul, Construct, Cook, and Doctor priorities?](https://github.com/simplyjaytea/simplyZOMBIES/issues/35).

## Considered options

- All six as depleting pools — rejected; mood is a running total and temperature/hygiene are not hunger-like drains.
- Binary comfortable/cold/hot flags — rejected; three degrees each side, with “uncomfortable” as the UI word for `a_little_*`.
- Drain every tick *and* rebuild modifiers every tick — rejected; side effects are the cost, not the subtract.
- Finish the whole blueprint before seeking — rejected; current action only, so a two-day craft cannot starve someone through soft cascade.
- Collapse as a sixth stance or a new injury — rejected; Need crisis is a field on `needs`.

## Consequences

- [How are needs shown in UI without raw numbers?](https://github.com/simplyjaytea/simplyZOMBIES/issues/38) owns prose; it should map `a_little_*` to “uncomfortable.”
- Sources, Cook refill, and job picker tickets consume this vocab; they do not reopen ranges or thresholds.
- Docs/04 still lists temperature and hygiene as deferred in the roadmap; this map pulled them into M2 as bands. Revise docs when the map settles, not piecemeal.
