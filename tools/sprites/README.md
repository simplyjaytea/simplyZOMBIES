# tools/sprites — the generators behind the generated art

The PNGs under `godot/assets/sprites/` are the source of record for the **game**: `appearance.gd`
resolves files, and `npm run godot:check:appearance` judges every one of them on the 32×32 canvas
every build. This package is the source of record for the **art** — the reason a colour is that
colour, and the thing that lets a whole batch be regraded without re-drawing it by hand.

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
| `draw.py` | pixel primitives — no PIL drawing, no resampling, no anti-aliasing |
| `parts/characters.py` | one function per body, and the `REGISTRY` naming them |
| `parts/props.py` | the seven district props, each authored to the footprint its content entry declares |
| `parts/wrecks.py` | car segment sets, and the debris scatter |
| `build.py` | the CLI, the registry merge, `--check` |

## The rules the art is held to

- **The canvas is 32×32, anchored on its centre** (`draw.SIZE`, the one copy of the number Python
  holds; `presentation/camera.gd`'s `ART_NATIVE` is the engine's, and the two gates cross-check). `godot/assets/sprites/README.md` is the
  authority; `build.py` refuses anything else before it writes, and `check_appearance.gd` refuses
  it again from the engine side.
- **Muted, always.** Every colour goes through `palette.clamp`: saturation ≤ 0.35, value in
  [0.12, 0.80]. docs/30's reference mood is not a thing to remember, it is a thing the module
  enforces. *(That mood is the overcast one, superseded 2026-09-03 by the warm dark-fantasy
  palette of the Dungeon Settlers look; the palette slice of that arc replaces this one clamp
  with three named families — muted, timber, accent — and re-pins every band from a measured
  table. Until it lands the module enforces the old cap on purpose: a colour that passes here
  today is not evidence about the new mood.)*
- **It has to read against the ground.** A body-forming ramp's mid tone must clear the brightest
  surface tint the district can draw by `GROUND_CONTRAST` in luminance, or importing `palette`
  raises. `SURFACE_TINTS` here is a hard copy of `presentation/palette.gd`'s, because Python
  cannot read GDScript — regrading the ground means editing both **in the same commit**, and a
  stale copy makes the guard lie. Tells drawn *inside* a silhouette (a strap on cloth) are exempt
  and say so in `GROUND_FACING`.
- **Light comes from the top-left**, matching `main.gd::_draw_bevelled_box` — `light_top_left`.
  Two exceptions, each with a reason: the player's rotating rig is shaded radially, because a
  directional bake on a body that spins claims the sun swings round the district when the player
  turns *(this exception retires with the pawn slice of the Dungeon Settlers arc — nothing
  turns, so every rig is lit from the top-left; docs/30, 2026-09-03)*; and a **segment set**
  (a car spanning two or three tiles) keeps only the lateral half of
  the gradient, because a diagonal one restarts at every canvas and bands the finished car
  light-dark-light along its length.
- **Regeneration is pixel-stable.** The wear passes (`Canvas.speckle`) take
  `random.Random(f"{key}:{salt}")` — seeded per key, never the global RNG — so a rebuild of one
  sprite cannot move another, and `--check` stays meaningful. The roll is taken for every canvas
  pixel *before* the eligibility test, the same fixed-draw-count discipline the worldgen passes
  follow: a stream advanced by the shape underneath it moves every speck downstream the day
  somebody widens a panel by a pixel.
- **Hand-authored art is never registry-owned.** The five PNGs that came from a person
  (`survivor_mara`, `zombie_shambler`, the three equip overlays) have no key here. Hand-polish
  later *replaces* generated art by deleting its key in the same commit as the authored file.
- **Every PNG lands in the same slice as its reader.** Nothing mechanical stops a stray generated
  file that no content entry names; the workflow is what stops it.
