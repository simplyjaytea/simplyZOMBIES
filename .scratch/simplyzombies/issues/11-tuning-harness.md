# 11 — Tuning harness for alpha

Type: grilling
Status: resolved
Blocked by: 04, 08, 09, 10

## Question

Alpha needs a **headless** way to know whether the locked slice is beating the player or starving tower defense — without a human sitting through ten 4-hour days. Combat parity is already a named risk ([Basic combat contract for early alpha](04-combat-contract.md) / roadmap risk 6). Fortify + director + save are now specified: night-with-boards, quiet-turtle floor (1 packet / 3 nights after day 8), live cap 24, v11 round-trip.

- Which **scenarios** ship in the harness (quiet turtle, noisy boards+bait, Mara dies mid-lull, melee-only vs bow-only vs pistol-only) vs stay anecdotal?
- Which **distributions** are gates vs informational (run length, death cause, siege nights / 10 days, packet size, melee/ranged outcome)? Roadmap wants thousands of headless runs; alpha budget is one box in CI.
- How does this relate to shipped benches (`godot/bench/bench.gd` tick budgets, `godot:m2:*` correctness gates, `check_m2_lethality.gd`)? New script vs extend?
- Seed set: how many seeds, and is `Nothing Personal` (director off) a required baseline so the harness can tell “field is mistuned” from “director is papering over it”?

Decision is the alpha scenario list + what is a CI gate vs a printout, so a builder does not invent a wave timer to make the numbers move.

## Answer

**Grilled 2026-08-15 — picks: Q1:A · Q2:A · Q3:C · Q4:B · Q5:A · Q6:A · Q7:A · Q8:B — plus Q9–Q11 on the same round (audio / keys / HUD ride other tickets). Resolved.**

Two speeds, one script. **CI** asserts director invariants by jumping the clock to dusk. **Nightly** (`HARNESS_FULL=1`) runs real 10-day `world.step` loops and prints; it never `quit(1)` on a distribution. That is how Q5:A (CI invariants, bench-style) and Q8:B (real 10-day loops, nightly) both stand. A default `godot:m2` that stepped 2.88M ticks would be an hour.

### Q1:A — Turtle floor is a CI invariant

Jump to dusk rising edge on days 8, 9, 10 (`tick = (day-1)*DAY_TICKS + dusk_offset`), annex `peak_noise < 25`, director registered. Assert **at least one** packet across those three dusks. Assert **zero** packet centres on annex rect `{x:40,y:40,w:22,h:20}` or within 32 m of gate `49,49` / `50,49`.

Nothing Personal pass of the same three dusks: director unregistered → **zero** packets (Q7). If that fail, the floor is leftover wanderers, not the director.

### Q2:A — Noisy night is informational

Script: board two windows, place+wind noisemaker, step a few hundred ticks. Print live count, avenue occupancy, `peak_noise`. `quit(0)` regardless of how many bodies arrived. Field unit tests already own `noise.emitted`. Do not CI-fail “not enough zombies” — that is how a wave timer gets born.

### Q3:C — No Mara-lull case in the harness

Lull still exists in [Director pressure for early alpha](09-director-pressure.md) (2 nights, bait does not cancel). Alpha harness does not assert it. Playtest / a later script can.

### Q4:B — Three short contact scripts, informational KD

Same file, not a 10-day colony. 12 shamblers, knife / bow / pistol, print connected / kills / player down. `quit(0)` always. Not a CI band. Parity contract stays `godot:m2:ranged`; this is a readout so a human can see the three branches on one screen.

### Q5:A — CI hard-fails invariants only

Hard fail: Q1 floor, packet-not-on-gate, Q7 Nothing Personal zero, plus whatever `godot:m2:save` already owns. Soft print: Q2 counts, Q4 KD, Q8 full-run siege nights / live cap. Over-time on the nightly loop prints and `quit(0)` like `godot/bench/bench.gd`.

### Q6:A — `godot/check_m2_harness.gd` + `godot:m2:harness`

Hook it on `godot:m2` next to roster/district/ranged. Default path = clock-jump invariants + Q4 contact prints. Do not extend `bench.gd` (ms) or `check_m2_lethality.gd` (infection).

`HARNESS_FULL=1 npm run godot:m2:harness` (or a `godot:m2:harness:full` script) is the nightly 10-day loop, seed `20260805` only, not on `godot:r6`.

### Q7:A — One CI seed, Nothing Personal required

CI seed is `20260805` (district). Two director modes on Q1. Extra seeds are a local flag, not CI.

### Q8:B — Real 10-day loops, nightly

`world.step` from boot through day 10 at 1× sim (speed 10× wall-clock is a runner concern, not a cheat of tick count). Print: nights-with-packet, max live, whether cap 24 hit, whether a packet touched the gate (should be 0 — if it is not, that print is the bug report; default CI already hard-fails the jump version of the same rule). Not a `godot:r6` gate.

`ponytail: default harness is the jump; full loop is a flag. Do not wait 57 minutes on every PR.`

### Explicitly deferred

Mara-lull harness case (Q3:C) · KD CI bands · 20-seed CI · thousands of campaign runs · stuffing this into `bench.gd`.

Gate `godot:m2:harness`: turtle floor fires on seed 20260805; Nothing Personal does not; packets never on the gate; contact scripts print; `HARNESS_FULL` is documented and off by default.

Status: resolved.

## Notes

- Docs: 17-director.md (Nothing Personal, variance floor), 23-roadmap.md risk 3 and 6, 09-director-pressure.md, 04-combat-contract.md, 10-save-load-determinism.md.
- Code hooks: `SimClock.DAY_TICKS` / `Phase.Dusk`; `SimBoot.playable(20260805)`; `godot:m2` in `package.json`; `bench.gd` quit(0) pattern.
- HITL 2026-08-15. Q3 skipped lull coverage on purpose. Q8 nightly full-step is not the PR path.
