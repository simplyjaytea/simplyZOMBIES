# Survivor generator pool and trait hooks

The slice generator is small tables, not Mara-lite uniques. Four traits have consumers; the rest are data so a builder does not invent twelve AI special cases.

Lock for [What does the survivor generator pool contain, and how do traits touch needs?](https://github.com/simplyjaytea/simplyZOMBIES/issues/36).

**Status:** accepted

## Pool

- ~12 given names + ~12 surnames, flat weights, authored in content JSON.
- 8 backstories, none is Mara’s pharmacy student: school caretaker (scrap), line cook (canned + Iron stomach bias), long-haul driver (water), veterinary nurse (bandage), fired security guard (bat), cyclist (nothing extra), warehouse picker (scrap), night auditor (Light sleeper bias). Kit is 0–1 of those items.
- 8 traits, 2–3 each, no duplicates. Squeamish + Steady hands is allowed (Mara already has both): Light sleeper, Squeamish, Steady hands, Iron stomach, Loud, Optimist, Night blind, Fast healer.
- Aptitudes: STR/CON/DEX, 3–8, total 15, backstory/trait may nudge ±1 then clamp.
- Appearance: 2–3 feature strings, no portrait. Uniques stay in `survivors/uniques/`.
- ~3 natural recruits stay director fog.

## Hooks in this slice

| Trait | Consumer |
|---|---|
| Light sleeper | Night-in-bed rest refill ×0.5 (sleeping rough stays half of that) |
| Squeamish | Mood on corpses/treatment; skips Doctor unless sole enabled Doctor |
| Iron stomach | Raw/spoiled meal mood hits are 0 |
| Steady hands | Treatment (already implied) |

Loud, Optimist, Night blind, Fast healer ship as labels with no consumer. No trait job-weight table. No “disciplined works through hunger.”

## Considered options

- Every listed trait gets a Need drain or job-affinity number — rejected; that is how the slice dies.
- Only Mara’s three are mechanical — rejected; Iron stomach is the food ticket’s hook.
- Backstories as named mini-uniques — rejected; recruits must be replaceable.

## Consequences

- Unique pipeline is unchanged: drop JSON in `uniques/`.
- Food mood numbers: [0005](0005-food-cook-spoilage.md).
