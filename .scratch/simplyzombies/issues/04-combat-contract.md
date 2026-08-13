# 04 — Basic combat contract for early alpha

Type: grilling
Status: resolved
Blocked by: 01, 02, 03

## Question

Alpha needs "basic combat" at parity: melee pays stamina/injury/bite risk, ranged pays ammo + tonight's horde (doc 09). Must lock tunables so neither side becomes emergency button.

- Melee: wind-up → connect/miss → recovery interrupt windows; `F` swing vs struggle (1 s, stamina-paid), 1.5 s first bite / 2 s thereafter while grabbed. Exhausted swings: refuse vs degrade (swing_speed/recovery) — land scaling now? Stagger vs kill-quality weights per weapon?
- Ranged: raise → steady → fire → recover → reload; accuracy cone by steadiness/skill/condition/optics/light, no hit chance shown. Noise per shot (~180 vs melee ~8) — keep magnitudes for 256 m district?
- Grabs: contact 1 m centre-to-centre, extra grabbers add strength (1 shambler 2/3 escape, 2 → 1/2, 3 → 2/5). How does stats MVP shift this?
- Targeting: no aim assist in alpha? How does iso pixel art change hit feedback?
- Performance: tick budgets for contact resolution at horde counts (doc 22).

Decision is locked combat loop + numbers for alpha that builder can implement without re-deriving parity.

## Answer

**Picks:** Q1:B · Q2:A · Q3:A · Q4:A · Q5:A — all recommended. Round grills 2026-08-13. Blocked by 02+03 noted but frontier asked without guessing their answers.

**Melee loop (shipped, locked):** `windup 6 ticks (0.3s) → connect/miss → recover 8 ticks (0.4s)` at `TICK_HZ 20`, `weight`-scaled. `F` = swing when free, struggle when held (1s, 20 stamina). Recovery not cancelable; windup abandoned on `!canAim` (sprint/crawl) or `entity.staggered` or `grab.started` — stamina not refunded. Only `attack.connected` emits noise `8` (~11 m). Miss silent. Arc `0.6 rad` half-angle (≈34°), reach centre-to-centre + `BODY_RADIUS 0.35`. Head roll 20% ×3 damage. All in `src/sim/combat.ts` / `godot/sim/combat.gd`.

**Q1 — exhausted swings degrade, not refuse:** Replace `if stamina.current < cost continue` in `melee.intake` (`src/sim/modules/melee.ts:176`, `godot/sim/modules/melee.gd:68`) with `swing_speed` + `swing_recovery` modifiers sourced from pool emptiness (same shape as pain/legs/exhaustion/encumbrance in `stances.ts` → modifier pipeline). Stats already registered; one subscriber. Keeps cost continuous. Measure before tuning — balance change to only loop game has. `ponytail: keep refuse path behind flag until bench `crowded-and-swinging` green; upgrade is remove flag.`

**Q2 — three weapons locked:**
| Weapon | reach | weight | damage | stagger | role |
|---|---|---|---|---|---|
| knife | 0.9 m | 0.6 | 9 | 4 ticks | fast/cheap, inside reach |
| bat | 1.4 m | 1.2 | 11 | 16 | stagger king, survival vs crowd |
| spear | 2.4 m | 1.0 | 10 | 8 | reach, needs space |
Stagger is survival, not damage — bat 4× spear by design. Hit tables: zombie `0.2/0.55/0.25`, survivor `0.2/0.55/0.09/0.03/0.1/0.03` walked in fixed order, one draw per connect. No axe/firearm here — that is #03's job. Kit may propose swap but must prove vs this baseline.

**Q3 — noise kept calibrated:** `unsuppressed 180 = 257 m (1 district)`, `suppressed 40 = 57 m`, `bow 4 = 5.7 m`, `melee 8 = 11 m`, `wall +18 m`, `atten 0.7/m` per docs/03. District stays 256 m even if alpha map cropped — one bad shot waking whole map is intentional horror. Ranged loop: `raise → steady → fire → recover → reload` (slow, interruptible, same cancel as melee windup). Cone tightens with steadiness/skill/condition/optics/light; sway IS cone, no % shown — clause 4.

**Q4 — grabs locked:** Contact `1.0 m`, pursuit `1.6 m` (hysteresis, no flicker). Bite `1.5s` then `2s` while held, 85% private transmission, 30% scratch presentation. Escape `2 / (2 + ΣgrabStrength)` → 1×0.5=67%, 2×=50%, 3×=40% with shipped strengths shambler 0.5 / screamer 0.3 / bloater 0.3 (from #01). Never zero. STR MVP multiplies numerator `1.0→1.3` bounded (≈1 band per docs/23 guardrails), landing with #02 without rewriting melee.

**Q5 — no aim assist:** Facing is input (shared with `VisibilityIndex`). No snap, no reticle %, no floating damage/percent. Sway + where shots land teaches. Being surrounded lethal because `0.6 rad` covers one at a time. Interrupt is physical — moved muzzle loses steadiness.

**Performance / impl:** Builder touches `melee.intake` + `windupTicks`/`recoverTicks` scaling only; `attack.connected` stays sole field writer. Buddy bench `crowded-and-swinging` held at sightless twin budget.

Status: resolved.

## Notes

- Docs: 09-combat.md, 22-performance.md, 03-attention.md#scale-and-calibration, bench/ + godot/bench.
- Blocks on roster, stats, kit — combat numbers depend on all three.
- HITL — lethality feel is human call.
