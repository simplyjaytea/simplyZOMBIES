# tools/sprites — the generators behind the generated art

The PNGs under `godot/assets/sprites/` are the source of record for the **game**: `appearance.gd`
resolves files, and `npm run godot:check:appearance` judges every one of them against the canvas
its own `canvas_of` declares, every build. This package is the source of record for the **art** —
the reason a colour is that colour, and the thing that lets a whole batch be regraded without
re-drawing it by hand.

## Running it

```bash
pip install pillow==12.3.0            # the one dependency, pinned
python3 tools/sprites/build.py        # write every registry key
python3 tools/sprites/build.py --only player_body
python3 tools/sprites/build.py --check   # regenerate and compare; writes nothing
npm run sprites:check                 # what CI runs; the line above with a name
```

`--check` re-renders every registry key and compares **decoded pixels** against the committed
PNG — never file bytes, which would go red on an encoder change that altered nothing anybody can
see. A key with no committed file fails too: the registry and the sprite directory are two halves
of one statement, and a key nothing has drawn is a generator nothing reads.

`sprites:check` runs in CI's `check` job and **not** in `npm run godot:m2` — that chain is
engine-only and stays pip-free, and a contributor without Pillow can still run every gate that
decides whether the game is correct.

## Why this is not a throwaway driver

CLAUDE.md says to delete the driver afterwards. That rule is about **measurement** drivers, whose
product is a number: once the number is in the record, the script is a liability. A generator's
product is committed art that the whole arc re-derives from, and moving it to `.hermes/`
guarantees palette drift between batches — which is the disease this method exists to cure. So it
lives in the repo, in the same commit as its first key, and `--check` keeps it honest.

## Layout

| file | what it owns |
| --- | --- |
| `palette.py` | ramps, the desaturation/value clamps, the ground-luminance guard |
| `draw.py` | pixel primitives; `Canvas(w, h, origin)` carries a centre or a feet origin |
| `parts/characters.py` | the eight rigs, the published skeleton, the `REGISTRY` naming them |
| `parts/gear.py` | the three equip overlays, generated against the published skeleton |
| `parts/props.py` | the seven district props, each authored to its content entry's footprint |
| `parts/wrecks.py` | car segment sets, and the debris scatter |
| `parts/edges.py` | the ground's edge cells, eight fringes a row, pasted into the atlas |
| `parts/buildings.py` | wall caps and faces, roof sheets and the door, window and garage overlays |
| `build.py` | the CLI, the registry merge, `--check`, `CANVAS`/`PAWN_KEYS` (mirrors `canvas_of`) |

## The rigs, the skeleton, and the draw order

`parts/characters.py` holds one function per rig — player, Mara, Ellis, the colonist, the
shambler, the screamer, the bloater, the raider — and every one of them draws through a single
`_figure` assembler rather than through its own drawing code. That is the point: a rig is a
dict of parts (`legs`, `torso`, `head`, `face`, optional `feet`, `arms`, `seam`, `hands`,
`hair_back`, `hair`, `tells`, and the required `shade`), and `_figure` is where the roster's one
fixed draw order lives — **legs → feet → torso → arms → seam → hands → hair_back → head → hair
→ face → tells → shade → outline** — enforced once rather than by convention in eight
functions. Getting the order wrong is not merely untidy: the outline is drawn *last*, after the
shade pass, because `OUTLINE` (`#161614`) is a channel delta of exactly 2 and a shaded outline
drifts to delta 3 — past `check_appearance.gd`'s achromatic bound on the colonist lane. The same
arithmetic is why the colonist's face is painted in a pure grey rather than in `OUTLINE`: a face
is drawn *before* shading, so an `OUTLINE` eye would be multiplied too.

Every rig is authored against a **published skeleton** — named rows in pixels above the soles,
negative y upward, defined once at module scope (`FEET_Y`, `LEG_TOP_Y`, `TORSO_TOP_Y`,
`SHOULDER_Y`, `HAND_Y`, `HAND_X`, `HEAD_CY`, `HEAD_R`, `SHOULDER_HALF`) — rather than against a
canvas row, so the rows do not have to be re-derived if the canvas ever grows again. Publishing
them is what lets `parts/gear.py` fit one generated overlay to all eight bodies instead of
authoring eight overlays with eight chances to disagree. The bloater is the one rig that moves
the numbers, and it moves exactly three: its own torso half-width and top, its own arm x, and
its own head centre — `FEET_Y`, `LEG_TOP_Y` and `HAND_Y` stay untouched, which is what keeps the
gear overlays fitting it too. `HEAD_R` is 5.0 and not the arc plan's 5.5 by measurement rather
than by taste: pixel centres on a 32-wide canvas sit at half-integer offsets from the middle, so
a shape centred on x = 0 is always an *even* number of pixels wide, and 5.5 renders 12 px, one
over the head bound, where every radius in [4.5, 5.5) renders 10.

A face is the three pixels `_face()` draws for every rig: two 1 px eyes `EYE_SPREAD` (1.5, so
3 px) apart, and one brow pixel above and to the left — dark stays dark after the shade pass on
the lit side, and a symmetric pair would have been four pixels where the convention allows
three. Every rig also gets exactly one asymmetric tell — a strap, a bob, a reaching arm — safe
to draw because the roster mirrors rather than rotates: a tell that swaps sides with the flip is
exactly what it does on a person who turns round, which was not true when a rig could spin.

## The rules the art is held to

- **Two canvases, one table.** `draw.SIZE` (32) is still the one tile-square number Python
  holds — `presentation/camera.gd`'s `ART_NATIVE` is the engine's copy, and the two gates
  cross-check. A tile-sized picture seen from above — a prop, a tile-art key, a scrap of debris
  — renders on `Canvas(SIZE, SIZE, origin="centre")`; every body and every equip overlay renders
  on `Canvas(characters.PAWN_W, characters.PAWN_H, origin="feet")` — 32×48, one tile wide and
  one and a half tall. `build.py`'s `CANVAS` table and `PAWN_KEYS` mirror `Appearance.canvas_of`
  and its own `PAWN_KEYS` — two copies because Python cannot read GDScript, the same standing
  arrangement as `SIZE` — and `check_appearance.gd` measures every committed PNG against the
  engine's copy every build. `godot/assets/sprites/README.md` is the authority on the shapes;
  `build.py` refuses a render at the wrong size before it writes, and `check_appearance.gd`
  refuses it again from the engine side.
- **The origin is the pivot, and it means two different things.** `origin="centre"` puts (0, 0)
  in the middle of the picture — on the 32×32 canvas that is between pixels 15 and 16, not
  pixel 16 — and the renderer hangs a centred picture symmetrically on the entity's ground
  point. `origin="feet"` puts (0, 0) on the middle of the picture's *bottom row* instead, so a
  pawn is authored in pixels above its own soles (negative y is up) and the renderer hangs its
  bottom row on the ground point plus the contact shadow's own drop (`FOOT_DROP_PX`, 3.0).
  Either way a shape drawn symmetric about the origin lands where the sim says the entity is.
- **In its family, always.** Every colour goes through `palette.clamp` under a named family —
  `muted` (S ≤ 0.30, V in [0.12, 0.72]: cloth, stone, glass, concrete, litter, the achromatic
  colonist rig — the manufactured and the worn-out), `timber` (S ≤ 0.45, V in [0.15, 0.80]:
  skin, sawn wood, rot, the zombie roster's flesh), `accent` (S ≤ 0.85, V in [0.30, 0.95]:
  fire, and nothing else so far) — and `clamp` and `ramp` default to `muted`, the tightest, so
  a call that names no family gets the strictest answer. docs/30's warm dark-fantasy mood (the
  Dungeon Settlers look, 2026-09-03) is not a thing to remember, it is a thing the module
  enforces; the overcast grade's single 0.35 ceiling is what this replaced.
- **It has to read against the ground.** A body-forming ramp's mid tone must clear the brightest
  surface tint the district can draw by `GROUND_CONTRAST` in luminance, or importing `palette`
  raises. `SURFACE_TINTS` (and `PAINT_TINTS`, the two paint rows) here are hard copies of
  `presentation/palette.gd`'s, because Python cannot read GDScript — regrading the ground means
  editing both **in the same commit**, and a stale copy makes the guard lie. Tells drawn
  *inside* a silhouette (a strap on cloth) are exempt and say so in `GROUND_FACING`. Standing
  things (`GROUND_READING`) are held either side of the ground instead, and the built surfaces
  (`BUILT_READING`: the wall and roof ramps `parts/buildings.py` paints with) either side of
  every floor including the two paint rows, because a front stands on the sidewalk and a roof
  covers the board floor — `guard_either_side_of_floors`. That rule moved four of the plan's
  seven building bases: timber, brick and shingle up to the lit side, tar down to the dark.
- **Light comes from the top-left**, matching `main.gd::_draw_bevelled_box` — `light_top_left`.
  Nothing on the roster rotates any more, so the exception that used to carve the player's rig
  out of this rule is gone with the rig: every pawn takes the same `nw_shade` (`Canvas.nw_shade`,
  `RIG_LIGHT_RADIUS` 15.0) as every prop, wreck and scrap of debris. The one remaining exception
  is a **segment set** (a car spanning two or three tiles), which keeps only the lateral half of
  the gradient (`axis="x"`), because a diagonal one restarts at every canvas and bands the
  finished car light-dark-light along its length.
- **The light passes measure from the picture middle, not the pivot.** `Canvas.middle` is a
  second coordinate frame that differs from the origin only on a feet-anchored canvas: measured
  from a pawn's soles, every body pixel sits on one side of the origin, so the ramp would clamp
  flat across the whole figure and stop reading as a direction at all. `RIG_LIGHT_RADIUS` is
  15.0 by measurement, not by eye — the smallest radius that clamps almost nothing of the union
  of the eight rigs' 4254 opaque pixels (0.02%, one pixel) while still spending the whole gain;
  the arc plan's estimate of 18.0 clamps nothing but reaches only 83% of the ramp, contrast a
  41 px figure cannot spare. On a centre-origin canvas `middle` and the origin are the same
  point, which is why every prop, wreck and debris key regenerated pixel-identical across the
  change that added it.
- **Regeneration is pixel-stable.** The wear passes (`Canvas.speckle`) take
  `random.Random(f"{key}:{salt}")` — seeded per key, never the global RNG — so a rebuild of one
  sprite cannot move another, and `--check` stays meaningful. The roll is taken for every canvas
  pixel *before* the eligibility test, the same fixed-draw-count discipline the worldgen passes
  follow: a stream advanced by the shape underneath it moves every speck downstream the day
  somebody widens a panel by a pixel.
- **Hand-authored art is never registry-owned.** Nothing under `godot/assets/sprites/` is
  hand-authored any more — `survivor_mara` and `zombie_shambler` were the last two rigs drawn by
  a person, and the three equip overlays (`item_pack_hiking_equip`, its `_front` half and
  `item_bat_aluminium_equip`) were the last hand art of any kind; the pawn slice replaced all
  five with generated keys, `gear.py` taking the overlays because a 32×32 overlay composited
  into the pawn's 32×48 rect stretches rather than sits. The rule stands for whenever hand-polish
  next replaces something here: a hand-authored file has no key in this package, so *adopting*
  one is a deletion, not an addition — delete the generated key in the same commit as the
  authored PNG, or `--check` and the committed file disagree forever.
- **Every PNG lands in the same slice as its reader.** Nothing mechanical stops a stray generated
  file that no content entry names; the workflow is what stops it.
