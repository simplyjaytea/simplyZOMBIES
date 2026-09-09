# Character fixtures — four sets, for the owner to judge

Authorized by the owner, 2026-09-09 session: *"character model overhaul to make it more like a
2d sprite based rpg with animations"* and *"the paper doll is quite ugly. Thought of replacing
it"*, followed by *"show examples of art first then I will decide"* on the animation, the facing
and the rigs, and **"a new kind of diagram"** on the doll.

This package ships **no game code and no game art**. Nothing under `godot/` or `tools/sprites/`
changed; `npm run sprites:check` is still `SPRITES_OK` at 151 keys, and `git status` was clean
outside this directory before commit. **The pick stays the owner's** — this note says what each
image shows and does not recommend one, the same standing arrangement as
`.hermes/plans/2026-09-01_art-style-fixtures/comparison.md`.

---

## Method

Everything here is a **transform of the shipped art**, never hand-drawn art beside it. Three
mechanisms do all the work, and each was chosen so that what the fixture shows is what a slice
would actually be:

* **The poser** (`poser.py`) reimplements `characters._figure` with a `Pose` beside the parts
  dictionary and monkeypatches it in, so every rig below is the *shipped* rig function, unedited.
  It adds two things the assembler cannot do: per-side legs and feet, and a y/x bias on the canvas
  so the whole upper body — including each rig's own `tells`, `hair` and `face` callables — moves
  together. The sole line never moves in any pose, because `Appearance.FOOT_DROP_PX` ties it to
  the contact shadow and `check_topdown.gd` pins the blit rect exactly.
* **The rig variants** (`rigs.py`) are transforms of the parts dictionary (R1, R3) or rebindings
  of the published skeleton's rows (R2) — the one move the 2026-09-08 squat-pawn slice proved is
  a session rather than a week. R2 also reloads `parts/gear.py`, which *from-imports* those rows
  and would otherwise keep the old copy.
* **The diagram** (`diagram.py`) is a new body model — limbs built from tapered rings rather than
  typed as polygons — with four renderers over it, so the four takes differ in rendering rather
  than in anatomy.

`verify.py` is the assertion the whole round rests on, and it passes:

    POSER_ADDITIVE_OK 8 rigs identical at rest, and a posed frame differs

All eight rigs rendered at `Pose.REST` come back **byte for byte identical** to the PNGs the game
ships, and a posed frame does not. So whichever animation is picked, a body standing still draws
exactly what it draws today, and `sprites:check`, `APPEARANCE_OK`'s size/roster/GREY lanes,
`WORN_LOOK_OK`'s FITS envelope and `TOPDOWN_OK`'s exact blit rect are untouched by the animation
itself.

**Two images are composites and say so**: `diagram/in-the-sheet.png`, `diagram/in-the-corner.png`
and `rigs/on-the-street-2x.png` paint candidates into the committed screenshots from
`2026-09-08_inventory-sheet/` and `2026-09-08_squat-pawn/`, because none of these candidates is
implemented in GDScript yet. The rects are the ones `ui/inventory_panel.gd` and `main.gd` compute.
The one thing a composite cannot show is the contact shadow the renderer draws under a body,
which no candidate here changes.

The modules in this directory are a **prototype, not a build step**: nothing imports them, no
registry names them, no gate runs them. They are here because if a candidate is picked its
implementation starts by promoting the poser into `parts/characters.py`, not by rebuilding it.

---

## Set A — the rigs (`rigs/`)

`roster-4x.png` (all eight rigs, plain), `kitted-5x.png` (pack, clothes, weapon, hat),
`boot-zoom-2x.png` (**the size you actually play at**), `on-the-street-2x.png` (composited onto
the shipped street).

| | What it is | What the images show |
|---|---|---|
| **R0** | As shipped. The control. | Held weapons hang beside the body with a gap; the hands are a pale 4 px blob behind them. The four human rigs share one outline and differ by paint. |
| **R1** | Same proportion, read harder | The hand becomes a fist one pixel further out with a knuckle line, so a weapon has something to sit against. Each human gains a tell that changes the *silhouette* rather than the paint: the player a turned-up collar, Mara's bob tucked behind one ear (asymmetric, so the flip swaps it), Ellis a high collar, the colonist a peaked cap. The face gains a fourth pixel — one mouth pixel below the eyes. |
| **R2** | Taller: 32×48 | Rows only, columns untouched. The figure goes 28 px → 40 px and the head from 46 % of it to about 35 %. Legs long enough to have a gait. It is a **canvas** change, so `PAWN_CANVAS`, the FLIP lane's exact rect, `WORN_LOOK_OK`'s CANVAS lane and all 31 overlays move with it, and `RIG_LIGHT_RADIUS` would want re-measuring. |
| **R3** | R1's shapes, banded shading | `nw_shade` quantised to three steps instead of a continuous ramp. Measured on the player rig: **67 distinct colours → 15**. Same light direction, no gradient. |

The face change in R1 amends `assets/sprites/README.md`'s "a face is three pixels" to four. A
two-pixel mouth read as a moustache at 32 px and a three-pixel band as a grimace; both were drawn
before one pixel was picked.

## Set B — the walk and the idle (`motion/`)

`walk-frames-6x.png` (every frame of every candidate), `walk-6x.gif` and
`walk-2x-boot-zoom.gif` (**all five looping side by side**, at the pace the game would play
them), `walk-on-the-street.gif` (in place on the shipped street — the camera follows the player,
so a walking player walks on the spot).

Frame 0 of every clip is the shipped picture. The lift is **2 px**: the legs are six pixels long,
so one pixel is a sixth and reads as a rounding error at the boot zoom, and three leaves three
pixels of leg with the foot merging into the trunk.

| | What it is | What it costs |
|---|---|---|
| **W0** | Static, as shipped | — |
| **W1** | Two-frame leg swap — the piece docs/23 already names | Legs and feet only. All 31 gear overlays stay valid untouched. |
| **W2** | Four frames, a contact between each pass | Same. The two extra frames are what turn a flicker into a gait: a two-frame swap has no moment with both feet down. |
| **W3** | + the weight shift | The whole upper body leans one pixel over the planted leg. Still nothing that moves a hand, so the overlays still follow for free. |
| **W4** | + the arm swing | **This is where the gear stops being free.** A weapon hangs off `HAND_Y`, so a hand that moves needs its overlay re-rendered per frame: 31 overlays × the frame count. |
| **I1** | The idle breath | One pixel of pelvis at a quarter of the walk's rate. Nothing else moves. |

## Set C — facing (`facing/`)

`views-plain-5x.png` (front, the mirrored west, back, and a side sketch, on five rigs),
`views-kitted-cost-5x.png`.

| | What it is | What it costs |
|---|---|---|
| **F0** | Face-on plus the flip. As shipped. | Nothing. Two apparent directions. |
| **F1** | + a back view | Four apparent directions from two authored views. **A second picture per rig *and* a second picture per gear overlay** — `views-kitted-cost-5x.png` is the same front-authored overlays composited onto a back view, which is what it looks like when they are not re-authored. Reopens the pawn convention a fifth time; docs/30 has refused twice. |
| **F2** | Four views | Four of each. The side view in the sheet is a **sketch only** and is labelled as one: a profile is a re-authoring, not a transform, and a fixture that pretended otherwise would be lying about the cost. |

## Set D — the new diagram (`diagram/`)

`takes-sheet-3x.png` (four takes × four bodies, at the 192 px the inventory sheet draws),
`takes-corner-2x.png` (the always-on corner glimpse), `in-the-sheet.png` and `in-the-corner.png`
(composited into the shipped screenshots).

The four bodies every take is drawn against are: nothing wrong; one arm cut and bleeding; a badly
hurt torso with an infected leg and an armoured head; and an arm gone under armour. The third is
the one that matters — a doll that reads well only when a body is unhurt is a doll nobody has
looked at during play.

All four keep the two rules that are not negotiable. The picture is handed a **state** (0–3) and
a handful of words and booleans and nothing else, so **no part is ever partly filled** — docs/05
prohibits percentages, hit points, segmented pips and any fill level by name. Armour stays a
stroke; a wound and an infection stay marks.

| | What it is |
|---|---|
| **D1** | **Outline, region wash.** Line art with no fill, and colour only where something is wrong. This is docs/30's own stated position — "an unhurt body draws no fill at all", so any colour on the figure is a located condition rather than decoration — drawn as line art for the first time instead of as a filled dummy. |
| **D2** | **The exploded technical chart.** Every part pulled a pixel off its neighbours and drawn as a plate with its own border, the way an exploded assembly drawing separates components. Uniform gaps, so they read as seams rather than as a body coming apart. |
| **D3** | **The silhouette, edge lit.** One dark body; the state carried entirely on each part's rim. The most anonymous a figure can be, which is the clause docs/05 asks for. |
| **D4** | **The part column.** Not a figure: the ten parts as named plates laid out in the shape of a body. "Which part" is answered by a word; the layout is what makes it a body rather than a list. |

The body model D1–D3 share is a person rather than a mannequin: a head about a sixth of the
figure, legs a shade under half of it, and limbs that meet the trunk. The chart being replaced
had a head a quarter of the canvas, legs beginning below its middle, ball hands at the elbows and
detached rectangular feet.

`in-the-corner.png` is the one that shows a thing the isolated sheets do not: over the street,
D1's thin light outline is the faintest of the four and D3's dark silhouette the most solid.

---

## What is not in this round, and why

* **No engine render.** Booting the game with a candidate means writing it over the committed
  PNGs and reverting afterwards (the 2026-09-01 round did exactly that and said so). Every
  candidate here is shown at the exact pixel size the game draws it, and the in-context images
  are composites onto real screenshots, which is the cheaper half of the same trick.
* **No swing, no muzzle flash, no corpse.** docs/23 names those as "a sheet per rig" and as a
  separate piece ("a corpse reads as a corpse"). They are not in the walk question.
* **No recommendation.** See the top of this file.
