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
and seats every frame's soles on the rest view's ground row.

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
  west, and declares no hands: a body lying down carries no layer.

Each frame declares `head`, `torso` and (on the survivor) `hands`, where the move took them, so
worn and held layers follow by the same contract as the walk. `godot:check:action` holds the
catalogue, the timing and the colours (a derived frame carries only its source's colours).
