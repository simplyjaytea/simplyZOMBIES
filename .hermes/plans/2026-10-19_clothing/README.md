# Clothe everyone (alpha A6), 2026-10-19

Shots for the owner to judge. Nothing here is read by the game.

- `before-after_*.png` — the same scene on `main` and on this branch, cropped around the
  player and a colonist (from `npm run godot:shots`, PR #148's harness, run against both trees).
- `before_*_1920x1080.png`, `after_*_1920x1080.png` — the uncropped frames.
- `side-by-side-with-pack.png` — the pack's own survivor (bare, and in its vest and helmet) and
  two of the zombie families, beside clothed survivors, all four views at 6x.
- `walk-cycle.gif` — the walk at the body's own 8 fps: bare, the default tee, leather jacket and
  jeans, the parka.
- `clothing-idle.png`, `clothing-walk.png` — every torso garment on the idle views, and the walk
  frames, from `godot/art/simplyzombies/clothing/preview.py`.

How the clothes are made and what they cannot yet do: `godot/art/simplyzombies/clothing/README.md`
and docs/23's record "clothe everyone".
