# Phase 2 props review

`source-contact.png` shows the four reproduced pack pictures at native pixel size over checkerboard. Every source was mechanically cropped at its published ground anchor after checking that the removed row had no pixel at alpha 128 or higher.

## Runtime captures

- `built-workbench.png` — the shipped suburb boot, seed `SimBoot.DISTRICT_SEED` (20260805), day 1. The driver gave the player the recipe's three scrap, pushed the existing `bench.build` command on the facing tile, and advanced the real channel for `SimGunsmith.BENCH_TICKS + 4`; it asserted exactly one workbench component before capture. This is the same entity the bench interaction uses.
- `prop_fridge-body-north.png` / `prop_fridge-body-south.png`, `prop_road_sign-body-north.png` / `prop_road_sign-body-south.png`, and `prop_streetlamp-body-north.png` / `prop_streetlamp-body-south.png` — actual deterministic furniture picks on the same map, with the player staged above and below each anchor and sight refreshed before the capture. These show the body/prop depth order and the standing picture's overlap fade. The unexplored edge remains visible in the same scene.

The capture used Godot 4.7.1 on `DISPLAY=:0`; the active fullscreen display produced 2560×1440 PNGs. All art shown is the runtime renderer output; the driver was temporary and has been removed.
