# A7 evidence: walks and breath, before and after

Rendered from the committed runtime PNGs (`godot/assets/sprites/`), the "before" from the
previous commit's. Each sheet is one row per view (south, east, north, west), drawn at 4×.

- `<body>_before.png`: the old four-frame walk.
- `<body>_after.png`: the eight-frame walk, then the rest view and the breath picture.
- `<body>_walk_before.gif` / `_walk_after.gif`: the cycle at the manifest's rate, four views side
  by side (before: survivor 8 fps, zombies 4-9; after: twice that, on twice the frames, so the
  step cadence is the same and the motion between steps is twice as fine).
- `survivor_kit_after.png` / `survivor_kit_walk_after.gif`: the survivor in the bike helmet, the
  plate carrier and the service pistol, composed by the layer contract (helmet on the frame's
  head offset, vest on its torso offset, pistol at the frame's own primary hand).

The survivor rows are generated art; the zombie odd frames and every breath are one-pixel row
shifts of the pack's own poses (docs/23's A7 record says which half is which).

Added 2026-10-20, after the clothing (A6) merged over this:

- `outfits_walk.gif` (half speed) and `outfits_walk_fullspeed.gif` (16 fps): the eight-frame walk
  dressed in four outfits, one row each -- tee and charcoal trousers, leather jacket and jeans,
  parka and insulated trousers, hazmat suit -- with the four views side by side.
- `outfit_<name>_frames.png`: every frame of one outfit, a row per view: the eight walk frames,
  then the rest picture and the breath.
