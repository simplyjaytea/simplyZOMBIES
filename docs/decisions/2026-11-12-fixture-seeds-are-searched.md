# A gate fixture that needs a thing searches a seed list for it

- **Date:** 2026-11-12
- **Decided by:** engineering
- **Systems:** the dormant gate (`godot:m2:dormant`, ASLEEP), the trees gate (`godot:check:trees`, STOCK)

**Decision.** A lane that needs a district to hold something (a dormant body, a storage room
with several barrels) tries a short list of seeds in order and judges the first that holds it.
It fails, naming the whole list, only when none does. The lists are fixture choices, not
measured numbers.

**Why.** Adding the police box and the village shrine moved the draws and emptied the pinned
seeds of three lanes (#393), each re-pinned by hand to another seed. Any new template can do it
again. The lanes already failed loudly when empty; now they also recover.

**Instead of.**

- Pinning one seed per lane, as before: breaks on every template that moves the draws.
- The settlers lane (`LANE_SEED` in `check_m2_settlers.gd`) is left pinned: seven behaviour
  lanes share it and "sites a camp" is not all they need (the recruit lane needs a settler in
  reach of E), so a search on one predicate would pick seeds other lanes then fail on.
