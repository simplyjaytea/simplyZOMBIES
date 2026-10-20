# Vehicles: before and after (2026-10-19)

Alpha plan A11, second family: the cars north-south and the five light vehicles, drawn in the
outpost pack's manner and at its scale. Record: docs/23, "Art & renderer — the cars
north-south, and the light vehicles".

| file | what it shows |
| --- | --- |
| `game-before-1280x720.png` | the base (`main` at bf6b41a): every class staged on open street at noon, the generated north-south cars at 2×5 / 2×6 / 2×7 beside the pack's east-west ones |
| `game-after-1280x720.png` | the same staging on this branch: the cars nose-north at 2×3 / 2×4, the drawn light vehicles |
| `game-before-after.png` | the two stacked, before on top |
| `sheet-cars-ns-beside-pack-ew-3x.png` | the six north-south cars (intact, wreck) over the pack's six east-west pictures they were drawn to match |
| `sheet-cars-ns-before-2x.png` | the generated north-south cars they replace (pale and burnt) |
| `sheet-light-{ns,ew}-before-after-3x.png` | the generated pale light vehicles, then the drawn pale, then green and burnt |

Captured by a throwaway SceneTree driver that boots the real main scene, writes the staged
records straight into the manifest (no Low tiles, no entities), hides the HUD layers and saves
the frame; deleted afterwards, as CLAUDE.md asks of drivers.
