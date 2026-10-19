# A9 evidence: the weapon turned to the cursor, and the blow felt

Captured from the real scene under Xvfb at 1280x720, camera zoom 128, by a throwaway driver
(deleted after use) that equips a service pistol, moves the real pointer and clicks. Each `before`
is the same driver on PR #154's head; each `after` is this branch. Frames are halved (2x art).

- `aim_circle_before.gif` / `aim_circle_after.gif` -- standing, the cursor swept once round the
  body. Before: the body turns its four views and the weapon points down one of four axes, under
  a white facing line. After: the weapon turns all the way to the cursor, about the hand, and the
  line is gone; the faint ring is the reticle at the cursor.
- `aim_walking_after.gif` -- walking east (D held) while the cursor sweeps round to the west: the
  feet keep east and the body and weapon follow the cursor, Project Zomboid's way.
- `hit_before.gif` / `hit_after.gif` -- three shots at a shambler a few metres east. After: the
  pistol kicks back in the hand, the flash leaves the turned muzzle, and a struck body flashes
  white and jolts away from the shot.

The record is docs/23's "Feel -- the weapon turned to the cursor, and the blow felt".
