# Zombie and corpse renderer review — 2026-10-02

Captured through the actual `presentation/main.gd` scene in Godot 4.7.1 on Mesa
llvmpipe, using a temporary controlled world and review labels. The driver is not
committed. The overview uses the game's default 2x art scale; the closeup uses 4x.

The four-second GIF is derived from forty real renderer captures, two simulation
ticks apart. The encoder coalesces identical consecutive captures into 36 encoded
frames while preserving the full four-second duration. Living actors have nonzero velocity and fixed fixture positions: this
proves the frame routing and layering, not full movement, collision or AI. Every
one of the 28 family/direction combinations produced four distinct rendered
frames. All corpse rows stayed pixel-identical throughout the capture.

Zombie remains were created through `SimRecruits.handle_death`; human bodies used
its `_make_corpse` path. The armored actors carry real removable equipment. Their
dropped helmet and vest remain visible as ground items beside/over their corpses.
The first human corpse still owns a helmet, with no upright overlay rendered.

- `game-zombie-corpses-overview.png`: seven families, four living views, two zombie
  corpse poses per family, and four human poses.
- `game-zombie-animation-2x.gif`: four-second loop from the actual renderer.
- `game-armored-heavy-4x.png`: enlarged equipment, heavy scale and directional views.
- `armored-motion-detail.png`: selected equipped frames, cropped from the captures.
- `game-focal-culling.png`: the real daylight observer cone keeps six of fourteen
  zombie remains visible, omits the other eight and renders outer moving zombies
  as anonymous peripheral glimpses.
- `game-corpse-overlap.png`: settled bodies slightly south of standing actors;
  living feet draw over the flat corpse pass.
- `visual-review.json`: capture counts and per-view frame uniqueness.

The all-family overview uses a wide observer cone solely to expose every fixture.
The Focal comparison restores the real daylight cone. No game rendering code was
modified by the capture driver. These images support the focused and full gates;
they do not replace a campaign playtest.
