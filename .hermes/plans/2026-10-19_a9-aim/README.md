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

- `backpedal_before_after.gif` -- walking west with the cursor held east, side by side: before,
  the east view's walk runs forwards while the body slides backwards (a moonwalk); after, the same
  frames run in reverse and the body steps backwards, still facing the cursor.
- `sidearm_before_after.gif` -- the service pistol (a secondary-hand item) fired at a shambler to
  the east: before, the far hand hides it behind the body; after, the wielded weapon comes round in
  front of the body seen from the side.

The record is docs/23's "Feel -- the weapon turned to the cursor, and the blow felt".
