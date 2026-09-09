# Water — what to look at, 2026-09-09

Two pictures for the owner to judge. The gate (`npm run godot:check:water` → `WATER_OK`) holds the
*properties*; a look is arbitrated by eye, which is what these are for.

## `ground_rows.png` — the new ground against the five it joins

Four variants of every atlas row at 4×, water sixth. What to look at:

- **Does it read as water beside the warm grounds?** This is the blue you authorised, and it is
  the one ground exempted from the warm-palette sign (`r - b >= 0.02`). The exemption is a named
  pin rather than a hole — `COOL_SURFACES` judges water with the *cool* pin, so it has to be
  measurably cool and not merely un-warm.
- **It is darker than you might expect, and that was not a preference.** The first tint (`#55636b`,
  value 0.42) was refused at import by `tools/sprites/palette.py`'s `guard_against_ground`: it made
  water the brightest ground in the game, and the `fatigue_drab` pawn ramp then cleared it by only
  0.067 against a `GROUND_CONTRAST` of 0.10 — a colonist standing on the bank would have read as a
  hole in the river. Shipped at `#424f5c`, value 0.361. **A new ground is bounded from above by the
  darkest pawn ramp.**
- **The saturation cap was deliberately not exempted.** Water sits at 0.283 against a cap of 0.30,
  so it is close to as blue as the current rules allow. A brighter blue needs a second exemption,
  and that call is yours — it is item 0d in `HANDOFF.md`.
- **The ripples are the only directional mark in the set.** Every other row is speckle or blocks;
  water gets horizontal crests with a trough under each, which is the cue that this surface moves.

## `ford_vs_deep.png` — the two halves of a river

Flat colour, no texture, so the separation is the only thing being judged. The ford is the authored
tint; the deep channel is that tint darkened by `WATER_DEEP_SHADE` (0.30) rather than a second
authored colour, the way a wall's face is lifted out of its cap — two colours would drift apart
under a regrade.

The two must read apart at a glance, because that difference is **where the river is crossable**.
A ford is an ordinary `Tile.Floor` on the water surface and walks; the deep channel is `Tile.Water`
and does not.

**The generated river landed the same day** — `forest_river_256.png` beside this file is
Blackpine Reach with its river and lake, and `../2026-09-09_yard/` carries the industrial park.
Read this file for the palette question and that one for the terrain.
