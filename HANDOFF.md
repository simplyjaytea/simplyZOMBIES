# Handoff

State of the project for whoever picks it up next — a person or a fresh session. Written 2026-08-05,
updated 2026-08-06 when the noise spine landed and 2026-08-10 when scent did.

**Read this, then [README.md](README.md), then [TODO.md](TODO.md).**

---

## Where things stand

| | |
|---|---|
| **Phase** | **Milestone 1, phase 2 done: scent.** Shout and the district walks toward you in a minute. Say nothing at all and it still finds you, in an hour. |
| **Merged** | [PR #1](https://github.com/simplyjaytea/simplyZOMBIES/pull/1) — the design docs · [PR #2](https://github.com/simplyjaytea/simplyZOMBIES/pull/2) — the attention spike · [PR #3](https://github.com/simplyjaytea/simplyZOMBIES/pull/3) — all of Milestone 0 |
| **In flight** | scent: continuous diffusion, wind, field memory, and the two ⚠ checkpoints that were riding on it — **both now closed** |
| **Next real work** | **Light and shadowcasting**, then the melee loop. See [Do this next](#do-this-next). |
| **Also landed, as design only** | **[Multiplayer](docs/27-multiplayer.md)** — authoritative host, survivor-vs-survivor PVP, and voice as a noise emitter. Specified, docs reconciled, **no engine code**. Filed as Milestone 3. |

## The build

`.github/workflows/pages.yml` publishes `dist/` to GitHub Pages on every green CI run on `main`.

> ⚠ **One manual step is still outstanding:** Settings → Pages → Source: **GitHub Actions**. Until
> someone with repo admin does that, the workflow runs and the deploy step fails. Nothing in CI
> depends on it.

The build is worth playing now, which is the whole reason it exists. What it cannot answer is in
[Open questions](#open-questions-nobody-has-answered), and the first one needs a human at a keyboard.

## What's in the repo

```
docs/           27 design documents. The README index is the reading-order authority,
                not the file numbers — 24-26 were written last but belong under "The world".
TODO.md         The backlog through Milestone 2, with all 8 roadmap risks pinned to the
                task that answers each one. Milestone 0 and the noise spine are ticked.
src/sim/        The simulation. Pure, headless, deterministic — kernel, modules, rng.
src/sim/field/  The attention field. Kernel, not a module (see below).
src/render/     Canvas renderer. Reads the sim, never writes to it.
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
npm test                 # correctness: 169 tests (~40 s -- the scent ones simulate hours)
npm run typecheck        # two projects — see the sim/ purity gate below
npm run lint
npm run bench            # tick budgets
npm run bench:frame      # frame budget, drives real Chromium
```

In the browser: `WASD` move · `Shift` sprint · **`Space` shout** · **`O` cycles the attention overlay
(off → noise → scent)** · `P` pause · `F5` save · `F9` load.

**Press space.** 4,055 of the district's 4,096 field cells go live, 298 of 300 shamblers switch to
seeking, and over the next minute the crowd within 50 m goes from about 30 bodies to about 90. Then
it fades and they drift off again.

**Then press nothing at all, and wait.** That is the other half, and it is new. Stand perfectly
still — the noise field sits at literally zero live cells, exactly as before — and the crowd within
50 m still climbs from 30 to 76 over an hour, on nothing but the scent a body cannot stop emitting.
Being quiet is no longer *safe*; it is *slow*, which is a much better answer to the question this
document has been asking since the noise spine.

**And press `O` twice** to put the scent overlay up, then watch a horde you disturbed walk off
downwind following its own smell. That one was not designed; see [what scent
changed](#what-scent-changed-and-what-it-corrected).

The HUD shows live cells and peak for **both channels**, the horde's state counts, and a **state
fingerprint** — that string is what the determinism test compares.

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
- **Budgets fail the build.** `npm run bench` for tick, `npm run bench:frame` for draw. The frame one
  drives real Chromium, because frame time cannot be measured in node.
- **Any module can be switched off.** Checked in CI for each module individually and all at once.
  This is also how sandbox presets and storyteller settings get implemented later — not as special
  cases, as this.

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

## Do this next

**Light and shadowcasting.** It is the third channel and the last one Milestone 1 owes, and unlike
scent it carries no open risk — which is a good reason to take it now rather than saving it.

- It is the only channel that is **not a field propagation at all**: shadowcasting from emitters,
  recomputed on emitter or occluder change, not diffused and not flooded. Expect to reuse the cell
  geometry and almost none of the propagation code.
- The overlay is already a channel cycler, so it has somewhere to go on arrival.
- Sensory profiles already read all three weights from content; light is the one still ignored in
  code. Screamers weight it 0.9 against a shambler's 0.1, so this is where "there is no single
  silence" stops being a slogan.

Take the **melee loop** after it — that is what makes the spatial hash worth building, and the hash
is deliberately still deferred until something needs neighbour queries.

**Not multiplayer.** [Doc 27](docs/27-multiplayer.md) landed as a specification and the cut-list
reversal is written into [the vision](docs/00-vision.md#cut-list), but nothing was built and nothing
should be built yet. PVP is meaningless without the melee loop and the contested recovery run is
meaningless without gear worth recovering, so it sits in Milestone 3 behind both. If you do pick it
up early, [roadmap risk 9](docs/23-roadmap.md#risks) — what a client may know about the attention
field — is a **design** question to settle before any transport code exists.

Still open and unclaimed: day/night, the per-tick propagation budget with its overflow queue, and
`Pursue on direct contact`.

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
- **How long is a day, really?** Four hours at 1× is still a guess.
- **Is a session with no pause still this game?** New, from the multiplayer design. The core loop
  claims the tension comes from irreversibility rather than APM; multiplayer removes the pause and
  keeps everything else, which tests that claim about as directly as it can be tested.
- **Does voice-as-emitter play as tense, or as a mute button?** Also new. If never speaking is
  dominant, the mechanic removed a channel instead of adding one.
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

One of those, the decay system, needed a **second** test written for it: the arithmetic was already
covered by a unit test calling `decay()` directly, which passed happily with the system unregistered.
Covering the maths is not covering the wiring.

A green suite says nothing about whether it *can* go red.
