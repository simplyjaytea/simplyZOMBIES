# M2 Lethality Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Complete the infection loop on the shipped bite/transmission seam: progression timeline, symptoms/diagnosis ambiguity, five responses, armor-as-coverage, and turning inside walls.

**Architecture:** Extend `godot/sim/modules/infection.gd` from one-shot transmission into a staged, tick-driven disease that never mutates `transmitted` after wound time. Keep `health.gd` owning located wounds/presentation (`bite` vs `scratch`) and body damage; `infection.gd` owns the private `zombieInfection` component and publishes stage/turn events. Armor reduces transmission at `bite.landed` time by reading equipped item coverage per `docs/10-items.md:129` — no damage mitigation. All read models filter through examiner skill; raw `transmitted` never reaches UI.

**Tech Stack:** Godot 4.7.1 Compatibility, typed GDScript, existing SimWorld tick (20 Hz), RngRegistry named streams, EventBus, modifier pipeline, ContentLoader flat `Dictionary` tree.

---

## Context / Assumptions

- Shipped seam: `SimHealth` records `injuries.wounds[].{kind,presentation,bodyPart,sustainedAtTick}` with 30% bite→scratch masquerade; `SimInfection` records `zombieInfection.exposures[].{source,bodyPart,exposedAtTick,transmitted}` using `rng.stream("infection").next() < 0.85`. Both subscribe to `bite.landed`. Verified isolated to their streams.
- World tick = 20 Hz (`TICK_HZ=20`). Day = 4h at 1× per README (14,400s/day = 288,000 ticks/day). Infection timeline 2–4 days → 576k–1.15M ticks. Use tick arithmetic, not wall clock. `SimWorld.tick` is authoritative; no `Time.get_ticks_msec`.
- CON neutral baseline: M2 implements `stats` hook `infection_progression` with base 1.0; CON later provides bounded modifier that scales duration, never flips `transmitted`.
- Armor per `docs/10-items.md` armor is coverage per body part → infection only. No `damage` reduction in this slice; collect coverage from `SimInventory.equipped_items` + item base `armor: {part: coverage0..1}` (new optional field, backward-compat: absent = 0).
- Determinism: progression, RNG for ambiguous presentation, and treatment outcomes all use named streams (`infection`, `injury`, `treatment`) seeded from master seed. Save/restore must round-trip `zombieInfection` and treatment courses.
- Save version: bump guarded by `SimSerialize.SAVE_VERSION` when shape changes; old saves rejected cleanly (already asserted in `world.gd:restore`).
- Docs authority: `docs/05-health-injury.md`, `docs/06-infection.md`, `docs/10-items.md:129`, `docs/23-roadmap.md` M2 slice.

## Files Likely To Change

- `godot/sim/modules/infection.gd` — stages, progression system, diagnosis helpers, treatment commands, turning
- `godot/sim/modules/health.gd` — keep wound intake; add `treatment` plumbing if needed (amputation removes limb, cauterize adds burn)
- `godot/sim/modifiers/stats.gd` — add `infection_progression`, `infection_resistance` if missing
- `godot/sim/modules/items.gd` — helper `armor_coverage_of(world, actor, bodyPart)` reading equipped bases
- `godot/sim/modules/inventory.gd` — no change except maybe `equipped_items` reuse
- `godot/content/items/armor.json` (new) or extend `godot/content/items/containers.json` — one or two sample armor bases with `armor: {torso: 0.6, arms: 0.3}` and `equipSlot`
- `godot/content/schemas/item.schema.json` — allow optional `armor` map, no breaking required fields
- `godot/sim/world.gd` — register infection systems in correct order (after health)
- `godot/ui/paperdoll.gd` / `godot/presentation/main.gd` — read-model only: show stage prose, never `transmitted`; tint stays `PartState` from `body`
- `godot/sim/kernel/serialize.gd` / `godot/sim/save.gd` — version bump + canonicalize new component
- Tests: `test/unit/infection.test.ts` (oracle reference), `godot/test/m2_infection.gd` headless harness, `test/integration/infection-*.test.ts`

## Step-by-Step Plan

### Task 1: Snapshot the current seam (no code)

**Objective:** Lock the observable contract before extending it.

**Files:** Read-only: `godot/sim/modules/infection.gd`, `godot/sim/modules/health.gd`, `src/sim/modules/infection.ts`, `docs/06-infection.md`

**Steps:**
1. `godot --headless --path godot --script res://check_r6_coverage.gd` — capture `R6_COVERAGE_OK` baseline
2. Note exposure shape, `BITE_PRESENTS_AS_SCRATCH_CHANCE`, `BITE_TRANSMISSION_CHANCE`, event types `bite.landed`, `injury.sustained`

**Verification:** Existing gates stay green; no file edits.

### Task 2: Define timeline constants and stage enum

**Objective:** Single source of truth for durations and stages.

**Files:** Modify: `godot/sim/modules/infection.gd:1-22`

**Step 1: Write failing test**

```gdscript
# godot/test/m2_infection.gd — headless
assert(SimInfection.Stage.Critical == 3)
assert(SimInfection.stage_duration_ticks(SimInfection.Stage.Latent) == 12*3600*20)
```

**Step 2: Run** `godot --headless --path godot --script res://test/m2_infection.gd` — FAIL missing `Stage`

**Step 3: Implement**

```gdscript
enum Stage { Latent=0, Onset=1, Progression=2, Critical=3, Turned=4 }
const LATENT_TICKS := 12*3600*20
const ONSET_TICKS_MIN := 12*3600*20
const ONSET_TICKS_MAX := 24*3600*20
const PROGRESSION_TICKS := 24*3600*20
const CRITICAL_TICKS := 12*3600*20
# neutral CON hook: duration * (1.0 / resolve("infection_progression"))
static func stage_duration_ticks(s: int, world: Variant = null) -> int: ...
```

`ponytail: durations fixed per docs/06; wire to modifier resolve when CON lands — ceiling is ±25% band, no transmitted flip.`

**Step 4:** Re-run — PASS

**Step 5: Commit** `feat(infection): stage enum and tick durations`

### Task 3: Extend exposure shape

**Objective:** Add `stage`, `stageEnteredAtTick`, `symptoms` without breaking old saves.

**Files:** Modify: `godot/sim/modules/infection.gd`, `godot/sim/kernel/serialize.gd` (if version bump)

**Shape:**
```gdscript
{
  source: int, bodyPart: String, exposedAtTick: int, transmitted: bool,
  stage: int, stageEnteredAtTick: int,  # new, default Latent
  cauterized: bool, antibioticsTicks: int, amputated: bool
}
```

Migration: `restore` fills missing keys with defaults; new saves write full shape. Bump `SAVE_VERSION` 10→11 with assert message preserved.

**TDD:** Write test that old save (only 4 keys) restores and progresses correctly.

### Task 4: Progression system (tick-driven)

**Objective:** Advance `stage` deterministically each tick based on elapsed ticks since `stageEnteredAtTick`.

**Files:** Modify: `godot/sim/modules/infection.gd:register_module`

**System:** `world.systems.register("infection.progress", "health", 10, func(w): ...)`
- Iterate `w.components.query(["zombieInfection"])`
- For each exposure where `transmitted==true` and not terminal (`amputated`/dead), advance when `w.tick - stageEnteredAtTick >= stage_duration_ticks(currentStage, w)`
- Publish `infection.staged` with `{entity, bodyPart, from, to}` when advancing
- `CON` scaling via `w.modifiers.resolve("infection_progression", entity)` if present, clamped 0.75–1.25, applied as `duration = base / factor`

**Verification:** Determinism test — same seed + same bite log → identical stage at tick N across two worlds.

### Task 5: Armor coverage helper

**Objective:** Read equipped armor coverage per body part.

**Files:** Modify: `godot/sim/modules/items.gd` (+ helper), New: `godot/content/items/armor.json`

**Helper:**
```gdscript
static func armor_coverage(world: Variant, actor: int, bodyPart: String) -> float:
  var cov := 0.0
  for item in SimInventory.equipped_items(world, actor):
    var base: Variant = item_base_of(world, item)
    if base is Dictionary and (base as Dictionary).has("armor"):
      var m: Dictionary = (base as Dictionary)["armor"] as Dictionary
      cov = maxf(cov, float(m.get(bodyPart, 0.0))) # max, not sum; ponytail: coverage composes by max until layering lands
  return clampf(cov, 0.0, 1.0)
```

Content: two armor bases (`cloth_wrap`, `scrap_vest`) with `equipSlot` and `armor` map. Extend `item.schema.json` to allow optional `armor: {type: object, additionalProperties: {type: number}}`.

**TDD:** Unit test — actor with 0.6 torso vest halves torso bite transmission vs bare.

### Task 6: Wire armor into transmission

**Objective:** Reduce `transmitted` chance by coverage at wound time.

**Files:** Modify: `godot/sim/modules/infection.gd` handler for `bite.landed`

**Change:**
```gdscript
var baseChance := BITE_TRANSMISSION_CHANCE
var cov := SimItems.armor_coverage(world, victim, String(event["bodyPart"]))
var effChance := baseChance * (1.0 - cov) # ponytail: linear; upgrade to material curve when armor tiers land
var transmitted := float(rng.call("next")) < effChance
```

Seed still consumed once per bite regardless of armor (determinism preserved).

**TDD:** Same seed, same bite sequence: bare victim transmits, armored same seed does not — proven by deterministic replay.

### Task 7: Diagnosis / read model (ambiguity preserved)

**Objective:** Expose only stage-gated prose, never `transmitted`.

**Files:** Modify: `godot/sim/modules/infection.gd` (add `diagnosis_of(world, entity, examinerSkill)`), `godot/ui/paperdoll.gd`, `godot/presentation/main.gd` HUD

**Contract:**
- `examinerSkill` 0..3 (none/basic/skilled/expert) per `docs/06-infection.md:53`
- Latent: "nothing" for all skills (indistinguishable)
- Onset: fever/fatigue prose for all; no discrimination
- Progression: skilled+ returns "likely infection" vs "likely sepsis" based on private truth; basic/none returns ambiguous
- Critical: obvious to all
- Implement as pure function reading `zombieInfection` + `injuries.wounds[]` + skill; no RNG, no mutation

**TDD:** `diagnosis_of` never returns `transmitted` field; assert skill-gated certainty matches table.

### Task 8: Cauterize (immediate window)

**Objective:** Modest transmission reduction at wound time; adds burn injury.

**Files:** Modify: `godot/sim/modules/infection.gd`, `godot/sim/modules/health.gd` (burn helper)

**Command:** `infection.cauterize {entity, bodyPart, atTick}` — valid only if `tick - exposedAtTick <= 5*60*20` (5 min). Effect: if `transmitted==true`, re-roll with `CAUTERIZE_REDUCTION=0.25` using `rng.stream("treatment")`; on success set `transmitted=false` and append burn wound; always publish `injury.sustained {injury:"burn"}`. Deterministic via treatment stream.

**TDD:** Outside window → rejected `{ok:false, reason:"too-late"}`; inside window consumes one treatment RNG sample.

### Task 9: Amputate (stages 1–2, limb only)

**Objective:** Removal of limb cures local exposures; permanent disability.

**Files:** Modify: `godot/sim/modules/infection.gd`, `godot/sim/modules/health.gd`

**Command:** `infection.amputate {entity, bodyPart}` — requires `bodyPart in [arms,hands,legs,feet]` and every exposure on that part is `stage <= Onset` (1). Effect: mark exposures `amputated=true`, set `body[part]=0`, publish `injury.sustained {injury:"amputation"}`, drain stamina to 0, require medic skill check placeholder (allow for now, gate later when skill web lands). Return `{ok:false, reason:"too-late"}` if any exposure past window.

**TDD:** Limb bite at Latent → amputate succeeds → no later stage advance; same bite at Progression → rejected.

### Task 10: Antibiotics (finite, multi-dose course)

**Objective:** Real chance to clear, declining efficacy, consumes irreplaceable stock.

**Files:** Modify: `godot/sim/modules/infection.gd`, New/Modify: content item `antibiotics` in `godot/content/items/supplies.json`

**Model:** `antibiotics {doses: int}` course item. System `infection.antibiotics` ticks: each dose taken advances `antibioticsTicks`. Clearance chance `ANTIBIOTIC_BASE_CLEAR=0.6 * (1.0 - 0.15*stage)` sampled once per course from `rng.stream("treatment")` at first dose; partial course wastes doses. Same stock also services `docs/05` sepsis placeholder (stub: no sepsis yet, but resource shared).

**TDD:** Full course in Latent clears in test harness with seeded clear RNG; stopped early wastes remaining doses and does not clear.

### Task 11: Quarantine and put-down (policy, not cure)

**Objective:** Mechanical quarantine marking and mood/attention hooks; put-down as immediate certainty.

**Files:** Modify: `godot/sim/modules/infection.gd` (components `quarantined`), `godot/sim/world.gd` (register), `godot/presentation/main.gd` (HUD count)

**Commands:** `infection.quarantine {entity, roomId}` sets `quarantined:{sinceTick, roomId}`; `infection.putDown {entity}` publishes `entity.killed` + `survivor.putDown`. No cure; quarantine isolates turning location (see Task 12). Mood hook: publish `mood.delta` event stub for later colony system.

**TDD:** Quarantined entity turns in Room A, not at feet.

### Task 12: Turning (death + reanimation)

**Objective:** End-of-timeline conversion: infected dies, then reanimates as shambler at same position.

**Files:** Modify: `godot/sim/modules/infection.gd` (turn system), `godot/sim/modules/health.gd` (reuse `killed` reap ordering)

**System:** When any transmitted exposure reaches `Stage.Turned`, publish `survivor.turned {entity, bodyPart}`, then `entity.killed`, then spawn shambler at `position` with `SimHealth.make_body` (zombie body) + tag `turnedFrom: entity`. Noise cascade: publish `noise.emitted {magnitude: 20, at: position}` (attention spine hook). Ensure this runs in `cleanup` phase after `health.reap` so death ordering deterministic. Save includes both dead survivor and new shambler entity.

**TDD:** Seed that always transmits + no treatment → survivor dead by ~72h and one new shambler exists at same tile. Seed that never transmits → no turn.

### Task 13: Determinism, save, and gate coverage

**Objective:** Prove the loop doesn't break parity/isolation.

**Files:** Modify: `godot/check_r6_ticks.gd`, `godot/check_r6_coverage.gd`, Add: `godot/check_m2_lethality.gd`

**Checks:**
- `check_m2_lethality.gd` — 4 cases: progression determinism (same seed → same stage at tick N), armor reduces transmission, amputation window enforcement, turning location with/without quarantine
- Extend `check_r6_coverage.gd` isolation: boot without `infection` module still boots; save/load round-trip with exposures + treatment state → `canonicalize(snapshot())` identical
- Bench: add `crowded-infection` scenario (200 infected) → `godot/bench/bench.gd` threshold headless 1.4ms (ponytail: slight bump for progression loop)

**Commands:**
```
godot --headless --path godot --script res://check_m2_lethality.gd
npm run godot:r6 && npm run godot:bench && npm run godot:validate
```

### Task 14: Docs and commit hygiene

**Files:** Modify: `HANDOFF.md` (In flight → M2 lethality), `docs/23-roadmap.md` (M2 slice checkbox delta), `README.md` (if new player verbs added: `K` cauterize, `A` amputate via inventory?)

**Commit sequence:** One commit per task above with `feat(infection): ...` / `feat(armor): ...` / `test: ...` prefixes. Local `3a90808` stays rebased beneath; no `--force` on `ts-oracle-final`.

---

## Tests / Validation

- `godot --headless --path godot --script res://check_content.gd` — `GODOT_CONTENT_OK` (armor schema allows new field)
- `godot --headless --path godot --script res://check_r6_ticks.gd` — `R6_TICK_PARITY_OK 120 ticks (self)`
- `godot --headless --path godot --script res://check_r6_coverage.gd` — `R6_COVERAGE_OK`
- `godot --headless --path godot --script res://check_m2_lethality.gd` — new M2 lethality suite green
- `godot --headless --path godot --script res://bench/bench.gd` — `BENCH_OK`
- `npm test` — TypeScript oracle still passes (no TS change; reference only)

## Risks, Tradeoffs, Open Questions

- **Tick math vs wall clock:** 12h at 20 Hz = 864,000 ticks; off-by-one at stage boundaries must be `>=` not `>`. Mitigate with exact `stageEnteredAtTick` and per-tick `>=` check plus a determinism golden snapshot.
- **Leaking `transmitted`:** UI must never read `zombieInfection` directly; audit `godot/ui/*` and `godot/presentation/main.gd` grep for `transmitted` after Task 7 — should be zero hits outside `infection.gd`.
- **Armor data shape:** Old saves have no `armor` field → coverage 0 by default. ContentValidator must not require `armor` on every item.
- **Save version:** Bumping `SAVE_VERSION` invalidates old test snapshots; update `godot/parity/expected/` fixture snapshots in same commit as bump, or migrate with defaults and keep version — prefer migration with defaults to avoid snapshot churn (decision at Task 3 implementation time).
- **RNG stream naming:** Adding `treatment` stream must not shift `infection`/`injury` sequences — derive from master seed independently via `RngRegistry.derive_seed(master, name)` (already does).
- **Scope creep:** Sepsis (bacterial infection) distinct from zombie infection per `docs/05:75` — explicitly out of this slice; antibiotics share stock but sepsis system is a stub that only consumes resource, not progression. Mark with `ponytail: sepsis progression lands after lethality loop proven`.

## Save Location

`.hermes/plans/2026-08-13_m2-lethality.md`
