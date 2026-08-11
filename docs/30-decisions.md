# 30 — Decision Records

## Why this document exists

Every chunk of work in this project has produced a handful of decisions that were cheap to make at the
time and would be expensive to reverse later. They are not design decisions — [docs/00](00-vision.md)
through [docs/29](29-movement-and-stances.md) own those — and they are not status, which
[HANDOFF.md](../HANDOFF.md) owns. They are the things the *code* made structural: an invariant that is
now enforced rather than intended, a mechanism that turned out to be the only one that works, or a
prediction that was wrong and is worth having on the record as wrong.

They lived in the handoff until Milestone 0 closed, at which point there were fourteen of them and
they were two thirds of a document people needed to read for its status. So they moved here, verbatim.

**Read this when** you are about to change something that looks arbitrary, or when a decision looks
like it was made by accident. Most of them were not. If you are about to "improve" one, the entry
usually says what breaks.

**Do not read this for orientation.** [HANDOFF.md](../HANDOFF.md) is where to start cold.

Entries are in the order the work landed, oldest first. Add to the end.

---

## What the spike settled

The three findings are **folded into the documents that specify the systems**. Don't redo this; the
docs are the authority now and [`docs/23-roadmap.md`](23-roadmap.md#spike-findings-attention-field)
keeps the evidence.

| Finding | What was decided | Now specified in |
|---|---|---|
| Gradient ascent alone makes **conga lines**, not a horde | Persistent per-individual angular bias (±0.62 rad), from the seeded RNG, in save state. No neighbour queries, no measurable cost. | [`docs/14`](14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own) |
| **Noise magnitudes aren't calibrated to district size** | The magnitudes were never wrong — the **unit** was never defined. 1 tile = 1 m, 0.7 attenuation per metre, 4 m field cells, **256 m district**, so one gunshot = one district. **Zero magnitudes changed.** | [`docs/03`](03-attention.md#scale-and-calibration), [`docs/24`](24-world-and-scale.md#how-big-a-district-is) |
| **Field memory is a no-op** | The spike tested it on the wrong channel. It's a **scent** mechanic in both specifying docs; residue-as-noise dies inside its own cell by arithmetic. Kept, on scent, with a Milestone 1 acceptance check that cuts it if nothing observable changes. | [`docs/03`](03-attention.md#field-memory-is-a-scent-mechanic) |
| **Rendering dominates simulation** (~30×) | Draw budget and sim-share-of-frame budget added; every benchmark asserts frame time, not just tick time. | [`docs/22`](22-performance.md#aim-the-budgets-at-the-renderer) |

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

## What Milestone 1 has found so far

- **Gradient ascent alone stops too early.** Noise decays with a 3 s half-life; the far half of a
  district is a minute's walk. Shamblers now carry a 20 s **travel commitment** — they keep their
  bearing after the gradient dies. Without it they forget mid-street, which reads as the field being
  broken rather than as noise fading. docs/03 already asked for this: *"the horde it already summoned
  is still walking."*
- **Decay shrinks loudness, not radius** — and this contradicted docs/03's prose, so
  [the doc was corrected](03-attention.md#scale-and-calibration). Multiplying the stored field
  leaves its shape untouched: five half-lives after a shout every cell is 1/32 of what it was and the
  edge has barely moved. The resulting behaviour is the one the design wants, but by a different
  mechanism than "inaudible in 15 seconds" implies.
- **Converging is not a different cost class from drifting**, which is the property the new budgets
  guard. 0.19 ms against 0.15 at 300 bodies; 1.38 against 1.04 at 2,000.
- **One shout wakes essentially the whole district.** 4,055 of 4,096 cells. That is what the
  calibration says should happen — a shout carries 171 m across a 256 m district — but nobody had
  seen the consequence before now. Whether it makes shouting the only interesting verb is a
  playtest question, not an arithmetic one.

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
  which way the wind blows. When [weather](16-weather.md) takes wind over in Milestone 3 it
  changes those four numbers and nothing else — and wind becomes save state at that point, which it
  deliberately is not now.
- **`liveCells()` and `peakNoise()` stayed noise-only.** Three assertions in the exit criterion read
  `liveCells() === 0` as "the district is silent", and folding in a channel that decays over hours
  would have broken the noise criterion for no reason. Scent got sibling methods instead.

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
[docs/03 was wrong and is corrected](03-attention.md#what-field-memory-turned-out-to-actually-do)
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
culling was the first — and it is [recorded in docs/22](22-performance.md#the-ci-benchmark-suite)
rather than quietly accepted. Anyone tightening that budget should raise the entity count first.

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

## What the ground changed

**The speeds moved, and docs/29 said they would not.** That document stated in as many words that
walk and sprint "are shipped and do not move", at the real-world 1.4 and 4.2 m/s. The repo owner
asked for faster, on game feel — at 1.4 a district is a three-and-a-half minute crossing and it
plays slowly — so they are 2.1 and 6.3, and
[docs/29 records the reversal](29-movement-and-stances.md#the-five-stances) rather than being
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

## What light made structural

The third attention channel, and the first thing it settled was where it does *not* go.

- **Light is not a field layer, and the field refused it twice.** The obvious home was
  `AttentionField` beside noise and scent, and two things in the code say no. `liveCells()` is read
  by three Milestone 1 exit-criterion assertions as "the district is silent", so a third channel
  folded in there breaks the noise criterion for nothing. And the geometry disagrees: the field is
  **4 m cells** while a shadowcast is **1 m tiles**, and light is the one channel where a wall is an
  *absolute* rather than a penalty — noise pays an 18 m-equivalent to cross one, scent ignores them
  entirely. Four-metre cells round away exactly the precision that makes shutters work *completely*.
  [docs/03](03-attention.md#light) already said light propagates by shadowcasting rather than
  flood-fill; the code now agrees with it.
- **Magnitude is range, so light takes the maximum and never the sum.** Two candles in one spot do
  not make a lamp and no number of them ever does, because ranges do not add. This is the same `max`
  the noise channel commits with and deliberately not scent's sum — scent sums because a crowd
  genuinely smells more than one body, and light does not work that way. `sightMetres` then takes the
  **min** with the observer's own eyes: light removes a penalty, it does not grant an ability, so a
  floodlight is not better than daylight and a shambler's twelve metres stay twelve.
- **Being lit by a lamp is not the same as being able to see one.** `SHAMBLER_EYES` reaches 12 m, so
  a 35 m lamp lights the ground under a zombie that has no sightline to the source and therefore
  feels no pull at all. That asymmetry is the mechanic rather than a limitation — docs/28 asks whether
  it can *see* the lit cell — and the first version of the test put the lamp at 20 m and measured
  nothing, which is how it was found.
- **Light is a third stimulus shape, not a variant of the two that existed.** Noise is an impulse:
  it overwrites the heading and commits for twenty seconds, and it is the only thing that moves a
  shambler into Seek. Scent is a bias on a gradient. Light has **no gradient** — the question is a
  per-observer sightline, not a field sample — so it is a gated lean, and sensitivity *scales* it
  rather than dividing a floor. There is no light floor in the calibration and there should not be
  one: light decays instantly, so "less than this is nothing" is already the edge of the shadowcast
  window where `magnitude - distance` reaches zero. One fewer tunable, and docs/14's Light column
  becomes legible — 0.1 leans a shambler 5% of the way per tick, 0.9 would lean a screamer 45%.
- **`NIGHT_AMBIENT` is derived, and the derivation has to be in tiles.** The rule is that a candle
  must be an upgrade rather than a formality, so bare-eyed midnight has to fall below the weakest
  emitter. Derived in metres — `48 * N < 3` — that admits 0.05, and at 0.05 bare eyes are 2.4 m and a
  candle is 3 m and **both round to a three-tile window**. The candle would have been an upgrade on
  paper and invisible in play. A shadowcast's window is an integer radius, so the comparison that
  decides whether the player can tell has to be made in the unit the geometry uses:
  `tileRange(48 * N) < tileRange(3)`, so `N <= 0.0417`, so 0.04.
- **One map-generation counter for both indices, not one each.** Vision and light both cache against
  the tile map, and two counters would let them disagree — a wall built between a lamp and a survivor
  stopping being seen through while the lamp kept lighting past it. The place two line-of-sight
  answers disagree is the place the exploit lives, so the counter moved to `World.mapGeneration` and
  `VisibilityIndex.invalidate()` — which had no caller — became `World.invalidateMap()`.
- **The counterplay is findable, not given.** The night could only come down because a candle exists
  to answer it, and the starting loadout is *empty* — so the guarantee is "findable during the
  opening day" (a run opens at 09:00, candles sit at loot weight 40) rather than "handed over". The
  cost is written down where it lands: the old rationale for a starting kit was that handing the
  player a real *item* keeps the whole chain on the path a session walks, and that guarantee now
  lives in the `dev` loadout and the integration suites instead, which is weaker.
- **The screen may draw a lit region only where the survivor can see it.** `NIGHT_WASH`'s comment
  forbids two mechanisms for one fact, and a pool of light thirty metres away with no sightline to it
  would be painted bright and be invisible — the screen asserting what the simulation denies. So the
  overlay draws **lit ∩ seen**, and the night wash derives from `sightMetres` rather than raw ambient.
  Standing in a lit pool lifts the dark *because the range genuinely grew*, which keeps it one number
  with two consumers rather than two answers to one question.

Cost, for the record, because it was not what was expected: `crowded-and-lit` — 2,000 bodies, 500 of
them with eyes, a floodlight in the street and a lamp in hand — holds **the same 4 ms budget as its
sightless twin**, at 2.54 ms against `crowded`'s 1.85. Light casts per *source*, not per observer, so
the only per-entity cost is one squared-distance reject per source and an arc test for what survives.
It scales with lamps rather than with bodies.

---

**Previous:** [23 — Roadmap](23-roadmap.md) · **Next:** [HANDOFF.md](../HANDOFF.md) ·
[Doc index](../README.md#documentation)
