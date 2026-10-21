# Motion: the eight-frame walks and the breath

Alpha plan item A7 (docs/23, "Frames on the render clock"). Everything a body shows while it
walks or stands, beyond the pack's own four rest views and four-pose walks, is built here by one
script, `build_motion.py`, and nothing else writes these files.

```bash
python3 godot/art/simplyzombies/motion/build_motion.py          # rebuild
python3 godot/art/simplyzombies/motion/build_motion.py --check  # MOTION_OK, or what drifted
python3 tools/sprites/build.py                                   # then crop the runtime PNGs
```

## What is generated and what is mechanical

**The survivor's walk is generated art.** `sources/` holds the four PixelLab strips
(`generation.json` names each job, its input and its prompt). Each was animated *from the pack's
own rest view*, so frame 0 of every cycle is the same body, the same palette and the same
outline as the standing picture -- the old four-frame walk was drawn separately from the idle
and popped its skin tone and its outline when a body set off. The script crops each frame at
the input's offset, binarises alpha at 128 (the pack's rule), drops specks under three pixels,
and seats every frame's soles on the rest view's ground row. Four of the east strip's eight
frames came back with the hips bare (skin and a black line where the pack's grey shorts are);
`restore_shorts` puts the band back where the cycle's neighbouring frames have it, in the rest
view's own grey, so the shorts never vanish mid-stride and the clothing painter
(`../clothing/parts.py`), which finds every frame's waist by that band, can dress all of them.
`close_outline` closes the ink ring where a generated pixel of skin or cloth touched the outside
(open on one side it becomes ink; open on two or more it is cleared), and `drop_hip_seams` lifts
the line of ink two east frames drew across the top of the legs, which showed through every pair
of trousers as a stripe. `recentre` moves each frame sideways so its head sits over the rest
view's (the side walks drifted forward through the cycle and snapped back on the loop), and
`retime_bob` moves the body from the hips up, as one block, to `SURVIVOR_BOB`'s head rows: two
even beats a cycle, no frame moved more than a row. The south, west and north walks wear the rest
view's head on every frame (`same_head`; the generator redrew it, which read as a nod), the
south's trunk is held to the rest view's 19 rows from head top to belt (`trunk`), every
frame stands a foot on the ground row, and ink on the silhouette's edge is the ring's own black
(`outline_black`). The survivor's breath (`survivor_breath`) lifts the chest a
row and plants the hands where they hung; the clothing painter puts each garment's rest picture
through the same function.

**The zombies' in-betweens and every breath are mechanical.** Each zombie family keeps its four
pack poses as frames 0, 2, 4 and 6; frames 1, 3, 5 and 7 are the pose before them with the rows
above the hip carried one pixel toward the next pose's height (down when the next pose stands
lower, up when taller; the stride's rhythm decides where they stand level). The breath is the
rest view with the rows above the chest one pixel up (the survivor inhales) or down (the dead
sag). The legs and soles never move, so no frame changes the anchor. This is a row shift of the
pack's own pixels, not new drawing -- `STYLE.md` asks for authored frames, and these are the
half of A7 that a later commissioning pass should replace with drawn in-betweens.

## The per-frame data

Every walk and breath member in `godot/assets/sprites/authored.json` declares where its head and
torso moved from the rest view (`head`, `torso`, pixels) and, on the survivor, where each hand
is (`hands.primary`, `hands.secondary`). The renderer reads them through
`Appearance.frame_offset` and `Appearance.frame_hand`; `godot:check:worn`'s FRAMES lane holds
them to the pictures.

## Actions (alpha plan A8)

docs/23, "Actions on the render clock". `actions.py` builds every action frame; `build_motion.py`
calls it and writes the members, the `actions` block (rate and loop per action) in
`authored.json`, and the pack manifests' frame lists.

**Generated: the survivor's swing, east, west and south.** `sources/actions/` holds the three
PixelLab strips, nine 64x64 frames each, frame 0 the pack's rest view pasted at (16, 12);
`generation.json` names the jobs, prompts and the two rejected jobs (four views in one input
drifted between quarters; the back view turned side-on). `SWING_KEEP` picks five frames a view:
guard, top, chop, follow-through, way back. The generator's white smear trails are dropped
(`_is_trail`, then the largest island), alpha binarised at 128, soles on the anchor row.

**Derived: everything else**, by whole-pixel moves of the pack's own pictures (`plan` lists the
moves per action and view):

- a **lean** slides the rows above the hip, `dx` at the head and nothing at the waist;
- a **dip** or **rise** moves them down or up (a rise repeats the hip row into the gap);
- a **fold** takes rows out of the shins from `KNEE_PCT` below the hip, so the shorts or the belt
  survive and the feet are never cut;
- a **step** moves the whole picture, kept `SIDE_CLEARANCE` from either canvas edge;
- the **crawl** is the back view's walk turned a quarter flat (`turn_flat`), drawn only east and
  west, and declares no hands: a body lying down carries no layer;
- a **fall** folds the knees over feet that are kept (`keep_feet`, which redraws the hip's top
  rows over the sunk body so a belt stays painted), then turns the body 10 degrees a beat, 10 to
  80, about the outer edge of its leading sole toward `FALL_SIDE`
  (`turn_about_feet`: Scale2x three times, sampled in whole-number sines and cosines from
  `TURN_TABLE`, back down, and the edge the turn opened ringed in the bare body's own darkest
  colour, so no colour is invented). Fall frames are on `fall_canvas`, 96 wide and the family's
  height, and each member says so in its own `canvas`. The fall then **settles onto the pack's
  own corpse** (`settle_plan`, `settle_frames`): prone for a side view, supine for the front and
  back (`LIE_POSE`), mirrored to the fall side, the heavy's and the bloater's widened by whole
  sixteenths to their belly mass (`BELLY_PCT`). The armored's prone corpse is widened by the
  same rule: 29x25 and 306 pixels in the pack, drawn 17/16 its size, 31x27 and 355 pixels, on
  the fall. The front and back views lie in one place, mirrored, nearest where the corpse overlaps
  the last turn most; the side views lie as a pair whose foot ends mirror within `SETTLE_MIRROR`
  columns, the pair whose feet move least from where each turned frame's lay (`SETTLE_FOOT`
  columns count as none). The runner's two turned frames lie 13 columns off mirror, so its
  corpses land 6 columns from each turned frame's feet. One beat count a family, the fewest that keep every
  step inside the bounds with a margin (`SETTLE_MASS_PCT`, `SETTLE_CENTRE_X2`, `SETTLE_EDGE`, the
  sole row held): each beat adds the corpse's pixels nearest the body first and drops the turned
  frame's farthest first, linearly by count, and keeps only its largest connected run. Every
  view carries its head whole (`HEAD_CARRIED`, `fall_head`, `corpse_head`), k/n of the way to
  the corpse's head on beat k, taking the corpse head's colours and shape over its last
  `HEAD_FADE` beat, a half swap (each pixel changes once, half on that beat, the rest on the hold
  frame). Face down the corpse's head is the top of its fall-side third; on its back it is the
  body's end, `HEAD_INSET` columns in from the end column at that column's middle row. An outline either picture draws that a beat buries inside the body takes
  the colour under it (`settle_frames`), so neither body's edge shows through the other. The
  corpse is the last frame, the settled body the renderer draws where the fall stood
  (`presentation/appearance.gd` `lying_key`).

**The reloads are drawn** (`reload_frames`, `RELOAD_BEATS`): eight beats for a magazine, eleven
for the tube. Each arm the reload moves is taken off the rest view (`ARMLESS` closes the torso's
outline where it hung) and drawn again as a jointed limb (`ARM_RIG`, `_limb`): an upper arm and a
forearm in the rest view's own outline and skin, the elbow bending out as the hand comes close or
across, a second outline where it meets open ground. From the front both arms are over the torso;
from behind they reach only to the edge of the back (`BACK_EDGE`), the hand point going on behind
it; side on the far arm is under the body, its forearm over the belly once it reaches round. The
magazine is a 2x3 block, outlined, in the held pistol's gunmetal (`_weapon_ramp`): the pistol's
drops out of the grip and lands the next beat (side on it falls ahead of the shin, since the grip
is over the legs), the long gun's is stripped from the well (`reload_long`, `LONG_WELL` pixels
along) and hangs from the off hand (`_held_mag_at`) before it falls, and it lies by the feet
(`MAG_SPOTS`) to the end, the long gun's on the off hand's side; side on, the fresh one hangs from
the fist at the back of the belt (`pouch`) for a beat, then seats with its foot showing under the
well. The shotgun is tube-fed (`reload_tube`): no magazine, a shell in the shells icon's colours
(`_shell`, `_shell_ramp`) brought to the loading port and pushed into it three times, the next
already in the fist as the hand goes back, then one rack. The west view's magazines and shells
mirror the east's pixel for pixel. The body dips a pixel as the weapon comes down and comes back
up to the stance, never above it, both at the knee (`_knee`). Outline an arm adds that would wedge
against the body's own, or that rings skin the reload's own held weapon covers (`_held_cover`,
read from the pack manifest), is taken back (`_trim`), and side on a back edge the far arm
thickens is kept to the pack's two pixels (`_thin_back`). From behind a long gun is held still
but for the rack's jolt, a pixel up: any other travel shows its muzzle or stock a frame at a
time.

Each frame declares `head`, `torso` and (on the survivor) `hands`, where the move took them, so
worn and held layers follow by the same contract as the walk. `godot:check:action` holds the
catalogue, the timing and the colours (a derived frame carries only its source's colours, a
reload's magazine only the held pistol's, the tube reload's shells only the shells icon's).

The clothing painter (`../clothing/action_wear.py`) rebuilds every action frame from these same
functions and holds the result to the committed picture byte for byte before it dresses it. Two
hooks exist for it and change nothing drawn: `reload_frames(..., trace=[])` appends each beat's
armless body, dip and colours, and `_draw_arms(..., record={})` records each limb's shoulder,
hand, elbow and the pixels it showed, so a sleeve can be measured along the bone it covers.
