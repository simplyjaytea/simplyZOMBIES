# The river, the lake and the yard — what to look at, 2026-09-09

Two pictures, both at the shipped 256 on the canonical seed 20260805. The gates hold the
properties; a look is arbitrated by eye, which is what these are for.

## `../2026-09-09_water/forest_river_256.png` — Blackpine Reach

The forest with its river and lake generated. What to look at:

- **The river reads as one thing at district scale.** It meanders because the centre drifts and
  the width is re-drawn at every step — a straight cut reads as a canal.
- **The pale edging is the bank**, and it is the half that matters mechanically: bank is an
  ordinary floor on the water surface, so you can wade it, it is the slowest and loudest ground
  in the game, and it is where a bottle gets filled. The dark middle is the channel, which is
  solid.
- **The breaks are bridges**, derived from the street manifest rather than drawn — they cost no
  randomness and land identically on every seed for a given street layout. A road that ran into a
  river and stopped is the one thing that would read as a bug rather than as terrain.
- **The lake is top-right.** It is an ellipse with a per-row jitter so the shore is not a drawn
  oval.

## `industrial_park_256.png` — Ordnance Way

The new fourth district type. What to look at:

- **It reads as hardstanding, not as a lawn.** That took a new content knob: the grass discs were
  hardcoded at half a block, so the first version looked like a suburb with sheds on it.
  `grassShare` is the fourteenth entry in the terrain block, defaults to the historical 0.5, and
  the yard sets 0.1.
- **The green patch centre-left is the colony annex**, which stamps its own ground and so keeps
  its verge wherever it lands.
- **Streets are 4 wide on purpose.** `VEHICLE_MIN_WIDTH` is 4, so a 3-wide district declaring a
  `vehicles` block would be a socket nothing reaches. The yard parks 95 vans and trucks here.
- 75 buildings and 226 loot sites, 223 of them industrial — the table that fills docs/12's last
  unauthored location.

**What is not decided:** whether the yard's danger reads right in play. `loot.industrial` ships at
danger `high`, between the commercial strip and the military cache, and the ten-day playtest is
what that number is for.
