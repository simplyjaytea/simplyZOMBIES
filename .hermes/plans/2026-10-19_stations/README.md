# Stations: before and after (2026-10-19)

Alpha plan A11, third family: the well, the latrine and the campfire, drawn in the outpost pack's
manner. Record: docs/23, "Art & renderer — the well, the latrine and the campfire".

| file | what it shows |
| --- | --- |
| `game-camp-{before,after}-1280x720.png` | the camp at noon on day 1 with the fire lit: the fire inside the hall, the latrine north of its wall. Before is the branch without this commit |
| `game-camp-before-after.png` | the two cropped side by side, before on the left |
| `game-well-{before,after}-1280x720.png` | the well south of the hall at noon |
| `game-well-before-after.png` | the two cropped side by side |
| `sheet-stations-before-after-6x.png` | the four pictures at 6×: the generated cold fire, lit fire, well and latrine on top, the drawn ones below |

Captured by a throwaway SceneTree driver that boots the real main scene, sets the clock to noon,
lights the fire's component for the camp frame, stands the player three tiles west of the
framing point, hides the HUD layers and saves the frame; deleted afterwards, as CLAUDE.md asks
of drivers.
