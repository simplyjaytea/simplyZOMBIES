# Clothe everyone (alpha A6), 2026-10-19

Shots for the owner to judge. Nothing here is read by the game.

- `side-by-side-with-pack-4x.png` (and the 6x `side-by-side-with-pack.png`) — the pack's own
  survivor (bare, and in its vest and helmet) and three of the zombie families, beside clothed
  survivors, all four views.
- `in-game_three-passes_*.png` — the same scene cropped around the player and a colonist, on
  `main` (underwear), the first flat-tone pass, and the shaded pass that shipped (from
  `npm run godot:shots`, PR #148's harness, run against each tree).
- `before_*_1920x1080.png`, `after_*_1920x1080.png` — the uncropped frames, main and the first
  shaded pass.
- `in-game_outfits_day-night.png` — the harness's day_street and night_lights scenes on the final
  art, moved onto the nearest open street and cropped at 4x: the player in the default slate tee,
  charcoal trousers and worn shoes, Ellis in the parka kit, Mara in the leather kit, and a stranger
  in the hazmat suit. `in-game_outfits_*_1920x1080.png` are the uncropped frames. The placement,
  the kits and the player's outfit list were set by a throwaway patch to PR #148's harness, not
  committed; the stranger borrows Mara's identity so it is drawn without a colony look's tint (one browns the suit, as it does any clothes).
- `walk-cycle.gif` (4x) and `walk-cycle-1x.gif` (native) — the walk at 120 ms a frame (a GIF
  counts in hundredths, so the body's 125 ms is shown as 120 in every file here),
  all four views: bare, the default slate tee, leather jacket and jeans, the parka, the hazmat
  suit. A GIF holds 256 colours and a frame here has about 1,200, so each frame is quantised;
  `walk-cycle-4x.apng.png` and `walk-cycle-1x.apng.png` are the same frames lossless.
- `clothing-idle.png`, `clothing-walk.png` — every torso garment on the idle views, and the walk
  frames, from `godot/art/simplyzombies/clothing/preview.py`.

How the clothes are made and what they cannot yet do: `godot/art/simplyzombies/clothing/README.md`
and docs/23's record "clothe everyone".
