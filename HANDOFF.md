# Handoff

State of the project for whoever picks it up next — a person or a fresh session. Written 2026-08-05,
updated the same day when Milestone 0 closed, again when Milestone 1 reached its exit criterion, and
again on 2026-08-06 when the melee loop landed.

**Read this, then [README.md](README.md), then [TODO.md](TODO.md).**

---

## Where things stand

| | |
|---|---|
| **Phase** | **Milestone 1, all but the clock.** The field runs, shamblers read it, and they can now kill you. |
| **Merged** | [PR #1](https://github.com/simplyjaytea/simplyZOMBIES/pull/1) — the design docs · [PR #2](https://github.com/simplyjaytea/simplyZOMBIES/pull/2) — the attention field spike · [PR #3](https://github.com/simplyjaytea/simplyZOMBIES/pull/3) — spike fold-in + Milestone 0 |
| **In flight** | The melee loop, together with Milestone 1 — see the warning below. |
| **Next real work** | **The day/night cycle and speed controls** ([docs/02](docs/02-core-loop.md)), the last of Milestone 1. Then Milestone 2. |

> ### Read this before branching
>
> **[PR #4](https://github.com/simplyjaytea/simplyZOMBIES/pull/4) merged into the wrong branch.** It
> was stacked on #3 and never retargeted, so when both merged within fifteen seconds of each other,
> all of Milestone 1 landed in `claude/handoff-review-prioritize-11eszj` instead of `main` — and
> `main` sat a milestone behind while its own `HANDOFF.md` told the next session to build what was
> already built. The fix rides along with the melee loop, whose branch is based on that commit.
>
> The lesson is cheap to state and was not cheap to find: **a stacked PR points at its parent branch,
> not at `main`, and merging the parent does not retarget it.** Check the base branch before merging
> anything stacked.

## What's in the repo

```
docs/           27 design documents. The README index is the reading-order authority,
                not the file numbers — 24-26 were written last but belong under "The world".
TODO.md         The backlog through Milestone 2, with all 8 roadmap risks pinned to the
                task that answers each one. Milestone 0 is ticked; Milestone 1 is ticked
                except for combat and the clock, listed under "Still open in this milestone".
src/sim/        The simulation. Pure, headless, deterministic — kernel, modules, rng.
src/render/     Canvas renderer. Reads the sim, never writes to it.
src/platform/   The host: input, the tick loop, storage, content loading, schemas.
content/        JSON content plus its JSON Schemas.
test/           Unit and integration, including determinism and module isolation.
bench/          The performance budgets. They fail the build.
spike/          THROWAWAY prototype. Its findings are absorbed into the docs, so it can be
                deleted whenever — see "the spike is now deletable" below.
```

## Running it

```bash
npm install
npm run dev              # the game at http://127.0.0.1:5174
npm test                 # correctness: 198 tests
npm run typecheck        # three projects — see the sim/ purity gate below
npm run lint
npm run bench            # tick budgets
npm run bench:frame      # frame budget, drives real Chromium
```

In the browser: `WASD` move · `Shift` sprint · `Space` swing (or struggle, when something has hold of
you) · `P` pause · `F5` save · `F9` load · `F3` state fingerprint · `F4` attention overlay. That fingerprint is the string the determinism test compares,
and it is **off by default**: computing it serializes the entire world (~16 ms at 2,000 entities), so
leaving it on costs more than everything else in the frame put together.

`F4` draws all three attention channels at once — red noise, green light, blue scent. **Developer
only**, and it must stay that way: docs/03's cut list rejects a player-visible attention readout
outright, because it "would collapse the game's central uncertainty into a number".

If Playwright can't find a browser, point it at one: `CHROMIUM_PATH=/path/to/chromium npm run
bench:frame`. In the standard container that is
`CHROMIUM_PATH=/opt/pw-browsers/chromium-1194/chrome-linux/chrome` — the bundled Playwright looks for
a build number the image does not carry, so the default path fails and the flag is not optional.

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
- **Vehicles were un-cut** after initially being cut at the vision level. `docs/00-vision.md` records
  the reversal and why the original objection was half right.
- **A district is 256 m, falloff stays linear.** Decided against re-authoring the magnitude table,
  because its ratios are load-bearing in six documents and only the unit was ever missing.
- **Field memory is scent, never noise.** Kept rather than cut, on the condition that Milestone 1
  prove it does something. **It did** — 19.4 m against 25.4 m — so the condition is discharged.

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

The exit criterion is met and asserted (`test/integration/exit-criterion.test.ts`). More useful to a
newcomer than the file list is *which invariants are now enforced rather than merely intended*,
because these are the ones you will trip over:

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
- **Budgets fail the build.** `npm run bench` for tick, `npm run bench:frame` for the frame. The
  frame one drives real Chromium, because frame time cannot be measured in node. It gates on
  **`loop.workMs`** — measured by the loop around its entire frame callback, not assembled from
  `sim + draw`. That distinction is the whole point: a sum only covers the parts someone remembered
  to instrument, and the first thing it missed cost 16 ms a frame. Anything added to the frame lands
  inside the measurement by construction.
- **Any module can be switched off.** Checked in CI for each module individually and all at once.
  This is also how sandbox presets and storyteller settings get implemented later — not as special
  cases, as this.

## What Milestone 1 built, and what it found out

The field is **kernel, not a module** (`src/sim/kernel/field.ts`), for the reason docs/19 gives:
a module may be switched off, and stimulus may not. Disabling it would not make a quieter game, it
would make a game where nothing can hear anything.

Things you will otherwise rediscover the hard way:

- **The three channels propagate differently on purpose, and the difference is the design.** Noise
  *floods around* obstructions on a uniform-cost search, so buildings are detours and streets are
  noise highways. Light is *occluded* — same map, opposite model. Getting these the same way round
  would quietly turn buildings into insulation, which docs/03 explicitly says they are not.
- **Light's line-of-sight is tested at tile resolution, not cell resolution.** A one-tile wall is a
  quarter of a 4 m field cell, so a coarse test let lamps shine straight through building walls.
  Storage can be coarse; occlusion cannot.
- **Scent's decay is written as a half-life, not a per-step rate.** The first version used an
  innocent-looking 0.0004 per step, which is 11% a minute — a noise channel wearing scent's name.
  docs/03's "hours" versus "seconds to a minute" is the whole reason the channels are not
  interchangeable, so the constant now says `SCENT_HALF_LIFE_SECONDS = 2 * 60 * 60` and the rate is
  derived.
- **The angular bias was already in save state**, drawn at spawn by Milestone 0 precisely so this
  milestone would not have to add it and change every recorded seed. `modules/zombies.ts` consumes
  it; it does not draw a second one.

### A benchmark that measures nothing still reports a number

The risk-5 scenario's first draft used a 45-magnitude generator, which reaches 64 m of a 256 m
district. 498 of 500 zombies stood outside it and never moved, scent covered 163 of 4,096 cells, and
it reported a comfortable **0.55 ms/tick** — for an idle horde over an empty field. The honest
version uses a 220-magnitude engine covering the district and seeds scent across it: **1.20 ms**.

Same shape as the frame-budget bug in the section above, and worth the habit it implies: when a
performance scenario passes easily, check that it is doing the thing before believing it.

### The spike is now deletable

Everything it proved is in the docs, and `docs/14-zombies.md` no longer needs it as a reference —
the angular bias is implemented in `src/sim/modules/wander.ts`. Deleting `spike/`,
`vite.spike.config.ts`, `tsconfig.spike.json` and the two `*:spike` scripts is a clean subtraction
whenever someone wants the repo tidier. It was left in only because deleting working demonstration
code is easier to do later than to undo.

## What combat built, and what it found out

The melee loop is a **module** (`src/sim/modules/combat.ts`), unlike the field: a world with no combat
in it is a coherent configuration, and a world where nothing can hear anything is not.

The part worth knowing before touching it is what it does *not* do. Combat never reads or writes
another module's components, and three couplings that would have forced it to are routed instead
through mechanisms that already existed:

| Coupling | Routed through |
|---|---|
| "a grabbed survivor cannot move" | a `move_speed` modifier — the player module multiplies it in without knowing who set it |
| "a crawler is slower" | the same, on the zombie |
| "who is prey" | the kernel's `Tags`, not a peek at `Controlled` |

That is docs/21's modifier pipeline doing the job it was built for, and it is why `player.ts` contains
no reference to combat and `combat.ts` none to the horde.

Four things measured rather than assumed:

- **Reach is doubly load-bearing**, and the second half was a surprise. Bite risk on a connect is
  divided by reach, and a grab lands at 0.9 m — so **no weapon with less reach than that can strike
  from outside grab range at all**. Bare hands mean fighting from inside it. Recorded in
  [`docs/09`](docs/09-combat.md#what-building-it-settled).
- **A crowd pins you, and the arithmetic is what makes it terminal.** Struggling costs stamina and
  there is no recovery while held, so one hold costs about a third of a tank, two about two thirds,
  and past three there is not enough in the tank however long you hold the button. The first version
  had struggling nearly free, and six zombies were an inconvenience.
- **The breach benchmark measured almost nothing, twice.** First it measured a survivor pinned in
  silence: no swings, so no noise, so 460 of 500 zombies stood exactly where they spawned. A
  generator at the survivor's feet fixed it. Then the guard test still failed, because a crowd
  ascending a point source runs out of gradient on the source's own 4 m cell and settles a metre
  outside contact range — so ~90 of 500 make contact, not 500. Both are in the scenario's comments.
- **The spatial hash was the expensive part of combat, and none of it was combat.** Rebuilt every
  tick over every positioned entity, it cost about a millisecond a tick at 2,000 entities and pushed
  the frame budget's p95 from 2.86 ms to 30.40 ms. Two changes, no behaviour: iterate storage order
  instead of `query`'s sorted array (the buckets are re-sorted on the way out anyway, so the sort
  bought nothing), and keep bucket arrays across rebuilds instead of dropping several hundred a tick
  for the collector. `quiet-night` ended up *faster* than before combat existed.

## Do this next

**Finish Milestone 1** with the clock, then Milestone 2. `TODO.md` lists what is left under "Still open
in this milestone": the day/night cycle, phase events, and speed controls
([docs/02](docs/02-core-loop.md)).

One piece of it now has a dependency worth knowing: **10× auto-drops to 1× on threat contact**, and
"threat contact" is a thing that exists — a zombie sets `pursuing` when someone comes within 3 m
(`src/sim/modules/zombies.ts`). The clock does not need to invent its own definition.

The two things this milestone was told to find out, it found out:

- **Scent is affordable.** 500 shamblers ascending a saturated district cost 1.20 ms/tick against a
  4 ms budget, and *less* than 2,000 idle entities. [Risk 5](docs/23-roadmap.md#risks) named continuous
  scent diffusion as the most likely thing to need rework; at this scale it is not.
- **Field memory is real, and kept.** A crowd drawn somewhere and then left in silence settles 19.4 m
  from the spot with residue on against 25.4 m with it off. The check was written to fail — the
  spike's residue existed too, and was still a no-op — so it asserts where the horde *ends up*, not
  that an emitter fired.

## Open questions nobody has answered

- **Is being quiet *tense*, or just slow?** Still needs a human playing, and it is now a better
  question than it was: going quiet is safe, and going loud has a consequence you can be killed by.
- **Is a fight worth having?** Melee is nearly silent by design (a connect is 8, against 180 for a
  gunshot), so clearing your approaches should be the quiet play. Whether it *feels* worth the bite
  risk is a question about a human, not about a benchmark.
- **How long is a day, really?** Four hours at 1× is still a guess — and the next thing anyone builds
  is the clock, so this one is about to matter.
- The rest are listed under "Open questions" in [`docs/23-roadmap.md`](docs/23-roadmap.md).

*"How big is a district?" is no longer among them — it's 256 m, forced by the noise calibration.*

## Conventions and gotchas

- **Never put an em dash in a heading you intend to link to.** GitHub's anchor slugs collapse
  ` — ` into a double hyphen, and it has silently broken links three times in this repo. Use a colon.
  Several headings were rewritten for exactly this reason.
- **Every doc opens with "why this exists" and closes with a cut list.** The cut lists are load-bearing
  — they're what stops scope creep, and `TODO.md` restates them at the end for the same reason.
- **The README index is the reading order.** File numbers reflect authorship order.
- **The container is ephemeral.** Anything uncommitted is gone when the session ends.
- `.claude/settings.local.json` is git-ignored globally and won't travel with the repo.

## Commands

See [Running it](#running-it) above for the game. The spike still has its own:

```bash
npm run dev:spike        # the throwaway spike at http://127.0.0.1:5173
node spike/measure.mjs   # scenario sweep + screenshots -> /tmp/spike-shots
node spike/compare.mjs   # conga-line A/B (gradient spread off vs on)
```

Spike controls: `WASD` move · `Shift` sprint · `Space` shout · `O` overlay · `L` +500 zombies ·
`J` toggle the spread fix · `M` field memory · `P` pause.

## A habit worth continuing

Every guard added so far was **mutation-tested**: break the thing on purpose, confirm something goes
red, put it back. That is not ceremony — it caught two guards that looked rigorous and tested nothing:

- A modifier-ordering test using `0.1 / 0.2 / 0.3` passed with the fold sort deleted, because later
  multiplications rounded the difference away. Catastrophic cancellation fixed it.
- The frame budget passes with viewport culling removed, because 2,000 flat rectangles are cheap. It
  is a regression guard today, not proof that culling earns its place; it will bite when sprites
  replace rectangles. Recorded here so nobody reads it as stronger than it is.
- **The frame budget itself was the third case, and the worst.** It computed its number as
  `draw + sim`, both of which stop measuring before the render hook finishes — so the HUD's
  per-frame `serialize()` sat outside the gate. The harness printed `work 2.82 ms` and
  `OK: within budget` on an 18.90 ms frame running at 53 fps. Reintroducing the bug against the
  fixed gate now reports `work 16.08 ms` and fails. A budget that cannot fail is worse than no
  budget, because it gets trusted.

A green suite says nothing about whether it *can* go red — and neither does a green budget.
