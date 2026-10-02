# Phase 4 light source captures

Captured from `godot/presentation/main.tscn` with Godot 4.7.1 on an exact-size 1280×720 SubViewport. The one-source comparisons share the same boot world (seed `20260805`), room, camera snap, source tile and night time (day fraction 0.90, ambient 0.04); each uses one active content source, with the light attention channel on to make its pool hue readable. The electric, glowstick and flare captures use the player's carried/equipped source path and their existing content magnitudes. `night-natural-alpha.png` repeats the single campfire with the light overlay off, showing the ordinary pool alpha. The disposable SceneTree driver was deleted after capture.

- `night-fire.png` — A lit campfire at the player's tile resolves warm `#ffd68c` and draws its flame.
- `night-electric.png` — The player carries the electric lamp (`#e5edf2`); its larger existing reach makes a broader neutral pool.
- `night-green-carried.png` — The player carries the glowstick (`#a8d58b`), showing the green pool.
- `night-red-carried.png` — The player carries the road flare (`#ee856c`), showing the red pool.
- `night-natural-alpha.png` — The same campfire-only night arrangement, ordinary attention channel.
- `night-overlap-wall.png` — Co-located lit campfire and carried electric lamp show the existing maximum-reach winner on the near side. A red road flare behind the vertical wall remains unseen and its far-side pool is not painted.
- `noon-same-view.png` — The same sources, room, camera and wall as `night-overlap-wall.png`, at day fraction 0.25 (ambient 1.0) with ordinary attention; full daylight paints no pools.

The capture driver logged the individual resolved tints as warm `ffd68c`, neutral `e5edf2`, green `a8d58b` and red `ee856c`. `godot:check:light` separately asserts exact near/far membership and alpha, max/tie overlap, viewport bounds, removed-source invalidation and wall rejection.
