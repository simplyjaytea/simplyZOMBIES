# First-person district size, measured

The first-person scene used to boot a 64-tile district. It now boots the district size and seed the
shipped game boots by default: `SimTileMap.DISTRICT_TILES` (256) and `SimBoot.DISTRICT_SEED`, the
same pair `session.gd` passes to `SimBoot.playable`. The gate sets a small 64-tile override
(`SMALL_DISTRICT_TILES` in `godot/check_first_person.gd`) before it adds the scene, so every lane
still walks a small district and stays fast.

## Measurement

- **Date:** 2026-11-01.
- **Machine:** AMD Ryzen 7 7800X3D (8 cores), NVIDIA GeForce RTX 5090, 32 GB RAM, Windows 11 Pro
  10.0.26200.
- **Engine:** Godot 4.7.1 stable, win64 console executable, Compatibility renderer.
- **Setup:** headed, window 1280x720, standing at spawn with the scene's own frame function
  running (no gate overrides). VSync disabled for the run, so the frame figure is the loop's
  frame interval and not capped at the display rate.
- **Build time:** from `PackedScene.instantiate()` plus `add_child` to the scene's `_ready` returning,
  which includes the sim boot. Three runs each.
- **Frame time:** the wall-clock interval between 300 consecutive `process_frame` signals, after
  the scene is built, plus the engine's `TIME_PROCESS` monitor. Three runs each. The mean of the
  300 frames is the figure the threshold names.

The driver was a throwaway script under `godot/` and was deleted after the runs. It is not
committed.

| Boot | Tiles | Build (ms), 3 runs | Mean build | Mean frame wall (ms), 3 runs | Mean frame process (ms) | Max frame wall (ms), mean of 3 |
|---|---|---|---|---|---|---|
| Before (the old 64-tile test district) | 64 | 121.4, 122.0, 119.7 | 121 | 0.67, 0.65, 0.74 (mean 0.69) | 0.62 | 18.99 |
| After (shipped default) | 256 | 1046.5, 1025.6, 1023.1 | 1032 | 0.98, 0.95, 0.97 (mean 0.97) | 1.68 | 55.3 |

The before row is the 64-tile scene as it stood on `pivot/first-person-foundation` at `9bf1de6c`.
The after row is the same scene with the shipped boot size and no chunking.

## Verdict

The threshold for splitting the district mesh into chunks was a frame over 10 ms or a build over
2 s, on this machine. The shipped size measures a mean frame of about 0.97 ms and a build of about
1.03 s, so neither threshold is crossed. The district stays as two meshes (`GroundTiles`,
`SolidTiles`), and chunking was not done.

Two things the numbers do not settle:

- The maximum single-frame wall time is about 55 ms at 256 tiles, against about 19 ms at 64. The
  run did not attribute that spike, and it is not the mean the threshold names. It is a single
  frame and the cause is not known.
- The figures are from one GPU. A slower GPU could make the 10 ms frame threshold tighter than it is
  here. A rerun on the machine the player will use is the check that would settle it.

## Gate

`npm run godot:check:first_person` gains a DISTRICT lane with a true positive and a true negative:

- **Default is shipped (true positive).** A fresh, unparented instance of the scene reports
  `district_tiles == SimTileMap.DISTRICT_TILES`, and the scene's `SEED` equals
  `SimBoot.DISTRICT_SEED`. The instance is freed before any sim boots.
- **Override is smaller (true negative).** The booted map is `SMALL_DISTRICT_TILES` (64) tiles, the
  scene's `district_tiles` is 64, and 64 is below the shipped 256.

Both halves were mutation-tested. With the gate's small size set to 256, the lane fails with
`DISTRICT: the gate's district (256) is not smaller than the shipped 256`. With the scene default set
to 64, it fails with `DISTRICT: a fresh scene boots 64 tiles, not the shipped 256`. Both edits were
reverted, and the gate was then run green.

No chunk-coverage assertion was added, because nothing was chunked.

## Limits

- The scene still draws the whole district as one ground mesh and one solid-tile mesh. At 256 tiles
  that is about 65,000 floor quads. The frame measurement says it is cheap on this GPU, not that it
  is cheap everywhere.
- The shipped 256 district builds a full sim world on boot. The gate avoids that cost by using the
  override, so the gate stays at its earlier run time (2 to 3 s on this machine).
