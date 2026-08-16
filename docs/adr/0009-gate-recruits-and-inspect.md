# Gate recruits and skilled Inspect

About three natural recruits, generator-rolled, at the gate after pressure grace. Hidden bite is a 15% accept roll. Learning that it is a bite is a timed Doctor Inspect, not a free panel — and the skill web is not in this slice, so Mara is the skilled rank.

**Status:** accepted

## Beats

Days **8, 12, 16** — one person each, rolled from the survivor generator ([0004](0004-survivor-generator.md)). They wait at the gate, not inside. Player `E`: accept (join, Need pools 50, eat from Stockpile immediately) or ignore. Still waiting at next dawn → they leave forever. Cap 3 accepts per run. Lull does not cancel a beat. Mara dead does not add a fourth. Nothing Personal: no beats.

Accept rolls **`transmitted` at 15%** on `rng.stream("recruits")` ([0007](0007-needs-era-save.md)). Refuse/dawn-leave does not roll. Default presentation: no visible wound. Same infection rules as anyone else after that.

## Inspect

Inspect is a **timed Doctor action** (~15 s), in range, not grabbed. Opening the Injuries tab is untrained prose only: no `transmitted`, no clock. The player cannot self-diagnose a hidden bite. Skilled rank is Mara (`examinerSkill` 2) unless some other survivor has Doctor enabled and is assigned. Squeamish takes the mood hit. Filthy blocks Doctor, so it blocks Inspect.

| Examiner | Stage 1–2 | Stage 3 | Stage 4 |
|---|---|---|---|
| Untrained / no Inspect | Fine / fever. Never bite vs sepsis. No clock. | “Ill.” | “Critical” (obvious to anyone). No clock. |
| Skilled (Mara) | Still no bite answer (amputation window). | “Probable infection” vs “probable sepsis” **plus** “maybe a day.” | Obvious; adds “hours.” |

Never a tick count, never a percent. Expert (stage 1–2 bite call + tighter clock) waits on the skill web. `diagnosis_of` already refuses to leak `transmitted`; this table is what the Job is allowed to say.

## Considered options

- Scavenge-tile person or no live recruits — rejected; docs/07 is someone at the gate.
- Injuries tab uses the selected survivor’s skill — rejected; “select Mara” would be the medic skill.
- Skilled clock from latent — rejected; deletes stage 1–2 uncertainty.
- Exactly one of three beats bitten — rejected; that’s a plot.

## Consequences

- Save: recruit entities + `recruits` stream in [0007](0007-needs-era-save.md).
- Death while `transmitted`: [0010](0010-death-corpse-and-leave.md).
- Doctor treatment still consumes bandages: [0003](0003-jobs-and-need-seek.md).
