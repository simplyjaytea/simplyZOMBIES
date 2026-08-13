# 02 — Stats MVP for early alpha

Type: grilling
Status: resolved
Blocked by:

## Question

Q1 asks for "basics of the stats". Roadmap planned STR, DEX, CON, INT, CHA, WIS with fixed-budget generation (no one high in all six) but Milestone 2 defers full attributes to 3A. Early alpha needs minimal stat set that actually changes play without full web.

- Which subset ships? Options: STR/CON/DEX (physical) vs full six with stubbed CHA/WIS vs. 2-stat (Strength + Constitution) hook already in code (grab escape power, infection timeline CON 0.75–1.25).
- How do stats modify: stamina pool, swing speed/recovery, grab escape, infection progression, diagnosis, carry?
- Generation: fixed budget + backstory/trait nudges? How to test no universally superior survivor and no mandatory rerolling (risk 2)?
- Save/replay: where do aptitudes live, how do they serialize deterministically?
- Upgrade path to full six + web 12–18 nodes without rewriting alpha saves?

Decision is minimal stat model + generation rule + per-stat effects for alpha.

## Answer

**Decision: STR + CON + DEX for alpha. INT/CHA/WIS deferred. Linear scaling. Numbers visible. Reroll allowed. Fixed-budget generation. Plain component + modifier hook. Upgrade path preserves saves.**

### 1. Which stats ship

- **Alpha ships 3: STR, CON, DEX.** Physical three where each has a live consumer from day one. CHA/WIS deferred — they need Director + NPC/relationship systems that are out of alpha (per ticket Q1 scoping). INT deferred for alpha — shallow web (12–18 nodes) earns region-tagged points without an INT accelerator; INT hook lands with full web in 3A.
- No stubbed dead bonuses in alpha UI: only the three shipped stats are defined, stored, shown, and consumed. The other three do not exist as fields.

### 2. Per-stat effects (bounded ~one band, linear for alpha)

All three scale **linearly** around baseline 5. Later balance may swap to diminishing returns without changing call sites. Every effect goes through the modifier pipeline (`SimModifiers`, `SimStats`) as a bounded `resolve()` so web/affixes compose correctly; no direct arithmetic on body maxima.

| Stat | Stat ID(s) | Base | Alpha effect | Formula (alpha tuning, re-balance later) | Guardrail |
|---|---|---|---|---|---|
| **STR** | `carry_capacity`, `grab_escape` | `carry_capacity` 25 kg, grab 2/3 vs 1 shambler | Raises hidden carried-mass before encumbrance slows + raises grab-escape power. Multiple grabbers still independently reduce (doc 09). | `carry = 25 + 3*(STR-5)` kg → 19–34 kg across 3–8. `escape_power = 0.50 + 0.10*(STR-5)`. Contest stays `P(escape)= power / (power + sum grabStrength)` so 1 shambler 2/3 → ~0.55–0.75 across band. | Never edits `SURVIVOR_BODY` maxima. |
| **CON** | `infection_progression` (ships), `injury_tolerance` (bounded) | `infection_progression` 1.0, damage taken 1.0 | Lengthens infection stage durations + raises effective injury tolerance as fractional reduction to incoming integrity loss. Never raises body-part maxima, never flips `transmitted`. | `inf_factor = clamp(1.0 + 0.05*(CON-5), 0.75, 1.25)` → 0.90–1.15 across 3–8. `duration = base / factor`. `damage_taken = clamp(1.0 - 0.04*(CON-5), 0.80, 1.15)`. | Docs 06:78 + 23 CON row. |
| **DEX** | `move_speed` | 1.0 | Raises movement speed in every stance without replacing stance tradeoffs. | `dex_factor = clamp(1.0 + 0.06*(DEX-5), 0.75, 1.25)` → 0.88–1.18. `effective = WALK_SPEED * SimStances.SPEED_FACTOR[stance] * dex_factor`. | Footstep noise **normalized by distance**, not per tick, so speed does not become stealth bonus (doc 23 DEX guardrail). Land that normalization with the stat or gate DEX on it. |

Tuning numbers are **initial alpha feel**; parity harness (ticket 04) is the validator.

### 3. Generation: fixed budget + bounded nudges, reroll allowed, numbers visible

- **Range:** integers **3–8**, midpoint **5**. Visible as numbers in alpha UI (not bands). Exact values are player-facing so the budget is legible.
- **Budget:** fixed total **15** across the three stats (average 5). Min 3 / max 8 enforced. Generated via seeded RNG stream `attributes` (`RngRegistry.derive_seed(master, "attributes")`) sampling uniformly from valid 3-stat compositions — deterministic, replay-identical, seed-isolated from other streams.
- **Backstory/trait nudge:** at most **±1** on one stat, compensated by ∓1 on another to keep total 15, clamped to 3–8. Purely explainable shifts (e.g. `mover: +1 STR −1 DEX`, `runner: +1 DEX −1 STR`, `hardy: +1 CON −1 STR`). 3–4 backstories for alpha; more content later, same mechanism.
- **Reroll:** allowed in alpha — chartering explicitly permits it. Reroll = new person (`name` + trait seed resampled), never an edit of one stat. Narrow band (3–8, total 15) ensures no universally superior roll. Risk 11 cohort check (large seeded cohort, verify no mandatory stat) remains the later gate; this rule is shaped to pass it.
- **Anti-dump/mandatory guard:** narrow band + fixed total + single ±1 nudge is the tester: large-cohort verification must show no stat dominates and no template is mandatory. If it fails, shrink the band before adding UI labor (risk 1 mitigation).

### 4. Where they live + serialization

- Component `aptitudes: {str: int, dex: int, con: int}` (alias `attributes` acceptable if existing content uses it — pick one, document it) on each survivor entity. Plain `Dictionary` in `ComponentStore`, included in `SimSerialize` snapshot/canonicalize, round-trips through save/load. No new singleton.
- Consumers read via `SimModifiers` sources `attr.str` / `attr.dex` / `attr.con` mapping to the stat IDs above. Adding a stat never requires a new system, only a new `SimStats` def + modifier source.
- **Upgrade path to six:** alpha saves that lack `int`/`cha`/`wis` keys load with midpoint default **5** for each missing stat (neutral, no effect). When six ship, loader fills missing keys with 5 and old saves remain valid without rewrite. Same rule for any future `aptitudes` missing key.

### 5. Explicitly not in alpha

- INT `skill_progress` accelerator, CHA relationship/faction trade, WIS inspection/warning. All three deferred to 3A where their consumers exist (web, relationships/Guard-Scout, factions/director).
- No global HP pool, no direct `SURVIVOR_BODY` maxima edits, no retroactive web grants, no per-tick noise stealth from DEX.
- Shallow web in alpha does not read INT.

## Notes

- Docs: 23-roadmap.md#planned-survivor-attributes, 05-health-injury.md, 06-infection.md, 09-combat.md (exhausted swings), 08-skill-web.md.
- Code hooks: `melee.ts` swing_speed/recovery pool scaling, grab escape contest, docs/06 CON scaling.
- HITL — numeric feel + reroll incentive is human judgment.
- Resolved 2026-08-13 via HITL grilling: owner chose A + linear + numbers-visible + budget-recommended + plain component + CHA/WIS deferred.
