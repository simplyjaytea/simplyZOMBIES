# Handoff

State of the project for whoever picks it up next — a person or a fresh session. Written 2026-08-05,
updated the same day when Milestone 0 closed.

**Read this, then [README.md](README.md), then [TODO.md](TODO.md).**

---

## Where things stand

| | |
|---|---|
| **Phase** | **Milestone 0 complete.** The architecture runs; there is no game on top of it yet. |
| **Merged** | [PR #1](https://github.com/simplyjaytea/simplyZOMBIES/pull/1) — the design docs · [PR #2](https://github.com/simplyjaytea/simplyZOMBIES/pull/2) — the attention field spike |
| **In flight** | [PR #3](https://github.com/simplyjaytea/simplyZOMBIES/pull/3) — the spike fold-in, plus all of Milestone 0 |
| **Next real work** | **Milestone 1 — the spine.** The attention field, and shamblers that read it. |

## What's in the repo

```
docs/           27 design documents. The README index is the reading-order authority,
                not the file numbers — 24-26 were written last but belong under "The world".
TODO.md         The backlog through Milestone 2, with all 8 roadmap risks pinned to the
                task that answers each one. Milestone 0's boxes are ticked.
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
npm test                 # correctness: 133 tests
npm run typecheck        # three projects — see the sim/ purity gate below
npm run lint
npm run bench            # tick budgets
npm run bench:frame      # frame budget, drives real Chromium
```

In the browser: `WASD` move · `Shift` sprint · `P` pause · `F5` save · `F9` load · `F3` state
fingerprint. That fingerprint is the string the determinism test compares, and it is **off by
default**: computing it serializes the entire world (~16 ms at 2,000 entities), so leaving it on
costs more than everything else in the frame put together.

If Playwright can't find a browser, point it at one: `CHROMIUM_PATH=/path/to/chromium npm run
bench:frame`.

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
- **Field memory is scent, never noise.** Kept rather than cut, but on the condition that Milestone 1
  proves it does something.

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

### The spike is now deletable

Everything it proved is in the docs, and `docs/14-zombies.md` no longer needs it as a reference —
the angular bias is implemented in `src/sim/modules/wander.ts`. Deleting `spike/`,
`vite.spike.config.ts`, `tsconfig.spike.json` and the two `*:spike` scripts is a clean subtraction
whenever someone wants the repo tidier. It was left in only because deleting working demonstration
code is easier to do later than to undo.

## Do this next

**Milestone 1 — the spine.** `TODO.md` has the tasks. The exit criterion is: *make noise, and they
come. Go quiet, and they don't.*

Two things worth knowing before starting:

- **Scent is the risky part**, not noise. The spike proved event-driven noise is nearly free; scent is
  the continuous channel [risk 5](docs/23-roadmap.md#risks) actually names, and it is still untested.
- **Field memory rides on scent** and has never been observed working, so the Milestone 1 acceptance
  check is real: switch residue off, and if nothing observable changes, cut the mechanic.

## Open questions nobody has answered

- **Is being quiet *tense*, or just slow?** Needs a human playing. With noise as the only channel,
  quiet is *completely* safe — which is the design as specified, and the strongest argument that scent
  isn't optional.
- **Scent cost.** Untested. It's the continuous channel [risk 5](docs/23-roadmap.md#risks) is actually
  about, so that risk is narrowed, not closed. It now carries a second question too: field memory has
  never been observed working, because it needs scent to exist first.
- **How long is a day, really?** Four hours at 1× is still a guess.
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
