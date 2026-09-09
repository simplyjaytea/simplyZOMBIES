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

## `shore_zoom.png` — the two waters at gameplay zoom

A 26×18 window of the river at 32 px a tile, which is the scale the game actually draws at. Added
on the owner's call that shallow and deep must be discernible. What to look at:

- **The dark navy is the deep channel**; the pale blue either side is the wadeable bank. The gap is
  value 0.209 against 0.361 — three times the separation between any two of the five original
  grounds.
- **The rim is what actually does the work.** Every deep tile draws a lit shoreline on each side
  whose neighbour is not also deep. A value gap alone reads as "darker water"; an *edge* reads as a
  bank, and it is the cue that says where a foot goes. A ford cut through the channel is outlined
  on both sides, so a crossing is visible before you are standing in it.
- **The channel is bounded from below.** The background is `#15141f` at value 0.122, so a darker
  channel would read as a hole in the map rather than as water.

**Wading it soaks you.** A ford is an ordinary floor on the water surface, so it has always walked
at ×0.45 speed and ×1.8 noise; what is new is that standing in it sets the wet state at once — the
rain slice's own field, dried by the same clock and the same fire — and a wet body reads one band
colder. Measured: `a_little_cold` on the ford against `comfortable` on dry ground one tile away.
