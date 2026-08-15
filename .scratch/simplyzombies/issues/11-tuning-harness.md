# 11 — Tuning harness for alpha

Type: grilling
Blocked by: 04, 08, 09, 10

## Question

Alpha needs a **headless** way to know whether the locked slice is beating the player or starving tower defense — without a human sitting through ten 4-hour days. Combat parity is already a named risk ([Basic combat contract for early alpha](04-combat-contract.md) / roadmap risk 6). Fortify + director + save are now specified: night-with-boards, quiet-turtle floor (1 packet / 3 nights after day 8), live cap 24, v11 round-trip.

- Which **scenarios** ship in the harness (quiet turtle, noisy boards+bait, Mara dies mid-lull, melee-only vs bow-only vs pistol-only) vs stay anecdotal?
- Which **distributions** are gates vs informational (run length, death cause, siege nights / 10 days, packet size, melee/ranged outcome)? Roadmap wants thousands of headless runs; alpha budget is one box in CI.
- How does this relate to shipped benches (`godot/bench/bench.gd` tick budgets, `godot:m2:*` correctness gates, `check_m2_lethality.gd`)? New script vs extend?
- Seed set: how many seeds, and is `Nothing Personal` (director off) a required baseline so the harness can tell “field is mistuned” from “director is papering over it”?

Decision is the alpha scenario list + what is a CI gate vs a printout, so a builder does not invent a wave timer to make the numbers move.
