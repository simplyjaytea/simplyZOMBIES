# 01 — Which three zombies ship in early alpha

Type: grilling
Status: resolved
Blocked by:

## Question

Early alpha needs exactly **3 zombie types** (Q1) on shambler-based attention field (gradient ascent + ±0.62 rad bias, scent memory).

Doc 14 defines roster: Shambler (baseline) + First wave (Stalker, Screamer ~week 6) + Second wave (Armored, Heavy, Bloater ~week 10) + Third wave (Runner, Tracker ~week 16). Pick 3 that prove thesis without overbuilding mutation/wave system.

- Is Shambler mandatory as type 1? What covers "numbers are difficulty" vs single-file fix?
- Which 2 prove opposing counters from roster? Screamer forces silent kill / invalidates "shoot and walk away"; Stalker invalidates casual noise; Armored invalidates light melee/bows; Heavy invalidates walls; Bloater traps melee cleanup. Which pair gives cleanest parity test for melee vs ranged?
- Do we need observer-based sighting (Screamer 300 noise relay, Runner) now, or defer sight-dependent types until visibility (doc 28) proven in iso?
- How does choice affect district, fortifications, and director grace/lulls for alpha?

Decision is roster + behavior deltas + what each invalidates in alpha.

## Answer

**Roster: Shambler + Screamer + Bloater.** Shambler mandatory (numbers are difficulty + bias fix proof). Screamer invalidates "shoot and walk away" / "be seen" — makes quiet branch mandatory. Bloater invalidates cheap melee cleanup — forces "kill at range, not indoors."

- **Shambler** — as shipped (`zombie.shambler`): sensory 0.2/0.1/0.9, speed 0.8, body 25/60/40, grab 0.5. Baseline. No change.
- **Screamer** — as `zombie.screamer` draft: sensory 0.4/0.9/0.2, speed 1.1, body 20/40/30, grab 0.3, `alarm_on_sight` with `alarm {magnitude 300, relay true, cooldownTicks 600}` (30s @20Hz). 12 m eyes (`SHAMBLER_EYES`), visibility primitive already built (`sim/vision/visibility.gd` + `shadowcast.gd`, cached per tile). Triggers on `detail != Unseen` (focal or peripheral). Relay is single `noise.emitted 300` routed through kernel flood-fill — 428 m reach, ~1.5 districts, streets as highways per doc 03 wall penalty 18 m/cell.
- **Bloater** — new `zombie.bloater`: sensory 0.1/0.1/0.9, speed 0.7 (slower than shambler), wander 0.3/mill 0.25/crawl 0.25, body 30/50/40, grab 0.3, behaviors `[shamble, pursue, blooms_on_death]`. Death: emit `scent.accumulated` 30 at corpse position + `contamination` flag within 6 m for 90s (no lingering diffusion math). If survivor has open wound/located bite in cloud, extra infection roll. `ponytail: replace flag with diffusive plume when scent floor/ceiling tuned; upgrade path is scent channel write + timed decay.` This is the "trap for competent players" — correct kill costs ammo, cheap melee poisons doorstep.
- **Wave timing (alpha fake wave, no mutation system):** Day 0–2 shambler-only (proves field + director baseline). Day 2 trigger flips composition to 80% shambler / 12% screamer / 8% bloater for remaining district spawns. Proves escalation without building 6/10/16 schedule. Mutation wave scaffolding deferred — single composition knob, manual district spawn.
- **Rejected:** Stalker (noise-led) redundant with screamer's noise trap; Armored/Heavy test fortifications not core loop; Runner/Tracker need sight + route trails not needed for alpha district.
- **District/director impact:** District needs one interior chokepoint + one street sightline so both threats matter (bloater indoor penalty, screamer sight occlusion). Director grace/lulls tuned for ~8% bloater density — sparse enough every bloater is a decision, dense enough melee-only fails.

Content: two JSON entries (`godot/content/zombies/screamer.json` already drafted, `bloater.json` new) + schema extension for `blooms_on_death` if not covered by `emits`/`behaviors`. Zero new field, zero new wave system.

Status: resolved — wayfinder decisions so far points here.

## Notes

- Consult docs/14-zombies.md, docs/03-attention.md, docs/24-world-and-scale.md (256 m district, 4 m cells), docs/15-base-building.md, docs/28-visibility-and-sightlines.md.
- HITL — requires human call on which strategies to break first.
