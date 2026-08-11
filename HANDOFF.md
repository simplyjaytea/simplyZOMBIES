# Handoff

State of the project for whoever picks it up next — a person or a fresh session. Written 2026-08-05,
updated 2026-08-06 when the noise spine landed, 2026-08-10 when scent did, again the same day when
seven multiplayer-era features were specified into the doc set, again when the visibility
primitive closed the wallhack, again when the ground grew under it, again when the sun started
setting, again when gear arrived and brought a grid to put it in, and again when hot reload closed
the last open box in Milestone 0.

**Read this, then [README.md](README.md), then [TODO.md](TODO.md).**

---

## Where things stand

| | |
|---|---|
| **Phase** | **Milestone 1, phase 4 done: the day.** Shout and the district walks toward you in a minute. Say nothing and it still finds you, in an hour. You cannot see it coming through a wall, where you walk decides how loud you are, and at midnight you can see a quarter as far as you could at noon. |
| **Merged** | [PR #1](https://github.com/simplyjaytea/simplyZOMBIES/pull/1) — the design docs · [PR #2](https://github.com/simplyjaytea/simplyZOMBIES/pull/2) — the attention spike · [PR #3](https://github.com/simplyjaytea/simplyZOMBIES/pull/3) — all of Milestone 0 |
| **In flight** | nothing. Visibility, then the surface layer, then the day/night cycle, then items and the grid inventory |
| **Next real work** | **[Grabs and bite risk](docs/09-combat.md#grabs)** — the swing loop landed and the half that makes melee *cost* something did not, so the parity contract is still open. Then **[the light channel](docs/03-attention.md#light)**: ambient light is built and drives what an observer can see; a torch does not exist, which is why night is softer than the design wants. See [Do this next](#do-this-next). |
| **Also landed, early and on purpose** | **[Items and the grid inventory](docs/10-items.md)** — Milestone 2 work pulled forward at the owner's request. Bases and affixes as content, items as entities, a Tarkov-shaped grid with rotation, nesting and stacking, and the first screen in the game. It neither blocked nor was blocked by the rest of Milestone 1: the whole thing is two new modules plus content, and the one place it touches combat goes through the event bus. |
| **Also landed, as design only** | **[Multiplayer](docs/27-multiplayer.md)** — authoritative host, survivor-vs-survivor PVP, and voice as a noise emitter. Specified, docs reconciled, **no engine code**. Filed as Milestone 3. |
| **And, also design only** | **[Visibility](docs/28-visibility-and-sightlines.md)** and **[movement stances](docs/29-movement-and-stances.md)**, plus the [condition view](docs/05-health-injury.md#the-condition-view), [aiming](docs/09-combat.md#aiming), and [z-levels deferred in writing](docs/23-roadmap.md#deferred-z-levels). Again **no engine code** — two of these are now Milestone 1 tasks. |

## The build

`.github/workflows/pages.yml` publishes `dist/` to GitHub Pages on every green CI run on `main`.

> ⚠ **One manual step is still outstanding:** Settings → Pages → Source: **GitHub Actions**. Until
> someone with repo admin does that, the workflow runs and the deploy step fails. Nothing in CI
> depends on it.

The build is worth playing now, which is the whole reason it exists. What it cannot answer is in
[Open questions](#open-questions-nobody-has-answered), and the first one needs a human at a keyboard.

## What's in the repo

```
docs/           29 design documents. The README index is the reading-order authority,
                not the file numbers — 24-26 belong under "The world", 28 sits beside the
                spine it serves, and 29 beside combat.
TODO.md         The backlog through Milestone 2, with all 8 roadmap risks pinned to the
                task that answers each one. Milestone 0 and the noise spine are ticked.
src/sim/        The simulation. Pure, headless, deterministic — kernel, modules, rng.
src/sim/field/  The attention field. Kernel, not a module (see below).
src/sim/vision/ Sightlines: the shadowcast, and every observer's cached view. Also kernel.
src/sim/locomotion.ts
                How fast things move. One PACE multiplier; every speed is a ratio of it.
src/sim/time/   The clock. Time of day is a pure function of world.tick -- no clock state.
src/sim/threat.ts
                "Is anything close?" -- the rule the speed control drops 10x on.
src/render/     Canvas renderer. Reads the sim, never writes to it.
src/render/sprites/
                The character models. Pure pose selection and figure geometry, split from
                the one file that touches a canvas -- Vitest runs in node.
src/platform/   The host: input, the tick loop, storage, content loading, schemas.
content/        JSON content plus its JSON Schemas.
test/           Unit and integration, including determinism and module isolation.
bench/          The performance budgets. They fail the build.
```

The spike is **gone** — deleted in the same change that ported its findings onto the real kernel,
exactly as the previous handoff said it could be. `docs/23-roadmap.md` keeps the evidence.

## Running it

```bash
npm install
npm run dev              # the game at http://127.0.0.1:5174
npm test                 # correctness: 464 tests (~70 s -- the scent ones simulate hours)
npm run typecheck        # two projects — see the sim/ purity gate below
npm run lint
npm run bench            # tick budgets
npm run bench:frame      # frame budget, drives real Chromium
```

In the browser: `WASD` move · `Shift` sprint · **`F` swing** · **`Space` shout** · **`O` cycles the attention overlay
(off → noise → scent → sight)** · **`1`/`2`/`3` speed (1×, 3×, 10×)** · `P` pause · `F5` save ·
`F9` load.

The HUD's `ground` line is the newest thing on screen: what you are standing on, and what it is doing
to your speed and your footsteps. Walk from a street onto a lawn and watch it go from `1.00x noise`
to `0.60x`.

**Press space.** 4,055 of the district's 4,096 field cells go live, 298 of 300 shamblers switch to
seeking, and over the next minute the crowd within 50 m goes from about 30 bodies to about 90. Then
it fades and they drift off again.

**The view is isometric now**, and walls stand up in it. `docs/00-vision.md` used to leave
Project Zomboid's "3D isometric fidelity" out of scope and now takes the projection while still
refusing the fidelity — the expensive half of PZ's view is z-levels, which
[docs/23 still defers](docs/23-roadmap.md#deferred-z-levels), and a wall here has a height
because it is drawn rather than because anything can be above or below it. The reversal is
written down in the doc itself. `W` is up the screen, not world north: the movement table in
`platform/input.ts` is rotated 45°, and `sim/` still has no idea a camera exists.

**Then walk up to one and press `F`.** There is a beat before the blow lands and a longer one
after, and during the second you are committed — the wedge on the ground is the swing, filling
as it winds up and draining as you recover. Swing at nothing and the recovery is the same
length, which is the lesson. Swing into three of them and you kill one at a time while the
other two close, because the arc covers one of them and the others are outside it. Watch the
noise overlay while you do it: a connect lights a handful of cells against a shout's 4,055, and
that is the whole reward of the melee branch. Break a shambler's legs and it keeps coming at a
quarter speed, drawn half size, which is exactly as easy to lose track of as docs/14 wants.

**Then press nothing at all, and wait.** That is the other half, and it is new. Stand perfectly
still — the noise field sits at literally zero live cells, exactly as before — and the crowd within
50 m still climbs from 30 to 76 over an hour, on nothing but the scent a body cannot stop emitting.
Being quiet is no longer *safe*; it is *slow*, which is a much better answer to the question this
document has been asking since the noise spine.

**And press `O` twice** to put the scent overlay up, then watch a horde you disturbed walk off
downwind following its own smell. That one was not designed; see [what scent
changed](#what-scent-changed-and-what-it-corrected).

**Then look at what you can no longer see.** The HUD's `sight` line counts the bodies inside the
viewport that the survivor has no sightline to; in a 2,000-body district it reads about **205 hidden
against 11 drawn**. Every one of those 205 used to be on screen. Walk into a building and the street
disappears; stand in the doorway and it comes back through the gap. **Press `O` a third time** for
the sight overlay, which draws the visible set itself — the wedge fanning out of a doorway and
stopping dead at the next building is the primitive working. Bodies you lose behind a wall leave a
mark that fades over three seconds and **does not follow them**, which is the difference between
remembering and being told.

Note the second number on that line: `shadowcasts`. It goes up when you cross a tile boundary and
sits still when you turn, which is the whole cost argument in one counter.

**Then press `3` and wait for dark.** A day is four hours at 1×, so the speed controls are how you
see one at all — at 10× a full day is 24 minutes and the night is six. The `time` line shows the day,
the hour, the phase and the light; watch `light` fall from 1.00 through dusk and the `sight` line's
hidden count climb as your view closes from 48 m to 12. A body ten metres away in daylight is a body
you can no longer see at midnight, and that is the mechanic rather than the tint. Walk into anything
at 10× and the speed drops to 1× on its own.

The HUD shows live cells and peak for **both channels**, the horde's state counts, and a **state
fingerprint** — that string is what the determinism test compares.

**And to change a number**, edit any file under `content/` while `npm run dev` is running. A valid
edit reloads the page on the same seed, so the fingerprint on the HUD is directly comparable before
and after — that is the whole loop, and [what it made
structural](#what-hot-reload-made-structural) explains why it restarts rather than hot-swaps. An
invalid edit does *not* reload: the run keeps going and the HUD grows a `content:` line naming the
file, the entry and the field.

If Playwright can't find a browser, point it at one: `CHROMIUM_PATH=/path/to/chromium npm run
bench:frame`. In a fresh container the provisioned one is usually at
`/opt/pw-browsers/chromium-*/chrome-linux/chrome`.

## Settled decisions: do not relitigate

These were each decided explicitly by the repo owner. If you're about to "improve" one, don't:

- **Hardcore is the thesis, not a difficulty slider.** Permadeath with succession into another
  survivor; no win condition plus an optional expensive escape.
- **No wave timer.** Horde pacing is attention-driven and director-paced.
- **Blank slates, no classes.** The build lives in found gear (PoE-shaped affixes) plus a classless
  skill web earned by doing. Applies to every survivor, not just the player.
- **Survivors are unlimited and procedurally generated.** Recruits arrive as unskilled nobodies — that
  is the counterweight that keeps permadeath meaningful.
- **Melee and ranged both good**, spending non-convertible currencies (body/bite-risk vs.
  ammo/attention).
- **Fully drivable continuous region**, no abstracted travel legs. **Full nomad play viable.**
- **Performance is pillar 6**, with CI budget gates that fail the build.
- **Stack:** TypeScript + canvas + Vite, no engine, with a portability contract keeping a Godot pivot
  cheap. **Saves may break pre-1.0** — stable IDs and a version stamp, but no migration framework.
- **The inventory is a grid, and weight is invisible.** Tarkov/DayZ-shaped: cells, footprints,
  rotation, nesting, and containers you have to wear to get. This *replaced* the weight-and-capacity
  model `docs/10-items.md` originally specified, and the argument is not genre nostalgia — a capacity
  bar is a number about your capacity, which
  [clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) prohibits outright,
  and a grid is the same information as shape. Weight is still simulated and still never printed:
  you find out you are overloaded by walking slower. **There is no kilogram on the inventory screen**
  and adding one is a contract violation, not a UX improvement.
- **Vehicles were un-cut** after initially being cut at the vision level. `docs/00-vision.md` records
  the reversal and why the original objection was half right.
- **A district is 256 m, falloff stays linear.** Decided against re-authoring the magnitude table,
  because its ratios are load-bearing in six documents and only the unit was ever missing.
- **Field memory is scent, never noise.** Kept rather than cut, on the condition that Milestone 1
  proved it did something. **It did** — though not the something that was written down. See
  [what scent changed](#what-scent-changed-and-what-it-corrected).

## What the spike settled

The three findings are **folded into the documents that specify the systems**. Don't redo this; the
docs are the authority now and [`docs/23-roadmap.md`](docs/23-roadmap.md#spike-findings-attention-field)
keeps the evidence.

| Finding | What was decided | Now specified in |
|---|---|---|
| Gradient ascent alone makes **conga lines**, not a horde | Persistent per-individual angular bias (±0.62 rad), from the seeded RNG, in save state. No neighbour queries, no measurable cost. | [`docs/14`](docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own) |
| **Noise magnitudes aren't calibrated to district size** | The magnitudes were never wrong — the **unit** was never defined. 1 tile = 1 m, 0.7 attenuation per metre, 4 m field cells, **256 m district**, so one gunshot = one district. **Zero magnitudes changed.** | [`docs/03`](docs/03-attention.md#scale-and-calibration), [`docs/24`](docs/24-world-and-scale.md#how-big-a-district-is) |
| **Field memory is a no-op** | The spike tested it on the wrong channel. It's a **scent** mechanic in both specifying docs; residue-as-noise dies inside its own cell by arithmetic. Kept, on scent, with a Milestone 1 acceptance check that cuts it if nothing observable changes. | [`docs/03`](docs/03-attention.md#field-memory-is-a-scent-mechanic) |
| **Rendering dominates simulation** (~30×) | Draw budget and sim-share-of-frame budget added; every benchmark asserts frame time, not just tick time. | [`docs/22`](docs/22-performance.md#aim-the-budgets-at-the-renderer) |

Also worth keeping: **event-driven noise propagation is vindicated** — 6 live field cells when quiet.

## What Milestone 0 built, and the rules it made structural

The exit criterion is met and asserted (`test/integration/exit-criterion.test.ts`), and the milestone
now has **no open boxes** — hot reload was the last one, and closing it is written up
[below](#what-hot-reload-made-structural). More useful to a newcomer than the file list is *which
invariants are now enforced rather than merely intended*, because these are the ones you will trip
over:

- **`sim/` cannot touch the host.** Lint bans `Math.random`, `Date.now` and browser globals; on top of
  that `tsconfig.sim.json` compiles `sim/` with **no DOM lib**, so any DOM access is a type error, not
  a review comment. `step(world)` takes no time argument — the sim can't read a clock because it is
  never given one.
- **Iteration order is never left to chance.** Component queries sort by entity id, systems sort by
  `(phase, order, id)`, event handlers by `(order, id)`, modifiers fold by `(source, seq)`. Every one
  of those is guarding the same failure: registration order is module import order, and bundlers
  reorder that. Two of them are proven by mutation tests that fail when the sort is removed.
- **Content fails loudly at load.** Unknown stat, unimplemented behaviour tag, circular `extends`,
  duplicate id — all rejected before the first tick, all naming file, entry and field, and nothing is
  published unless everything validated.
- **Budgets fail the build.** `npm run bench` for tick, `npm run bench:frame` for draw. The frame one
  drives real Chromium, because frame time cannot be measured in node.
- **Any module can be switched off.** Checked in CI for each module individually and all at once.
  This is also how sandbox presets and storyteller settings get implemented later — not as special
  cases, as this.

## What hot reload made structural

The last Milestone 0 box, and reviewing it found something worse than an unfinished task: the handler
already existed, said **"content reloaded"**, and changed nothing. It rebuilt the registry and
assigned it to a module-local variable, while the world held the one it was handed at boot —
`World.content` is `readonly`, so the republish landed in an object nothing referenced. A lie in a
balancing tool is worse than a gap in one, because the gap does not get trusted.

- **Reload means re-run the seed, not swap content under a live world.** docs/20's loop is "tweak a
  JSON value, **reload**, re-run the seed, compare outcomes", and the emphasis is load-bearing. Most
  of content is read through the registry on demand — `ItemBase` stores an id and nothing else — but
  four things capture it: affix modifiers folded into the modifier store at spawn, the `MeleeWeapon`
  snapshot written on equip, container grids sized from their base, and the attention field's
  calibration, derived into `private readonly` scalars in the constructor and not swappable at all.
  A live swap refreshes some of those and not others, which is a world disagreeing with its own
  content. Re-running the seed refreshes all of them by construction.
- **The edit is validated into a registry that is then thrown away.** The probe is the whole trick: a
  typo must not take the run down and come back as a blank page with the message in a console nobody
  is reading. Valid, and the page reloads; invalid, and the run keeps going with `content: …` on the
  HUD naming file, entry and field.
- **Content values must not reach the save, and now that is asserted rather than assumed.** Editing
  `massKg` and re-booting the same seed produces a **byte-identical** world that nonetheless disagrees
  about what the survivor is carrying. That is the property that makes the fingerprint a fair basis
  for a before/after comparison, and it is also why the divergence control in the same test has to
  edit the *affix pool* instead — only content the roller reads at spawn moves the state.
- **An unresolved content id is loud, at the two moments content and world can disagree.** It used to
  degrade in silence: `itemBaseOf` returned `undefined` both for "not an item" and for "its base is
  gone", so a renamed base produced a district of nameless 1×1 objects weighing nothing. Those two
  facts are now separate, and the readers throw. The *check* is deliberately not in the readers
  though — they are called from the HUD and the renderer, so discovering it there means throwing once
  per frame. `verifyContentReferences(world)` runs at boot and after a save is applied, reports every
  problem in one message the way a bad content load does, and passes trivially on a world with no
  items.
- **A save can be stale in a way the version stamp cannot see.** Saves record ids and never content,
  and editing JSON does not change the build — so `SAVE_VERSION` will never catch a save taken
  against a different content set. The id check is what covers it, and it runs inside the existing
  catch so the failure is a notice rather than a crash.

## What the ground made structural

Four decisions, and one of them is a correction to something this document said two sections down:

- **A surface is a second array, never more values in the tile enum.** A tree stands on grass and
  rubble lies on tarmac, so one enum would have to enumerate a product of two sets. This is doc 28's
  opacity-is-not-solidity lesson arriving one layer down, and it arrived on its own — the surface
  layer was written before anyone noticed it was the same shape.
- **Terrain multiplies the emitter; it never replaces it.** Sprinting is six times a walk on every
  surface in the game, because `walking: 1` and `sprinting: 6` are calibrated against the field and
  the ground is a modifier on top. There is a guard on that ratio specifically. The alternative —
  terrain *setting* a magnitude — would have quietly retired docs/03's table.
- **`indoors` is written at generation time, because it stops being answerable afterwards.**
  Buildings have doorways, so a flood fill from the map edge walks into every interior, and
  "enclosed on all four sides" is true of the whole district once you count the perimeter wall. The
  first version of that guard used exactly that heuristic and measured nothing. The generator knows
  its own footprints; it writes them down. Weather and the light channel are the next two consumers.
- **One `PACE` multiplier, and every speed is a ratio of it.** The 1.4 m/s walk used to be a literal
  in `player.ts` and a comment's worth of arithmetic in `shambler.ts`, and the sprint threshold was
  the hardcoded midpoint of two numbers it could not see. A ratio spread across three files is a
  ratio that drifts, and this one drifted the moment the pace changed.

## What the day made structural

- **Time of day is a pure function of `world.tick`.** No clock state, nothing new in the save,
  nothing that can disagree with the world it was taken in. Starting at dusk is starting at a
  different tick. **The price is that `world.tick` is no longer "ticks since the run began"** — two
  tests were quietly measuring the wrong interval within minutes of this landing, because both did
  arithmetic against an absolute tick. Anything wanting elapsed time subtracts a start tick now.
- **A run opens at 09:00.** Tick 0 is the start of dawn, which is the darkest moment of the cycle.
- **The phase publisher is stateless.** It compares the phase at this tick with the phase at the
  previous one rather than remembering what it announced. A remembered phase is either save state
  that can disagree with the tick, or a re-announcement of a transition that already happened.
- **Night is a smaller view, not a darker screen.** Range is a property of light, so ambient scales
  it; the wash over the canvas is derived from the same number so the two cannot drift. Two
  mechanisms for one fact would disagree at the edges, and the one that decides is the simulation's.
- **`TICK_HZ` moved to a leaf module.** The clock needs it and the clock cannot import `world.ts`,
  which imports the visibility index, which imports the clock. On the far side of that cycle the
  constant is `undefined` at module-init time, so `DAY_SECONDS * TICK_HZ` evaluated to `NaN` and
  every save in the suite failed on a canonicalizer correctly refusing to serialize one.
- **The speed control scales the accumulator, never the timestep.** A variable timestep would put
  the speed setting into the replay record.

## What sight made structural

Five decisions that are cheap now and expensive later:

- **Opacity and solidity are two properties, never one enum.** A window stops a body and not a
  sightline; a curtain stops a sightline and not a body. docs/28 calls conflating them "the single
  most likely way to get this wrong", and the guard is not a comment — `blocksSight` and `isSolid`
  read different tables, and defining one as the other turns three tests red.
- **The primitive is kernel, and it has exactly one implementation.** `world.vision` exists in a
  world booted with every module off, for the same reason field decay does: a module that can be
  switched off must not be what decides whether the game draws through walls. The renderer asks it
  rather than running a cheaper check of its own, because the place two line-of-sight checks
  disagree is the place the exploit lives.
- **Geometry is cached, arcs are not.** The shadowcast is keyed on the observer's *tile*; the focal
  and peripheral cones are a dot product evaluated per query. So turning on the spot is free and
  crossing a tile boundary is not, which is the opposite of what the arcs suggest and the reason
  the cost holds at all. Fold facing into that key and the budget scenario still passes — only the
  "turning is free" guard catches it.
- **The visible set is derived, and stays out of the save.** It is a pure function of positions,
  facings and the map, all three of which the snapshot already holds. Storing it would be a second
  copy of a fact and a way for a save to disagree with itself.
- **The occluder pass runs on its own RNG stream, after the layout.** Windows, foliage and low cover
  are dressed onto a finished district rather than rolled with it, so the layout a seed produces is
  byte-identical to the one every existing calibration was measured against. Drawing from the layout
  stream would have moved every building — a change that only meant to add windows, quietly
  relocating the district out from under the noise and scent numbers.

## What scent made structural

Five more decisions that are cheap now and expensive later:

- **Field memory is its own module**, not a branch inside the shambler. That is what makes the
  acceptance check honest: `boot({ disabled: ["field-memory"] })` is a shipped configuration a
  sandbox preset could use, so the check toggles the real game rather than editing the code under
  test. The isolation test picked it up for free.
- **Scent reaches the field through `scent.accumulated`**, exactly as noise reaches it through
  `noise.emitted`. The event already existed in the vocabulary with no publisher. A corpse, a
  latrine or a smokehouse needs no knowledge that the field exists.
- **Diffusion is a gather, not a scatter.** Each cell pulls from its neighbours instead of pushing.
  Same physics, but a scatter accumulates into a cell in whatever order the loop arrives, and float
  addition is not associative — so determinism would have depended on iteration order. Gathering
  makes it fall out of the loop's shape with no sorting at all.
- **Wind lives in four normalised outflow weights derived once**, so the diffusion loop does not know
  which way the wind blows. When [weather](docs/16-weather.md) takes wind over in Milestone 3 it
  changes those four numbers and nothing else — and wind becomes save state at that point, which it
  deliberately is not now.
- **`liveCells()` and `peakNoise()` stayed noise-only.** Three assertions in the exit criterion read
  `liveCells() === 0` as "the district is silent", and folding in a channel that decays over hours
  would have broken the noise criterion for no reason. Scent got sibling methods instead.

## What the noise spine made structural

Four decisions that are cheap now and expensive to reverse later:

- **The field is kernel, not a module.** `docs/19` draws the line at "the tick loop, the entity store,
  the event bus, and the attention field", and so does the code: `world.field` exists in every world,
  including one booted with every module off. Decay and the `noise.emitted` subscription are also
  kernel — a module that can be switched off must not be what stops noise from fading.
- **Nothing writes to the field directly.** Emission is a published fact (`noise.emitted`) and the
  kernel is the only subscriber. A trap, a generator or a vehicle engine reaches the field by the same
  route as a footstep, and needs no knowledge that the field exists.
- **Input is drained once per tick, by the kernel.** It used to be the first system's job, which
  quietly made input single-consumer — the second module to ask got an empty list. The determinism
  test's negative control is what caught it.
- **The field is in the save, sparsely.** Live cells only. Watch for `-0`: `canonicalize` rejects it
  outright and a decaying float will reach it, so anything under the floor snaps to a hard zero.

## What Milestone 1 has found so far

- **Gradient ascent alone stops too early.** Noise decays with a 3 s half-life; the far half of a
  district is a minute's walk. Shamblers now carry a 20 s **travel commitment** — they keep their
  bearing after the gradient dies. Without it they forget mid-street, which reads as the field being
  broken rather than as noise fading. docs/03 already asked for this: *"the horde it already summoned
  is still walking."*
- **Decay shrinks loudness, not radius** — and this contradicted docs/03's prose, so
  [the doc was corrected](docs/03-attention.md#scale-and-calibration). Multiplying the stored field
  leaves its shape untouched: five half-lives after a shout every cell is 1/32 of what it was and the
  edge has barely moved. The resulting behaviour is the one the design wants, but by a different
  mechanism than "inaudible in 15 seconds" implies.
- **Converging is not a different cost class from drifting**, which is the property the new budgets
  guard. 0.19 ms against 0.15 at 300 bodies; 1.38 against 1.04 at 2,000.
- **One shout wakes essentially the whole district.** 4,055 of 4,096 cells. That is what the
  calibration says should happen — a shout carries 171 m across a 256 m district — but nobody had
  seen the consequence before now. Whether it makes shouting the only interesting verb is a
  playtest question, not an arithmetic one.

## What the day changed

**The dark is the first thing in this project that takes something away from the player.** Noise,
scent and terrain all *added* a channel to read. Night removes one: at midnight the survivor sees
12 m, and the HUD's hidden count goes up accordingly. It is also, right now, a mechanic with no
counterplay — there is no torch, no lamp, no shuttered window to be on the right side of, because
those are all the light channel. **That is why `NIGHT_AMBIENT` is 0.25 rather than something
genuinely dark, and it should go down the day emitters land.**

**The clock cost a circular import and two silently-wrong tests, and both were the same mistake.**
The import cycle made `DAY_TICKS` `NaN`; the tests assumed `world.tick` counts from zero. Both come
from time of day being derived from the tick — which is still the right call, because it means a
save cannot disagree with the world it was taken in, but it is not free and the cost is worth
knowing before somebody derives the next thing from the tick too.

**Four hours a day is still a guess, and now it is a guess you can feel.** At 1× a development
session never reaches nightfall, which is why the speed controls stopped being a convenience and
became a prerequisite. Whether four hours is *right* is still unanswered — but it is one constant,
and now there is a way to sit through one and find out.

## What the ground changed

**The speeds moved, and docs/29 said they would not.** That document stated in as many words that
walk and sprint "are shipped and do not move", at the real-world 1.4 and 4.2 m/s. The repo owner
asked for faster, on game feel — at 1.4 a district is a three-and-a-half minute crossing and it
plays slowly — so they are 2.1 and 6.3, and
[docs/29 records the reversal](docs/29-movement-and-stances.md#the-five-stances) rather than being
quietly reworded. What the multiplier protects is the *reason* that sentence existed: every ratio it
was defending is untouched, because everything scales together.

**The sprint threshold was the first thing to break, and it broke silently.** It was `2.8` — the
midpoint of 1.4 and 4.2 — and at a walking speed of 2.1 it is still between the two, so nothing
failed and nothing looked wrong. At a pace multiplier of 2.0 a *walking* survivor would have emitted
the sprinting magnitude. It is derived now, with a guard.

**Terrain is a bigger deal for stealth than for pathing.** The speed spread is deliberately narrow —
a district crossing goes from 122 s on pavement to 135 s over grass — but the noise spread is not:
the same walk carries 1.4 m on tarmac, 0.9 m on grass, and 2.4 m across rubble. Undergrowth is the
only cover on open ground and it is *both* the slowest surface and a loud one, so you can be unseen
or unheard and not both. That asymmetry is the whole mechanic, and it is the first thing to play
before tuning either table.

**Worth knowing before anyone raises `PACE` again:** noise is emitted per tick, not per metre. Going
faster does not make you louder, it shortens every exposure, so a large pace increase makes stealth
*easier*. At 1.5 the effect is small. At 3 it would be a balance change wearing the costume of a
game-feel one.

## What sight changed, and the guard it caught

**The wallhack was bigger than it read on paper.** "The renderer draws every entity in the viewport"
is one sentence; the number is 216 bodies in the viewport of which the survivor can actually see 11.
Ninety-five percent of what the game was showing was information the player was not entitled to.
That is worth knowing before playtesting anything about tension, because every previous session's
sense of how the horde "reads" was formed against a district with no walls in it.

**Turning is free and walking is not.** The intuitive model is that the arcs are the expensive part
— they are what changes when you look around. The opposite is true, and only because of how the
cache is keyed: the shadowcast is per *tile* and the arcs are a dot product per query. An observer
spinning on the spot costs nothing at all. This is also the mutation that a lazy version of this
work would fail silently — folding facing into the cache key passes the benchmark, passes every
correctness test, and quietly makes looking around cost a shadowcast a tick.

**The cost was never the shadowcast.** One 12 m cast is 0.07 ms and a 48 m one is 0.18 ms, which at
20 Hz per observer per tick would be ruinous. Measured over 600 ticks with 51 observers: **690
casts**, a little over one per tick, because a drifting body crosses a tile about every two seconds.
`crowded-and-watched` lands at 1.34 ms against `crowded`'s 1.32 — inside the noise. **The budget is
guarding the cache, not the algorithm**, and the case still unmeasured is observers that *sprint*,
which pay every three ticks rather than every forty.

**A guard that looked rigorous tested nothing — the fourth one so far.** The renderer-occlusion test
counted bodies in range that the survivor could not see, and it passed with the sightline check
deleted outright: the arcs alone hide everything behind you, so "some bodies in range are hidden"
was true for a reason that had nothing to do with walls. Fixed by counting only bodies *inside the
arcs*, which leaves occlusion as the only thing that can hide one, and backed by a two-tile case
where a body is dead ahead behind a single wall. The pattern is now unmistakable, and it is always
the same shape: **the guard passed because something else in the system produces the same
observable.**

**Something the frame benchmark lost.** Occlusion took the entities it measures from 216 to 11, so
it now guards drawing 95% less than it did. This is the second mitigation to weaken it — viewport
culling was the first — and it is [recorded in docs/22](docs/22-performance.md#the-ci-benchmark-suite)
rather than quietly accepted. Anyone tightening that budget should raise the entity count first.

## What scent changed, and what it corrected

Four things came out of this build that are worth more than the checkbox.

**Field memory works, and does the opposite of what the doc said.** The acceptance check passed
decisively — but not by making a mill site sticky. Residue makes the **horde migrate**: it lays
scent, the plume drifts downwind, it climbs into its own plume, and repeats, crossing most of a
district in an hour. With residue off it stays within 7 m of where it gathered. So the site it
gathered at actually *empties faster* — 37 bodies within 50 m at twenty minutes, against 73 with the
mechanic off. It is self-limiting: the crowd spreads along the district edge, the residue burns out,
they disperse. This is better than what was specified — the horde now has a location and a heading
between events, and wind became tactical before the weather system exists — but
[docs/03 was wrong and is corrected](docs/03-attention.md#what-field-memory-turned-out-to-actually-do)
rather than quietly reworded.

**Scent needed a floor of its own, and sharing noise's silently broke it.** The noise floor sits near
zero so `reach = magnitude ÷ attenuation` holds exactly — an identity a diffusive channel does not
have. Sharing it made the *floor*, not the half-life, govern how long a smell lasted: diffusion
dilutes a plume until every cell crosses the threshold at about the same moment, so a deposit
evaporated in ~2 minutes while the calibration claimed 90. This was invisible in the arithmetic and
only showed up when the lifetime was measured. There is a guard on it now.

**Risk 5 is closed, and it was never the cost.** Continuous diffusion is 0.0377 ms per step, 0.0075 ms
amortised per tick — a tenth of a percent of the budget — and it is the *same* cost whether the
district is saturated with scent or completely fresh, because the step scans the grid rather than the
live cells. The roadmap has feared this since it was written. What actually scales with the horde is
per-entity AI, which noise already paid for. **The hard part of scent was calibration, not
performance**, and that is the useful thing to carry into light.

**A guard that looked rigorous tested nothing — the third one so far.** The scent lifetime test passed
with the decay term deleted outright, because a plume still evaporates by dilution. Decay only
accounts for about a quarter of the loss, so the 90-minute half-life was entirely untested behind it.
Fixed by measuring decay in isolation, with the diffusion rate set to zero. **Covering the behaviour
is not covering the constant that produces it.**

## What the models made structural

Four things, and one correction to a prediction this document made.

- **The projection owns how tall a metre is, not the renderer.** `RISE_SCALE` was a renderer
  constant while walls were the only thing with a height. A body standing in front of a wall has to
  rise at the same rate or it reads as the wrong size for the district, which is the projection's
  own argument -- one answer, because the place two pieces of code disagree is the place the bug
  lives -- arriving one layer down.
- **The depth tie is the renderer's to break, not the projection's.** `depthOf` still ties for
  anything on the same diagonal and its test still says so, because that genuinely *is* the ordinary
  isometric ambiguity. Flat squares never showed it; standing bodies do. So the comparator resolves
  it -- occluder, body, player, entity id -- and the player sorting last on a tie is a fairness
  property rather than a cosmetic one: a shambler at identical depth must never hide you.
- **A ground decal cannot live in the depth pass.** The swing wedge was drawn inside the player's
  own slot, which was correct while a body was a mark on a tile and wrong the moment bodies stood
  up: a mark on the floor was painting over the legs of anyone further along the diagonal. Anything
  that is *on* the ground now draws before anything that stands on it.
- **Peripheral vision constrains the art, not just the query.** docs/28 says the arc notices
  movement and withholds identity, and the renderer already enforced that by refusing to draw a
  still body. A real model gives the identity straight back by silhouette -- you would read the
  stoop and know it was a shambler. So glimpses and memory marks share one anonymous shape with no
  posture, no limbs and **no facing**, because a body that turns tells you which way it is looking
  and the arc did not earn that either.

**A prediction that turned out wrong, which is worth more than one that didn't.** The habit section
below recorded that the frame budget passes with viewport culling removed "because 2,000 flat
rectangles are cheap", and that it would bite once sprites replaced them. Sprites have replaced them
and it did not bite: 2.26 ms with the cull deleted against 1.89 ms with it, both inside the 4 ms
budget. The reason is that *visibility* rejects 1,986 of 2,001 bodies before anything is drawn, so
the viewport cull is removing work occlusion would remove a few lines later anyway. Two guards
overlapping almost completely, and the one that looked like it was carrying the budget was not.

**Reviewing generated art needs a tool, and the tool finds things.** 336 sprites cannot be checked
by walking around hoping to meet each one -- the crawl frames need a shambler with destroyed legs
standing in front of you. `M` blits the raw sheets, and it immediately showed the shambler's stoop
carrying its head a full body-width past its hips: not a shamble, a head that had come off. The
containment test caught three more before that -- a crawler whose wider shadow overflowed a box
sized from the standing one, and a wind-up that out-reached its headroom. **A recording sink is the
whole reason those were catchable in node.**

## Do this next

**[Grabs and bite risk](docs/09-combat.md#grabs), or [the light channel](docs/03-attention.md#light) —
whichever you have appetite for.** Both were the next work before items jumped the queue, and neither
moved while items landed.

Two things the item system left deliberately unfinished, if you would rather continue that thread:

- **Nothing wears out.** `Condition` is on every item, `conditionFactor` reads it, and damage and
  swing speed both already scale with it — but no system ever *lowers* it. Wear is driven by use, so
  it wants to be a subscriber to `attack.connected` rather than a system of its own, which is a small
  change in `modules/items.ts` and no change anywhere else. `item.broke` is declared and unpublished.
- **Attachments are content with no reader.** Bases declare their slots (`head`, `haft`, `wrap` and
  so on) and nothing looks at them. The design wants attachments to move freely between compatible
  bases, which is the mechanic that lets a build survive an upgrade; the grid already knows how to
  hold them.

**[The light channel](docs/03-attention.md#light) — the emitters.** It has been the open Milestone 1
task since the noise spine, it was blocked on an algorithm, the algorithm exists, and now the
*ambient* half is built and pointing straight at the hole where the rest goes.

**Start by turning the night down.** `NIGHT_AMBIENT` is 0.25 because a survivor at zero would be
blind with nothing to do about it. A torch changes that, and the number should follow it down in the
same change — otherwise the channel lands and the dark it was built for is still soft.

- Light *is* a shadowcast from the emitter with the emitter's magnitude as its range —
  `shadowcast()` takes exactly those arguments. The emitter table does not change and nothing about
  the field's structure changes.
- The [sensory profile's](docs/14-zombies.md#sensory-profiles) Light column goes live with it. A
  screamer weights light 0.9 against a shambler's 0.1, so this is where "there is no single silence"
  stops being a slogan.
- **Give zombies eyes in the same change, not before it.** `SHAMBLER_EYES` and
  `boot({ observers })` exist and the cost is measured, but nothing hands a zombie an `Observer`
  yet, deliberately: docs/14's first design rule is that sight must not make them tactical, and
  landing sight and its one stimulus together is the safe way to honour that.
- `Observer.rangeMetres` is a daylight constant *because there is no light to derive it from*. When
  the channel lands it becomes a lookup, and that is the only field that changes.
- One consequence to plan for: light is the only channel where a wall is an absolute rather than a
  penalty. Noise pays 18 m-equivalent to cross one and scent ignores walls entirely. That asymmetry
  is the counterplay — shutters work, and they work completely.

The **melee loop landed** — wind-up, connect or miss, recovery, stamina, stagger, reach, the
zombie damage model, and the spatial index it was waiting on. What did *not* land is
**[grabs and bite risk](docs/09-combat.md#grabs)**, and that is the more urgent of the two
tasks above: with no bite risk, melee's only cost is stamina, so
[the parity contract](docs/09-combat.md#the-parity-contract) — the thing docs/09 exists to
enforce — is not satisfied. Melee is currently strictly cheap, which is precisely the failure
mode that document opens by naming.

Grabs need a survivor who can be injured and infected, which means an injury model and the
infection module. The seam is already there: `entity.staggered` interrupts a wind-up today,
and nothing can stagger a survivor yet.
[Movement stances](docs/29-movement-and-stances.md) are the other near neighbour: `Stamina`
now exists in its designed home and the ladder is where walking-1 and sprinting-6 become a
decision rather than a shift key. It is also what docs/09's "exhausted swings are slow, weak,
and miss" is waiting on — the swing refuses outright when it cannot be paid for, because
scaling the windows needs the modifier pipeline. **The `Low` occluder class and the
`Eye.Crouched` parameter are already in the map and the primitive** waiting for stances too —
cover that hides you also blinds you, and both halves are one line each away.

**Not multiplayer.** [Doc 27](docs/27-multiplayer.md) landed as a specification and the cut-list
reversal is written into [the vision](docs/00-vision.md#cut-list), but nothing was built and nothing
should be built yet. PVP is meaningless without the melee loop and the contested recovery run is
meaningless without gear worth recovering, so it sits in Milestone 3 behind both. What did change:
[risk 9](docs/23-roadmap.md#risks) — what a client may know — now has a *buildable* answer rather
than a proposed one, because the filtered view's missing half was this primitive. It is still a
**design** question to settle before any transport code exists.

**And not a health bar.** Item by item, the seven features that prompted the multiplayer round are
specified in the docs and backlogged; the one that was asked for and refused is a bar of any kind.
The [condition view](docs/05-health-injury.md#the-condition-view) ships instead — a paperdoll of
located conditions in skill-scaled prose, which carries strictly more information than a bar and
none of it numeric. If a future session finds itself adding a fill percentage, that is the moment to
re-read [clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable) rather than
the moment to quietly amend it.

Still open and unclaimed: the per-tick propagation budget with its overflow queue,
`Pursue on direct contact`, and the **simulation half of last-known-position memory** — the renderer
fades a mark where a body was last seen, but no observer *remembers* anything, and the prose version
belongs with the condition view.

## Open questions nobody has answered

- **Is being quiet *tense*, or just slow?** Half-answered, and the half that is answered is the one
  that was blocking. Quiet is no longer *completely safe* — the noise field still reads zero live
  cells when you stand still, but scent finds you anyway over about an hour, 30 bodies within 50 m
  becoming 76. Whether an hour of creeping pressure *plays* as tense or merely as slow is still a
  question for a human at a keyboard, but it is now a tuning question rather than a design hole.
- **Does one shout being a district-wide event make shouting the only verb?** New, from watching it
  run. The magnitudes are right and the reach is what docs/03 calibrated for; the question is whether
  a stimulus that always recruits everybody leaves room for the quieter ones.
- **Does a migrating horde make the district legible or unpredictable?** New, and the most interesting
  thing this build produced. A disturbed horde now walks off downwind following its own scent, which
  means the player can *read* where it went from the wind — or be surprised by a crowd arriving from
  a direction nothing happened in. Which of those it feels like is a playtest question.
- **Is 90 minutes the right scent half-life?** It is the constant the whole channel's feel rests on
  and it was picked, not derived. Residue lasts ~40 minutes in practice, which is what makes the
  migration self-limiting; halving or doubling it changes how long a mistake follows you around.
- **Is a district you cannot see tense, or merely opaque?** New, and the most immediate consequence
  of the visibility work. The survivor now sees 11 bodies where 216 were being drawn. Reading the
  horde was already meant to be a skill; the question is whether removing that much information
  makes the district feel dangerous or just makes it feel empty until something is suddenly adjacent.
  A human at a keyboard, and the first thing to check next session.
- **Does the ground actually change where you walk?** New. The street is fast and loud, the yards
  are slow and quiet, and undergrowth is slow, loud and the only cover. The tables say a route is a
  decision; whether a player *notices* that without a readout is the question, since the HUD's
  ground line is a developer tool and the shipped game will not have it.
- **Are the arcs right?** 60° focal inside 190° total was picked, not derived, and docs/28
  deliberately declined to name numbers so that nobody would read them as settled. They are per
  observer and in one file. Widening the peripheral arc is a one-line experiment.
- **Does a body standing still in your peripheral vision deserve to be invisible?** It is the
  mechanic as specified — movement is noticed out there, identity is not — and it means a shambler
  that stops moving nine metres to your left is simply not on screen. Correct, and possibly
  horrible.
- **How long is a day, really?** Four hours at 1× is still a guess — but it is now a guess you can
  sit through, at 10×, in 24 minutes. `DAY_SECONDS` is one constant.
- **Is night tense, or just a nuisance?** New, and the sharpest question this build produced. Night
  currently takes the survivor's sight from 48 m to 12 and offers nothing in exchange, because the
  light channel does not exist. If it plays as pressure, the number should go *darker* when torches
  arrive. If it plays as an annoying filter, that is a signal the dark needs its counterplay before
  it needs more of itself.
- **Is a session with no pause still this game?** New, from the multiplayer design. The core loop
  claims the tension comes from irreversibility rather than APM; multiplayer removes the pause and
  keeps everything else, which tests that claim about as directly as it can be tested.
- **Does voice-as-emitter play as tense, or as a mute button?** Also new. If never speaking is
  dominant, the mechanic removed a channel instead of adding one.
- **Is the grid a decision or a chore?** The newest question, and the one nothing but playing will
  answer. Tarkov's inventory is famously either the best part of the game or an admin screen, and
  which one it is here depends on numbers that are currently guesses: pocket size (4×2), the pack
  grid (6×8), and how often a run actually fills it. **If rearranging is fiddly rather than tense,
  the fix is bigger cells and fewer of them, not a better UI.**
- **Does invisible weight read at all?** Encumbrance costs speed and stamina recovery and prints
  nothing, per clause 4. That is the right principle and it may simply not be *legible* — if players
  never notice they are overloaded, the signal needs to be louder in the world (gait, breathing,
  footstep noise) rather than quieter in the UI.
- The rest are listed under "Open questions" in [`docs/23-roadmap.md`](docs/23-roadmap.md).

*"How big is a district?" is no longer among them — it's 256 m, forced by the noise calibration.
"What does continuous scent cost?" is no longer among them either — 0.0075 ms a tick, and it was
never going to be the problem.*

## Conventions and gotchas

- **Never put an em dash in a heading you intend to link to.** GitHub's anchor slugs collapse
  ` — ` into a double hyphen, and it has silently broken links three times in this repo. Use a colon.
  Several headings were rewritten for exactly this reason.
- **Every doc opens with "why this exists" and closes with a cut list.** The cut lists are load-bearing
  — they're what stops scope creep, and `TODO.md` restates them at the end for the same reason.
- **The README index is the reading order.** File numbers reflect authorship order.
- **Events are queued, not immediate.** `publish` enqueues; handlers run on `drain`, which the tick
  does once. Anything that publishes outside a tick and expects the effect immediately -- `equip` at
  boot, a test asserting on the result -- has to drain first. This cost an hour: the melee bridge
  looked broken when it was only late.
- **A right-click mid-drag is not a `pointerdown`.** Once the primary button takes pointer capture,
  Chromium delivers no second `pointerdown` for another button -- only `contextmenu`. Verified by
  instrumenting the canvas. `platform/pointer.ts` keys rotation off `contextmenu` for this reason.
- **`npm run bench:frame` needs a browser path here.**
  `CHROMIUM_PATH=/opt/pw-browsers/chromium-*/chrome-linux/chrome npm run bench:frame`.
- **The container is ephemeral.** Anything uncommitted is gone when the session ends.
- `.claude/settings.local.json` is git-ignored globally and won't travel with the repo.

## A habit worth continuing

Every guard added so far was **mutation-tested**: break the thing on purpose, confirm something goes
red, put it back. That is not ceremony — it caught two guards that looked rigorous and tested nothing:

- A modifier-ordering test using `0.1 / 0.2 / 0.3` passed with the fold sort deleted, because later
  multiplications rounded the difference away. Catastrophic cancellation fixed it.
- The frame budget passes with viewport culling removed, because 2,000 flat rectangles are cheap. It
  is a regression guard today, not proof that culling earns its place; it will bite when sprites
  replace rectangles. Recorded here so nobody reads it as stronger than it is.

  **Sprites have now replaced the rectangles, and it did not bite.** The same mutation with
  character models in place: draw 2.26 ms with the cull deleted against 1.89 ms with it, both
  comfortably inside the 4 ms budget. The prediction was wrong, and the reason is worth having --
  *visibility* rejects 1,986 of 2,001 bodies before anything is drawn, so the viewport cull is
  removing work that occlusion was going to remove a few lines later either way. The two guards
  overlap almost completely, and the cheaper-looking one is not the one carrying the budget.

  So the note stands, with its expiry removed: viewport culling is still a regression guard rather
  than a proven cost saving, and the thing that would actually make it earn its place is a case
  where a great many bodies are *visible* at once -- a horde in open ground at night, not a street
  full of bodies behind walls.

The noise spine's three guards were each broken on purpose and confirmed red:

- Delete the angular bias → twenty shamblers in one cell collapse to a single heading.
- Delete the decay system → the district never falls silent.
- Delete the travel commitment → the horde forgets the moment the gradient dies.

Scent's seven were done the same way, and one of them found a hollow guard on the first try:

- `addScent` sums → change it to `max` and two bodies stop smelling more than one.
- Wind weights → pair each neighbour with its own weight instead of the opposite one and the plume
  drifts *upwind*.
- Scent decay → **the first version of this guard passed with the decay term deleted**, because a
  plume evaporates by dilution anyway. Now measured in isolation with the diffusion rate at zero.
- The scent floor → point it at noise's floor and a smell's lifetime collapses.
- Kernel diffusion → unregister the system and the field only ever holds what emitters wrote.
- The scent bias → remove it from the wander branch and standing still is safe forever again.
- Residue → the acceptance check *is* the mutation, and it toggles a shipped module rather than
  editing the code under test.

Sight's guards were done the same way, and the fourth hollow one turned up on the first try:

- Reveal every tile the wedge touches instead of only those whose centre is inside it → the symmetry
  check finds asymmetric pairs at every corner.
- Define `blocksSight` as `isSolid` → three tests go red at once: the window, the foliage, the
  low cover.
- Ignore the eye level → standing and crouching see the same thing over a car.
- Recompute unconditionally → "standing still is free" fails.
- Fold facing into the cache key → "turning is free" fails, and *nothing else does*.
- Make `invalidate()` a no-op → a wall built after the view was computed is invisible to it.
- Delete the sightline check from `detail` → **the first version of this guard passed**, because the
  arcs hide a third of a circle by themselves. Now counted inside the arcs only, plus a two-tile
  case with one wall.

The ground's guards were done the same way, and turned up a bug and a hollow guard in one sitting:

- Drop the surface factor from `movement.integrate` → grass, rubble and brambles all cross at the
  same speed.
- Drop it from `attention.emit-movement` → the two readings in the real district become equal.
- Hardcode the sprint threshold back to `2.8` → the "still exactly halfway" guard fails, and
  *nothing else does*, which is precisely why it needed its own assertion.
- Stop laying undergrowth under screening → the district loses a surface, and a bush becomes a free
  sightline break.
- **"Is this tile indoors?" answered by shape rather than by the generator** → the first version
  scanned outward for solid tiles in four directions, which the map perimeter satisfies for every
  tile in the district. It passed while measuring nothing, and it was hiding brambles growing in
  people's living rooms.

The day's guards were done the same way:

- Range ignores ambient light → night becomes a tint, and the "shrinks what a survivor can see"
  guard fails.
- Drop the rounding to whole tiles → dusk costs a shadowcast every tick.
- Make the phase publisher remember what it announced instead of comparing two ticks → the
  transition counts go wrong.
- Start a run at tick 0 → it opens in the dark, and the guard that says otherwise fails.

One of those, the decay system, needed a **second** test written for it: the arithmetic was already
covered by a unit test calling `decay()` directly, which passed happily with the system unregistered.
Covering the maths is not covering the wiring.

A green suite says nothing about whether it *can* go red.
