# 30 — Decision Records

## Why this document exists

Every chunk of work in this project has produced a handful of decisions that were cheap to make at the
time and would be expensive to reverse later. They are not design decisions — [docs/00](00-vision.md)
through [docs/29](29-movement-and-stances.md) own those — and they are not transition sequencing,
which [docs/31](31-godot-rebuild-roadmap.md) owns, or status, which
[docs/23's milestone status sections](23-roadmap.md#where-milestone-2-stands) own.
They are the things the *code* made structural: an invariant that is now enforced rather than
intended, a mechanism that turned out to be the only one that works, or a prediction that was wrong
and is worth having on the record as wrong.

They lived in the handoff until Milestone 0 closed, at which point there were fourteen of them and
they were two thirds of a document people needed to read for its status. So they moved here, verbatim.

**Read this when** you are about to change something that looks arbitrary, or when a decision looks
like it was made by accident. Most of them were not. If you are about to "improve" one, the entry
usually says what breaks.

**Do not read this for orientation.** `CLAUDE.md` and [docs/23](23-roadmap.md) are where to start
cold.

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
  lives -- arriving one layer down. *(Superseded by the top-down reversal below: with no vertical
  axis to draw, `metres_to_rise` and `RISE_SCALE` are deleted rather than moved. The "one answer"
  principle it argued for is what survives.)*
- **The depth tie is the renderer's to break, not the projection's.** `depthOf` still ties for
  anything on the same diagonal and its test still says so, because that genuinely *is* the ordinary
  isometric ambiguity. Flat squares never showed it; standing bodies do. So the comparator resolves
  it -- occluder, body, player, entity id -- and the player sorting last on a tie is a fairness
  property rather than a cosmetic one: a shambler at identical depth must never hide you.
  *(Superseded by the top-down reversal below: depth is now `y` alone and tiles left the depth
  pass entirely, so the only tie left is two bodies on one row, where draw order is invisible --
  their sprites share a baseline.)*
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

## What pursuit made structural

The last open box in the Zombies section, and the first stimulus in the game that is allowed to
persist. Noise commits for twenty seconds and fades; scent and light end the tick they stop being
sensed; contact holds until the survivor gets clear. That difference is what most of these entries are
about.

- **The design document contradicted itself, and the code could not.** docs/14 rule 4 said both
  "indefinitely" and "for as long as you're audible", which are two different mechanics — one is a
  latch, the other is noise-conditional. Settled toward distance: you get out of pursuit by getting
  away. [docs/14 is corrected](14-zombies.md#baseline-behavior) rather than implemented around, per the
  rule that when a task and its doc disagree the doc is wrong.
- **Contact is a distance, and that is what makes it robust.** `threat.ts` already argues the point for
  the speed control: distance is the one measure that does not vary with the light. Tie contact to a
  sightline and shutters switch pursuit off; tie it to noise and standing still does. Neither is what a
  zombie with its hands on you is doing — it has not been *perceiving* you for a while. The consequence
  is that pursuit works in the dark and works on a shambler with no eyes, both asserted.
- **Two radii, because one flickers.** A survivor on a single boundary enters and leaves pursuit on
  alternating ticks. It costs nothing and reads as a seizure, and it makes every assertion about the
  state machine flicker with it. Release is wider than contact, which is also the honest reading of
  "indefinitely": pursuit does not time out, it just needs you to actually get away.
- **The absence of a pathfinder is the feature.** docs/14 asks for a zombie that "will grind against a
  wall between them and you", and pointing the heading at the target produces exactly that for free —
  `movement.integrate`'s collision resolution stops the body while the heading keeps pointing. A
  pathfinder here would be the single change that makes them tactical.
- **AI must not read derived state that is missing from the save.** The first version asked
  `world.spatial.queryRadius`, which is the obvious tool and wrong twice. The hash is derived and
  deliberately excluded from the snapshot, so a freshly booted world that has had a save applied has an
  **empty** index rather than a stale one — and the first tick after a load found no contact where a
  continuous run found some. Within a run the one-tick staleness is harmless because it is identical for
  every shambler; across a save boundary it is a byte-level divergence. `melee.test.ts`'s mid-wind-up
  save assertion is what caught it.
  *The candidate sets were also the wrong way round: the hash indexes every body, so it answers "what
  is near me" and makes the caller filter, when the question is "which of the handful of survivors is
  near me". Walking survivors is cheaper and reads only saved state. The hash stays right for melee,
  which asks what is near a swing, where the candidate set genuinely is everybody.*
- **`ComponentStore.query` allocates and sorts, so it does not belong in a per-entity loop.** Asking it
  per shambler per tick is two thousand allocations and two thousand sorts a tick, and it put a
  *uniform* slowdown across every benchmark scenario — including ones with no pursuit in them, which is
  what gave it away. A cost that appears where the feature is absent is not the feature's cost. The
  survivor list is gathered once per tick instead; it cannot change mid-tick, so it is not a cache that
  can go stale.
- **A budget set from one measurement in one container is not a budget.** `crowded-and-lit` shipped at 4
  ms because it measured 2.54 once on a fast container, and "it holds its sightless twin's budget" was
  too good a claim to check twice. A worktree at the merge commit measures the *same code* at 3.75 avg
  and 4.41 p95 in a loaded one — 8% headroom, on a CI runner slower than either. Raised to 6 ms, with
  the honest reading written down: five hundred observers genuinely costs about 1.2 ms over the
  sightless twin, and docs/22 blesses visibility as a different cost shape. `crowded-and-watched` at
  fifty observers stays at 4 ms and remains the guard on recompute-on-change.
- **The backlog's own counts are a second copy of a fact, so a test asserts them.**
  `test/unit/handoff.test.ts` checks that every `**Done (n):**` / `**Open (n):**` header matches the
  checkboxes beneath it, that no ticked box sits in an `Open` group, and that the milestone table's rows
  sum to its total. It exists because the counts drifted within one session of being written — ticking
  four boxes left them filed under `Open` — which is the same class of drift that deleting `TODO.md` was
  meant to end. `npm run handoff:regroup` is the fixer, and it is idempotent. *(2026-08: the test,
  the fixer, and HANDOFF.md itself were all retired; condensed status now lives in docs/23 and the
  itemised record in git history.)*

## What the stance ladder and the condition view made structural

- **`move_speed` had no reader, and the modifier that wrote to it did nothing.** The stat has been
  registered since the modifier pipeline landed, and `inventory.encumbrance` has been writing a speed
  penalty to it since the grid landed — but `movement.integrate` never consulted the stat registry, so
  an overloaded survivor resolved to a lower speed and then walked at exactly the same pace as an
  empty-handed one. `inventory.test.ts` asserted `resolve("move_speed")` came back lower and passed the
  whole time, which is the shape of the bug worth remembering: **a test that asserts the mechanism
  instead of the effect will pass through the effect being absent.** The integration test now walks two
  survivors and compares the ground they cover.
  *One line fixed it, and it paid for three things at once: encumbrance became real, the shambler's
  `CRAWL_SPEED_FACTOR` stopped being a hand-applied multiply on the velocity and became a named
  `injury.crippled` modifier, and docs/29's six speed sources — legs, feet, pain, exhaustion,
  encumbrance, limp — got somewhere to write that `explain()` can answer for.*
- **A stance is a decision about the attention field, so noise comes from the rung and not from the
  speed.** The two disagree, and the disagreement is the point: the surface layer slows a jogging body
  below a walking pace, and a survivor who got quieter by wading into undergrowth would be reading the
  wrong number. Emission asks `Posture` when the body has one and falls back to `SPRINT_THRESHOLD` when
  it does not — which is not a legacy path, because a shambler has no stances and a generator has no
  speed.
- **The tick that empties the transition clock is the tick the rung changes on.** Written the other way
  round — decrement, `continue`, step on the next pass — every rung silently cost
  `STANCE_CHANGE_TICKS + 1` ticks and `stanceChangeTicks()` was lying about the price by 25%. Caught by
  a test that used the helper to decide how long to step, which is the argument for having tests take
  their timings from the code rather than from a literal.
- **Abandoning a wind-up keys off the *decision* to sprint, not the arrival.** docs/09 says breaking
  into a sprint abandons a wind-up, "which is what makes running away mid-swing a decision" — and a
  bat's wind-up is shorter than the eight ticks the walk-to-sprint transition takes, so reading the
  current rung alone would have let the blow land every time and the rule would never have fired once.
  A capability is therefore asked of both the rung a body is on and the rung it is heading for.
- **Exhaustion takes the fast rungs away and leaves the slow one.** docs/29 wants "sprint becomes
  unavailable before it becomes slow", so an empty pool drops jog and sprint to a walk rather than
  scaling them. **Crawl is deliberately exempt**: it is "the last resort that is not running" and the
  verb left to a survivor whose legs are gone, so being too tired to crawl further has to mean lying
  still rather than standing up into the thing you were crawling away from.
- **`Eye.Crouched` was threaded end to end a milestone before anything could ask for it, and the bet
  paid.** `map/tilemap.ts` shipped the parameter with a comment saying stances were not built and
  nothing set it, on the argument that the alternative was re-threading the visibility primitive the
  day they arrived. The day they arrived it cost one assignment — and **no cache invalidation at all**,
  because `VisibilityIndex.refresh` already keys on `observer.eye`. Writing the field *is* the
  invalidation.
- **Low cover cuts both ways for free, because sight is symmetric.** `shadowcast` is built so that if A
  sees B, B sees A, so a crouched survivor behind a car cannot see over it and cannot be seen over it
  from the same predicate. There is no second rule, and there is no way to get one direction without
  the other — which is why the test asserts both halves in one place. A test checking one half is how
  the two directions come to drift apart.
- **A survivor has six body parts and a zombie has three, and that asymmetry is the design.** docs/14
  wants three *because* three is what makes a zombie a zombie: a torso that never kills, a head that is
  instant, legs that make a different and quieter threat. A fourth would dilute a distribution that says
  exactly what it means. docs/05 wants six because it answers a different question — not "how do I stop
  this thing" but "what is wrong with this person and what does it cost them", and arms, hands and feet
  are the parts whose loss costs work rather than life. Two vocabularies, one seam: `attack.connected`
  carries a part name and the health module looks it up on whatever body the target has.
  *The hit-location roll consumes exactly one number from the stream either way. The shape of the
  distribution moved; the shape of the stream did not, which is what kept determinism intact.*
- **The condition view's ban on numbers is enforced by the snapshot, not by discipline.**
  `conditionView` hands over a `PartState` and a sentence per part and nothing a fill could be computed
  from — no integrity, no maximum, no fraction. docs/05 says the design "is most likely to be talked
  into a health bar" here, and **the cheapest way to keep a bar out of a screen is to make the screen
  unable to draw one**. `paperdoll.test.ts` serialises the view and asserts no part's maximum and no
  decimal appears in it, so a future field carrying `40` for the torso fails at the boundary rather
  than turning up as a bar six months later.
- **`Unhurt` means undamaged, with no tolerance band.** The first threshold was 0.99, which is the kind
  of number that looks careful and makes the first scratch invisible. The whole argument for prose over
  a bar is that it says *something happened here* before it says how much.
- **One body, drawn at two sizes, rather than two bodies.** The paperdoll calls the same
  `drawHumanoid` the district does, with a larger zoom and a per-region tint map — because the
  paperdoll's entire claim is that it is a picture of *this survivor*, and a second figure drawn by a
  second function is one that will eventually disagree with the street about what crouching looks like.
  The world sprite supplies no tint and is unchanged byte for byte: located conditions belong on the
  condition view, and a survivor whose bad leg was amber out in the street would be a health bar with
  extra steps.
- **The stance ladder cost the pose sheet one row, not five.** `pose.ts` predicted docs/29's five
  stances would each become an entry. Crawl already had a pose, and walk, jog and sprint differ by
  *pace* rather than by posture — a jog is a walk whose phase advances faster, which is a number rather
  than a silhouette. Only `Crouch` was a new shape. The sheet went from 336 cells to 384, and its guard
  now derives that count from `FRAMES_PER_ARCHETYPE` instead of restating it.
- **The player-facing readout goes *inside* the frame budget; the developer readout stays outside it.**
  `main.ts` keeps the HUD in the DOM so the HUD is not inside the budget it exists to measure. The
  condition glimpse is the mirror of that argument: it is for the player, so its cost is cost the game
  owes, and it draws on the canvas over the night wash — over, because a readout the dark can take is
  not a replacement for a health bar. Measured at 1.45 ms average draw against a 4 ms budget.

## What grabs and bite risk made structural

- **Pursuit contact and physical grab range are different facts.** A shambler notices and commits at
  1.6 m, but it cannot hold a survivor until 1.0 m. Using one radius for both erased weapon reach:
  the 1.4 m bat and 0.9 m knife were interrupted before their first blow. The split preserves the
  intended identities -- knife risky, bat dependent on spacing, spear safest.
- **Melee exposure is physical, never an invisible counterattack roll.** Reach and stagger buy real
  safety. A bite comes from remaining in a hold, first after 1.5 seconds and every 2 seconds after,
  rather than from an unrelated chance attached to every successful hit.
- **More grabbers diminish escape without declaring it impossible.** Escape is
  `escapePower / (escapePower + totalGrabStrength)`: default one/two/three-shambler chances are
  two-thirds, one-half, and two-fifths. Escape power is fixed at one today; Strength can raise that
  side later without rewriting the contest.
- **Wound truth, visible presentation, and transmission are three separate facts.** Every landed bite
  is stored as a bite, 30% present as scratches, and an independent named stream decides the private
  85% transmission flag at wound time. The condition boundary receives presentation only. All three
  ride the save, which is why save format 10 exists.
- **Milestone 1 owns the irreversible decision, not the disease game.** The infection module records
  exposure and stops. Symptoms, diagnosis, treatment, armor reduction, stages, and turning remain
  Milestone 2 rather than arriving as speculative scaffolding behind one bite.

## What the outline figure changed

- *(Note from the top-down reversal, 2026-08: the "hostile camera" premise below is moot -- the
  world view is now flat too. The paperdoll stays exactly as it is, because the argument that
  actually decided it was never the camera but the job: a readout whose purpose is to say **which
  part** wants a face-on diagram with every part in the same place every time, and no world
  camera, isometric or top-down, is that diagram.)*
- **The paperdoll is a diagram now, not a portrait, and the reason is the camera.** The record
  above — "one body, drawn at two sizes, rather than two bodies" — is reversed here on purpose, so
  it is worth being precise about what was wrong with it. The argument for reusing `drawHumanoid`
  was that a second figure would eventually disagree with the street about what crouching looks
  like. What it did not weigh is that the street's camera is *hostile to the paperdoll's one job*:
  an isometric projection puts the far arm behind the torso, foreshortens the legs by half, and
  lays a prone body up-screen. A readout whose entire purpose is to say **which part** cannot be
  drawn by a camera that hides parts. The figure is now `render/sprites/outline.ts`: an anonymous
  human seen flat on, stroked rather than filled, with all six of docs/05's parts visible in every
  posture and each in the same place every time.
- **The agreement the old record was protecting survives, one level down.** The two pictures no
  longer share a *function*; they share the **predicate** and the **fractions**. `poseForStance` is
  still the only answer to "is this body low", and it still reads `stanceSpec(stance).eye`, so the
  panel cannot draw a crouch the shadowcast does not believe in. `CROUCH_HEIGHT_FRACTION` and
  `CRAWL_HEIGHT_FRACTION` are imported from the world rig rather than copied. That is a *weaker*
  coupling than a shared function and it is the right one: what the two figures must agree about is
  the simulation, not the geometry.
- **Prone is a rotation, not a second silhouette — and the world rig is right to do the opposite.**
  docs/14 wants a crawler in the district to be a distinct low shape, because a scaled-down
  standing body under an isometric camera does not read as prone. On a flat diagram there is
  nothing to scale down: a person turned a quarter turn *is* what lying down looks like from above.
  So the outline has one set of proportions and one figure, and the posture that used to need its
  own silhouette is a change of frame. Two sets of six parts to keep in agreement became one.
- **The test got to make the obvious assertion again.** The old posture test compared a crouch by
  height and prone by *shape*, with a paragraph explaining that a crawler's topmost ink legitimately
  sits above a crouch's under the district's camera. That paragraph was a projection leaking into a
  readout's test. It now asserts what a player sees: prone lower than crouched, crouched lower than
  standing, and prone longer than it is tall.
- **An unhurt body draws no fill at all**, which is the strongest form docs/05's "colour, never
  fill" has taken yet. The figure is line art; a hurt part is filled in its state's tint and an
  unhurt one is not. So on a healthy survivor the screen issues *zero* fill operations on the body
  — there is nothing on it for a fill *level* to grow out of, and `paperdoll.test.ts` asserts that
  emptiness rather than trusting it.
- **The corner is measured off the figure's box, not off its height.** A prone survivor is wider
  than a standing one is tall, and the glimpse's old anchor — derived from the zoom — put a
  crawler's hands off the edge of the viewport. `outlineMetrics` sizes the box around the widest
  posture and both tiers lay out against it, which is the same lesson `cellMetrics` learned from
  the crawler's shadow. Measured at 1.73 ms average draw against the 4 ms budget.

## What the Godot rebuild decision made structural

- **The product roadmap survives the engine change.** Milestones 0 and 1 remain complete as behavior;
  the rebuild reproduces them and returns to Milestone 2 at lethality. Engine work has its own
  [transition roadmap](31-godot-rebuild-roadmap.md) so implementation phases cannot silently reorder
  product scope.
- **This is a clean Godot rebuild with an oracle, not a syntax port and not a blank slate.** Native
  presentation is rebuilt for Godot. The TypeScript game, its seeds, command logs, snapshots, tests,
  and measured behavior remain authoritative evidence until cutover.
- **Parity gates decide authority.** A Godot screen that resembles the current game is a candidate,
  not the replacement. Determinism, content, saves, acceptance behavior, performance, web delivery,
  and the five-minute playable loop all have explicit gates.
- **Product feature development pauses at the current boundary.** Critical fixes to the oracle are
  allowed; new Milestone 2 mechanics wait until cutover so two versions never need simultaneous
  feature development.
- **The TypeScript runtime is temporary after approval but indispensable before cutover.** It remains
  playable at the public root, with the Godot candidate beside it, until the replacement is proven.
  After cutover there is one shipping runtime, plus a tag and fixtures for historical comparison.
- **R0 is approved and reproducible.** The rebuild uses typed GDScript on exact Godot 4.7.1,
  Compatibility rendering, Web plus Windows, and `godot/` as the project root in this repository.
  The TypeScript public build remains at `/`; the Godot candidate will live at `/godot/` until
  cutover. Pre-1.0 player saves do not receive a cross-engine migration layer.
- **The parity seed is an executable contract, not a prose promise.** The canonical R1 fixture lives
  inside the exportable Godot project, the TypeScript oracle writes its expected snapshot, and the
  Godot headless run compares against it with an explicit float tolerance. Windows and web artifacts
  must build and boot; drawing a similar grid is not enough.

## What the stats MVP made structural

- **Aptitudes are a component plus modifier sources, never body-max edits.** STR/CON/DEX live on
  `aptitudes` and write `attr.str` / `attr.dex` / `attr.con` into `SimModifiers`. Adding INT/CHA/WIS
  later is a new stat def plus a missing-key default of 5 — old saves do not need a rewrite.
- **`infection_progression` is a rate.** High CON *lowers* the rate so `duration = base / rate`
  lengthens the timeline (docs/06, docs/23). The wayfinder table's `+0.05` sign would have shortened
  it; the lengthens prose wins.
- **Grab escape keeps the shipped 2/3 baseline.** `grab_escape` base is 1.0 (oracle
  `BASE_ESCAPE_POWER`), STR adds ±0.10/pt. Ticket 02's 0.50 was the shambler term, not the numerator.
- **DEX cannot be stealth.** Footstep magnitude scales by the same `move_speed` factor as locomotion,
  so noise-per-metre stays put when someone is simply faster.
- **Uniques are content.** `SimSurvivors.spawn_unique` walks `survivors/uniques/`; another JSON is
  another person. The generator remains unbuilt.

## What the alpha roster/district/ranged slice made structural

- **Playable boot is `SimBoot.playable()`, not the R1 fixture.** `main.gd` generates the 256 m
  district, blits `map.district.alpha`, and registers kernel field/vision. Parity scripts still
  construct `World.new(fixture)` with no extra modules. Pass `--parity` to force the walking
  skeleton in the main scene.
- **Overlay is blit, not a generator fork.** `SimTileMap.apply_patch` copies rect arrays only.
  `r1-walking-skeleton` stays byte-identical because it never calls `apply_patch`.
- **`noise.emitted` reaches the field through kernel subscribers**, not the attention module.
  Screamer 300 and pistol 180 share that path. Tests that never `attach_kernel` will see the
  event and a silent field.
- **Exhausted swings degrade.** `REFUSE_EXHAUSTED_SWINGS` keeps the old refuse path for a
  `crowded-and-swinging` A/B; default is off.

## What the sided-limb split made structural

- **Survivor limbs are sided.** `SimCombat.SURVIVOR_BODY_PARTS` grew from six parts to ten —
  head, torso, and a left/right pair each of arms, hands, legs, feet. Prompted by a UI review of
  the paperdoll surfacing a real gap: docs/05's permanent consequences already promised "a
  one-armed survivor," an outcome the previous single aggregate `arms` value could not produce,
  since amputating it took both arms at once. This is design catching up to its own prose, not a
  new feature.
- **Per-limb toughness, not per-limb weight.** Each side keeps the whole limb's old integrity
  (`arm_left`/`arm_right` are each still 20, not 10) so one connecting hit costs what it always
  did. `SURVIVOR_HIT_LOCATION_WEIGHTS` is what halves — the chance of hitting *an* arm is
  unchanged, only which one is now recorded.
- **One sentinel for "is this a survivor body."** `SimHealth.is_survivor_body()` replaced three
  separate `body.has("arms")` checks in melee and health. A body's shape is checked in one place
  so it only has to be updated in one place next time it changes.
- **Crawling needs both legs; a bad leg is a limp.** `is_crawling()` requires `leg_left` and
  `leg_right` to both be spent for a survivor — a single ruined leg is the permanent-limp
  consequence docs/05 already named, not the "can no longer stand" one.
- **Bumped `SAVE_VERSION` to 13, not migrated.** A v12 body dict has the old key names and would
  silently mismatch every part lookup rather than fail loudly. `save.gd` already declines to
  migrate pre-1.0 saves, so the version bump is the whole fix.
- **`check_m2_save.gd` and `check_m2_fortify.gd` each assert `SAVE_VERSION` independently.**
  Updating one and not the other is exactly how this was caught mid-review, by `godot:r6`
  rather than by inspection. Left duplicated rather than refactored under this change; a real
  fix is one shared assertion both gates call, not two copies kept in sync by discipline.

## What the backlog audit made structural

- **The backlog counts were wrong by roughly a third, and no guard could see it.**
  Milestone 2 read 33 done / 77 open; auditing every checkbox against the gates and modules
  put it at 67 / 43. Building, Director, Death & succession, Survivors, Needs, Skill web,
  Combat and Items each listed shipped, gated features as open — `M2_FORTIFY_OK`,
  `M2_DIRECTOR_OK` and the rest had been green for sessions while the document said
  otherwise. Nothing was built to move the number.
- **`handoff.test.ts` checked arithmetic, not truth.** Every stale item passed it, because
  they were correctly *counted* as open and merely wrong about the code. A document can be
  internally consistent and externally false, and that is the failure mode that actually
  happened — four times.
- **Evidence per box is what makes an audit possible.** Most `[x]` items already carried an
  italic note naming the gate or file, which is the only reason this audit was tractable
  rather than archaeology. `check_handoff.gd` required it for Milestone 2, so a tick was
  a falsifiable claim instead of an assertion taken on faith. It could not verify truth —
  nothing cheap can — but it put the next reader one `npm run` from checking. *(2026-08: gate
  retired with HANDOFF.md; the evidence-per-claim rule carries on in docs/23's status section,
  where every "landed" names its gate.)*
- **Scoped to the live milestone.** Milestones 0 and 1 are closed and their boxes predate the
  convention; the first draft of the gate demanded 41 retrofitted notes on finished work.
  Drift only matters where the work is still moving.
- **Partial work stays open with a note saying which half.** "Colony morale hit; work
  priorities cleared" is half shipped — `_make_corpse` clears `jobPriorities`, nothing
  applies grief — so it stays `[ ]` and says so. Rounding a half-done item up is how the
  count drifts in the honest direction next time.
- **The guard caught its author mid-audit.** Three boxes were ticked in place rather than
  moved into their `Done` group — exactly the drift the counts exist to catch — and
  `_no_checkbox_is_misfiled` flagged all three before the commit.

## What the paperdoll revamp made structural

- **`condition.gd` gained three fields, all words or booleans.** `wounded`, `infected`, and
  `armored` join `part`/`state`/`prose`. Each was chosen because it structurally cannot become
  a number: `wounded` says a wound was recorded, not which kind or how many; `infected` is
  `diagnosis_of_part`'s `actionable` word, the same non-leaking read the HUD already uses,
  never a stage integer and never `transmitted`; `armored` says coverage is greater than zero,
  never the coverage fraction. A part with several things true draws several marks — the ban
  holds by construction, not by the paperdoll choosing to be tasteful about it.
- **`diagnosis_of` and `diagnosis_of_part` share one stage-to-label function.** The pre-split
  `diagnosis_of` had its `match worst: ...` block inline; adding a per-part variant by copying
  that block would have been the same mistake the `SAVE_VERSION` duplication above already made
  once this session. `_diagnosis_for_stage()` is now the one place a stage becomes a sentence,
  and both callers use it.
- **`armor_coverage_of` is public.** It was `_armor_coverage`, called only from the bite-landed
  handler. The paperdoll needed the same "is this part protected" fact without a second
  implementation reading `equipped_items` and an item's `armor` dict — the underscore was a
  convention, not a boundary, so the fix was a rename, not a rewrite.
- **The figure faces the viewer.** Screen-left is the person's right, screen-right their left —
  the same convention every anatomical chart and paperdoll UI uses. Named once in `SIDE_NAME`
  rather than re-decided at each of the eight limb-drawing call sites, and irrelevant to
  gameplay today since nothing selects a limb by clicking the figure.
- **Armour is a stroke, not a second fill.** A protected part keeps its condition tint (the fill)
  and gets a distinct, thicker outline over it. Two colours competing for the same fill would
  have forced a choice between showing you *how hurt* and *how protected* a part is; the stroke
  says both without picking.

## What aid-while-held made structural

The rule "you cannot channel while `grabbed`" was one clause and read as obviously right. It cost a
colony: the balance harness measured a held survivor spending two thirds of their life bleeding and
forbidden from answering it, and both wiped seeds wiping by blood loss. Relaxing it turned out not
to be a one-line change, because a hold and a channel had been mutually exclusive and now meet.

- **The exemption is derived, never passed.** `_can_channel(world, entity, self_pressure)` looks
  like a caller-supplied override and deliberately is not: every call site computes the flag from
  the verb and the patient (`verb == "pressure" and actor == patient`), and the per-tick re-check
  re-derives it from the running channel's own state rather than remembering what was granted at
  begin-time. So the only thing the parameter can ever unlock is a hand on the actor's own wound,
  and a channel cannot carry a permission it would no longer be granted. It defaults to `false`,
  which is the safe direction for any future caller that forgets to say.
- **Seven rules, written down, each gate-asserted.** R1 the exemption; R2 `grab.started` cancelling
  everything it touches *except* the victim's own self-pressure; R3 a stagger still cancelling
  everything; R4 struggle and press coexisting; R5 becoming fully free cancelling your own
  self-pressure and only that; R6 self-aid deferring while a break-away runs; R7 `context()`
  forcing `pressure` while held. They
  are enumerated in `treatment.gd`'s header rather than left to be inferred from four subscriptions
  and a pin, because inferring them is exactly how the two systems would drift apart.
- **A grab is no longer the same event as a stagger.** They shared `_interrupt`; they now do not,
  and `_interrupt_grab` is a separate function for a reason that is fiction as much as mechanism.
  Being knocked off your feet takes your hand off your own arm. A second set of hands closing on
  you does not.
- **R4 was decided by arithmetic, not taste.** "Pressing is your action, so you cannot struggle"
  was costed first: every hold resets the bite clock, an NPC struggle cycle resolves in ~17–33
  ticks, so a press that suppressed struggling takes roughly five bites across a 400-tick deep-wound
  press and never ends. "Struggle cancels the press" banks ≤25-tick fragments against 100/200/400-
  tick channels, which is nothing. Coexistence is the only one of the three that produces a
  survivor who both stops bleeding and gets out.
- **R7 exists because a read model that lies about legality is worse than no read model.** Without
  it a held survivor carrying a sterile dressing picks `bandage` every tick, is refused by R1 every
  tick, and bleeds to death with the answer in their pack. A picker has to know what is actually
  legal.
- **`fortify.gd` keeps its own unexempted `_can_channel`.** Boarding a window with a zombie on your
  arm stays exactly as illegal as it sounds. The two copies were already separate; that they now
  say different things is the point, not drift.
- **R5 was inverted on a measurement, and the inversion is the point of writing rules down.** As
  first shipped, R5 said a press already paid for outranked a break-away: tear free mid-press and
  `treatment.pin`'s zero landed after `shambler.pin`'s run, so you stayed on the wound. It is
  defensible in isolation — a wound you are holding closed should slow you down — and in play it
  cancelled the break-away speed fix landed in the same slice for exactly the survivors using the
  aid: 94 of 120 escapes on seed 404 were mid-press, 89 of the 91 following re-grab windows were
  exactly `REGRAB_COOLDOWN_TICKS` with none above, and total grabs rose. R5 now says the opposite —
  `grab.broken` cancels the victim's own self-pressure — and the reason it is a *clean* inversion
  rather than a new special case is the symmetry with R2, which is the whole arbitration in two
  lines:

  > `grab.started` cancels everything touching the victim **except** their own self-pressure.
  > `grab.broken` cancels **only** their own self-pressure.

  A second set of hands closing does not peel your palm off your arm; becoming free is what takes
  it off, because that is the moment you have somewhere to be. Both handlers are aimed at one named
  entity rather than at a situation, which is why a free treater's dressing on a patient who tears
  loose survives — that patient has stopped being dragged, so the channel is *more* viable than it
  was, and reach is re-checked every tick anyway.
- **The drain ordering was designed around rather than engineered away.** `grab.broken` is published
  inside the escape tick and handlers run at `drain()`, at the end of `world.step()`, so on that one
  tick the press still exists and still pins the escapee — flight begins the tick after. Moving the
  cancel earlier would have meant either publishing outside the event bus or giving one module a
  privileged same-tick path, both of which trade a working rule for a special case. The tick costs
  0.105 m of gap, and the gate asserts movement from the tick after release: CLAUDE.md already
  records that an event published into a tick lands after that tick's systems have run, and the
  instruction is to write the test around it rather than tolerate a fudge factor inside the
  measurement.
- **What the inversion cost, and why it did not flip the flag.** The fragments arithmetic that
  decided R4 decides this too, in the other direction. A press cancelled at every escape banks
  nothing, so a 400-tick deep-wound press has exactly two completion paths: one unbroken 400-tick
  hold, which the cycle length makes vanishingly unlikely, or free and clear after the colony kills
  or sheds the holder. Measured across four seeds, neither happened once — presses completed went
  from 25/9/26 to zero — while grabs and bites fell by about a third. Fewer holds, no clotting, and
  the net on survival was negative. The rule stands because the alternative was measured to be worse
  for the lever it blocks, not because it made the colony live.
- **A break-away's heading is a preference, not a commitment.** The residual the inversion left
  behind was a locomotion bug wearing a design call's clothes. `_break_away` pointed *straight*
  away from the holder and committed; a colony is grabbed where a colony lives, which is against
  the annex walls, so it pointed into masonry and `_integrate_movement` zeroed a blocked axis — 86%
  of break-away ticks blocked on both axes on seed 404, 0.010 m covered per tick against a nominal
  0.105. It now fans out from straight-away and takes the nearest heading with a clear run, which
  keeps everything the shove-off was (one heading, taken once, no per-tick re-derive, no RNG, no
  pursuit solver) and changes only which one. Ground per tick went to 0.104, and 90210 became the
  first hard seed to stop wiping. The negative in AWAY-CLEAR is the load-bearing half: in open
  field the committed heading must still be straight-away *exactly*, so the fan cannot quietly
  re-aim every escape in the game.
- **R8 reverses "a partial press buys nothing", and the reversal is the same discipline that
  produced R5.** The original rule was deliberate and is quoted in `check_m2_treatment.gd`'s
  header: pressure was worth nothing until finished, and the assertion existed specifically to
  fail if a partial hold ever banked. R5's inversion is what made it untenable — once the escape
  cancels the press, a 400-tick deep-wound press has no reachable completion path while holds
  arrive every ~50 ticks, and the harness measured exactly that: 126 presses begun and **zero**
  completed across ten compressed days of 404, all three deaths blood loss. R8 banks the served
  ticks **on the wound**, not on the presser, so whoever picks the press up next inherits it; a
  medic finishing what the patient started with their own hand is the same wound getting the same
  total pressure, and the sim has no reason to care whose palm it was. Two exceptions carry the
  cost: a **stagger** banks nothing (R3 already singles it out as the one thing that takes your
  hand off your own arm, and this is what makes that rule mean something), and **bandaging never
  banks** (a dressing is applied, not accumulated, and it spends a supply at completion). The bank
  does not decay — pressure that has been held is progress toward a clot, and a decay clock would
  be a second timer nothing else in the module has — but it is cleared at completion and at
  `SimWounds.reopen`, because a wound torn back open is not the wound that was pressed.
- **What is still between the loop and the flip.** Both changes above are net positive and
  measured, and neither is enough. `GRABS_ENABLED` stays `false` because seed 404 still ends `0/2`;
  docs/23 carries the seed-by-seed numbers. What is left is no longer a bug but the shape of the
  colony: a two-person colony spread across a district cannot answer the contact rate the district
  produces. The "rescue can never reach" finding was **re-measured rather than repeated**, and it
  has partly dissolved — with escapees covering ground, a free colonist now comes within
  `RESCUE_METRES` for 135 ticks on 90210 and 18 on 31337, where nothing came inside 6 m before. On
  404 it still never does. That is a call about how the slice seats its people, not another lever
  in the contact loop.

## Pain is derived; painkillers are the trap working

- **Pain is a pure function of the wound list, never stored.** A cached total is one more thing
  that can disagree with the wounds it summarises, and it would have to be saved, restored, and
  kept in step with every path that adds, closes or reopens a wound. Deriving it costs a loop over
  a handful of dictionaries and cannot drift.
- **`pain_of` and `raw_pain_of` are both public, on purpose.** docs/05's whole argument about
  painkillers is that what a survivor *feels* and how hurt they *are* come apart. Code that asks
  "how impaired is this person" wants the first; code that asks "how bad is this actually" wants
  the second. One function with a flag would have made every call site decide, badly.
- **Suppression is strong enough to be worth taking.** A weak dose would make painkillers a
  rounding error and the tactical option would not exist. docs/05 wants them to be genuinely useful
  *and* a way to get someone killed, and the second only follows from the first.
- **The exhaustion mood cost is deliberately small.** It stacks with the need sources and with the
  mood bands landed earlier this milestone, and a large one would push an ordinary hard day into
  the miserable band — which starts sulks and arguments. "Worked hard today" is not what that band
  is for, and the gate asserts an empty tank alone stays clear of it.
- **Work speed is not a modifier, so it is not in the modifier pass.** `needs.work_mul` is a plain
  multiplier read directly by the walk and the job tick, so pain's and exhaustion's contributions
  to it live there while their contributions to accuracy, swing and mood live with the other
  modifiers. Splitting one condition across two mechanisms is not ideal; putting a non-modifier
  into the modifier pipeline to avoid it would be worse.
- **A gate correctly failed on correct behaviour, and the gate was what changed.** The concussion
  assertion from the previous slice asserted that an ordinary head cut changes *nothing* about
  reactions. Once pain landed, every wound slows reactions a little, so that control went red on a
  change that was right. It is now a magnitude comparison — and a conservative one, because a
  concussion carries *less* pain than a cut of the same severity and still has to come out slower.

## `kind` became a table, because four injuries are not severities

- **The three shipped injuries were severities of one wound; the four remaining are not.** Scratch,
  Laceration and Deep wound differ only in how much integrity was lost, so a single bleeding wound
  with a severity band covered all three and `kind` could stay a label ("cut" / "bite"). Fracture,
  sprain, burn and concussion break that: they are not primarily bleeding, their recovery does not
  track severity (a sprain heals faster than a laceration; a fracture takes an order of magnitude
  longer than a deep wound), and two of them impair far beyond their band. So `WOUND_KINDS` is one
  row per kind and every consumer reads it.
- **One table rather than four branches.** `append_wound`, the recovery tick, the impairment pass
  and the sepsis roll all ask the kind. Spread as `if kind == "fracture"` checks, the bleed rate
  and the clot clock would eventually disagree about what a fracture is — the same argument that
  put the loot roller in one file and the shambler's speed behind one accessor.
- **A kind nothing produces is content, not a feature.** Each of the four gets exactly one
  reachable cause from docs/05's own Cause column, and none needed a new subsystem: three ride
  events that already fire and one rides a state change `world.gd` already makes. The burn cause is
  another connected socket — `infection.gd` had published `injury.sustained/burn` since cauterise
  was written and nothing listened, so searing a bite left no mark on the arm it seared.
- **`world.gd` publishes the collapse; `wounds.gd` decides it is a sprain.** The zero-stamina sprint
  demotion is exhaustion, which docs/05 lists as a sprain cause, but world.gd must not grow a
  dependency on a module. It announces; whoever cares subscribes.
- **The perception half of a concussion is deliberately not faked.** docs/05 asks for "reaction and
  perception loss". Reactions map onto `swing_speed` and `ranged_accuracy`, which exist. Perception
  has no seam — vision is a shadowcast with no modifier hook, and "blurred description text" is a
  presentation channel that does not exist. Adding a stat nothing else reads, purely so the row
  could list three keys, would be a modifier that *looks* wired and is not, which is the exact
  failure three other slices this run were spent undoing.

## Sepsis: a socket connected, and deliberately not lethal yet

- **It was a socket, not a gap.** `needs.gd` published `sepsis.checked` with a hygiene multiplier
  every dusk and nothing subscribed to it — `sepsis_mul` was gated, correct, and reached no wound.
  That is the third one this run (the shambler's `crawlFactor` and `Staggered` state were the
  others), which is enough of a pattern to name: a gate that asserts a *helper* returns the right
  number does not assert anything reads it.
- **All four factors in one expression.** docs/05 drives the probability from severity, hygiene,
  cleanliness of the dressing, and treatment skill; `sepsis_chance` takes all four, so no caller
  can apply three of them. An undressed wound is worse than a dirty rag, which is what makes a bad
  dressing better than none.
- **The roll lives with the wound, the hygiene stays with needs.** `wounds.gd` owns the record and
  the recovery clock sepsis has to block, so the roll is there; `needs.gd` owns hygiene, so it
  computes the multiplier and hands it over rather than having wounds reach across and re-derive
  it.
- **Antibiotics accept a septic survivor with no bite at all.** This is docs/05's first consequence
  made mechanical — "the finite, uncraftable supply that saves someone from a bite is the same
  supply that saves someone from a dirty laceration" — and it has a second effect that matters
  more: refusing would let the player distinguish sepsis from a bite by which verb was legal, which
  is exactly the ambiguity the separation exists to create. `_spend_one_course` is shared rather
  than copied, because two implementations of "take one off the stack" is how one finite supply
  becomes two.
- **The sepsis cure is deterministic where the zombie-infection one is a roll.** docs/05 has
  bacterial infection as the treatable one and zombie infection as the gamble, and that asymmetry
  is most of why the two are worth keeping apart.
- **Not lethal in Milestone 2, on purpose.** Sepsis is debilitating and permanent until treated: a
  septic wound stops healing entirely and clears only to antibiotics. That produces the budget pull
  docs/05 asks for without adding a death path to a lethality model whose balance is the thing
  currently standing between `GRABS_ENABLED` and its flip. Making sepsis kill is a balance decision
  with a measurement attached, and it should arrive with one.
- **One modifier per survivor, not one per infected wound.** Two septic wounds are a worse
  situation but not twice the fever, and stacking the source would make a survivor with four
  scratches unplayable for reasons nothing in docs/05 asks for.

## Food is content, and bad food has a consequence

- **The retired `FOOD` table is pinned by value in the gate.** Moving three foods from a GDScript
  dictionary into content is the kind of change that silently rebalances a diet, so
  `RETIRED_FOOD_TABLE` in `check_m2_needs.gd` holds the old numbers and asserts content still says
  them. The move is provably about *where* the numbers live. A later content edit that changes the
  diet will fail this and have to be deliberate about it.
- **Presence of the `food` block is what makes something edible.** `is_food` asks nothing else — no
  id prefix, no class check, no second list to keep in step. Adding a food is one block.
- **Illness is a third thing, not a reuse of the first two.** docs/23 keeps bacterial infection
  distinct from zombie infection; food poisoning is neither, so it is a bounded self-limiting bout
  in `needs.gd` rather than a stage in `infection.gd` or a use of the sepsis path. Nobody dies of
  it in Milestone 2. That is what lets it be a small thing that makes cooking worth the fuel,
  instead of a second lethality system to balance.
- **One authored number, two cases.** `illnessChance` is per food and multiplied by
  `SPOILED_ILLNESS_MUL` when the item has actually gone off, rather than authoring raw and spoiled
  chances separately. A content edit moves both together, which is the same reason the jam chance
  is derived from the condition band rather than written per weapon.
- **`iron_stomach` is immunity, not a discount.** It already zeroes the mood penalty; a trait that
  half-protects from two related things is harder to reason about than one that fully protects
  from both.

## A jam costs time, and the chance is not authored

- **The jam chance is derived from the condition *band*, not written down.** `JAM_CHANCE_BY_BAND`
  is keyed off `SimItems.condition_band` — the same function that produces the word the inventory
  screen shows for that item. That coupling is the point: a weapon the player is told is "failing"
  cannot be one that never jams, and docs/10's table ("49–20%: serious; firearms jam regularly") is
  the authority for both at once. Authoring a per-weapon `jamChance` would have let the two drift
  on the first content edit.
- **`jams` is a content flag rather than an inference.** It would have been easy to say "anything
  with a magazine can jam", but docs/09 and docs/11's Gun Oil both say *firearms*, and a bow has
  nothing to stovepipe. A flag also means adding a crossbow that does jam stays a data edit.
- **A jam costs time and nothing else.** The stuck round is not spent — it comes out during the
  clear — because docs/09 specifies exactly one cost ("clearing a jam takes longer than a reload")
  and an interruption that already costs more than a reload does not also need to eat ammunition.
  The weapon returns to Idle rather than resuming the shot: a jam that auto-resumed would be a
  pause, not a jam, and the decision to try again should be one somebody makes.
- **The clear time is a multiple of the weapon's own reload, not a constant.** "Longer than a
  reload" is the claim, so it is expressed as a relationship. A flat number would silently stop
  being longer the first time a firearm was given a slower reload.
- **The backlog's "content declares slots nothing reads" is the wrong half.** `slots` is in the
  item schema and *no content declares it either*, so attachments are a slice — content, a reader,
  and attachment items — rather than a hookup. docs/23 now says so.

## Mood consequences are a decline, not a cliff

- **A threshold was the shipped behaviour and it contradicted the spec.** Mood had one consequence
  — at `-80` the survivor left — and nothing between "fine" and "gone". docs/04 describes the
  opposite: "a slow, sour decline where the colony stops functioning ... more frightening and more
  recoverable than a dramatic break". A cliff at -80 *is* the dramatic break. Hence bands, each
  adding a consequence to the one below, read through one `SimNeeds.mood_band` so nothing compares
  against a mood number of its own.
- **Slower work is a skipped tick, not a multiplier.** `ticksLeft` is an integer countdown in
  seven places, and a 0.75× multiplier on an integer is a rounding argument waiting to happen. The
  skip is keyed off `world.tick`, so it needs no RNG at all — the mistake is the part that is a
  gamble, and it should be the only part.
- **Arguments are capped and decay, and that is the whole design.** An unbounded mood source would
  let two miserable survivors drive each other past the leave threshold in a few minutes and empty
  the colony, which is precisely the rage meltdown docs/04 rules out. Capped and draining, misery
  spreads and sticks without becoming a spiral you cannot pull out of. The damage is also
  deliberately **not symmetric** — the arguer loses nothing, because they are already miserable by
  precondition and charging both sides makes any two unhappy people a spiral.
- **Refusing jobs is a bounded sulk, not a priority threshold.** The obvious shape was "refuse
  anything ranked below N", and it does not work: the Auto preset ranks every column at 3, so any
  threshold refuses nothing or everything, and a survivor who downs tools entirely is the meltdown
  again. A sulk drops the current assignment, idles for a bounded span, and expires on its own.
- **Two things this slice found rather than introduced.** Job progress was seven copies of the same
  two-line countdown — six chances for a consequence to apply nearly everywhere and miss one, the
  same shape as the shambler speed reads. And hooking the refusal on `_pick` made it fire **exactly
  never** in a booted colony: an NPC takes a standing Guard job (`ticksLeft` 0, no completion) on
  the first tick and never picks again, so a gate that only asserted "a refusal is possible" would
  have passed a consequence no player could ever meet. It hooks `_tick_one` now, placed after the
  needs-seek branch so a sulking survivor still eats and sleeps — a refusal to work, not to live.

## Modification: what is data, what is code, and what stays a gamble

- **A consumable's operation is content; the operation itself is code.** docs/11 asks for exactly
  this split — "a modification consumable declares which operation it performs and against which
  item classes", and "adding a genuinely new operation is one entry in the
  modification-operations registry". So `modification: {operation, appliesTo}` is an item-base
  block and `SimModification.OPERATIONS` is the registry. The schema deliberately does **not**
  make `operation` an enum: the registry is the authority, and a duplicated list in JSON would
  drift from it. `check_mods.gd` asserts every declared operation is in the registry and every
  `appliesTo` class is one items actually have — neither of which a schema can express.
- **A reroll is unconditional.** It does not keep the better of the two outcomes and there is no
  confirmation step, because docs/11 is explicit that "using Duct Tape on a Field-Tested item with
  five good affixes might reroll the one you loved" *is* the mechanic. A reroll changes a tier and
  never the set of affixes — that is what separates it from a Scrap Kit and from the Solvent that
  will eventually strip.
- **Craft moves two different odds, and injured hands move one of them back.** docs/11 draws the
  distinction and this preserves it: Craft weights rolls toward higher affix *tiers* (a developed
  crafter gets better affixes, not more of them) and separately reduces the *failure* chance.
  Injured hands raise failure and **cancel** the tier bias rather than inverting it, so a good
  crafter working hurt is an ordinary one and never worse than a novice. Two destroyed hands are a
  refusal, not a penalty — "a wounded crafter should not be at the bench" read literally. Hands are
  compared as `SimHealth.part_state` values, never raw integrity: a hand maxes at 10 and a torso at
  40, which is the trap CLAUDE.md names.
- **The failure floor is load-bearing.** `MIN_FAILURE` stops an arbitrarily good crafter reaching
  certainty. docs/11's endpoint is "expensive control", not determinism, and a bench that cannot
  fail is not a gamble.
- **Breaking is reachable only from a degraded item.** A failure costs condition; a failure below
  `CRITICAL_BELOW` zeroes the item *and its ceiling*, so repair cannot bring it back. Gating it on
  prior degradation means a fresh find is never one bad roll from scrap, which keeps the tension in
  "do I risk the axe I like" rather than in "do I dare touch anything".
- **Two gaps this slice exposed rather than created.** An item's tier was rolled at spawn, used to
  decide affix count, and discarded — so nothing could afterwards ask how many slots an item has,
  which is the one question a Scrap Kit must answer. It is an `itemTier` component now. And there
  was no way to re-derive an item's modifiers after editing its affixes;
  `SimItems.reapply_affix_modifiers` removes **by affix source** rather than clearing the item's
  modifier scope, because the scope can hold modifiers this module did not put there.

## What a place yields is content, not code

- **Loot tables moved out of `boot.gd`, for the same reason appearance moved out of the draw
  loop.** docs/12 already said resources, location loot tables and spoilage rules are JSON, and
  that "rebalancing the whole economy is a data pass with no code change" — while the code had two
  `const` arrays, `RESIDENTIAL_KITS` cycled round-robin and a single `MILITARY_KIT`, with the ammo
  counts as an `if` on the item id inside the placement loop. Adding a location type was a new
  branch. It is now `content/loot/tables.json` against `loot.schema.json`, and adding a school or
  a marina is one entry plus map tagging.
- **The tier is a property of the place.** `tierWeights` per table replaces `SimItems.roll_tier`'s
  global distribution for placed loot, which is what makes docs/12's risk gradient mean anything:
  a military cache rolls 1.000 above `scavenged`, a house 0.141, and a table declaring no weights
  falls back to the global 0.304 — the three measured in `TIER-BY-PLACE`, where the fallback
  sitting *between* the other two is what proves the counter is reading the weights rather than
  the seed.
- **New randomness gets its own stream.** Table rolls draw from `lootTable`, not the `loot` stream
  `SimItems.spawn_item` takes tiers from. Sharing one would make every table edit shift the tier
  sequence for everything spawned afterwards, which is a determinism footgun for anything
  measuring across such a change.
- **The gate exists because the validator is shallow, and it paid for itself on the first run.**
  `content_validator.gd` checks top-level types and rejects unexpected top-level keys; it does not
  recurse, so nothing inside `entries`, `rolls` or `tierWeights` is schema-enforced — the same hole
  a wrong key sat in inside `item.wrap.cloth`'s armor block for weeks. `check_loot.gd` found three
  things nobody was looking for on its first run: `_roll_range` passed `hi + 1` to an `int_range`
  that is inclusive on **both** ends and so rolled one over every declared maximum; and the siting
  check, run against a 64-tile test map, reported the district's far half as masonry, which is
  `world.is_blocked_tile` treating out-of-bounds as blocked and the reason that assertion now boots
  at `SimTileMap.DISTRICT_TILES`. Both are in the gate as pinned behaviour rather than as a fix
  somebody has to remember.

- **A container is a loot site rolled late, and that is the whole of the difference.** Rather than
  a second content type with its own table shape, a map site that declares `container` stands a
  `searchable` holding the same table instead of scattering it. One roller (`sim/loot.gd`, extracted
  from `boot.gd` precisely so the two callers cannot drift), one `lootTable` stream, one
  distribution — a player who walks into a room of loose tins and one who opens the cupboard those
  tins were in are drawing from the same table.
- **Site depletion is a flag that nothing clears, and that is deliberate.** docs/12 puts resource
  respawn timers on the cut list because they "would defuse the expanding-radius pressure, which is
  load-bearing", so `searched` is set once and there is no timer, counter, or refill path to find.
  The two "nothing"s are kept distinct — `nothing-here` against `already-searched` — because they
  mean completely different things to somebody deciding whether a building is worth the walk.
- **Searching is instant, not a channel.** `fortify.gd`'s channel machinery was right there and was
  not used: a channel exists for things you can be interrupted out of, and the risk in a scavenging
  run is the walk there and the noise on the way back, not a progress bar in an empty room. Recorded
  rather than left as an omission, with fortify named as the template if it ever needs to change.
- **A container is announced, not drawn.** It has a `position` and no renderer path, the same as
  beds and campfires, so what the player gets is `SimContainers.hud_clause` in the HUD — prose, no
  digits, and it never says how much came out. That is the standing scarcity ban doing its job
  rather than a placeholder, but the missing sprite is the Art track's open prop renderer and
  docs/23 says so rather than letting it read as finished.

## A night is drawn, not computed

`SimDirector`, gated by `npm run godot:m2:director` (VARIANCE, BOUNDS, SIDES). docs/17's first
sentence about what the director does is "the director doesn't pick a number for the night" — and
it was picking a number.

- **Strain chooses a distribution, not a night.** The three signals the old `size` calculation used
  — a colony that can fight, a colony that has been loud, a colony left alone too long — are
  unchanged in meaning; they pick a row of `NIGHT_WEIGHTS` now instead of adding up to a packet
  size. That is the difference between pacing and a schedule, and it is what makes the seed reach
  the director at all: check_m2_balance.gd's own comment already said the seed moved nothing but
  the edge pick, and the harness had been reporting the same 3 sieges and 7 quiet nights on every
  seed it ran.
- **Every row keeps a non-zero weight on quiet and on siege.** docs/17 rule 4 asks for a variance
  floor *and* ceiling; a row that zeroed either end would make one of them unreachable at that
  strain rather than merely unlikely, which is a different design.
- **The quiet floor already existed and was unreachable.** `if size == 0 and nightsSinceQuiet >=
  FLOOR_QUIET_NIGHTS` sat directly after an unconditional `size = BASE_SIZE`, so `size == 0` was
  never true: rule 4's floor was written, gated by a constant, and dead. It is reachable now
  because a night can genuinely draw quiet.
- **Rule 5 is why `director.night` carries `drawn` as well as `shape`.** "Never rubber-band
  silently" is a player-facing rule, but the mechanical consequence is that a bound which fires and
  a night which never tested the bound have to be distinguishable. Without `drawn` the gate could
  only wait for a rare natural three-siege run and hope — with it, the state can be pinned and the
  bound asked directly.
- **Packets arrive where the field points.** They always came from the south, which was the one
  authored approach, so ten nights of a campaign came down the same street. The noise along each
  edge picks the side now — docs/17's migration lever says a crowd arrives "somewhere the field
  decides" — and a silent district gets a *seeded* pick rather than a default, because falling back
  to a fixed side would put the whole distribution back where it was on every quiet week.
- **Its own RNG stream.** `directorNight` rather than `director`, so adding a draw per night leaves
  the edge picks and zombie-type draws byte-identical. A new decision must not reshuffle old ones.
- **`world.gd` copies the director's scalars instead of listing them.** `SimDirector.snapshot_of`
  existed to keep the save complete and was called by nothing — the eighth dead socket of the
  milestone — while `world.gd` hand-listed three keys, so `lullFromTick` and `weekPeakNoise` were
  written every night and dropped by every save. Copying scalars keeps world.gd module-agnostic
  (it must not depend on a module) and means a future dial is saved without world.gd learning what
  it means.

## Grief is colony-wide, because relationships are Milestone 3A

`SimNeeds`'s grief block, gated by `npm run godot:m2:needs` (GRIEF, ONCE). docs/23 asked for "the
colony morale hit on a death"; docs/04 lists **grief** and **witnessing a death** as two separate
negative mood sources; docs/07 says grief is "scaled by closeness" and that relationships are "what
gives response #5 its price".

- **The closeness half is deliberately absent.** Pairwise opinions are Milestone 3A and building a
  relationship model to land a mood hit would be the wrong order. What shipped is the part that
  needs nothing: somebody the colony lived with is dead, and everybody feels it.
- **Witnessing is the second magnitude, and it is newly askable.** 18.00 for a survivor who saw it
  against 7.00 for one who did not. Until the sightlines slice gave every survivor eyes,
  `world.vision` answered for the player alone — a colonist had no view to consult, so "did anybody
  see this" had no answer at all. It runs through the same `line_of_sight` a shot is refused by,
  and a survivor with no eyes grieves the lighter amount, which is the honest reading of "we have
  no idea whether they saw it".
- **A put-down costs more (×1.6).** docs/06's response #5 is supposed to have a price and docs/07
  names relationships as what provides it. This is the part of that price payable now: it is worse
  for everyone when the colony did it rather than the district. `survivor.putDown` marks the body
  and the grief handler reads the mark.
- **Capped, for the argument cap's reason.** Grief stacks across deaths and stops at 40.0. An
  uncapped source would let a bad night drive the whole colony past `LEAVE_AT` in one stroke,
  which is the rage meltdown docs/04 explicitly rules out. It drains over about thirteen in-game
  hours: grief lasts most of a day and then it does not.
- **The dedupe is a component on the body, not a set in the module.** CLAUDE.md's trap says
  `entity.killed` fires more than once for the same individual — health.gd on a destroyed head,
  infection.gd on a put-down and again on turning — so the colony would have paid two or three
  times for one funeral. A module-level `static var` would have been shared between the two worlds
  a gate boots *and* would not survive a save; `mourned` is neither.

## Attachments: the content declares what it multiplies

`godot/sim/modules/attachments.gd`, `content/items/attachments.json`, gated by
`npm run godot:m2:attach`. docs/10's attachment slots are "the mechanism that lets a build survive
an upgrade", and the backlog's note that no content declared `slots` was wrong — every weapon base
has declared them since the item pipeline landed. What was missing was anything that fits into one
and anything that reads one.

- **An attachment declares what it multiplies, and the module names none of them.**
  `attachment.ranged` and `attachment.melee` are tables keyed by the profile field they scale, so
  `{"noise": 0.22, "flash": 0.35, "cone": 1.2, "damage": 0.9}` *is* the suppressor. Adding a kind
  of attachment is a data edit, which is the rule docs/10 already states for bases and affixes and
  which has no reason to stop holding here. Nothing in `attachments.gd` says suppressor, optic or
  magazine.
- **Multipliers, never adders.** An extended magazine is 1.5× rather than +4 rounds, so two
  attachments compose identically in either order and neither has to know the host's numbers. The
  cost is that "+1 round on anything" cannot be expressed; nothing has asked for it.
- **`SCALABLE` is a whitelist, and that is the point.** Folding "whatever key matches" would let a
  typo — `magsize`, `range` — behave exactly like an attachment that does nothing, which is the
  hardest bug in this codebase to see. The list is per kind, and the gate asserts every key any
  shipped attachment declares is in it. That is the nested-shape check the content validator
  cannot do, in the same slot `check_appearance.gd` occupies for `appearance`.
- **`cone` is a property of the weapon, not of the person.** `ranged_accuracy` is a stat and
  resolves on the *entity*, so an item-scoped modifier would have been read by nothing. The
  profile carries a `cone` multiplier that `ranged.gd:_refresh_cone` folds in after the entity's
  own accuracy, which is also the more correct model: an optic is bolted to the gun.
- **The findability assertion is a dead-socket check.** docs/10 says attachments are "found, not
  crafted", so an attachment in no loot table is content nobody will ever hold. CONTENT in the
  gate fails on that, and on a `fits` naming a slot no shipped base declares — the two ways an
  attachment can be complete, correct and inert. This milestone has turned up six of those; this
  is the first slice that shipped with the check built in rather than the socket found later.
- **Reachable by command, on the `item.modify` precedent.** `item.attach {host, item, slot}` and
  `item.detach {item}`, two commands rather than one toggle, because they carry different
  arguments and a toggle would have to guess. There is no inventory screen for it yet and docs/23
  says so.
- **Scoped out, deliberately:** attachments have no condition of their own, so docs/10's
  "suppressors wear out fast" is half-shipped — the accuracy cost is real, the wearing out is not.
  An optic is not yet useless in the dark and a weapon light is not yet an attention emitter; both
  want the light channel, which is its own item.

## Sightlines and memory: one refusal, one recollection

`godot/sim/modules/sightings.gd`, `SimRanged.can_target`, `SimVisibility.line_of_sight`, gated by
`npm run godot:m2:sight`. docs/09 ("what you cannot see, you cannot aim at") and docs/28 ("memory,
not deletion") are two halves of the same rule and landed together for that reason: a shot that a
wall refuses is only fair if losing sight of something does not delete it.

- **Every survivor has eyes now, and did not before.** `boot.playable` set an `observer` on the
  player and on nobody else, so `world.vision` answered for exactly one entity in a booted
  district and every per-observer question about a colonist — an alarm_on_sight zombie noticing
  one, a colonist noticing anything — was being asked about a view that did not exist. That is the
  **sixth dead socket** this milestone: `SimVisibility` was complete, correct, gated, and
  consulted for one entity out of a colony. `SimSurvivors.give_eyes` is the one place a survivor
  gets a view and a memory, and `spawn_unique`, `boot_playable`, `spawn_generated` and the
  succession handoff all call it rather than each setting the component themselves.
- **The sightline test is geometry, not the facing arc.** `detail` narrows by focal and peripheral
  cones because *attention* is directional; a bullet is not. `line_of_sight` is walls and range
  with no arc, and it is what `can_target` asks. The arc version would have produced the case
  where the thing inside your sights is the thing you are not allowed to hit, and — worse — an NPC
  unable to swing at something standing directly behind it.
- **`can_target` is permissive for a shooter with no eyes at all.** Every ranged fixture in the
  suite predates sightlines and spawns a body, a weapon and a target with no `observer` between
  them; if the absence of a view read as "sees nothing", each of them would have silently stopped
  hitting. `tiles_for` returning null is the one call that separates "no eyes" from "eyes, and a
  wall", so the refusal is written against that rather than against `line_of_sight` being false,
  and NO-EYES in the gate is the assertion that says so.
- **One answer, in `ranged.gd`, because npc_combat.gd asked for it by name.** That module's own
  note said a private line-of-sight check there "would be the second answer docs/28 warns about"
  and that the rule, when it landed, should land in `ranged.gd` for everybody. It did:
  `_nearest_threat` calls the same `can_target` the shot will call, so a colonist never spins to
  face something through a wall and then declines to fire.
- **A record is a position and a tick, never a track.** Nothing follows an unseen body. The
  remembered point is where the thing was standing when it was last in view, it goes stale on a
  clock (fresh / recent / stale, then forgotten at two minutes), and MEMORY in the gate asserts
  the recalled position does *not* move when the body does.
- **Watching something fall erases the record; a kill out of sight does not.** A body you saw go
  down is not a place you are still wary of, and one that died behind a building is still, as far
  as you know, behind that building. The asymmetry is the whole model in one line.
- **The prose degrades in its counting, not only in its clock.** A fresh sighting gets a number
  ("two of them, east, a moment ago"); anything older gets a hedge ("a few of them, east, a while
  ago"). docs/28's own example says "three of them", and clause 4 forbids handing the player
  certainty they have not earned — degrading the count rather than only the timestamp satisfies
  both. There is no distance in the clause, because a remembered distance is exactly the precision
  nobody has; a bearing is what somebody would actually say.
- **Storage is an Array of records, not a Dictionary keyed by entity.** A component round-trips
  through JSON on every save and JSON has no integer keys: a dictionary would come back with
  String keys and the first `seen[entity]` after a load would silently miss — the same family of
  trap as the packed-array copy in CLAUDE.md, and cheaper to avoid than to find.
- **The renderer's private memory is gone.** `presentation/main.gd` kept its own `entity -> {x, y,
  tick}` dictionary for the fading marks. It reads `SimSightings.remembered` now, because a mark
  on the ground and a colonist's decision to shoot at one have to be the same recollection, or the
  mark is telling the player something nobody in the world knows. How long a mark *fades* stays a
  presentation constant — the sim remembers far longer than the renderer draws.
- **Firing at a remembered position costs nothing extra, and that is the design.** docs/09 prices
  it as "180 noise and 60 of muzzle flash whether or not anything was still standing there", and
  `_fire_shot` already publishes both before the hit test and spends the round before it. So the
  only thing `npc_combat._shoot_where_it_was` adds is the *decision* — the option the player has
  always had by pointing and pressing F. An NPC takes it only when nothing is visible, and only on
  a memory still inside the Recent band: spending ammunition the player has to go out and find, on
  a memory the survivor would describe as "a while ago", is the colony being wasteful rather than
  the colony being autonomous.

## What the top-down reversal made structural

The projection moved from isometric 2:1 to flat top-down (docs/00 carries the reversal argument;
this section carries what the change turned out to be made of).

- **The projection is four functions now, and a gate holds them.** `world_to_screen`,
  `screen_to_world`, `depth_of`, `visible_bounds` -- identity scale, its inverse, `y`, and the
  camera AABB. Everything else in `projection.gd` (`metres_to_rise`, `project_angle`,
  `projected_radii`, the raster helpers) existed to serve a skewed axis and is deleted, not
  ported. `check_topdown.gd` (`TOPDOWN_OK`, in the `godot:m2` chain) pins the axes, the
  round-trip, and depth-is-y; each assertion fails against the old isometric maths, which is the
  true negative the gate convention demands. The TS oracle keeps its isometric
  `projection.test.ts` frozen -- the parity ledger row is `replacement`, not `exact-port`.
- **Occlusion management was the isometric view's real price, and it deletes whole.** The wall
  extrusion, the fade heuristic for walls covering the player, the indoor stub height, and the
  per-frame depth sort over every visible tile all existed to manage what standing geometry hides.
  A top-down camera hides nothing, so none of them have a replacement -- built mass reads from a
  2 px bevel on a flat fill instead. What must *not* be confused with them is sim vision:
  `tiles_for` / `detail` gating survives untouched, because walls blocking *sight* is the
  simulation's fact, and walls blocking *view* was only ever the camera's.
- **The anonymity rule now binds facing indicators, and the code finally agrees.** The glimpse
  rule above -- one anonymous shape, no posture, no limbs, no facing -- was being skirted by the
  renderer, which drew a moving peripheral body with its full sprite, gear, and facing line. Under
  top-down every drawn body would otherwise advertise its heading, so the rule is now enforced at
  the draw site: a `Peripheral`-detail body is a flat untyped disc, and sprite, equipment, and
  facing are `Focal`-only. A tightening, recorded here because it changes what a player sees.
- **WASD stopped lying.** The 45-degree input rotation (`DIAG`) existed to make screen-up out of
  world-diagonal. Screen axes are world axes now; the keys are cardinal unit vectors and the sim
  sees the same command shape it always did.
- **The interim art convention is upright-on-flat, on purpose.** The five shipped 64×96
  feet-anchored figures keep drawing unchanged on the flat floor -- an upright pawn over a
  top-down tile is precisely the RimWorld read -- so the projection could land without waiting on
  art. The 64×64 centre-anchored canvas that replaces them is its own decision, taken with the
  regenerated sprites in the same commit so the two conventions never coexist. *(Note,
  2026-09-03: the interim convention turned out to be the direction -- "The Dungeon Settlers
  look" below returns to a feet-anchored upright pawn, on a 32×48 canvas this time; 32×40 and
  squat since 2026-09-08.)*

## What the worldgen arc decided

The owner authorized the sandbox arc (2026-08-25) — docs/24's district generation built for real —
and made six scope calls in the same sitting; a seventh, raiders, joined by the owner's session
goal the same day. Recorded here because each will look arbitrary from the code alone, and because
three of them deliberately move measurements that other decisions were parked on.

- **Rich district before region.** One district, generated properly (authored templates,
  procedurally assembled, ~40–70 buildings, two live district types), before any multi-district
  work. Milestone 3B keeps the region, the connecting roads, and streaming; the arc ships the road
  *seam* as district-JSON connection points the street pass must terminate at — data something
  reads from day one, because a dead field named `connectionPoints` would be the tenth socket.
- **Any seed is a playable world.** The sandbox is seeded: a run may roll or accept a world seed,
  and generation plus siting plus a survivability validator (docs/01's "no unwinnable starts",
  made mechanical) must hold on all of them. 20260805 stays the canonical seed the gates and
  balance bands are measured against — variety is not an excuse to stop pinning numbers.
- **The generator sites the annex.** The civic annex stops being a fixed blit at (38,38) with
  compile-time twins (`SimDirector.ANNEX`, `SimFortify.GATE_A/B`, the (46,45) start) and becomes
  an authored template the generator places per seed, its anchors written onto the map object —
  a pure function of (seed, size, content), so saves keep regenerating the world from the seed
  and `world.snapshot()` never grows a map. The constants are deleted rather than deprecated: a
  missed consumer should fail to compile, not limp. This also turns "a bigger colony building" —
  half of the owner's still-open colony-shape decision — into a future content edit rather than a
  code change; the decision itself stays open.
- **The wall-attenuation defect is fixed inside this arc, at ≥ 8 of 16.** A 4 m attention cell
  goes solid when at least half its tiles are — building rows attenuate, a lone fence does not.
  The all-16 rule had left 0 of 4,096 cells solid on the shipped district, an 18 m penalty applied
  on zero transitions. Fixed now because the arc re-measures every layout-derived band anyway;
  the same harness runs price both changes once.
- **Surface speed goes live.** `SimSurface.speed_on` — authored, tabled in docs/24, and read by
  nothing — gets wired into locomotion beside the stance multiplier, with the fast tier re-run
  before and after. The street becomes the fast way that announces you; undergrowth stays the
  slow way that hides you. Noise-only ground was half a mechanic.
- **Two district types ship live, not one and not seven.** Residential suburb and town center.
  One type would prove nothing about "a type is a data entry"; seven would ship five entries
  nothing places, which is the dead-socket pattern in content form. Town center is the type that
  forces the second loot table (`loot.commercial`) and the dense-streets generator path, which is
  exactly the coverage the claim needs.
- **Raiders close the arc, as one component and one draw.** A hostile band the director draws on
  its own `raid` stream (new randomness, new named stream), reusing melee, ranged and wounds
  wholesale. Hostility is a single `allegiance: {faction}` component read through one helper —
  not a second combat AI — and unmarked bodies default to `colony`, so every existing fixture
  stands untouched. The band's live cap is separate from the horde's (`RAID_LIVE_CAP`, not
  `LIVE_CAP`) because raiders must not eat the night-pressure budget; the entry side is drawn
  rather than read off the attention field, because a band scouts, it does not follow a smell;
  and a dead raider drops its kit and despawns corpse-less, because `components.query` does not
  check alive and a corpse would hold the cap forever. No looting AI, no withdrawal, no factions
  — docs/18 stays Milestone 3.

Worldgen RNG stays off the world registry — generation runs before a world exists — but the three
magic XOR salts become named derivations (`RngStream.derive_seed(seed, "worldgen.streets")` and
kin), one stream per pass, keeping the property this file already records for the occluder pass:
dressing changes never move the layout.

## Sleep quality: a fixed calibration point, and a floor that never reaches zero

- **A typical good night is pinned to the pre-slice number, exactly.** `sleep_quality` could have
  been introduced at any scale — 0..1, 0..100, its own units — but the moment it multiplies
  `SLEEP_FULL_NIGHT` it can silently rebalance every night the colony has ever had. Fixing "bed,
  indoors, comfortable, unwounded, quiet" to read exactly 1.0, so the pre-slice `full = 100.0` on
  a bed is unchanged, means this slice is provably about *bad* nights only — the ordinary case
  nobody was complaining about does not move a point.
- **The floor (`SLEEP_QUALITY_FLOOR`, 0.2) is arbitrary and deliberate**, the same family as
  `PAINKILLER_SUPPRESSION` and the mood-band thresholds: a night can be bad, never a night that
  restores nothing. A sim where the worst possible night is a zero has a way to starve a survivor
  of rest entirely through pure environmental bad luck, which is a death spiral no bandage or bed
  can answer — the same "no rage meltdown" shape docs/04 already rules out for mood. 0.2 keeps a
  night in a warzone worth a fifth of a good one: real, felt the next morning in `work_mul`, and
  never a trap nothing can climb out of.
## The treatment ladder: what each rung costs, and what stays legal

- **Two verbs, not three, and the record says which.** docs/05's first aid is stop it, clean it,
  close it, then rest. `pressure`/`bandage` were the first rung and `SimWounds._is_recovering` —
  fed and not exerting — has been the fourth since Slice 3. Only the two in the middle were
  missing. Writing "the ladder landed" as though four rungs arrived would have hidden the one that
  was already there and gated, which is the kind of drift the checkbox ledger died of.
- **They are entries in `CHANNEL_VERBS`, not a state machine.** Everything about a channel — the
  pin, the interrupts, the per-tick re-check, the whole R1–R10 arbitration — is verb-agnostic, and
  the R1 held-body exemption is derived by name from `verb == "pressure" and actor == patient`. So
  a verb added afterwards is refused to a grabbed body *by inheritance*, for free. "For free" is
  precisely the kind of claim that quietly stops being true, so the gate asserts it explicitly
  rather than reasoning about it.
- **Bandaging an uncleaned wound stays legal.** It is the shortcut, and refusing it would turn a
  decision made under pressure into a rule: a survivor with a deep wound, a dressing, and no
  antiseptic would be forbidden the only answer they have and would go on bleeding while they
  looked for one. What the shortcut costs is priced instead — 31 septic against clean-then-dress's
  17 over the same 240 seeded rolls — and it is charged twice over, because a dressed wound is out
  of reach of the `clean` verb afterwards. Taking a dressing off is not a verb, so "dress it dirty
  now" is a commitment rather than an ordering preference. That is the decision the rung exists to
  pose; a refusal would have deleted it.
- **`close` requires a stopped bleed.** Suturing an artery that is still open is not first aid, and
  mechanically it would collapse the ladder into one verb: a `close` that also stopped the bleeding
  would make `pressure` and `bandage` optional, and the first rung is the one that decides whether
  a survivor lives. The refusal has its own word — `still-bleeding`, not `not-bleeding` — because
  the two point at opposite problems and the reason string is what the panel shows.
- **`clean` does not stop a bleed either**, for the same reason from the other side. Cleaning is
  time spent losing blood, which is what makes "clean it first" a real cost rather than a free
  prefix.
- **The Medicine floor is deep-wound-only.** A skill wall over the whole verb would make suturing
  a colony capability that either exists or does not, and would lock every early colony out of the
  rung entirely; a floor on the deep wound alone says the thing docs/05 actually says, which is
  that the hard case needs a medic. Anybody can close a laceration, and the gate asserts the novice
  who is refused a deep wound is granted the lesser one — otherwise "unskilled" would pass on a
  flat wall.
- **A reopened wound is dirty again.** `_reopen_from_overwork` already erased the pressure bank by
  name; it now erases `cleaned`/`cleanTier` beside it. A flag left behind would go on buying a
  sepsis discount every dusk for work the sprint had undone, silently and with no wrong number to
  notice — the same failure mode as the stale bank, and the reason the assertion is an exact
  reprice rather than a directional one.
- **The uninvested paths are numerically unchanged, on purpose.** `SEPSIS_CLEAN_MUL["none"]` is
  1.0 and an unsutured wound's earned tick is still `+ 1`. A new rung should cost the player who
  ignores it nothing new, or the balance measurement it rides on stops being about the rung. Both
  are pinned by the gate, so a future edit that "improves" the discount by taxing the base instead
  goes red.
- **Suturing speeds the part, not just the wound.** A closed wound knits at `CLOSED_RECOVERY_MUL`,
  and the limb's integrity regen carries the same multiplier — because the wound closing is what
  ends the recovery window, so a wound that closes twice as fast on an unchanged regen rate would
  leave the limb permanently weaker for having been treated. The rate is derived from the same
  number in both places rather than authored twice.
## Focus drift: what moves a survivor off Auto

- **A day number, never the tick the day turns over.** The cadence is
  `Clock.day_number(world.tick) != skillWeb.driftDay`, compared per survivor. The obvious spelling
  — fire on the tick the day changes — is a gate that passes and a feature that never runs, because
  the balance harness's fast tier and every compressed campaign *jump* the clock to each day's dusk
  and land on no boundary tick at all. Written that way the drift fires for nobody in exactly the
  runs that measure it; `check_m2_web.gd` mutates the cadence into that shape and the lane goes red,
  which is the only reason to trust the shape that shipped. `driftDay` lives on the component rather
  than in a `static var`, because a static is shared between the two worlds a gate boots (this
  document has said so twice already for components and once for the kernel), and it round-trips a
  save as an int value rather than as a Dictionary key.
- **A lead of two, because one is a coin flip.** A survivor whose top two focuses are one point
  apart is one job away from being the other thing, and a focus change rewrites the whole job row —
  so a margin of one would have colonists changing careers most mornings and thrashing the work
  grid with them. Two points is the smallest margin that cannot be produced by a single job, which
  is the honest definition of "settled" here.
- **The player's choice outranks the sim's, and provenance is what says so.** `jobPriorities`
  carries `focusSetBy`; the `job.focus` command writes `"player"` and everything else writes
  `"auto"`. Drift refuses to move a `player` row. It is deliberately *not* keyed on the focus name:
  a player who deliberately puts their medic back on `Auto` has made a choice, and a rule that read
  "Auto means nobody has decided" would undo it the next morning. Manual keeps its own early return
  as well, so the lock survives even where provenance is absent (an old save, a fixture that writes
  the component by hand).
- **Endurance votes for nobody.** `focusRegions` maps Melee → Fighter, Ranged → Scout, Medicine →
  Medic, and Craft *and* Survival → Worker; Endurance is in none of them. Every survivor sleeps and
  Rest earns Endurance, so a region everybody earns equally is not evidence about anybody — include
  it and it wins most votes and points at no focus. Craft and Survival are summed rather than taken
  at their max because the Worker job row spans both (Haul, Cook, Construct, Repair): they are two
  halves of one role, not two roles.
- **One point for who they used to be.** A backstory that names a trade adds `HISTORY_NUDGE` (1) to
  that focus, matched by word against `focusHistory` in the web content. It is a nudge in the
  arithmetic rather than a tie-break, and that is the whole reason it exists: under a lead of two a
  tie-break can never change an outcome, so a tie-break here would have been a twelfth dead socket.
  As a nudge it decides a near-tie — one Doctor job plus a nursing history drifts, the same job with
  a history that names nothing does not — and it can never outvote a career. A survivor whose
  winning focus rests on the nudge alone, with no earned points behind it, is not moved at all:
  docs/08's "you cannot grind a build you aren't living" runs the other way too.
- **The tables are content, next to `focusPaths`.** `focusRegions` and `focusHistory` live in
  `content/colony/skill_web.json` because they are the same kind of statement as the paths already
  there — which region argues for which focus is a design knob, not a branch. Nothing validates that
  file (there is no `colony` schema, and the frozen oracle's `CONTENT_TYPES` does not list the
  directory either — proven by running `npm test`, not assumed), so the gate asserts the shapes it
  depends on itself, including that the Auto path still names no Craft node.
- **The surplus pass buys cheapest-first, and only ever in the node's own region.** Points are
  region-tagged (docs/08), so leftovers can only ever reach nodes of the region that earned them,
  and a path's savings can never be spent on something else. Cheapest-first with ties by content
  order makes the spend deterministic without a coin, so no new RNG stream was needed — and it
  matches docs/08's own shape, where the cheap broad nodes near the centre are where anyone drifts.

## Survivor generation: a look is a tint, an age is a word, a line is its own field

- **`colony/looks.json` declares `tint` only, never `sprite`.** `check_appearance.gd`'s
  `_sprite_keys_resolve` fails the build for any declared sprite with no 64×64 PNG behind it, and
  no art exists for a generated colonist's face today. A look could have waited for that art, but
  a colony of identical role-colour discs is the worse failure in the meantime — docs/01's variety
  is a variety of *tint*, an axis art can widen later without a second content shape or a code
  change; `presentation/main.gd` already reads `identity.look` as a plain content id, the same
  path a sprite would take. Six looks ship, not sixty: enough for the vertical slice's handful of
  survivors to read as different people, sized like the eight backstories and four age bands
  beside it rather than authored as a finished palette.
- **The rolled age lives on `identity.age` as an integer and is printed nowhere.** The
  condition-view health-bar ban (docs/05 clause 4, `godot:ban:healthbar`) is about integrity, not
  age, so an age number would not trip that gate — but printing "34" on a screen that otherwise
  says "barely out of school" would be the one number on the whole survivor sheet, and docs/01's
  scarce-and-unreliable information contract does not carve out an exception for age just because
  it is harmless to know. The number exists so the aptitude nudge and the age-band prose lookup
  have something to compute from; `person_clause` is the only other reader, and it always goes
  through the band's authored word. `godot/check_m2_recruits.gd`'s PROSE lane greps the rendered
  clause for `[0-9]` so the rule is mechanical, the same shape as the health-bar ban's key
  allowlist.
- **A backstory's `line` is authored separately from its `label`, even where the two would read
  almost the same today.** `label` is the short tag `_generator_pool` and `check_m2_recruits.gd`
  match ids and traits against; `line` is prose meant to sit inside a sentence, looked up at read
  time by `person_clause` rather than baked onto `identity` at spawn. Collapsing them into one
  field would save eight lines of content today and cost the ability to make "a line cook" read as
  "ran the line at a diner downtown until the power went" tomorrow without touching code — the same
  bet docs/12 already made for item names versus their flavour text.
- **The age nudge and the backstory nudge share one clamp-and-rebalance-to-15 pass, applied
  together rather than as two sequential passes.** The loop that brings a triple back to budget
  after a nudge will, on a tie, decrement whichever stat the nudge just raised — measured on the
  probe that set the ±2 dex threshold in `check_m2_recruits.gd`'s AGE READS lane, a single ±1 nudge
  still moved the same-direction average by about 1 point over 200 same-seeded pairs, so the
  absorption is partial, not total. Running the two nudges through the loop separately would let
  the second nudge's rebalance partially undo the first's in the same tie-prone way; running them
  together means there is exactly one rebalance to reason about, and the harness measured that one.
- **`traitConflicts` ships with one pair, not the four docs/07 once sketched.** docs/07's example
  prose named *Tough*/*Frail*, *Hoarder* and *Grudge-holder* alongside *squeamish*/*iron_stomach*,
  but only the last pair is drawn from the eight traits `generator.json` actually authors — the
  other three name traits that were never added to the pool. Shipping conflict entries for traits
  that do not exist would not be a conflict rule, it would be a rule with nothing to erase, and
  `check_m2_recruits.gd`'s dead-socket lane (`traitConflicts` names must resolve into the `traits`
  pool) would fail the build the moment it tried. The honest scope is the one pair the pool can
  actually contradict: `squeamish` pushes a survivor to break off a fight sooner, `iron_stomach`
  lets them stand more of it — `npc_combat.gd`'s `break_off_state` already reads them as the two
  ends of the same threshold, which is what makes the pair a genuine contradiction rather than a
  decorative one. The mechanism itself is general — `SimRecruits._erase_conflicts_of` walks
  whatever pairs `traitConflicts` declares, and the dead-socket and true-positive lanes are
  written against a synthetic multi-pair fixture pool precisely so a second pair can be added
  later by editing content, not code, the day a trait exists to conflict with something else.
  Adding *Tough*/*Frail*-shaped traits to the pool today just to give the conflict table a second
  row would be four traits nobody reads (the same shape as the four already-inert ones,
  `steady_hands`/`loud`/`night_blind`/`fast_healer`) authored solely to decorate a list.

## Who manages a survivor's skill web: the choice is Focus, and nothing beside it

- **There is no autonomy toggle, because Focus already is one.** The obvious shape for "let the
  player decide whether the NPC assigns their own points" is a boolean beside the focus word, and
  it is the wrong one: docs/07 already says that a survivor *with* a Focus auto-allocates along a
  path and that "setting Focus to Manual gives full control of that one survivor's web and
  inventory". A separate flag would make two fields that can disagree — `Medic` + "manual", or
  `Manual` + "auto" — and every reader of the web would then have to decide which one wins. One
  field cannot disagree with itself. The work grid renders and cycles the focus word directly, and
  `FOCUS_CYCLE` ends on `Manual` so it sits one right-click from `Auto`.
- **Choosing `Auto` is a handback, so it is stamped `"auto"`, not `"player"`.** Provenance
  (`jobPriorities.focusSetBy`) is what daily drift asks before it moves anybody, so "the player set
  this" means "do not touch it". Stamping every command `"player"` — which is what the intake did
  when provenance landed, because nothing yet clicked it — makes `Auto` the one choice that cannot
  be undone: a player who clicks round to the word meaning *you decide* freezes that survivor out of
  drift for the rest of the run, with nothing on screen that could say so. The exception is one
  ternary in the `job.focus` intake and it is the difference between a cycle and a trapdoor.
  `set_priority`'s forced flip to `Manual` goes the other way for the same reason: hand-editing a
  cell of the grid is unambiguously a person's choice, so it stamps `"player"`.
- **`web_view` carries no cost and no point total, so affordability is boolean by construction.**
  The temptation is `{name, cost, affordable}` — it is one more field and it draws a nicer screen.
  It is also a number crossing into presentation, and two of them (cost, and the points implied by
  which nodes are affordable) reconstruct a progress bar over a survivor's web. This is the
  [condition view's](05-health-injury.md#the-condition-view) argument, transplanted: a node the
  survivor cannot pay for is simply **absent** from `learnable`, so the screen cannot compute what
  it was not given. `godot:m2:autonomy`'s VIEW lane is the mechanical half — a key allowlist plus a
  `[0-9]` scan over the serialised view, the same shape as `godot:ban:healthbar`.
- **A buy is refused outright for anybody not on Manual, rather than merged with autospend.** Two
  spenders on one purse is a race with no correct answer: the player picks a node, `_autospend`
  fires on the next `_earn` and takes the points first, and the click silently did nothing. Refusing
  it with a reason (`web.refused` `"auto"`) keeps the bargain docs/07 actually offers — a Focus buys
  freedom from the decision, Manual buys it back — and keeps the surface honest, because
  `web_view.learnable` is empty for the same survivors the intake would refuse. The order of the
  four reasons (`auto`, `unknown`, `owned`, `points`) is the order in which knowing is useful.
- **No per-node provenance.** `skillWeb.nodes` stays a flat array of ids; nothing records whether a
  node was bought by the player, by a focus path or by the surplus pass. Recording it would force an
  array of records, and an array of Dictionaries cannot be edited by handing an element back —
  `Array.erase` and `Array.find` match by *value* in 4.7.1 (CLAUDE.md). That is a real trap to walk
  into for a field no rule reads: nothing in the design treats a player-bought node differently from
  an auto-bought one, and a node once bought is permanent either way.
- **The intake registers at input order 15, one after `jobs.intake` at 14.** A player who flips a
  survivor to Manual and clicks a node in the same frame pushes two commands into one tick. At
  order 13 the buy would read the focus as it was *before* the flip and be refused `"auto"` for a
  survivor who is no longer on auto — a click that fails for a reason the screen has already
  stopped showing. The ordering is one integer and it is load-bearing.

## The art style: B, picked from a reference

Decided by the owner, 2026-09-01, from the built comparison fixtures
(`.hermes/plans/2026-09-01_art-style-fixtures/`) and a supplied reference screenshot rather than
from the fixtures alone. The pick is **B — the rotating player**, the brainstorm doc's Zero
Sievert read, and the reference fixes the mood the arc is aimed at: muted, overcast, desaturated
urban decay — lane-marked asphalt, wrecked cars, dumpsters, debris and corpse dressing, rain,
high-overhead pixel art with 3/4 touches on roofs and props. *(Superseded 2026-09-03 by "The
Dungeon Settlers look" below: the rotating player and the overcast mood both go. What survives
of this entry is the HUD boundary, the gradual-fidelity boundary and the anonymity clause.)*

Three boundaries were set in the same decision, because the reference image contains things the
pick does **not** adopt:

- **The reference's HUD is not the pick.** It shows a red health bar and a green stamina bar —
  exactly what [clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) bans
  and `godot:ban:healthbar` enforces. Asked directly, the owner re-affirmed the ban. The art
  direction is the *world*; the HUD stays prose.
- **Only the player rotates.** B's cost is rotation support and equip overlays re-authored on the
  rotated rig; its risk is the peripheral-anonymity clause — a loop that rotates every body leaks
  facing for people the player should read as anonymous. NPCs, colonists and zombies stay
  face-on. *(Reversed 2026-09-03: nobody rotates, the player included -- heading is a
  horizontal flip plus the indicator line. The anonymity clause this boundary protected lives
  where it always did, the peripheral disc, and is untouched. See below.)*
- **Fidelity is allowed to arrive gradually.** The reference is hand-crafted pixel art; the arc
  starts from procedural and placeholder passes and improves, and a slice is judged by the
  brainstorm's invariants (silhouette → tint → detail, one loud tell per type, art never leaks
  sim state) rather than by matching the reference stroke for stroke.

**Rain is ambience, not weather** (added by the weather slice under the same decision). The
reference's rain is adopted as a presentation layer keyed off the tick, not as a simulation: it
never starts and never stops, nothing in the sim reads it, and no mechanism depends on it.
docs/16's weather is Milestone 3, and when it lands the layer is re-keyed to it rather than
competing with it. **Reversed in part 2026-09-06** — the owner opened a minimal rain state
(docs/adr/0015, "Rain as sim state" below): the sim now decides *whether* it rains and the layer
is re-keyed to it exactly as this clause promised; what the rain *looks* like stays this layer's.
**Superseded in full 2026-09-06** — the weather-look slice re-keyed the whole sky, not only rain,
to `SimWeather.kind` (docs/adr/0016): the sim now decides which of six kinds is on screen and
this clause's "when it lands" is the slice below.

**Every body is an overhead rig** (added by the characters slice, under four further owner
directives of 2026-09-01). All character sprites are authored true-overhead like the player's,
which retires the second boundary's "stay face-on" half — and only that half: **NPCs still never
rotate.** `body_rotation(false, *) == 0.0` and the one-transform socket stand untouched, so an
unrotated rig faces up-canvas whatever its body's real heading, and the indicator line keeps
carrying the truth. The player's own rig slims (a wide silhouette strobes at 20 Hz under free
unsmoothed rotation). Gear renders on detailed bodies — pack, long gun, headwear — as earned
Focal information, beside the standing shared-raider-body clause: every raider archetype resolves
one body, because which raider carries the gun is not something a look across a street may
answer. `check_m2_raiders.gd` holds that from the content side and `check_appearance.gd`'s roster
lane from the resolver's. *(Reversed 2026-09-03: the one convention is the face-on pawn,
feet-anchored on a 32×48 canvas -- see below. What survives: one convention for all eight rigs,
the shared raider body, gear as Focal information, and the assembler's shade-before-outline
order. The radial-shading exception retires with the rotation, and the indicator line comes
back on for the player, because a flip is two-state and facing is continuous.)*

**Road width is a layout decision, paid for in buildings** (owner, 2026-09-02, from the roads
plan). The suburb's streets went from 6 to 7 wide because a centre line needs a centre row: with
a sidewalk each side, a 6-wide street is a four-row carriageway and its line sat on row 3 of 1..4
— two lanes one side, one the other — and no amount of paint fixes an even count. The paint now
refuses to mark an even carriageway rather than shift the line half a tile, and 7 gives two tiles
of lane each way, which is what a two-tile vehicle needs. `_fit_scale` consumes the width, so the
number is not free: at 256 every extra tile of street is a tile of block, and the 40–70 building
band `check_m2_district.gd` pins is the ceiling on how wide a road may get (9 was refused on that
arithmetic before it was tried). Two further decisions were taken with it: **vehicles will be
layout, not dressing** — a worldgen pass writing a `map.vehicles` manifest beside `map.streets` —
so the standing rule that dressing stays balance-neutral is honoured rather than amended when the
2-wide footprints land; and **driving stays in Milestone 3B**, behind the drive benchmark, with
the footprints and the manifest shaped so a future vehicle entity is spawned from a record that
already exists.

The fixtures earned their keep here twice over: they showed B's rotation working under the
anonymity clause before the pick, and they surfaced that the shipped game has no player sprite at
all — the first slice of the arc authors one, which no candidate style could have skipped.

**The reference look** (owner, 2026-09-02, from four supplied screenshots of a Zero Sievert-like
top-down game — third-party, so not committed, and described here in words the way the first
reference was: chunky pixel art with 1 px outlines; people about a tile in size seen from
straight above, gun held forward; cars, vans, dump trucks and forklifts from above at real scale,
a sedan two tiles by five; buildings drawn three-quarter, a roof seen from above over a south
wall of windows, doors and garage doors; dense pine forest with cabins and dirt paths; an
industrial yard of silos, radio towers and containers; a brick warehouse street with a dashed
centre line; textured ground with no tile grid; rain; a torch cone at night; and the red and
green bars clause 4 bans). The 2026-09-01 pick stands — B *is* this read, the brainstorm named
it so — and what the references decide is everything around the bodies *(2026-09-03: the pick
no longer stands for the bodies or the mood; the decisions below that survive are marked)*.
Eight decisions, taken
in one sitting from the exploration that preceded them, recorded once here and each paid for in
the slice that lands it (docs/23, "the reference-look arc", in order):

- **The art-native scale is 32 px per tile, down from 64.** The boot zoom of 64 becomes a clean
  2× upscale and the 16/32/64/128 ladder is untouched. A person was 24 px of a 64 tile (0.38)
  and the reference's person fills the tile; the honest migration keeps the rigs' pixels and
  shrinks the tile around them, so props and street art halve and bodies do not. The choice was
  put as 16 / 32 / stay-at-64; 16 is the reference's own grain and 32 was chosen as one step
  finer. Every gate that pinned `64x64` now reads `CameraUtil.ART_NATIVE`; `draw.py`'s `SIZE`
  is the one other copy, because Python cannot read GDScript, and the two gates are the
  cross-check. *(Amended 2026-09-03: the 32 px tile and the ladder stand; the "rigs keep their
  pixels" sentence does not -- the pawns are re-authored on a taller canvas, a person about
  0.7 of a tile wide and 1.3 tall.)*
- **Buildings read three-quarter inside their footprint.** The south-facing wall row draws as a
  face carrying that row's windows and doors, a roof draws over interior tiles while the player
  is outside, every other wall stays the flat cap. Nothing hangs over a walkable tile, so the
  tile depth sort docs/00's reversal deleted does not return, and roof and wall material are
  template content (`look: {roof, wall}`) with a purpose-built gate, because the validator is
  shallow. *(Extended 2026-09-03: the roof rule stands; every wall tile also draws with
  thickness -- a lit cap and, where its south neighbour is open, a south face -- inside its own
  footprint. See below.)*
- **A roof is cut out where the sim sees.** It replaces only the black: an interior tile seen
  through a window or door still shows floor and bodies. Whole roofs — the reference's look —
  would hide a zombie the sim says is seen and the colonists act on; that is the screen refusing
  a fact, and clause 4 is about what the sim withholds, not what the screen hides. Draw ⊆ seen
  holds for interiors, the lit-pool discipline again. The footprint of a partly-seen building is
  the one new tell, the same soft one the rain cull already gives.
- **A canopy is a picture; a body under it is a silhouette.** Pine canopies are three-tile
  pictures drawn after the entities at alpha 0.85, thinning to 0.45 within a tile of the
  player; a body under one is a dark shape, never gone. The opaque, solid Tree tile is untouched.
  *(Superseded 2026-09-03 before it shipped: no canopy layer. A tree is a tall feet-anchored
  sprite in the entity sort, and it is the tree that fades behind a body, never the body.
  "Never gone" survives; the Tree tile is still untouched.)*
- **A forest district lands inside this arc, ahead of the sedan.** Denser stands, dirt streets
  and trodden paths, cabin templates, its own structural before/after and a hand-run FAST
  column. The industrial yard — silos, towers, containers, the warehouse street, the forklift —
  is named under Milestone 3B and not built: new district scope is what CLAUDE.md's pause is
  about, and one district is the size of a slice.
- **The old one-wide wreck runs stay in worldgen and draw as junk heaps.** They are what the
  balance harness was measured on, and the dumpster episode showed the run length moving two of
  four seeds. Real vehicles are two-wide `map.vehicles` records — sedan 2×5, van 2×6, truck
  2×7, the class table the references settled, which closes the wait the roads record left open.
- **The torch is named, not built.** A light item with a direction, a cone drawn from the gun
  hand, its own attention cost. It is sim, not paint, and lands as its own gated slice after the
  look does.
- **Not adopted, re-affirmed.** The HP and stamina bars (`godot:ban:healthbar`), the status-icon
  row (the HUD speaks in words), and NPC rotation (only the player's body turns). *(Amended
  2026-09-03: rotation is no longer the boundary -- nobody rotates. The bars and the icon row
  stay refused, and Dungeon Settlers' name plates join them.)*

**The ground is a texture whose mean is the palette** (the ground slice, under the same
decision). The reference has no tile grid and a visibly textured ground; ours was a flat tint
per surface with a hairline between tiles. The texture is one atlas of cells, four variants a
row, one row per ground the draw loop knows, and the palette keeps its authority: every cell is
authored around its row's tint, a gate pins each cell's mean to that tint from the decoded
pixels, and the blit is modulated by `flat / tint` so a cell averages to exactly the colour the
flat fill drew — the indoor mix, the sidewalk substitution and the position-hash variation all
survive as tints over the picture, and every lane that reasons about ground colour keeps meaning
what it says. Below zoom 32 the flat tint draws, because at 16 px a tile the texture is noise;
the hairline is gone from both branches. One shape was refused with the decision: a texture
whose colour lives in the PNG, which would have moved the mood out of `palette.gd` and into
pixels no gate reads.

## The Dungeon Settlers look, 2026-09-03

Decided by the owner, 2026-09-03, from the Steam store screenshots of *Dungeon Settlers*
(store.steampowered.com/app/2798330) — third-party, so not committed, and described here in words
the way the two earlier references were. What they show: a flat top-down settlement at about 32
px a tile seen at 2×, which is slice 1's ladder exactly; **upright, face-on pawns** about one tile
wide and one and a half tall, with faces, hair and clothing, feet on the tile, a small dark shadow
under them and a name floating above; **no roofs at all** — timber walls drawn as thick beams with
a lit top cap and a one-tile front face on the south side, every interior, its furniture and its
pawns always in view, props drawn three-quarter; a **dark, cool, near-black ground** around the
settlement with warm, light walkable ground inside it — flagstone, olive grass, brown dirt,
planks — meeting at organic, ragged edges with no grid anywhere; a **warm dark-fantasy mood** in
which torches are the loudest thing on screen, fully saturated orange with a warm pool, and the
void and the night are the one cool thing; and a HUD of portraits, health bars and numbers. No
frame shows a tall conifer: the forest in the overview is small flat dead trees drawn as
background dressing.

This entry supersedes the 2026-09-01 style pick for the bodies and the mood and amends the
2026-09-02 reference-look decisions where they touch either; each earlier clause carries its own
italic note at the point it changed, and the list at the end of this entry names, in one place,
what dies and what survives. It was taken before slice 3 of the reference-look arc, so nothing
built under the old direction is thrown away: the 32 px tile and the ground atlas are the floor
this stands on. Twelve decisions, recorded once here, each paid for in the slice that lands it
(docs/23, "the Dungeon Settlers arc", in order; the plan is
`.hermes/plans/2026-09-03_dungeon-settlers-arc.md`):

- **Bodies stand up.** Every rig — player, colonists, zombies — is an upright, face-on pawn,
  feet-anchored on a taller-than-wide canvas, and heading is a horizontal flip: **nobody
  rotates, the player included.** This reverses "B, the rotating player" and "one convention,
  true overhead". A flip is a two-state readout and facing is continuous, so the indicator line
  comes back on for the player; the peripheral-anonymity clause is unharmed because a glimpsed
  body never reaches the blit — it draws as the anonymous disc, as it always has. The rotation,
  its forward constant, its facing-line helper and the one-transform socket retire in the pawn
  slice, and `TOPDOWN_OK`'s rotation lane becomes a flip lane with the same red-both-ways
  discipline: zero transforms in the entity loop, proved on a fabricated body first.
  *(Amended 2026-09-08: the canvas is 32×40 and the figure is one tile tall with a big head --
  "Overcast or torchlight" below. The flip, the anchor and the assembler are unchanged.)*
- **The mood is warm dark fantasy.** A cool near-black dark around a warm-lit district, timber
  browns, saturated fire and lamp light. This reverses "muted, overcast, desaturated urban
  decay". Every band that pinned the overcast mood — the generator's single saturation clamp,
  the road lane's saturation cap and paved-value band, the weather lane's accent bounds — is
  **re-pinned to a measured table in the palette slice, never loosened in passing**; the
  generator's one clamp becomes three named families (muted, timber, accent) and an un-migrated
  call gets the tightest. The sentence that made this affordable survives verbatim: the mood is
  enforced by properties, not remembered. The properties change from "muted" to "warm, and cool
  only where the dark is".
- **Roofs are cut out where the sim sees, as approved, and walls gain thickness.** The
  2026-09-02 roof rule stands unchanged: draw ⊆ seen. What is added is the wall treatment —
  every wall tile draws inside its own footprint as thick mass with a lit cap and, where its
  south neighbour is open ground, a south face in the building's `look` material, with that
  tile's window or door drawn in the face. Nothing hangs over a walkable tile and no tile depth
  sort returns. *(Amended 2026-09-08: the south face will hang one tile over walkable ground
  and join the entity y-sort, so a body on that tile draws over it -- the wall-face piece in
  docs/23's what's left; no tile sort returns even then.)*
- **Trees stand up.** A tree is one tall feet-anchored sprite, one tile wide and three high,
  y-sorted with the bodies — not a canopy drawn over them. The frames' own small flat trees were
  offered and declined: the tall conifer extrapolates the style, and it buys the multi-tile
  sorted sprite the vehicles spend. A canopy wider than its trunk would hide bodies east and
  west of it, which no depth rule can answer, so one tile wide is the rule. The opaque, solid
  Tree tile is untouched.
- **The tree fades, never the body.** A tree draws opaque and drops to about half alpha only
  while a Focal body's ground point falls inside its screen rect. The recorded silhouette rule
  (bodies under canopies at 0.85, 0.45 near the player) is superseded before it shipped: a
  dimmed body is a body carrying a fact about foliage, the wrong place for it. "Never hidden"
  survives; where it lives changes.
- **Props, furniture and vehicles read three-quarter**, matching the walls. Vehicles stay
  two-wide `map.vehicles` records at the decided footprints — sedan 2×5, van 2×6, truck 2×7 —
  and their art is **one three-quarter picture per class, variant and axis**, two keys a variant,
  feet-anchored on the footprint's south edge and y-sorted like a tree. Per-tile segments (eight
  keys a variant, turned by the renderer) retire for vehicles: a three-quarter roofline cannot be
  cut at a tile seam and a segment cannot overhang the tile to its north. The junk heaps keep
  the segment convention.
- **The ground has edges.** Between two grounds the darker one draws the edge, once, onto the
  lighter tile — one sheet of eight shapes by seven rows, hash-free and deterministic, its cells
  held to the same mean-is-the-palette rule as the atlas. A tile with no unlike neighbour draws
  no edge.
- **What a survivor wears is drawn on the pawn, in one order, on one skeleton.** The pawn rigs
  publish their shoulder, hand, leg and head rows as named constants, so one generated overlay
  per item base fits all eight bodies; per-rig tailoring, layered pieces and dye are a later
  slice, named rather than smuggled.
- **The per-tile vary softens.** `RoadPaint.VARIATION_MAX` 0.025 → 0.01, the owner's call from
  the ground slice's zoom-64 picture, where the offset read as patchwork once the grid was gone.
- **Unchanged, restated so nobody re-litigates.** 32 px a tile at 2× and the zoom ladder; the
  ground is a texture whose mean is the palette, extended to the edge sheet; rain is ambience
  and keeps its cool hex; the forest district lands inside the arc; the torch is named, not
  built; the industrial yard is Milestone 3B; the old one-wide wreck runs stay and draw as
  heaps; the entity y-sort that trees and vehicles join is the one `TopDownProjection.depth_of`
  has carried since the top-down reversal — no *tile* is sorted, no wall fades, no stub height,
  and the z-level refusal stands.
- **Not adopted.** The portraits, health bars and numbers of the reference's HUD (clause 4,
  `godot:ban:healthbar`, `godot:check:hud`), and its name plates over every pawn: a floating
  name is a certainty about identity the peripheral clause denies, and the frames show one on
  every figure, so the next session will be tempted. Names stay in inspect text and prose.
- **The fourth canvas convention in a month, said out loud.** Hand-authored 64×96 face-on, then
  generated overhead 64×64, then 32×32, now a generated 32×48 pawn. What makes this one
  different is that it is chosen from a named reference's gameplay proportion rather than
  derived from a projection argument, and the constraint that drove the churn — free rotation,
  which forced a square, centre-anchored, radially shaded canvas — is gone. Nothing mechanical
  prevents a fifth; all eight rigs are generated, so a re-author is one assembler edit and a
  rebuild. *(The fifth came on 2026-09-08 -- 32×40, squat -- and was exactly that: the rows
  of one skeleton, one rebuild, and thirty-one overlays that refit by re-rendering. "Overcast
  or torchlight" below.)*

**What each earlier decision becomes**, in one place:

1. "The art style: B, picked from a reference" — amended: the rotating player dies; the HUD
   boundary, the gradual-fidelity boundary and the anonymity clause survive.
2. "Only the player rotates" — reversed: nobody rotates. The clause it protected lives in the
   peripheral disc, untouched.
3. "Every body is an overhead rig" — reversed: the convention is the face-on pawn on 32×48.
   Survives: one convention for every rig, the shared raider body, gear as Focal information,
   the assembler's shade-before-outline order. The radial-shading exception retires.
4. "The reference look", the 32 px tile — stands; its "rigs keep their pixels" sentence is
   amended.
5. Three-quarter buildings — extended: the roof rule stands, the wall gains thickness.
6. The canopy silhouette — superseded before it shipped.
7. Two-wide vehicles — stand; the art convention is amended to one picture per axis.
8. "Not adopted" — re-affirmed and extended with the name plates.
9. The overcast mood — superseded by warm dark fantasy, held by per-family properties.
10. "Rain is ambience" — unchanged at the time; reversed in part 2026-09-06 (below).
11. "The ground is a texture whose mean is the palette" — stands, extends to the edge sheet.
12. docs/00's depth-sort reversal — not reopened; the entity sort was always there.

**What ships today versus what is decided** is the distinction every reader of this entry needs:
the palette, pawn and wall slices landed the same day (their clauses close this entry), so the
table is warm, every body is a face-on pawn that flips, and a building draws its walls thick
and its roof where the survivor cannot see; the edges, the trees, the worn look and the
vehicles are still the old code, their comments say so, and each moves with its own slice.
Anyone reading a comment that describes the old direction should read this entry before
"fixing" it in either direction. *(Every one of those has landed since — the edges on
2026-09-03, the trees, the worn look and the sedan on 2026-09-04, the van and the truck on
2026-09-05 — so no comment in the tree describes the old direction any more, and docs/23's
record is the one copy of which slice landed when.)*

**Paid for, the palette slice (2026-09-03) — the mood is warm dark fantasy: a cool near-black
dark around a warm-lit district, held by warmth and value, not mutedness.** The property that
holds it is a sign with a margin: every district surface, wall, paint, prop and memory tint is
warmer than it is cool (r − b ≥ 0.02), and the two darks the district sits in plus the glass
are the other way round (b − r ≥ 0.02) — the old overcast table is refused by that one line,
five of its keys being literally cool. Saturation keeps a ceiling on the ground (0.30, moved
from 0.25 for the dirt, the one band the slice moved) because a bright lawn is not this world,
but it is no longer the thing doing the work. The generator's clamp becomes three families —
muted, timber, accent — and the default is the tightest, so an un-migrated call cannot loosen
the mood by omission. The one accent so far is fire: the campfire's ember ships at the torch
orange as authored, because this document's clamp note always said the one thing allowed past
the ceiling is a light source, and the warm grade takes it at its word. Every other margin —
the wall faces, the ground item, the composed colonist grey, the ramps' ground clearance — was
re-measured and printed rather than moved; docs/23's record carries the numbers, and the one
thin one (the colonist grey at +0.013) is named there as the owner's to widen.

**Paid for, the pawn slice (2026-09-03) — a body is a face-on pawn standing on its own point;
facing is a flip and a line, and nobody rotates.** The canvas is one tile wide and one and a
half tall, anchored on the feet, and the anchor is derived from the shape — a square picture
centres on its point, anything else stands on it — so the tree and vehicle sheets that follow
are feet-anchored by construction rather than by a second list. The soles stand on the contact
shadow's own three-pixel drop, one number read by both, so the shadow line and the sole line
cannot drift apart. A body facing west is the same picture handed to the renderer in a
negative-width rect (probed in 4.7.1 before it was written: the texture mirrors at position ..
position + |width|, so the flipped rect keeps its left edge); the draw loop holds zero
transforms and the flip lane counts them, proved on a fabricated body first. The indicator line
comes back on for the player: a flip is a two-state readout of a continuous heading, and the
line carries the exact facing for everybody. The rotation, its forward constant, its
facing-line rule and the generator's radial shade are gone rather than stubbed. The rigs
publish their skeleton — feet, leg top, shoulder, hand, head — as named constants, because the
worn-look slice fits one gear overlay to all eight bodies on them; the three hand-authored
overlays retire for generated ones on the pawn canvas, and nothing in the sprite directory is
hand-authored any more.

**Paid for, the wall-and-roof slice (2026-09-03) — a wall is drawn with a thickness inside its
own tile, and a roof draws where the screen was black, never where the sim can see.** A wall
tile in a building that declares a look draws its material's cap seen from above, or its face
where the tile south of it is open ground — the building's front, with that tile's window or
door drawn in the face — and everything stays inside the wall tile's own rect: nothing hangs
over a walkable tile and no tile is sorted. The rule is per tile, never a footprint's south
row, because a gabled front is not one flat row and the annex's south wall is compound. A roof
draws over the interior tiles the survivor cannot see, of a building at least one tile of
which they can see, while they stand outside it; a tile the sim says is seen never takes a
roof, so an interior seen through a door keeps its floor and its bodies. How a building looks
is content — `look: {roof, wall}` on every template and the annex, the material names
resolving through the dressing block to sprite keys — and a material nobody has drawn yet
draws the procedural cap and bands, the supported fallback that keeps the wall lane's subject.

**Paid for, the edges slice (2026-09-03) — the darker ground draws the edge, once, onto the
lighter tile.** Between two different grounds the darker one's ragged fringe is blitted over
the lighter tile's floor, on the side or outer corner the darker one lies on; the lighter never
draws onto the darker, and a corner draws only where neither of its sides already carries the
boundary, so every boundary is drawn exactly once. Darker is the luma of the row's palette
tint, so the order is the palette's and there is no second table to drift. The cells are held
to the ground's own rule — their mean is the row tint — and live in the ground atlas beside
the variants, because an edge is drawn right after the floor it lies on and a second texture
between two floor blits breaks the batch (measured: one draw call became two thousand). A
wall, a window or a tree is not ground: it takes no edge and gives none, and its own picture is
the edge.

**Paid for, the trees slice (2026-09-04) — a tree is a picture that stands in the entity sort;
a pawn north of the trunk is behind it, one south is in front, and the tree fades rather than
the body.** One tall picture, one tile wide and three tall, hung on its trunk tile's south-edge
centre the way a pawn is hung on its soles, sorted with the bodies by that point and never
flipped or rotated. Draw is a subset of seen: an unseen trunk draws nothing, and the tile stays
Opaque and Solid to the sim. Which picture a tree takes is a hash of the seed and the tile out
of the dressing block's list, never a sim stream, and a block that names no tree draws the two
discs it always drew. The fade is the one rule about a body under a canopy: the tree goes to
about half alpha while a Focal body's ground point lies inside its rect, and the body is never
dimmed — the 2026-09-02 silhouette clause is superseded before it shipped. One tile wide is the
load-bearing number: a canopy wider than its trunk hides the bodies east and west of it, and a
y-sort has no answer to that.

**Paid for, the worn slice (2026-09-04) — what a survivor is wearing is drawn on the pawn, in one
order, on one skeleton.** One ordered table names the slots the renderer draws and which side of
the body each goes on, because the order layers compose in is the picture and an under list plus
an over list can only say it by their concatenation. One overlay serves every rig: slice 4
published the skeleton, overlays are authored on the same pawn canvas, and the renderer composites
them at the body's own rect, so there are no per-rig variants to keep in step. A slot absent from
the table stays declarable in content and draws nothing, which is a renderer decision and not a
content one. Two limits are the size's, not the method's, and are recorded rather than papered
over: at 32 px several one-handed weapons in the same fist at the same angle read alike, and a
piece fitted to the shared skeleton sits a little wide on the narrowest rig and off the hand of
the widest — both acceptable because the rigs that strain equip nothing.

**Paid for, the district slice (2026-09-04) — a district's character is content, and the numbers
that make it are defaults a district may override, never literals a second district must be forked
to change.** The terrain pass's thirteen numbers, and the surface its streets are laid on, are
read off the district; every default equals the literal it replaced, so the district that existed
first is byte-identical and is checked to be, by hashing the generated map before and after. That
check is the point: an RNG stream is a sequence, so a pass that draws a different number of times
moves every tile decided after it, and a refactor that *looks* like pure extraction is exactly
where that happens. A second district is also the cheapest test of what the first one's code
assumed — dirt streets found a frontage test that counted pavement, which would have sited every
colony beside a connection-point opening with no gate red. And a path is a *dressing* pass: it
writes the surface layer only, so it feeds the speed, noise and ground-texture readers that
already existed and adds none of its own. Where a new district's numbers are judged is its own
question — a lane that judges a sparse district at the gate's small size can pass on a handful of
tiles, or fail for having nothing to judge, neither of which is about the code under test.

**Paid for, the vehicle slice (2026-09-04) — a car is a record the layout wrote, not a shape read
off its neighbours; and the picture is one three-quarter view per axis, standing in the entity
sort.** The resolver this replaced decided front, middle or rear from one-axis neighbours, which
cannot express a two-wide object at all: it could only ever draw a car one tile wide, and it
answered from whatever Low tiles happened to touch, so a doorway or a protected tile shortened a
car rather than moving it. Now the `worldgen.vehicles` pass parks `{x, y, w, h, axis, class,
facing}` into `map.vehicles` and writes the Low under it, and every reader asks the record. A Low
tile is therefore exactly two things and the manifest says which — part of a parked car, or a heap
of junk — which is a property a gate can hold, and does.

Two keys a variant, one per axis, is what decision 11 bought, and it has three consequences worth
writing down. The first is that the last transform in the renderer retired with the segments it
turned: `main.gd` now sets none at all, and the flip lane asserts that over the whole file rather
than over one loop. The second is that a west-facing car is the east-facing picture in a
negative-width rect — the pawn's own flip, reused — so `facing` reaches the art on the east-west
axis and not on the north-south one, where a car seen from behind and one seen from the front are
the second picture two keys does not buy. That is a limit, it is recorded here rather than left to
be discovered, and closing it is a third key per variant whenever it is worth the files. The third
is that a picture standing on its footprint's south edge overlaps tiles it does not occupy, the
way a pawn and a tree already do; a body sorts against the car's south edge, so one north of it is
behind and one south is in front, and a body standing *on* the bonnet sorts by its own y, which is
consistent and slightly odd.

Where the gate stands one is the honest part. Street width is scaled to the map, and measured it
is 2 tiles at the 64 the balance harness boots — below the 4 a two-wide car needs a kerb row
either side of — so the harness never stands a vehicle and the FAST lines cannot move. The suburb
reaches 5 at 128 and 7 at 256, and it is the only district that ever exceeds 3: the town centre and
the forest are 3 wide at every size, so neither stands a car at all, and neither carries a
`vehicles` block, because a block on a district whose streets can never hold one is a socket
nothing reaches.

**Decided but not yet shipped (owner, 2026-09-04) — three vehicle classes are told apart by
height, not by length, so the sedan comes down before the van and truck go in.** Slice 10's rule
gives a vehicle picture its footprint plus one tile of roofline north. That fixes every class's
east-west canvas at 96 rows *whatever its length*, and the sedan shipped filling 93 of them, which
is why it reads van-like. A van and a truck built on the same rule could therefore only have been
drawn longer than a car, never taller — three boxes of one height differing in length, which is
not three classes. The owner's call was to lower the sedan rather than change the rule: a car is a
low bonnet, a raised inset cabin and a low boot, and once it occupies about seventy rows the
twenty it gives back are exactly the headroom a van and a truck need to stand taller. Nothing
mechanical moves — not the canvas rule, not `VEHICLE_ROOFLINE_TILES`, not `vehicle_canvas()`. The
headroom was in the canvas all along; the sedan was simply spending it.

The general fact worth keeping, because it will outlive these three classes: **the constraint is a
property of the axis, not of the class.** A north-south canvas grows with length freely (192, 224,
256 rows) because length runs up-canvas there. It is only east-west, where length runs across and
height runs up, that every class shares one ceiling. A rule that reads as symmetric in the table
is asymmetric in what it permits. And note how the problem was found: from a screenshot, not a
proof — the slice-10 record called the sedan van-like off one frame, and 93-of-96 was measured
afterwards off the committed PNG. Every gate was green throughout and none of them could have
caught it, because no gate judges whether a picture reads as the thing it depicts. *(Shipped
2026-09-05 as the van-and-truck slice; the clause below records what it cost and what it holds.)*

**Paid for, the van and truck slice (2026-09-05) — the height decision is a property of the
pictures, and a property of the pictures can be gated.** The scale came down from 32 to 20 px a
metre for every class and both axes — one camera for one street — and the sedan sits in 73 of
its 96 east-west rows where it filled 93, a low deck and a cabin inset eight pixels each side.
The van is a box to row 92; the truck is a **flatbed**, its cab at the van's height over an open
timber bed whose end stands 13 rows under it. A box truck was refused for the reason the decision
gave: a box truck and a panel van are both closed boxes and would collide exactly where the
decision separates them, and the bed is the one silhouette a van cannot have. The three paint
jobs are shared across the classes — the record's variant is the paint and its class is the
shape, and a white van needs no fourth ramp.

The clause above ended on "no gate judges whether a picture reads as the thing it depicts", and
that is the sentence this slice answers, narrowly: nothing judges *reading*, but the decision was
stated as numbers — lower, taller, stepped — and numbers on decoded pixels are exactly what a
lane can hold. `WRECKS_OK`'s SILHOUETTE lane reads every east-west picture and refuses a sedan
over 76 rows, a van or truck under 86, a van whose two ends differ, a truck whose bed end is not
at least 10 rows under its cab, and any class it has no expectation for; the shipped set clears
each band by 3 to 6 rows, and a van drawn at the sedan's roof was refused as "under the 86 a
tall class must" before the change was committed. The same slice closed the two sockets three
classes open up: the manifest lane stands every declared class on both axes of its hand map and
proves two records on one corner differing only in class resolve two pictures, and the placement
lane counts what landed per class and **names** any weighted class that never did — the
sabotage that pinned the pick to the sedan was refused as "vehicle.van ... never landed", which
is the assertion a zero passing quietly would have hidden. Sim: none. `_vehicles` already read
each class's footprint out of content and weighted the pick from the district's list, so the
suburb's classes block gained two rows and nothing in `godot/sim/` moved; the 64-tile map every
gate boots is byte-identical on twenty-four seeds, and at 128 and 256 only the suburb's parked
rows changed. The one renderer number that had remembered the sedan — a seven-tile search
margin "because a sedan is five tiles long and its picture six tall" — now derives from the
footprint table (`Appearance.vehicle_reach_tiles`), because a constant sized for one class is
the same shape as a guard read by nothing: right until the second class arrives.

---

## Driving, 2026-09-05

**Directed by the owner as a session goal** ("make vehicle props into drivable things"), which
moved the piece out from behind Milestone 3B's drive benchmark. Several calls had to be taken to
build it at all; they were taken as first cuts under the standing rules rather than put to the
owner mid-session, and each is recorded here so it can be re-decided by looking at it rather
than by discovering it. The record of what shipped is docs/23's; this is why it is shaped so.

**The entity is the truth and the map is its shadow.** A car had to survive a save, and the map
does not: it is regenerated from the seed. So every record becomes an entity at boot, and the
Low tiles and the manifest record are rebuilt from the entity — at spawn, after every footprint
change, and after `world.restore`, the way `SimFortify.sync_map` already puts boards back on
windows. The alternative, mutating the record in place, would have parked every driven car back
at the kerb on load. The record keeps the layout's corner as `hx`/`hy` so the paint hash does
not change colour as the car moves, and carries `gx`/`gy` so the picture stands on the live
centre rather than snapping tile to tile. Every reader that already asked the record keeps
asking it.

**Four headings, and nobody rotates.** The Dungeon Settlers look gives a car exactly two
pictures, so a driven car has four headings and not an angle: the dominant axis of the driver's
move names the wanted heading; the same heading accelerates, the opposite brakes to a stop and
turns the car round in place, a perpendicular brakes and then turns the footprint about its
centre onto whole tiles. A turn snaps the centre by at most half a tile so the footprint is
always whole tiles, which is what lets the Low tiles be exactly the record. A car turning round
shows decision 11's limit (one picture for both north-south facings) every time it does it; that
was already recorded and is now visible.

**E, not Q — the owner's call, 2026-09-05.** The first push put the door on a key of its own,
because E is fortify's context ladder and the suburb stands its car-boot loot on a car's tail
tile, so E beside a car had to keep meaning "search the boot". The owner asked for E within the
hour, and the boot did not have to be demoted to grant it: the car is a rung of the ladder
below the loose items and the containers (the boot is one) and the people waiting in reach, and
above the furniture — so E beside a car with a boot on it still searches the boot first, and E
with nothing else in reach opens the door. From the wheel E means exactly one thing, out, and
never falls through to whatever the car happens to be standing over; at speed it does nothing
at all. `vehicle.toggle` stays a command for gates and replays, and `M2_VEHICLES_OK`'s E-KEY
lane holds every one of those orderings both ways.

**Bodies are not probed.** A parked car is walk-through cover today (docs/30, the vehicle
slice), and a moving one stays walk-through: nothing is run over, nothing is pushed. A hit is a
balance mechanism — a car that kills shamblers is a weapon the director never priced — and it
wants a measured slice of its own rather than a probe added in passing. Named in what's left.

**Shelter for noise.** A body at the wheel is off the shambler's menu (`_gather_survivors`
skips `mounted`), and the engine is loud: 24 under way for a sedan against a sprint's 6 and a
shout's 120, 4 idling with the driver in. Those numbers are a first cut on the body's scale
and have never been run against the director, because the 64-tile harness parks no car; the
engine is the emitter system every footstep already uses, so changing them is content. What a
shambler does about a car it cannot open is nothing, and that is the half named in what's left.

**A parked car costs the tick nothing.** `velocity` and `attention_emitter` arrive with the
driver and leave with them, so a parked car sits in no per-tick query. The first cut looked
every car's class up every tick and cost 1.9 ms a tick at 128; the profile of the systems found
it, not reasoning. A footprint change bumps both the map's own `vehicle_generation` (the
drawing node's tile index) and `world.invalidateMap()` (every NPC path and every occlusion
cache), because a car that has moved is a map that has changed; measured at 128 with jobs
running, driving costs 0.3 ms a tick with the invalidation in, so it stays.

**SAVE_VERSION 18.** A v17 save has no vehicle entities, so restoring one into this build would
sync a street with no cars on it. Refused, per the standing rule that saves may break before
1.0 and are not migrated.

**Fuel and "hitpoints" are numbers the player never sees (owner's goal, 2026-09-05, the second
of the session).** The goal asked for a fuel and hitpoint system checked by interacting with the
hood. The health-bar ban is not about bodies, it is about certainty the player has not earned,
so a car's integrity and litres live on the component and reach the screen only as words —
five for the engine (sound, scuffed, battered, failing, wrecked), six for the tank (dry to
full) — through a `hood_view` held to a key allowlist exactly as the condition view is. What
the words *do* is mechanical and legible: a battered car is slower, a failing one crawls, a
wreck or a dry tank will not run. A crash is the one thing that spends integrity, and it spends
it on the square of the speed against the class's own top, so a damaged car crashing at the
lower top it can still reach is hurt less; a wreck takes four runs at a wall, not two, which
was found by the gate rather than designed. Nothing puts litres or integrity back yet: a jerry
can, a siphon and a repair channel are each a verb on the E ladder with its own gate, and they
are named in what's left rather than half-built here.

**The dashboard: the machine's instruments are not the body's (owner's goal, 2026-09-05, the
third of the session).** The goal asked for speed, a makeshift dashboard, and whether the car
is in drive, park or neutral. `ui/hud.gd` opens with "no gauges — not for needs, not for
condition, not for threat", and the health-bar ban is the same thought: a number on the body
invites optimising the number. A car's instrument cluster is a different thing. A speedometer
and a fuel gauge are what a driver actually looks at, they belong to the object and not to the
interface, and a needle on an unlabelled dial gives the player exactly what a real one does —
a fraction they read by eye and cannot quote. So `dash_view` carries two needle fractions
(`speedo`, `gauge`) beside its words and booleans, and nothing else numeric; the dials have
tick marks and no numbers; the speed is also a word; the engine's condition is a lamp (off,
amber, red) and a word, never a value; and the HUD's own prose lines are untouched. The line
this draws: **a gauge may show a machine's state, never a body's**, and the digit rule holds
on both sides of it. If the owner wants numbers on the dial, that is a change to
`check_vehicles.gd`'s DASH lane and to `godot:check:hud`'s premise, not a tweak.

**One interact key, two places to stand.** "Define the interact key" was read as *name it once
and make it mean one thing*, not as *add a key*: `main.gd`'s `INTERACT_KEY` is E, routed by
name, pushing `use.context` and nothing else, and the legend's E row says what it does. The
hood and the door are that one key at the nose and at the side, because a body standing at the
front of a car and pressing "interact" is looking under the hood and one at the driver's door is
getting in — the place is the verb, which is the diegetic rule the HUD already follows. If the
owner wants the hood on a key of its own, `at_hood` is the test and the ladder is the one place
to move it.

**Light vehicles: the same module, told apart by content (owner's goal, 2026-09-05, the fourth
of the session).** The goal asked for bikes, scooters, skateboards and electric bikes, driveable
like the cars but with more balanced speeds, each with a small dash that makes sense. Every call
below was taken as a first cut with no owner to ask, and each is a content edit or a line:

- **One module, three content keys, no `if class == "bicycle"` anywhere.** A bicycle is a
  `vehicle` entity with a manifest record and a picture per axis exactly as a sedan is; what
  differs is `drive.power` (engine / battery / muscle), `cab` (a closed body or not) and `dash`
  (which instruments). The alternative — a `SimBikes` module beside `SimVehicles` — would have
  been a second copy of the leading-edge probe, the map shadow and the save path, and every
  later fix would have landed in one of them. Content decides; the module reads.
- **The speeds sit between a walk and a car, on purpose.** Bicycle 6.5, e-bike 7.5 under power,
  e-scooter 6.0, skateboard 4.5, kick scooter 4.0, against a walk's 2.1, a sprint's 6.3 and the
  cars' 8..10. A bicycle just outruns a sprint and a skateboard does not; that is the "more
  balanced" the goal asked for, read as a spread the CONTENT lane now holds (an engine is faster
  and louder than a sprint; everything else is faster than a walk, quieter than a sprint and
  slower than a truck). None of it has met the director; the 64-tile harness parks nothing.
- **The trade is the cab.** A car's driver is off the shambler's menu; a rider is not, and a grab
  or a crash at speed puts them off the machine where they stand (`_unseat`). That is what
  balances a quiet tireless bicycle against a loud thirsty sedan — exposure, not a speed nerf.
  The rider's body takes nothing from the fall, the same half the cars shipped; the wound is a
  measured slice named in docs/23.
- **A flat battery is a slower ride, not a dead one.** `unpowered` on a battery class is what
  the rider makes with the charge gone — pedalling the e-bike, kicking the e-scooter along —
  because an e-bike with a flat battery is still a bicycle and refusing to move it would be the
  sim lying about the object. An engine's `unpowered` is zero, which is what a dry tank means.
- **Legs are free.** Pedalling costs no stamina and no hunger. Considered and deferred rather
  than typed in: the stamina pool a sprint draws on exists, and hooking a ride into it is one
  line, but what rate is a balance claim and CLAUDE.md says measure, never theorise.
- **The dash follows the machine.** A car's cluster is a car's; a handlebar computer is one
  small dial, the motion word, two lamps and a charge bar only where there is a battery to
  gauge; a board's strip is the motion word, a row of pips and a foot-down lamp. `motion` puts
  the gear in the layout's own words — a bicycle is pedalling, never in drive. The dial on a
  flat e-bike stays the class's top, so the ride reads slower on the same dial; a dial that
  rescaled itself would be a gauge that lies. Still words and needles, never a digit: the
  machine-not-body line of "The dashboard" above holds unchanged.
- **They park in the same pass, on the same spans.** A one-wide body parks at lane 1..width-2
  where a car parks at 1..width-3 — the lane draw happens after the class draw either way, one
  draw whatever the range — and the span test stays at four tiles for every class, so the
  64-tile map every gate boots is byte-identical and `M2_BALANCE_OK` cannot move. The right
  place for a bicycle is a 3-wide town-centre street, and that pass is a slice of its own
  because it moves the harness's map. A car-boot site never hosts on a body under two across.
- **The three car shells are the bike shells.** `car_pale`, `car_green`, `car_burnt` paint the
  frames, so a pale bicycle beside a pale sedan is one street's paint; burnt on a bicycle is the
  rust and char a fire leaves. Told apart by silhouette, never by length alone — the cars'
  rule carried down: bicycles level, scooters stemmed at the nose, the skateboard under a dozen
  rows, the e-bike fuller than the bicycle by its battery.
- **SAVE_VERSION 19.** The weighted class list changed what a seed parks, so a v18 save's cars
  would restore over freshly parked bicycles. Refused, per the standing rule.

## The gear catalogue, 2026-09-06

The owner asked for more gear — weapons, clothing, backpacks, gas cans, tools, food, drinks — and
decided the shape of the slice in four answers: catalogue **plus** a `drink` block **plus**
refuelling from a can; a generated overlay for every new base in a drawn slot; a shotgun and a
hunting rifle; about thirty bases. Thirty-one landed (`godot:m2:gear`'s CATALOGUE lane counts
them), and four decisions were taken along the way that are worth writing down.

- **A `drink` block mirrors `food`, and is judged whole.** Presence is what makes an item a
  drink — `SimNeeds.is_drink` asks nothing else, exactly as `is_food` asks only for `food` — so
  the water bottle's +50, a literal in `SimNeeds.drink` since the needs module landed, is content
  now. The one rule the reader adds: a block declaring a `rest` lift without both crash keys is
  not drinkable *at all*. The validator does not recurse, and a stimulant with its crash left off
  would be a free lift nothing reports; `drive_of` refuses a half block for the same reason.
- **A stimulant is a loan on the rest pool, not a modifier on a stat.** docs/04: "no
  caffeine-style hard reset; stimulants exist as rare loot with a real crash afterward". The lift
  is paid into `rest` now; the crash is a debt (`stimulantCrashRest`) on a clock
  (`stimulantUntilTick`) debited from the same pool later. Chaining **compounds and defers** —
  a second can adds its crash to the pending one and pushes the clock out — because a chain
  that reset the debt would be the hard reset the doc forbids. Every reader of rest (the drain,
  `work_mul`, the HUD clause, the passed-out crisis) sees the move for free; a stat modifier
  would have bypassed all of them and needed its own HUD line, work multiplier and collapse.
  The tell is a word, "wired", ranked below groggy and above shaken. The energy drink's numbers
  (thirst 15, rest 20, crash 25 three in-game hours on) are first cuts: 20 buys about three and
  a half waking hours at `drain_rest`, the crash lands when most of it has drained, and repays
  with interest. NPCs never drink one — the loan is a player's decision.
- **A can pours whole, and `empties` is one spend path.** A fuel can carries `fuel: {litres}` and
  pours `min(litres, room)`; the rest is spilt. Not a per-instance litre count: an item instance
  already carries a condition, a stack and an affix list, and a can that remembered its litres
  would need a fourth number, a mass that moved with it, a fill word for the can and a HUD clause
  for the word. What a spent unit leaves behind — the bottle without the water, the can without
  the fuel — is the top-level `empties`, read in `SimNeeds._consume_item`, the one place a unit
  is spent, so a drink, a wash, a wound cleaned with the bottle and a poured can all leave the
  same thing. That closed a socket nobody had named: `SimJobs._water_work` had hunted
  `item.water.bottle.empty` since the Water job landed and nothing in shipped play had ever
  produced one. The refuel channel is `SimVehicles`' own (`refuel` on the body, `REFUEL_TICKS`
  200, interrupted by a stagger, a grab, walking off the nose or the can leaving the pack) rather
  than fortify's `construct`, because that channel puts `CONSTRUCT_NOISE` on the field every tick
  and the presentation plays the board one-shot on it, and a pour is quieter than the footsteps
  the body already makes. On the E ladder the can comes before the look: any refusal — no can, a
  full tank, a battery, a bicycle, a wreck — falls through to the hood report, whose words say
  why. The jerry can's shipped 11.5 kg is ten litres at 0.75 kg/L in a four-kilo can; the number
  was made honest, not moved. A battery refuses a can by name — the charger is docs/23's piece.
- **The firearms are first cuts inside the shambler's numbers.** A shambler is head 25, torso 60;
  the pistol does 18 at 180 noise. The pump shotgun does 30 at 15 m and 220 noise (a shout is
  120, a running engine 24..36), the hunting rifle 34 at 60 m and 200; both jam, both feed off
  their own round (`item.ammo.12g`, `item.ammo.rifle`), both take the shipped attachments through
  the slots they declare. Military cache only. The balance harness ran before and after on the
  same four seeds (the record has both tables) and every band held; the fast tier cannot see a
  gun fired, so the melee-vs-ranged parity measurement in what's left is where these numbers
  will actually be judged.

What this slice deliberately did not take, each named in what's left rather than smuggled: the
industrial loot table (a fifth location means re-tagging buildings in a district profile, which
moves loot sites and therefore the harness's map — its own measured slice, so the fuel bottle
sits on a residential garage shelf for now against docs/12's "industrial and vehicle sources
only"); ground-item sprites; the six undrawn equipment slots (the leather gloves, steel-toes,
medic pouch and bandolier are equippable and draw nothing, like the seven bases before them); a
tool class with verbs of its own (every `tool` here is a light or a bench consumable, and the
CATALOGUE lane refuses one that is neither); the siphon, the repair channel and the charger.

## The splint, and the limp a bad fracture leaves, 2026-09-06

The owner opened a survival-systems session and picked the splint first, with the rule decided
up front: **a leg fracture that heals unsplinted leaves a permanent limp; splinted, it mends
clean.** Deterministic rather than a roll, because a roll is a consequence the player cannot
learn from — "I let it set on its own" is a lesson, "the dice went against me" is not. Five
calls were taken while landing it.

- **The closer is a property of the wound kind, not a ranking in treatment.gd.** `close` used to
  ask `_closable_wounds` "does this kind bleed", which was correct for as long as a suture was
  the only closer and silently excluded the one injury a splint is for. `WOUND_KINDS` now carries
  `closeKind` per row and the ladder matches the kit to the wound *exactly*: a suture never
  splints, a splint never sews, and a leg carrying both a stopped cut and a fracture is closed
  twice, one kit each, worst wound first. `CLOSE_KINDS` stays as the vocabulary the schema enum
  mirrors, not a pick order — which is what `_best_closer` used to be written as, "so `splint`
  is an entry in the array", and that would have handed a fracture a suture.
- **The limp is a component, not a wound.** A wound heals and leaves the list; the limp is
  exactly the thing that does not, so a record on `injuries.wounds` would either be a wound the
  recovery loop keeps trying to close or a special case in every reader of that array. `lasting`
  is its own component — an Array of `{kind, bodyPart, sinceTick}` records, never a Dictionary
  keyed by part (the JSON-key trap) — and being a new component it costs no `SAVE_VERSION`:
  nobody had a limp before, so an old save correctly loads without one.
- **The modifier is recomputed every tick, not applied once.** `wounds.impair` strips
  `injury.limp` and re-adds one `move_speed ×0.90` per limping leg from the live component, the
  same strip-then-add every wound family uses. An apply-once modifier would survive a save
  through `modifiers.save()` and that is the problem: it would be a second copy of the truth,
  and the day the component and the modifier disagreed nothing would say so. Recomputing makes
  the load, the despawn and a future "the limp was treated" all fall out of the structure.
- **0.90 per leg, compounding, and a limp is cheaper than the fracture was.** A fractured leg
  walks at 0.88 while it knits (impair floor 2); a limp at 0.90 after; two limps at 0.81. The
  owner picked ten percent from three offers (five reads as a story with no cost, fifteen reads
  as worse than the injury). A bicycle's 6.5 still outruns it. The number is content-shaped and
  sits in one constant.
- **No HUD line, a word on the body screen.** `lasting` joined the condition view as a word from
  `LASTING_WORDS` — the field arrived with two values it can take, `bandage`'s lesson — and the
  body screen prints it as a tag. The HUD stays quiet on purpose: `hud_clause` is ranked
  prose about what is wrong *now*, and a permanent condition there is a sentence the player
  reads every minute for the rest of the run. A blind eye and a scar, when they land, are two
  more words in the same list; a blind eye still has no perception stat to attach to and a scar
  is a mood-and-social effect, both named in what's left.

What it deliberately did not take: NPC job walking reads `work_mul` rather than `move_speed`, so
the limp, like the per-part leg impairment before it, slows the controlled body and not an NPC
on a job (the locomotion debt entry); and the impact-fracture roll gives every fracture Laceration
severity, so setting a bone needs no Medicine at all — whether it should is the
diagnosis-with-skill piece's question.

## The pantry reads its keeper, and a cook claims the pot, 2026-09-06

Two named defects from the food side of the survival session, one decision each.

- **Spoilage reads the best living colonist's `spoilage_rate`.** The `surv.cook` node ("a careful
  pantry", ×0.95) is bought per survivor and the modifier it applies is scoped to that survivor;
  spoilage sits on the item. Three scopes were offered and the owner picked the first: the
  pantry is the colony's, so one careful pair of hands keeps all of it — `min` over the living,
  resolved once a tick, not once per item. "The survivor who stowed it" would have needed a
  per-item owner and a save-shape change to feel one node; "global only" would have moved how web
  nodes apply. The clock is a new `aged` field advanced by the rate rather than a rescaled
  `spoilTicks`, because a rate that changes mid-life (a keeper dies, a node is bought) has to
  apply from that tick forward and a baked-in deadline cannot. `repair_cost`, the other dead
  stat in the same entry, stayed dead: repair spends one whole scrap, and ×0.9 of an integer is
  a design (a debt accumulator, or fractional scrap) rather than a reader.
- **A cook's claim is a component on the item, live only while the job is.** `reserved: {by,
  job}` on the raw, checked against the holder's *current* job rather than trusted, so a claim
  whose holder died or was re-assigned heals the moment anybody looks at the pile instead of
  blocking it until somebody remembers to clear it. `_do_cook` re-validates at completion the way
  `treatment._complete` and `fortify._place_scrap` do — a meal is spawned only if the raw is still
  there and still this cook's — which closes both halves of the defect (two meals from one raw,
  one meal from nothing) without a second bookkeeping system.

## Well water is untreated, and a fire makes it clean, 2026-09-06

docs/04 has said "untreated water carries illness" since it was written, and the Water job
filled a bottle with clean water by rename for the whole milestone. The owner picked this as
the third survival slice; it was named in what's left and landed in the same commit. Four calls.

- **A second bottle base, not a flag on the first.** `item.water.bottle.untreated` is its own
  base with its own `drink` block, and the well produces it. A `purity` flag on the instance
  would have needed every reader of "is this water" — the wash, the wound-cleaning tier, the
  NPC seek, the HUD word — to learn a second question; a base is content, and every one of
  those readers already asks the base. The illness is the food-poisoning bout, unchanged: one
  `illnessChance` key on the `drink` block, the same stream, the same `iron_stomach` immunity,
  the same non-lethal cost. 0.15 a bottle is a first cut for the owner.
- **Boiling is instant at a lit fire, and it is a rename.** The well's rename in reverse: the
  bottle keeps its instance, nothing is spawned, nothing is drawn from a stream. A channel with
  ticks and interrupts was considered and left for the day a measurement asks for it — the cost
  a boil is meant to carry is the *fire*, which is a light emitter twenty metres wide and the
  loudest thing a colony owns at night, and that cost is already real.
- **NPCs light a fire to boil, and drink it raw only at soft.** The seek walks to the nearest
  campfire and lights it if it is out — the same call the Cook job makes, and the same attention
  cost, so a colony with no clean water is a colony whose fire is lit more. With no fire at all,
  a survivor drinks well water untreated only below `SOFT` (thirst under 30): a roll on the
  illness stream is worth it against the dehydration clock and not before. Between `SEEK_START`
  and `SOFT` with no fire they wait. The `dehydrating` crisis did not reach this rung when it
  landed, because `_tick_one` stopped a survivor in crisis before the seek ran — a pre-existing
  hole in the crisis path, named in docs/23 rather than widened here, and closed on 2026-09-06 by
  the playable state's "a starving colonist still eats" piece.
- **E boils before it touches the fire.** One interact key, decided 2026-09-05: at a lit fire
  with a bottle of well water, E boils; with nothing to boil, E douses as before; at an unlit
  fire `boil` refuses and E lights it, so the second E boils. The refusal reasons are the
  ladder's own words (`no-fire`, `unlit`, `no-bottle`) rather than a new vocabulary.

Bottled water from loot tables stays clean — it is bottled — so a colony that finds enough of
it never boils, and whether the tables should carry less of it is a balance question for the
harness, not a number to move here.

## Rain as sim state, 2026-09-06

The fourth slice of the survival session, and the one that overrides a written decision: ADR
0002's "weather-lite rain flag — rejected; weather is a second game". The owner was asked and
chose to open it, minimally — scent washed and bodies wet, nothing else — with a random schedule.
The calls:

- **One state, on the world, on its own stream.** `world.weather` is three scalars saved like the
  director's, and spans are drawn on a `weather` stream from content ranges. Not an entity, not
  a component: weather is a singleton the oracle already named as one (`src/sim/kernel/world.ts`).
  The first span is always dry so that no gate world ever meets rain by accident; a save without
  the key restores dry; `SAVE_VERSION` went to 20 because a v19 save restored into this world would
  load dry and reseed its schedule — a world that loads and is quietly not the one saved.
- **Two readers in opposing directions, and a third for the eye.** docs/16's rule. Wetness is one
  integer on the needs component (`wetUntilTick`): outdoors in the rain for 200 ticks makes you
  wet, a roof or a clear sky dries you in an hour, a lit fire in twelve minutes, and a wet body
  reads one temperature band colder *before* the wrap buys one back — so a soaked survivor in a
  wrap on a mild day is comfortable and a soaked one at night by no fire is freezing at once.
  The scent half-life is halved while it rains, handed to `diffuse_scent` as a parameter so the
  field never learns what weather is (it does not know which way the wind blows either). **This
  was the slice's measured correction:** the first cut was ×0.85 *a step*, and the step runs
  every five ticks, so it compounded 240 times a minute and flattened the whole field inside a
  second of rain; the balance harness read that as a colony wipe on seed 90210 and tripled grabs
  on 20260805, and a variant driver (rain / rain-without-wetness / rain-without-scent) pinned it
  on the scent, not the wet — the guess had been the other way round. A half-life factor is the
  shape docs/16 meant by "masks scent heavily", and the gate now refuses a rain that leaves under
  half the dry scent after a hundred ticks. The
  streak layer is drawn only while it rains; `rain_look.gd` stays a pure function of the tick and
  `INTENSITY_MIN` now means "within a span the sky is never empty".
- **The numbers are first cuts, recorded for the owner.** Dry 12–36 h, wet 2–6 h (a spell every
  day or two — the owner asked for "random weather" and these are the ranges the draw uses),
  the scent half-life halved, 200 / 12000 / 2400 ticks to wet, to dry, to dry by a fire. All
  content, one file.
- **What it did not take.** Wind (the four calibration weights, still not save state), fog,
  seasons, a ranged penalty, thirst relief, rain on the noise channel (`noise_propagation` stays
  unread), a wetness pool with its own HUD row. Each is docs/16's and each is a slice.

## The sky has kinds, 2026-09-06

The weather session, opened by the owner the same day rain landed, against ADR 0015's "each is
its own slice in Milestone 3" (ADR 0016 records it). Four answers shaped it — storm, cold snap
with snow, heat wave and a shifting wind, in that order; kinds as content; a simple calendar;
snow that lies as well as falls — and the spine took these calls:

- **One kind at a time, clear between spells.** `world.weather.kind` is one of six, each a JSON
  entry declaring its range, its seasonal weights and its modifiers, and `SimWeather` exposes
  one accessor a modifier, every one an identity under clear. A non-clear span is always
  followed by clear and the first span is always clear, which keeps every gate world in the
  chain under the sky it booted under and keeps the schedule readable: a spell, a gap, a spell.
  Additive flags were considered and refused — three timers that overlap are a state nobody
  designed.
- **The calendar is five days a season and the weights are the season's.** A ten-day run sees
  spring's rain and summer's heat; winter's cold snap and snow are in the tree and drawable on a
  longer run or a different `startSeason`. `seasonDays` is the one number, content, the owner's.
- **Wind is state and the field is told, and it prevails.** Direction re-rolled daily at
  strength 0.6 (the field's old fixed lean), handed to `set_wind` and re-applied by the tick
  on any mismatch rather than on a restore hook — the field's `restore` copies only its two
  layers, `adopt_map` builds a fresh field, and world.gd must not learn a module's name. The
  first cut drew any direction at all and a storm doubled it; the integration measured that as
  a per-seed coin toss on the harness's survival floor (docs/23's record has the table), and
  docs/16 says *prevailing* wind that shifts over days. So the day's angle wanders within
  `windDriftDeg` (45°, climate content; 180° is the free wind back) of the field's calibrated
  lean — the direction every district siting was measured under — and no shipped kind
  multiplies it (the `windMul` key stays, gate-exercised). Whether the wind should be free is
  the owner's (`HANDOFF.md`). Noise stays undirected: docs/16's "strong wind carries noise
  further in one direction" is a propagation the field does not have, and the ADR says so
  instead of pretending.
- **The living slow through the modifier store, globally; the dead through their one accessor.**
  A global-scope `move_speed` under source `weather` reaches every body that resolves the stat —
  the player, raiders, the noise-per-metre scaler, and a recruit who arrives mid-snow — and is
  re-applied idempotently by the tick against `appliedMoveMul`. Snow's slowing keys off the
  **cover** (half laid) and not the fall, so the snow underfoot outlives the snowfall. And
  `SimJobs._walk` now resolves `move_speed` at all: it never had, so every movement penalty in
  the game had reached the player alone. A defect closed on the way and measured, not a design.
- **The shift sits between the base and the wet.** A cold snap reads one band colder day and
  night, indoors too — a roof is shelter from the wet, not from the cold — and only a lit fire
  cancels it; a heat wave reads one band hotter by day outdoors and nothing cancels it, the
  night being its own relief. `_hotter` is `_colder`'s mirror, and it is the one line through
  which the hot half of `TEMP_ORDER` — in the enum since ADR 0002, set by nothing — is reached.
- **The numbers are first cuts, recorded for the owner.** Every range, every weight, every
  multiplier in the six entries and the climate: docs/23's record and `HANDOFF.md` item 0.
- **Heat is a dose, and heatstroke is what armour costs.** The heat wave's slice mirrors the
  cold's clock exactly -- `hotSinceTick` beside `coldSinceTick`, the same `EXPOSURE_TICKS`,
  cleared by any roof, the night or the end of the spell -- because the two ends of the ladder
  should read the same way to a player and because a second timing constant would be a second
  thing to tune. What the dose buys is deliberately capped: the sun alone deepens `a_little_hot`
  to `very_hot` and never further, body armour is worth a band the moment it goes on (docs/16's
  "armor becomes punishing"), and `extremely_hot` -- heatstroke -- is reachable only in armour
  after twice the exposure, so the deep band is a choice somebody made rather than weather that
  happened to them. **Body armour is coverage, not a slot:** anything equipped whose base armours
  the torso at 0.4 or better, which is the leather jacket and the scrap vest as shipped and not
  the cloth wrap. The slot would have answered wrong twice -- the vest armours the torso from the
  `vest` slot, and the wrap sits in the `torso` slot at 0.3, which is a garment. **The wrap stays
  warm in the sun**: it still buys one band back through `_shift_temp`, so a wrapped body reads
  comfortable where a bare one reads `a_little_hot`. That is on purpose and it is the same rule
  it has always been -- a wrap moves you toward comfortable from either end -- rather than a
  cooling effect anybody designed. **The corpse multiplier is the corpse's**: `corpseScentMul`
  multiplies the emit loop only for an entity carrying a `corpse` component, so what the heat
  does is make the dead carry, and a living body's scent under a heat wave is byte-identical to
  its scent under clear. **The spoilage line is generic**: `_tick_spoilage` multiplies the pantry
  rate by `SimWeather.spoilage_mul` and names no kind, so the cold snap's and the snow's 0.5 read
  the same line the heat wave's 2.0 does. **No heatstroke injury**: the deep band is a mood, a
  work multiplier, a HUD sentence and a dropped job, and it writes nothing to the body -- an
  injury component would be a health-system decision and it is not this piece's to take.
- **The storm's noise is a half-life, its lightning is a noise, and Guard works through it.**
  `noiseHalfLifeMul` 0.4 is handed to `attention.decay()` as a factor on that tick's half-life,
  the shape `diffuse_scent` already had and for the same reason twice over: this decay runs
  every tick rather than every fifth, so a per-step multiplier would compound 1200 times a
  minute and flatten the layer instead of shortening it. The field is told a number and still
  does not know what weather is. A strike is a plain `noise.emitted` at 60 on a random open
  outdoor tile plus a `weather.lightning` for the screen, and nothing else — no sim light
  (the ADR's refusal), no sound, because `sfx.gd` dispatches one-shots by exact magnitude and
  there is no thunder sample; 60 is deliberately none of 180, 120 or 4, so the dispatcher plays
  nothing rather than a gunshot. The tile is drawn by rejection, sixteen tries and then silence,
  rather than by walking the map for a strike that happens once every few minutes. And the work
  refusal exempts **Guard**: standing the gate is watch, not work, and a storm is exactly the
  night somebody has to be on it — the same night nobody can hear anything coming. Rest is
  exempt too, and need-seek returns long before the refusal, so a dehydrating survivor still
  walks out to the well. `godot:m2:storm` is the gate.
- **What it did not take.** Fog, a ranged penalty, thirst relief, barricade damage, firewood,
  frostbite, tracks, phase lengths by season, survivor forecasts, a sim light pulse per strike
  (the owner chose noise and a screen flash). Each is named in what's left; fog came off it on
  2026-09-08 (the bullet at the end of this entry).
- **The look slice, 2026-09-06.** `rain_look.gd`'s constants became one pure function a kind,
  `look_of`, returning a `{fall, slant, lenMin, lenSpan, intensityMin, count, colour}` record —
  rain's own numbers unchanged, a storm the same fall and lean at a higher floor and half again
  as many streaks, and snow its own shape (slower, more lean, short enough to read as a dot) on
  its own `snow` palette key rather than rain's. The cover is a lerp at the *one* place the
  ground colour is already resolved in `_draw_district`, guarded by the same `is_indoors` check
  every other floor branch there reads, so an indoor tile is never snowed on and cover 0.0 is
  `Color.lerp` at weight zero — byte-identical to today, which is what keeps `check_topdown.gd`'s
  GROUND lane pinned. The flash is one `world.events.drained` read for a `weather.lightning`
  event, drawn as a full-screen wash and forgotten the same frame — no subscription, no state,
  the `_camera_shake_from_events` precedent for reading the drained record rather than
  subscribing to the bus. Owner's calls: snow falls *and* lies (a ground regrade, not only a
  sky layer); lightning stays the screen flash ADR 0016 already chose, never a sim light pulse;
  the look itself is arbitrated by screenshot, not by property bounds alone. Gate
  `godot:check:weather`, seven lanes now (ACCENT, DEAD SOCKET, RAIN PURE, RAIN WIRED, ROOF,
  COVER, FLASH); docs/23's record has the measured numbers.
- **The cold snap's pantry, and the snow's, 2026-09-06.** `_tick_spoilage`'s rate is
  `pantry_rate(world) * SimWeather.spoilage_mul(world)`, one generic read with no per-kind
  branch — the heat slice writes the identical line in its own worktree, so the two merge without
  a conflict. Cover melts at the climate's `meltPerTick` under **any** kind without its own
  `coverPerTick`, cold snap included, because only `snow.json` declares one; that is the shipped
  first cut, not a deliberate "cold preserves the pack" rule, and it is named here so a future
  session does not read it as intent. What docs/16 promises for the cold half that stays unbuilt,
  and why: firewood and its consumption (no fuel model exists to spend), frostbite as a permanent
  injury (the wounds ladder has no cold-exposure hook to fire it from), crops failing (no crop
  system), and tracks in snow (no tracker reads a footprint anywhere). Each stays named in what's
  left rather than stubbed.
- **Fog, the seventh kind, 2026-09-08.** The owner's four calls, taken in one session before a
  line was written: **its season** — autumn-heavy with a spring weight (`spring 2 / summer 1 /
  autumn 4 / winter 1`), because the calendar starts in spring at five days a season and a
  ten-day run never reaches docs/16's foggy autumn, so an autumn-only fog would never appear in
  the milestone's own exit-criterion run; **its look** — the sight collapse the sim already
  makes visible (an unseen tile is simply not drawn, so the district edge closes in on its own)
  plus one pale veil on its own `fog` palette key, drawn between the flash and the night wash,
  never a radial gradient and never the fog-of-war shading docs/28 refuses; **its effects** —
  sight both ways and scent muffled, and nothing else: no explicit ranged-accuracy modifier and
  no outdoor-work refusal, because a target beyond a fogged range cannot be shot and a district
  that stops at twelve metres is hard to navigate without a second mechanism saying so, and
  docs/16's "two systems in opposing directions" rule argues against a wait-it-out state; **its
  numbers** — `sightMul` 0.25 and two to eight hours, first cuts. The design calls the slice
  itself took: **one number, both sides.** `sightMul` reaches every observer through
  `SimVisibility.refresh(world, map, sight_mul)` as a *parameter* SimBoot resolves and hands
  down — the module knows walls, arcs and light and never learns what a fog is, the
  `attention.gd` idiom — scaling `metres` and `cast_metres` together so `range_squared` closes
  for the living and `full_squared` closes the dead's lit-target escape with it; and
  `SimShambler.sight_reach` multiplies by the same accessor, so a shambler's 3.8 m falls to
  0.95 m, inside its own 1.6 m contact radius: in a fog the dead have no sight worth the name and
  hunt by nose and ear. Neither gate on a zombie seeing may shrink alone. **Not in the sight
  rule itself.** The multiplier is deliberately kept out of `_sight_metres` and
  `SimLight.sight_metres`: their ratio against `range_metres` is the night wash's alpha, and a
  fog folded in there would paint midday in the night's colour. The night stays the night's,
  the veil is the fog's, and they stack; `godot:m2:fog`'s SOCKET lane holds that line textually.
  **The save bumps** (v26) though no `world.weather` key changed: `kinds()` is sorted, `fog`
  sits between `cold_snap` and `heat_wave`, and the `weather` stream's kind roll now accumulates
  in a different order — the v21 reason, again. **What the FAST balance tier cannot see** is
  recorded rather than hidden: it steps two thousand ticks after each window and never exhausts
  the first clear span, so its four seed lines are byte-identical before and after and prove
  nothing about fog either way (docs/23's record has both). What fog did not take, still in
  what's left: the ranged penalty in rain, tracks, forecasting, noise downwind — each its own.

## The trap and the bait are Milestone 3A, 2026-09-06

The roadmap audit of 2026-09-06 found the Milestone 2 scope table promising "walls, gate,
barricades, one trap, and one bait emitter" while the tree had walls, the gate and barricades
(`godot:m2:fortify`) and nothing else: no trap or bait content, no gate, no what's-left entry, and
the Milestone 3A list already naming "traps, and bait" as its own. The owner's call, made the same
day: **cut both to Milestone 3A.** The slice's building is the three that shipped. docs/15's traps
and bait sections are unchanged — they are the spec, and docs/15 was never scoped by milestone.
What this leaves the slice: sieges are answered by walls, the gate, barricades and bodies, and the
director's minimum siege cadence (risk 3) is measured against that and nothing more. If the human
ten-day playtest finds building without a trap has nothing to defend *with*, that is a reason to
revisit, and it is a playtest finding to bring back here, not a reason to smuggle one in.

## The playable state, 2026-09-06

The owner's session on getting the game to a good playable state. Three code-grounded surveys
(survival and needs, the NPC colonists, the zombies and the director) were read against docs/02's
ratchet and docs/04, 07, 14 and 17, and found both loops the exit criterion needs open-circuited:
the colony loop at the NPC's end (the boot colony does no work, because Ellis's authored row is
Guard 1 and the Guard job never completes; NPCs never open a container; a colonist at zero hunger
stops seeking and dies beside a full pantry) and the attention loop at the zombie's end (a
shambler acquires a survivor only inside 1.6 m and has no sight; days 1–7 send nothing; nothing
has ever breached on any seed; the balance harness measures a 64-tile map sixteen times denser
than the 256 the player boots). The owner answered twelve questions the same day. Each is a
decision, not a number; the numbers inside each are first cuts that land with their slice and
are recorded there.

1. **The target is the ten-day human playtest**, docs/23's exit criterion, not a shorter loop.
2. **Order: the colony loop first, then the zombies; lethality and presentation last** — the
   small sim fixes that make the base alive give the zombie slices something to threaten, and
   the harness moves once per system rather than twice.
3. **Zombies perceive as docs/14 is written.** Every zombie gets an observer — sight through the
   existing shadowcast, scaled by light — and the authored `sensory` block weights noise, scent
   and light per type. Measured against the harness before and after.
4. **Two grace nights, then the strain table every night.** The `live < 8` trickle gate goes.
   The variance floor and the siege cap stand. Re-measured.
5. **Boot population scales with the district**: a density of 20 per 64 tiles of side, so the
   harness's 64 keeps its 20 and the played 256 boots 80. The linear reading is this plan's call:
   the owner's two numbers fix it, and a per-area reading (320) would sit ten times over the
   live cap and refuse every night.
6. **Guard is a dusk-to-dawn post.** By day a survivor with Guard set works the rest of its row;
   at dusk it takes the post. Ellis builds and hauls by day and watches by night.
7. **Body damage slows and staggers**: torso integrity feeds a speed factor and a stagger chance
   the way legs feed the crawl; the head stays the only kill.
8. **Boards, barricades and doors break by pressing.** A door tile class that opens, closes and
   breaks, and zombies press on any barrier on their path with pressure scaling by how many are
   packed against it (docs/15). Doors as a tile class *plus* an entity component through
   `sync_map` — the window-board precedent — is this plan's call, because `SOLID` is a const and
   a door is not.
9. **Cold, heat and sepsis can all kill**: hypothermia and heatstroke as injuries on the
   exposure ladder, sepsis lethal untreated on a dusk clock. Each with a measurement. This
   closes the long-standing sepsis item.
10. **NPCs scavenge too, near home**: containers the colony has seen, within a radius of the
    annex; the far district stays the player's run (docs/02).
11. **Zombies emit to the field**, driven by their `emits` block, and lay residue in every state.
    The horde entity stays Milestone 3B.
12. **The screen speaks of the colony**: prose world-lines for death, succession, run-over,
    arrival and bereavement, and click-to-select on a colonist so the third-person prose that
    already exists reaches the screen.

One more call the plan takes inside decision 3: `extends` in zombie content is **resolved**, the
way the frozen oracle resolves it (child wins, objects merge, arrays replace), rather than deleted
from the schema — deleting it would triplicate every shared block and need a schema edit the
oracle must also pass. The pieces are docs/23's playable-state group, in landing order; each
records its own numbers here as a bullet under this entry when it lands.

- **Guard is the night post, 2026-09-06.** The watch is Dusk and Night by `Clock.phase_of`,
  nothing finer: a survivor with Guard on their row is called to the post at dusk only off a job
  that has not begun a channel and only where Guard outranks that job in the row's own sort
  (priority, then name), so a doctor finishes the dressing before she stands the gate, and the
  watch completes at dawn — an Endurance point, the same region Rest pays into, because a night
  stood is docs/08's hard night. The preset-over-authored rule for a focus change: the preset
  wins every cell it names and the content row keeps every cell it does not, and Manual is the
  content row again — the alternative, authored-over-preset, would let `Guard 1` outrank a Medic's
  `Doctor 1` by the name tie-break and put the medic on the gate. `Auto` deliberately stays without
  Guard: its nine columns at 3 tie-break alphabetically, and Guard would win every dusk for every
  Auto survivor at once, so nobody would haul after dark. Ellis's and Mara's day columns
  (`Construct 3, Cook 3, Water 3`; `Cook 2, Water 3`) are first cuts.
- **A crisis walks, and a fire burns down, 2026-09-06.** A survivor in a hunger or thirst crisis
  cannot work (`work_mul` stays 0) but walks at half pace (`walk_mul`, `CRISIS_WALK_MUL 0.5`):
  the alternative — a crisis that stops the body — is the dead end the surveys found, a colonist
  dying beside a full pantry. Half rather than full because docs/04 puts weakness before
  collapse, and rather than zero because zero is the defect. A fire's burn-down is a clock from
  the last lighting (`CAMPFIRE_BURN_TICKS 36000`, half a night) and not a douse at dawn, because
  a fire lit at midnight to boil a bottle must not go out at six for a reason nobody can read;
  cooking holds it, since a cook standing at a dead fire would be a lie the screen tells. No fuel
  is spent: firewood is docs/16's unbuilt cold half and stays named in what's left.
- **Near home is a radius, and known means seen, 2026-09-06.** A colonist searches a cupboard only
  if somebody has looked at it — the memory is `sightings`' second array, filled by `detail`, so a
  survivor does not walk to a box nobody has seen and the information-scarcity contract holds for
  NPCs as it does for the player — and only within `HOME_RADIUS_TILES` (40) of the annex's centre.
  A radius rather than "inside the annex" because the annex holds no cupboards, and rather than
  the whole map because docs/02 makes the far district the player's run and the Guard slice
  measured what hauling across the whole district costs. Haul is bounded the same way for the
  same reason. Forty is a first cut: the whole of the 64-tile harness map, so the FAST lines are
  moved by the search itself and not by the bound.
- **A density, linear in the side, 2026-09-06.** `wanderers_for(tiles)` is `20 × tiles / 64` and
  the live cap `32 × tiles / 64`, so 64 boots 20 under a cap of 32 as it always has and 256 boots
  80 under 128. Linear in the side rather than the area because the owner's decision named the
  two numbers (20 and ~80) and the per-area reading, 320, would be ten times the old cap; the cap
  scales with the population because it is a statement about how many bodies a district holds,
  and a flat 32 at 256 would have refused every night from the first. Measured at 256: ~105
  ticks a second against ~1,085 at 64, which the record carries as the price every later
  256-tile measurement pays.
- **Eyes see what is lit, and only the dead's eyes do, 2026-09-06.** A zombie's sight samples
  the light at the target (`lit_target` on `shambler_eyes()`), because the oracle's rule —
  `min(eyes, max(ambient, lit at the observer))` — is a rule about how far *you* can see from
  where you stand, and applied to the dead it made every zombie blind after dark and blind to a
  survivor under a floodlight, which is the screamer's purpose inverted. The player's eyes keep
  the oracle's rule on purpose: `tiles_for(player)` is what cuts roofs out and pools the light
  wash, and a 48 m shadowcast after dark would open every roof in sight; a survivor seeing a
  lit window across the dark is a presentation decision for another day, and NIGHT-LIT pins the
  scoping so it cannot widen unnoticed. Waves: `introducedInWave` n arrives on day
  `1 + 2n`, so wave 1 is the day-3 mix the old constant opened; the stride is the one number
  the old rule had, and docs/14's "week 6" schedule is Milestone 3's to re-time. `extends` is
  resolved per world on `world.content_resolved` rather than in a static because a static memo
  is shared between the two worlds a gate boots, and the EXTENDS lane boots two with two trees
  to prove the difference. Screamer and bloater declare `grab` because docs/14 makes the grab
  every type's primary threat, and `behaviors` replaces rather than merges. The reach of sight
  as a stimulus is the type's `sensory.light` on its eyes, `range × sqrt(light)` — the weight is
  docs/14's "poor eyesight" as a number, and the square root because a tenth of 12 m is 1.2 m,
  inside the 1.6 m contact the slice exists to fix. **And the stimulus shipped off for one
  slice** (`SimShambler.SIGHT_ENABLED`, the grabs-flag precedent) — not a reversal of decision
  3 but its sequencing: measured on the FAST tier, sight that closes on a colonist wiped seeds
  at 12 m and at 3.8 m alike, because a shambler whose hold a struggle broke re-took the
  colonist it could still see, and until the torso slice a colonist with a knife could not
  finish it. The torso slice gave the colony that answer and the same four seeds held with
  sight alone, so it ships on from the commit after that slice; the table's flip waits on its
  own measurement. And the dead recast
  their sight only every two tiles (`ZOMBIE_RECAST_TILES`): the shadowcast is the
  oracle's algorithm ported cell for cell and stays so, a 12-tile cast is ~1.5 ms, and eighty
  bodies casting on every tile crossing were a third of a 256-tile step; walls a tile off their
  true offset are an approximation a zombie can afford and a person cannot, so a survivor's cast
  still moves with their tile. Measured before choosing — a tick stride did nothing, because
  casts follow tile crossings, not ticks.
- **Two grace nights, then the table, 2026-09-06.** `GRACE_NIGHTS` 2 is docs/17 rule 2 ("week
  one is quiet") re-timed for a ten-day playtest: a week of grace in a ten-day run is a run
  with three nights in it. Two rather than one because the first dusk is spent learning the
  annex, and rather than three because the trickle it replaces had already been sending a
  probe on night 3 whenever the district was thin. **It ships 7** — the old pacing, one static
  from the decided 2 — for the reason sight ships behind its flag: measured at 2 the compressed
  tier wiped a seed the colony could not have held, and the floor that catches it is the one
  CLAUDE.md keeps. Two of the owner's decisions now sit at their old values behind gates that
  prove the new ones, and that is deliberate: the alternative was to decide, alone, that a
  compressed 64-tile floor may lose a seed, which is the owner's call (HANDOFF item 5). The
  stream is not touched on a grace night,
  which is a determinism promise rather than a pacing one: a campaign's night draws must be the
  same sequence whether or not the grace length changes again. A lull opens at the next dawn,
  not at the breach, because the night the wall came down is already decided and the quiet
  docs/17 rule 1 promises is the *following* night's; a second disaster inside a lull extends
  the close and keeps the edge, because a lull that restarted would read as the game resetting
  its own clock.
- **The dead write to the field, 2026-09-06.** The emitter is built from `emits` and nothing
  else — a type with no block carries zeros — so what a zombie gives off is a content number
  the way its speed is. Noise goes to `ambient` and `walking` alike because a groan is not a
  footstep: the noisemaker's shape, and the one the screamer's 4 needs to mean anything while it
  stands. Scent 1 on the base — a living person's — was measured into place from a first cut of
  8: the driver's sweep (docs/23's table) found the crowd held together at every magnitude
  and the magnitude deciding only how far the dead's plume outweighs the living's, twelve times
  at 8; a crowd of twenty that smells like twenty people keeps the residue's reason and leaves
  the field about the living. A body's hearing
  threshold rises by its own noise, because the field is a maximum and a groaning type would
  otherwise chase itself; the alternative, subtracting a body's contribution from the field,
  would need the field to know who wrote what, which docs/03 says it never does. One roll a
  cloud rather than one a body: a cloud is a discrete event with a source, and the second
  bloater has to be a second risk or the type stops mattering after its first death.
- **The torso, 2026-09-06.** Speed factors 1.0 / 0.85 / 0.65 / 0.5 and stagger chances
  0 / 0.35 / 0.6 / 1.0 by part state, not by raw integrity, because `part_state` is the one
  place that normalises a body and a zombie type authors its own maxima (CLAUDE.md's
  "parts do not share a scale"); the maxima are the type's own (`bodyMax`) rather than the
  shared table's because the table read a screamer's whole torso as two thirds of a
  shambler's. A stagger of 20 ticks rather than the weapon's 8 because the weapon's is the
  blow's recoil and this is the body's failure, and the max rather than the sum because a
  second knock during a stagger extends it, the rule `shambler.stagger` already had. The roll
  is by the *resulting* state so the hit that takes a torso across a band is the hit that can
  drop the body, and on its own stream so a torso hit moves no other draw. The head stays the
  only kill: docs/14's damage model, and the one thing every decision here was made inside.
- **Doors, 2026-09-07.** A tile class and an entity component rather than a tile per state,
  because `SOLID` and `OPACITY` are consts indexed by tile and a door is not a const: the
  window board set the pattern (state on an entity, overlaid by `sync_map`) and a door is the
  same pattern with an `open` bit. Open by class so a map is judged without a world — the
  survivability walk, the enterability check and the scatter all read a doorway as ground,
  and the boot is what shuts it. A walker's open is unlatched and the player's is latched
  because the two mean different things: a colonist walking through wants the door to close
  behind them and the player pressing E wants the door to stay how they left it. Sixty ticks
  of swing so a second colonist three seconds behind the first walks through the same open
  door. NPCs open a latched door too — the latch is "do not swing", not a lock — so the
  colony can leave a shut annex by day. The dead never open a door; how they get through one
  is the pressing slice's, and a closed door is a wall to them until then, which is the one
  behaviour this slice changes for the district's teeth. The post steps inside the gate so
  the gate can shut behind the watch.
- **Pressing, 2026-09-07.** The press is a kernel fact — the tile that stopped a wanted move
  — rather than a fortify-side adjacency test, because "wants to get through" is what a
  barrier should charge for and adjacency charged for standing still; the old board wore a
  stage for every shambler idling beside it. Superlinear pressure (`n × (1 + 0.5 × (n − 1))`)
  is docs/15's crowd as a number: a lone body at a door is a nuisance and four are a breach,
  and the alternative, linear, makes four bodies exactly four times a nuisance, which is not
  what a crowd at a door is. Costs a stage of 40 / 160 / 90 (board / door / scrap) keep the
  board's old pace exactly and make a door four times a board, because a door is the thing a
  colony shuts and a board the thing it improvises. Only the dead press, because the living
  open doors, and a raider that wanted through would not stand at one.
- **Re-arm and withdrawal, 2026-09-07.** A colonist re-arms only when unarmed — armed never
  swaps — because "the better weapon" is a valuation the colony does not make yet and a rule
  that swapped on a number would have Ellis putting down the pipe for every knife on the
  floor. Pack first, then the nearest working weapon near home, because the stockpile is where
  a colony keeps its spares and a body should not cross the district for a bat. A worn-out
  weapon drops rather than vanishes because a thing the player can repair should be a thing
  the player can find. A band goes home on a clock (6,000 ticks, five minutes) with nothing to
  fight, and at once below half strength, because docs/17's raiders are a *pressure*, not a
  garrison: a band that lost is a band that leaves, and one that found nobody has no reason
  to stand in the road; the entry tile as the exit because that is the road it knows.
- **The cold, the heat and sepsis kill, 2026-09-07.** A dose of exposed ticks rather than
  the clock's difference, because the compressed tier jumps a day between windows and a
  clock-keyed death would be a death by artefact; the band still reads the clock, as it did.
  Two exposures to a wound and three to a death in the cold, three and four in the heat and
  only in armour, because docs/16 makes armour the thing the heat wave punishes and the sun
  alone should never kill a body that took its jacket off. Frostbite on an extremity and
  heatstroke on the torso because that is where each lands on a person; a laceration's
  severity so each impairs the part without bleeding, and never septic because there is no
  opening. Three dusks for sepsis because a night is the unit sepsis is already rolled in,
  three is long enough to find a course and short enough that a fever is a decision, and the
  second dusk's clause says worse so the decision is prompted before it is too late. A course
  clears the sepsis at once and the count at the next dusk, because the count is read at
  dusk and a cure at noon should not need the clock to notice it.
- **The screen speaks of the colony, 2026-09-07.** The chronicle is sim-owned and saved,
  not a presentation-side log, because what the colony lost is a fact about the run and not
  about the screen — a save reloaded next week should still know who died on day two, and the
  grave or epitaph that reads it later should not need the sim to remember twice. The screen
  reads only the last two hours and at most three lines, because the world column is a place
  for news and a death on day two is not news on day four; the record keeps everything. A death
  is written once per entity and only for a body with an identity, because `entity.killed`
  fires up to three times for one person and once for every zombie. The lines carry names and
  nothing numeric — no day, no count — because the chronicle sits on the HUD and clause 4 owns
  the HUD. A click selects rather than orders, because the owner's decision 12 is about what
  the screen *says*; orders are the micromanagement cliff (docs/23 risk 1) and stay unbuilt.
  Only a Focal body is clickable, because what you cannot see you cannot point at, and clicking
  your own pawn clears the selection because that is the cheapest way back to your own lines.
  The ring is thin and in the player colour and nothing else about the pawn changes: it marks
  whose lines you are reading, not whose turn it is. `hud_panel` was deleted rather than wired,
  because the `panel: true` prose it returned was one sentence longer than the HUD glimpse and
  said nothing the glimpse did not.

## Overcast or torchlight, 2026-09-08

Decided by the owner, 2026-09-08, from a design brief built on the shipped renderer's own
screenshots and sprites, regraded and overlaid to put a picture beside each question (the mock
images are not committed; the brief described what each showed). The question was how far a
"graphics overhaul toward Zero Sievert and the other inspired art pieces" should go, given that
the art had already been to Zero Sievert once (2026-09-01/02) and back (2026-09-03, "The
Dungeon Settlers look" above). Seven answers, each recorded once here and each paid for in the
slice that lands it (docs/23, "Art & renderer — overcast or torchlight", in order):

- **A hybrid.** The Dungeon Settlers spine stays — face-on pawns that flip, walls with a lit
  cap and a south face, roofs cut out where the sim sees, tall sorted trees, three-quarter
  vehicles on one skeleton with thirty-one overlays — and the *world* takes Zero Sievert's:
  the grade, density, grain, the torch, a remembered map. Reopening the pawn convention a fifth
  time was refused for the body's *orientation* (nobody rotates, still) and taken for its
  *proportion* (below). The projection stays flat top-down: "somewhat isometric" is the
  three-quarter read inside it — wall faces, three-quarter props, a squat pawn — and a real
  isometric projection, reversed twice in docs/00, is not what was asked for.
- **The mood is overcast by day and warm by night.** Cool, desaturated daylight under a grey
  sky, and the pools, the fire and the torch kept as the one saturated thing after dark —
  which is what Zero Sievert itself does. This amends "the mood is warm dark fantasy" above
  for the day and keeps it for the night, and the sentence that made the warm regrade
  affordable survives verbatim: the mood is enforced by properties, not remembered. The
  PALETTE lane's one warm family becomes two measured families keyed to the phase, re-pinned
  in the grade slice and never loosened in passing.
- **Unseen ground is the remembered map, dimmed.** Tiles the survivor has seen persist,
  desaturated, and bodies are never drawn in them; a tile never seen stays the void. Zero
  Sievert's whole-map-darkened read was refused by clause 4 — it shows layout the survivor
  never saw. Draw ⊆ seen becomes draw ⊆ seen ∪ remembered, over the sightings and memory tint
  the sim already keeps; the lit-pool discipline is unchanged.
- **The wall is Dungeon Settlers' construction: a cap and a one-tile face below it.** The face
  hangs over the tile to the south and **joins the entity y-sort**, so a body standing on that
  tile draws over it the way a body draws over a tree. This amends the 2026-09-03 wall clause's
  "nothing hangs over a walkable tile": a face does, as an entity-sort member, and no *tile*
  depth sort returns even then. The 2026-09-02 roof rule stands untouched.
- **The pawn is squat: one tile tall, with a big head and short legs.** Picked from a strip of
  real rigs at five heights, then squashed a second time on sight ("shorter legs and a bigger
  head"). Paid for below.
- **Weapons are the read.** What a survivor carries and wears keeps drawing on the pawn, and on
  the shorter body the held weapons read larger against it — the Zero Sievert emphasis the
  owner named — without a picture moving: every overlay hangs off the published skeleton.
- **The references, named.** Zero Sievert, Dungeon Settlers, Project Zomboid and RimWorld;
  nothing new supplied. Each is third-party and stays uncommitted; what each one bears on is
  what docs/00's influence table already says, and this entry adds only that RimWorld's pawn
  proportion is now the pawn's.
- **Not adopted, re-affirmed a third time.** The bars, the icon row and the name plates; 32 px
  a tile and the zoom ladder; the flat projection.

**Waiting on the owner, not on code.** One answer — *"when selecting the character, sprite art
will appear"* — names a picture on select that the tree does not have and this entry does not
decide: a portrait was refused with the Dungeon Settlers HUD on 2026-09-03, and a larger
picture of the selected pawn in the colony panel is not a portrait, but which of those was meant
is the owner's to say. It is named in docs/23's what's left as "the picture on select" and is
not pickable until then.

**Paid for, the pawn slice (2026-09-08) — a body is a squat, face-on pawn one tile tall, and
the head carries the read.** The canvas is `Appearance.PAWN_CANVAS`, one tile wide by one and
a quarter tall (32×40), feet-anchored as before; the 32×48 canvas of 2026-09-03 was superseded
rather than resized, because a proportion is a re-authoring and not a crop. Only the *rows* of
the published skeleton moved — `FEET_Y 0, LEG_TOP_Y −6, TORSO_TOP_Y −16, SHOULDER_Y −14,
HAND_Y −8, HEAD_CY −21, HEAD_R 6.0`, with `HAND_X 8.4` and `SHOULDER_HALF 8.0` untouched — and
that is what made the slice a session rather than a week: all thirty-one gear overlays are
authored against those names and refit by re-rendering, and the four numbers moved by hand were
the ones that hung *below* the hand (the bow's lower limb, the lamp, the lantern, the school
bag's depth), which on the tall rig was empty canvas and on the squat one is the legs and then
the soles. The figure is 27–29 px tall (26–30 the bound; the bloater 25 with its head sunk),
the head 12×13 (≤ 13×14) and 46 % of the figure where it was 27 %, the eyes one column further
apart, every column bound of the 2026-09-03 slice unchanged (shoulders ≤ 22 human, 26 bloater,
≥ 3 px side clearance). The bloater's three own numbers are published beside the family's
(`BLOATER_HALF`, `BLOATER_HAND_X`, `BLOATER_HEAD_SINK`) rather than typed into one rig.
`RIG_LIGHT_RADIUS` re-measured to 13.0 by the same rule as before (2982 opaque pixels, reach
−5.5 to +13.5; 0.13 % clamped, the whole gain spent). No new gate: `TOPDOWN_OK`'s FLIP lane
re-pins the canvas to n × 5⁄4 and the exact rect at the boot zoom to `Rect2(68, 23, 64, 80)`,
`WORN_LOOK_OK`'s FITS lane carries the new skeleton copy and still holds every overlay inside
the eight-rig envelope (the spear tip stops under the screamer's crown on purpose), and
`APPEARANCE_OK`'s GREY lane re-measured the colonist at a median of 0.7020 and a tightest
composed margin of +0.018 — thinner than the +0.022 of the tall rig, still the owner's to
widen, and quantised to about a byte as before. Nothing under `godot/sim/` moved.

## The inventory sheet, 2026-09-08

The inventory has been mechanically complete since Milestone 1 — a grid per container, twelve
equipment slots, nesting to depth three, attachments, modification, eighty-nine bases — and the
screen has never reached more than four of its commands. The owner opened an overhaul from four
mockups and decided it in six answers. Each is recorded here because each will look arbitrary
to the next session, and none of them is.

- **The Tab screen is a fixed sheet, not a desktop.** Every carried container has been its own
  window since 2026-08-19 — draggable, pinnable, its position remembered per label in
  `user://ui_prefs.json`. That bought quick pouches usable during play and cost a screen where
  two bags could stack on each other (they did: the pockets spent a session under a hiking
  pack, which is why `_alloc_default` exists at all). The pick is one fixed layout: the body
  and its twelve slots on the left, one **column of bag grids in a fixed order** — pockets,
  belt, vest, back, then any nested container the player has opened — in the middle, an
  **inspect pane of words** on the right, and a **quick strip** along the bottom. `prefs.gd`
  keeps the opacity slider and loses `windows`; `pinned_opacity` goes with the pinning. What
  the pinning bought is bought instead by the quick strip, which is on screen during play and
  is the same belt and pockets.
- **A verb is present or absent, never greyed.** Right-click opens a drawn word menu built from
  `SimInventory.verbs_for`, which asks the sim whether each command would succeed. This is
  `work_panel.gd`'s idiom and `SimTreatment.response_view`'s contract: a thing you cannot do is
  not there, rather than there with a reason beside it. The rule that keeps it honest is that
  the predicate the menu asks is the *same function* the intake runs — `SimNeeds.can_use` is
  extracted out of `use_item` rather than written twice, because two copies of "can you eat
  this" is the shape every dead socket in this milestone has had.
- **A container is the same component a pack is.** The obvious build was a second kind of
  container with its own contents and its own fit test. The pick was to reuse `container {w, h,
  items}` exactly, so a cupboard is a grid in the sense every other grid in the game is one and
  `item.move` is how you take from it. Two fit tests is one of them being wrong; what the reuse
  cost is a **reach guard**, because `item.move` had never known who was moving the item and a
  cupboard across the room is not a pocket. The `opening {container}` component is what says
  somebody is standing at it, and it holds the id as a value rather than as a key, because a
  Dictionary keyed by an entity id does not survive a save (CLAUDE.md's traps).
- **Looting is a small window, not the whole screen.** A cupboard has been a HUD sentence and an
  instant scatter onto the floor since site depletion landed. It becomes a real container with
  a grid, opened by the same E ladder, drawn beside the pockets **without leaving the
  district**. The reason is the trade docs/12 is built on: the risk in a scavenging run is the
  walk there and the noise on the way back, and a full-screen modal at every cupboard is a
  player who stops looking at the street. The full sheet still shows it when you open it there.
- **The condition words move onto the pawn — one body, the player's own.** docs/23 has asked
  for "condition and stamina readouts in the world, not a corner" since the prose contract
  landed. What ships is one short digit-free line beside the player's own body and nothing
  above anybody else's: a line over every pawn is a **name plate**, refused with the Dungeon
  Settlers HUD on 2026-09-03 and refused again here. The corner column keeps its lines, because
  `check_hud`'s quiet-survivor and selected-colonist lanes are what prove the prose contract and
  a tag that replaced them would leave those lanes with nothing to judge.
- **The quick strip takes 1–6; game speed moves to `-` and `=`.** Numbers on a hotbar are the
  one place a digit on the screen is not a measurement — it is a key's name — and the strip
  shows a stack count for the same reason the grid does (docs/10: counting discrete objects is
  not uncertainty collapsed). Speed had 1/2/3 and moves rather than sharing, because a key that
  means two things mid-fight is the bug the E ladder was built to avoid. Pressing a strip key
  on a bandage does not open a menu: it is `treat.context` with the rung chosen by what you
  pressed, so the T ladder and the strip cannot disagree about what first aid means.
- **How a thing looks is content, still — and a class glyph is the fallback.**
  `item.appearance.sprite` has been in the schema since the appearance pipeline landed and read
  by nothing (the milestone's twelfth dead socket; a dropped item is a fixed ten-pixel square).
  It gains a reader, `Appearance.item_look`, resolving the declared key when there is art and
  falling back to **one drawn shape per item class** — never an `if id ==` branch, which is the
  rule that entry exists to keep. Per-base pictures are their own slice; the socket closes now.
- **The paperdoll becomes a pixel body chart.** Asked to judge the drawn figure at the size the
  sheet draws it, the owner's word was "too alien". The procedural body is one file and every
  proportion in it is a constant, so re-proportioning was the cheap answer and was offered; the
  owner picked the chart. Ten parts by three poses generated in `tools/sprites`, each part
  modulated by its state tint — which is a colour on a shape, not a fill on a bar, and so still
  inside the ban the condition view enforces. The armour stroke, the wound and infection marks
  and the stance word are unchanged; `godot:ban:healthbar` never sees this file, because the
  doll reads `SimCondition.view` and nothing else, which is the whole reason the ban is
  mechanical there rather than here.

**What the chart made structural.** The art the doll draws is a **mask**, not a picture of a
person in colour: near-white, multiplied by the state tint at draw time. That is what let a
textured doll keep a ban that was written for a drawn one -- `godot:ban:healthbar` judges
`SimCondition.view` and has never looked at this file, and the art is handed a *state* and knows
nothing else, so there is no fraction for it to leak even by accident. It also bought the armour
indication for free (the same texture, four times, a pixel out, in steel) and cost one new
palette family, `chart`, which is the only thing in `tools/sprites` allowed outside the value
bands every world colour is held inside -- named as an exception in `palette.py` because it never
stands on the ground and the ground-contrast rules have nothing to say about it.

**What this does not change.** The health-bar ban and the digit ban (`godot:ban:healthbar`,
`godot:check:hud`); the grid as the honest picture of capacity, with weight never printed
(docs/10); site depletion, which stays "rolled once, `searched` never cleared"; and the sim's
ignorance of presentation — every new read model returns words and shapes, and every player act
still goes through the command queue.

## The character overhaul, 2026-09-09

Decided by the owner, 2026-09-09, from a fixture round rather than from prose: asked how deep
the animation should go, whether a body is ever seen from behind and whether the rigs are
re-drawn, the owner's answer was **"show examples of art first then I will decide"**, and the
round that answers it is `.hermes/plans/2026-09-09_character-fixtures/` — four sets of candidate
art, every one of them a *transform* of the shipped generator rather than hand art beside it, so
that what the pictures showed is what a slice would actually be. Its `comparison.md` describes
each image and recommends none, the arrangement the 2026-09-01 art-style round set.

The round's own load-bearing result, and the reason the animation answers below are affordable:
all eight rigs rendered at rest through the prototype's pose layer come back **byte for byte
identical** to the shipped PNGs, with the true negative in the same script (a lifted foot must
not render identically to rest). So a body standing still draws exactly what it draws today, and
`sprites:check`, `APPEARANCE_OK`'s size, ROSTER and GREY lanes, `WORN_LOOK_OK`'s FITS envelope
and `TOPDOWN_OK`'s exact blit rect are untouched by the animation itself.

Four answers, each paid for in the slice that lands it (docs/23, "Art & renderer — the character
overhaul", in order):

- **The rig keeps its proportion and gains a fist, a tell and a mouth — and banded shading.**
  The squat one-tile body of 2026-09-08 was re-offered at 32×48 and **kept**, so the head stays
  46 % of the figure and the "shorter legs and a bigger head" call stands. What changes is the
  read at that size: the hand becomes a fist one pixel further out with a knuckle line, so a
  held weapon has something to sit against instead of floating beside the body; each human gains
  a tell that changes the **silhouette** rather than the paint (the player's turned-up collar,
  Mara's bob tucked behind one ear — asymmetric, so the flip swaps sides the way a tucked bob
  does when a person turns round — Ellis's high collar, the colonist's peaked cap); and
  `nw_shade` is quantised to three steps instead of a continuous ramp. That last is measured
  rather than asserted: the player rig goes from **67 distinct colours to 15** at the same light
  direction, which is the "muddy at the boot zoom" complaint answered by throwing away a
  gradient nobody can see at 32 px.
- **A face is four pixels.** `assets/sprites/README.md`'s "a face is three pixels" becomes four:
  two eyes, a brow, and **one** mouth pixel below them. One and not two — a pair reads as a
  moustache at this size and a three-pixel band as a grimace, and both were drawn before the one
  was picked. The head is 46 % of the figure, which is the one place a pixel buys the most.
- **The walk is four frames with the weight shift.** A contact between each pass, the lift **2
  px**
  (the legs are six pixels long, so one is a sixth and reads as a rounding error at the boot zoom
  while three leaves the foot merging into the trunk), and the whole upper body leaning one pixel
  over the leg carrying it. The two-frame leg swap named since 2026-09-08 was drawn and shown and
  is **superseded**: at six pixels of leg it is close to invisible at the boot zoom, which is a
  thing the picture said and the prose could not. The arm swing was offered and **not** taken, so
  nothing above the hip that a weapon hangs off moves and the thirty-one gear overlays follow the
  walk for free. An idle breath is a separate call and is not taken here.
- **A body is drawn from four directions.** The pawn convention is reopened a fifth time and this
  time it moves: front, side and back are authored, west is the existing negative-width mirror of
  east, and the sim's `facing` picks between them. This supersedes the "nobody rotates, the player
  included" clause of 2026-09-03 **as a rule about what a body may show**, and leaves it exactly
  intact **as a rule about how it is drawn**: a view is a fourth picture, never a transform, so
  `check_topdown.gd`'s two counters stay at zero and the flat projection is untouched. The cost is
  stated rather than discovered — every extra view is another picture per rig *and* another
  picture per overlay, and the side view is the one piece in the set that is a re-authoring rather
  than a transform, so it is the one that is not a single session.
- **The condition diagram is the exploded chart.** Ten parts pulled a pixel off their neighbours,
  each drawn as a plate with its own border, the way an exploded assembly drawing separates
  components; uniform gaps, so they read as seams rather than as a body coming apart. This is the
  **third** answer to this screen — the drawn capsule figure was "too alien" on 2026-09-08, the
  pixel body chart that replaced it was "ugly" on 2026-09-09 — and what the two rejected ones have
  in common is a mannequin. The chart's anatomy is what went, not its arithmetic: the body it is
  drawn on is a person, a head about a sixth of the figure and legs a shade under half of it,
  where the mannequin's head was a quarter of the canvas and its legs began below the middle of
  it. Separation is what answers "which part" without a label.

**What this makes structural.**

- **A pose is a parameter, not a picture.** `characters._figure` gains per-side legs and feet and
  a canvas bias that carries the whole upper body — including each rig's own `tells`, `hair` and
  `face` callables, which is what keeps eight rigs and thirty-one overlays in register for
  nothing.
  Frame 0 of every clip is `Pose()` and must stay byte-identical to the shipped key; that equality
  is the assertion the animation slices are held to, and it is red the moment a pose leaks into
  it.
- **The view is an axis of the key, and the frames go in a horizontal strip.** Not a grid, for a
  measured reason: `check_worn.gd`'s `_row_of` keys off `PAWN_CANVAS.y`, so the legs/torso/head
  row
  predicate survives a horizontal widening and a 2D grid would destroy it outright.
- **`check_worn.gd`'s FITS lane must go per column and per view, or it goes weaker without
  erroring.** `_bounds_of(image)` iterates the whole image, so on a strip the eight-rig envelope's
  `max_x` widens from 26 to about 90, every overlay fits trivially, and its corner-pixel true
  negative still passes. This is the "a gate that cannot fail is worse than no gate" failure with
  no red line to announce it, and it is named here because the next session will not find it.
- **One sheet per rig, blitted by region, is now mandatory rather than an optimisation.** Four
  views times four frames is about 468 pawn textures where 39 ship today, and this repo has
  already
  measured draw calls going 539 → 1,410 when wall materials became separate textures, because a
  texture change between two blits breaks the 2D batch. The atlas lands with the frames.
- **The face bound moves and the colour bound tightens.** Four face pixels, and a rig carrying
  fifteen colours rather than sixty-seven; `APPEARANCE_OK`'s GREY lane re-measures per column
  rather than quoting, because the extra columns are real posed bodies and the composed margin is
  a byte or two.

**What this does not change.** The flat top-down projection and 32 px a tile at 2× (reaffirmed a
fourth time); the feet anchor and `FOOT_DROP_PX`, so the sole line and the contact shadow are one
number in every pose and every view; the health-bar ban and the digit ban, which the new diagram
is inside by construction — it is handed a *state* and a handful of words, so no part is ever
partly filled and no fill level is computable; the refusal of bars, icon rows and name plates; and
the sim's ignorance of presentation. Nothing under `godot/sim/` moves for any of it.

## Art we did not generate, 2026-09-09

Decided by the owner, 2026-09-09, opening with *"we might look into getting proper sprites"*.
Three answers, and the first one is what makes the other two cheap.

- **Commissioned to this project's spec, not bought as a pack.** An artist comes to the geometry
  in `assets/sprites/README.md` — 32×40, feet on the bottom row, the published skeleton, the
  1 px outline — rather than the project adapting to a pack's grid, its proportions and its
  frame layout. What that buys is that nothing about the renderer has to bend: the canvas table,
  the anchor rule, the blit rect and the flip all keep meaning what they mean, and the whole of
  the support work is letting art the generator did not draw *exist* and holding it to the spec
  it was commissioned against. The bought-pack path was costed and refused: it would have put
  the published skeleton out of use for those rigs, left `check_worn.gd`'s FITS lane with
  nothing it could judge them by, and carried a share-alike licence into the asset tree.
- **Equipment stays drawn on the body, and that is a requirement of any art we take.** "What you
  wear shows on your body" landed 2026-09-04 and is gated; most character art bundles its
  clothing into the frame, which would un-ship it. So a body whose jacket cannot be taken off is
  art this project cannot use, and the brief says so in those words. It is also what keeps the
  2026-09-08 "weapons are the read" call true: on a one-tile body the held weapon is a large
  share of the silhouette, and it is an overlay.
- **The pawn arc pauses; the diagram does not.** R3, W3 and F2 hold until it is known whether
  commissioned bodies are coming, because bought or drawn bodies would make all three moot. The
  exploded body chart does not wait: it is UI art on its own canvas, its only lane is
  `check_appearance.gd`'s CHART, and the animation arc never touches that file's CHART lane.

**What this makes structural.**

- **Two tiers, declared rather than inferred.** Every PNG beside `authored.json` is either
  *generated* — drawn by `tools/sprites` and re-rendered pixel for pixel by `sprites:check` — or
  *authored*, and declared. A filename convention was the obvious alternative and was refused:
  the point of the declaration is that a key nobody declared is a build failure that says which
  tier it is missing from, where an undeclared PNG used to be a file nobody could account for.
  `build.py` refuses a key claimed by both tiers, because one says "regenerate me and compare
  every pixel" and the other says "do not".
- **`authored.json` is one file with two readers, which is the point.** `tools/sprites/build.py`
  reads it so `--check` knows not to regenerate; `presentation/appearance.gd`'s `canvas_of`
  reads it so the renderer knows the shape. Every other shape table in this project is carried
  twice — `PAWN_KEYS` in Python and in GDScript, `VEHICLE_FOOTPRINTS` in both — because Python
  cannot read GDScript, and each of those pairs is a thing that can drift. For authored art the
  file is the shared copy, and a declaration the renderer disagrees with is a MANIFEST failure
  rather than a picture that stretches.
- **The spec is held against the art that already meets it.** `godot:check:authored`'s SPEC lane
  measures the eight *generated* rigs against the same bounds it will measure a commissioned one
  against — height 25–30, shoulders ≤ 22 (26 for the one broad rig), head ≤ 13, side clearance
  ≥ 3, soles on the bottom row, every edge pixel `#161614`. A spec measured only against art
  that does not exist yet is one nobody can be held to; this way a bound going red means the
  roster and the brief have drifted apart, which is a thing worth being told. Shoulders and head
  are read at the published skeleton rows rather than off the silhouette, because the widest row
  of a body is not its shoulders and the widest row above the middle is not its head.
- **Art nothing reads is refused at the declaration.** A declared key names the content entry
  that draws it, and the gate checks the entry actually does. That is the dead-socket rule
  applied before the socket exists, and it is cheaper here than anywhere else it has been paid
  for: a commissioned PNG sitting in the tree looking finished, drawn by nothing, is exactly the
  shape twelve of them had.

**Named, not fixed: what the first commissioned body costs.** An authored rig is not in
`Appearance.PAWN_KEYS`, and that array is what `check_topdown.gd`'s FLIP lane iterates and what
`check_worn.gd`'s `_rig_keys()` counts — a count that asserts **exactly eight**. It is also the
source of `check_worn.gd`'s FITS envelope, the union of the eight rigs' opaque boxes that every
equipment overlay is measured inside. So the slice that lands the first commissioned body widens
all three deliberately, or the body arrives with its equipment judged against a roster it is not
in. Naming it here rather than pre-emptively widening them is the same rule as everywhere else:
a gate loosened for art that does not exist yet is a gate that cannot fail.

**What this does not change.** The generated tier, which is still 151 of the 151 keys and still
the source of record for every zombie, every tile, every vehicle and the whole of the art's
reasoning; `sprites:check`'s pixel-exact comparison, which is untouched for those keys; the
canvas, the anchor and the flip; and the sim's ignorance of all of it.

## Water, and the one cool ground, 2026-09-09

The owner asked for a default town — city, forest, factory, river and lake — with procedural
generation beyond it, and the answer was that most of it already exists: the city and the forest
are shipped district types, the generator has rolled districts from a seed since the worldgen arc,
and `docs/24`'s "authored templates, procedurally assembled" is the same split the question
proposed. **Water was the one piece that existed nowhere** — no tile, no surface, no pass, no
content key, and no mention in docs/24 either. Four decisions shaped it, and one of them amends an
earlier decision of the owner's.

- **Water is one tile and one surface, not four kinds of blue.** docs/24's ground rule is two
  arrays, never one enum, and water is the case that rule was waiting for: deep water is
  `Tile.Water` standing on `Surface.Water`, and a ford is an ordinary `Tile.Floor` standing on the
  same surface. Enumerating deep-vs-shallow as tile classes would have been a product of two sets
  again, which is the mistake the ground layer exists to avoid.
- **Deep water carries the window's pair: solid, transparent.** It stops a body and not a
  sightline, so a river is a barrier you can be shot across. This is why nothing in the pathfinder
  or the shadowcast changed: `SimPath._footing` already accepts `Floor` (so a ford walks) and
  `walkable_tile` already refuses a solid tile with only a Door exception (so a channel does not),
  and `blocks_sight` reads the opacity table, which answers Clear. A water-shaped special case in
  either would have been the wrong answer arrived at twice.
- **A ford is worse than every other ground on both axes, and that is not a broken rule.** Speed
  ×0.45 and noise ×1.8 — the slowest and loudest ground in the game. docs/29's "nothing may be
  strictly better than anything else" forbids a free lunch; a ford is the opposite of one, and it
  is never weighed against walking on grass. It is weighed against walking all the way round.
- **Water is genuinely blue, and it is the one ground exempted from the warmth sign.** This
  **amends [the Dungeon Settlers look](#the-dungeon-settlers-look-2026-09-03)**, whose warm mood is
  held by a mechanical margin — every district surface, wall, paint, prop and memory tint warmer
  than it is cool, `r - b >= 0.02`. The owner's call was that water reads as water or it reads as
  nothing. The exemption is a **named pin, not a hole**: `check_road_look.gd`'s `COOL_SURFACES`
  judges the exempted ground with the *cool* pin instead of skipping it, so a water tint drifting
  to neutral grey fails exactly as a warm ground drifting to grey does — and the saturation cap is
  **not** exempted, which is what keeps "blue" from becoming garish. Water joins `COOL_FAMILY`
  beside the glass, which is the entry that was already the exception to the mood.

## The main area, 2026-09-09 / 2026-09-10

The owner's two decisions about the region, and the four things building it made structural.

- **The extent: a 2×2 of full 256 m districts, nearly touching.** Chosen over a roomier grid of
  smaller ones, explicitly accepting that it sits on the measured line, because **a district staying
  exactly 256** is what keeps every balance band, the survivability validator and the harness
  measuring the thing they were calibrated on. The shipped number is **528 = 2 × 256 + a 16-tile
  seam**: 512 exactly would leave literally no room between the districts, and shrinking them to 248
  to hit it would give up the one property that made the choice.
- **This amends docs/24's district spacing, and the amendment is the point rather than a detail.**
  That document argues *in writing* for 300–500 m between districts, with a reason — packed
  edge-to-edge a 3×3 spans 768 m and the player walks 800 m by week 6, so they would cover the
  region on foot before ever needing a vehicle. A 16-tile seam is far under that and leaves roadside
  wrecks and road blockages nowhere to live. It is shipped anyway because the measurement (docs/23's
  record) says a 912-tile region runs at 0.46× real time and cannot be resident. **The extent is
  content, not a constant**, precisely because there is no headroom: `cellTiles` is the dial to turn
  when a real run says so, and turning it needs no code change.
- **The colony can be established anywhere.** So the annex is not assigned to a district: every cell
  generates colonyless and candidates are ranked across all four. That answer matches the
  vertical-slice design record word for word — Task 8's *"Any location can host a camp. There are no
  hard suitability restrictions; danger, exposure, and time-to-establish are the cost."* — which
  covers a **runtime** half this arc did not build. The generation-time half landed; Task 8 is named
  in docs/23's what's left rather than smuggled in beside it.

### The outpost, and the path it exposed, 2026-09-10

- **An outpost is reach, not danger** -- the owner's call, taken after being shown that "outpost" had
  no prior design authority: the word existed only in the camp slice's own record. It extends where
  colonists will work, which is the answer to docs/12's expanding radius, the difficulty curve the
  world generates on its own. The alternatives (a stash, a raider target, all three at once) are
  named in what's left; useful before dangerous was the explicit ordering.
- **`_near_home` draws a circle per place the colony lives, not one around home.** The constant did
  not change; how many circles it draws did. An abandoned camp draws none -- it is a known empty
  site, not somewhere anyone works.
- **The stockpile is the one home reader that does not follow a camp, and now says so where it is
  read.** `is_stockpile_tile` means "indoors, floor, inside the annex"; a camp has no roof, so a
  camp-relative drop point would be a stockpile the rain falls into. The consequence is a real trade
  and it is recorded rather than hidden: an outpost extends what colonists collect and not where
  they put it, so a far outpost still costs the walk home.
- **A gate can pass because it re-tests the previous slice.** The first `REACH` lane established a
  camp far away and called it an outpost -- but `SimCamp.create` makes the new camp *home*, so the
  lane was proving that home's radius moves with home, which the camp slice had already proved. It
  stayed green with outpost reach removed entirely. The fix is two camps plus an explicit assertion
  that `home_of` is not the far one. **Proving the negative is the only thing that found it**, and
  the shape is worth naming: a lane whose fixture accidentally satisfies the *previous* mechanism
  tests nothing new.
- **The dead-socket rule has a second level.** `check_m2_camp`'s READS lane asserted that
  `jobs._home_centre` moved, and the record beside it claimed three further functions moved with it.
  They did not, and the lane could not have noticed: it asserted the reader, never the readers of
  that reader. Asserting that a mechanism has a reader is not the same as asserting that the things
  said to hang off that reader do.
- **Pillar 6 decided the order.** Reach measured **9.8 ticks/s against 62.8** -- under the 20 Hz
  clock -- because of one enclosed item, not because of distance. The owner chose to fix the
  underlying pathing defect first rather than cap the reach or accept the cost. After the fix,
  **78.4**. A feature that breaks budget does not ship until it is fixed, and "the defect is
  pre-existing and already listed" is not an exemption when the feature is what makes it reachable.
- **A failed plan is a result, and gets remembered like one.** `_walk` plans once per map
  generation now: `pathFailGen` separates "no route" from "path consumed", and an `unreachable`
  component on the target -- shaped like `reserved`, keyed by `mapGeneration` so a door opening
  clears it -- stops the work-finders re-offering it. `SimPath.find` is untouched and still cannot
  tell "guard exhausted" from "no path"; the fix is that nothing asks it twice.

### The camp, and where home is, 2026-09-10

- **The owner's shape for a camp: temporary, evolvable later, usable as an outpost.** Asked whether
  the generated annex and a player camp were one concept or two, the answer was neither of the two
  offered — a camp is a *lighter* thing than the annex, there may be more than one, and turning one
  into something permanent is later work. So `SimCamp` allows many camps with exactly one flagged
  `home`, and deliberately gives a camp no indoor floor, no stockpile and no walls.
- **Home is a read model with the map anchors as its floor.** `annex`, `gate_a`, `gate_b` and
  `player_start` were generation-time entries in `map.anchors`, read independently by seven modules
  across 24 call sites, and `map.anchors` is never serialised — so an anchor written at runtime would
  vanish on the next load silently. `sim/home.gd` is one ladder whose last rung is what each caller
  did before, which is what lets a world with no camp answer byte-identically. **Four readers were
  left on the anchors on purpose** and each says why in the code: the stockpile (a camp has no indoor
  floor), recruits (strangers at an outpost is a design question), boot (generation-time), and
  `can_scrap` (about the authored gate).
- **A camp is a prop entity, because there is no place-emitter.** The only recurring emission in the
  sim comes from the two per-entity systems in `attention_emitter.gd`; a place emits by having
  something stand on it, which is what the campfire, the latrine and the noisemaker already do. That
  also means **no `SAVE_VERSION` bump** (it stays 29): `component_store.save()` is generic and a new
  component is the case `serialize.gd`'s ledger already records for treatment.
- **It carries no emitter of its own, and the plan for the slice was wrong about that.** An emitter
  with every channel zero is a dead socket of the shape CLAUDE.md lists eleven of. What emits at a
  camp is the fire, the light and the people, all of which emit already — which is the same reason
  the director needed no change: `_emit_packet` never targeted the colony, and the pull is the field.
- **Establishing is a channel and its own key.** Task 8 asks for "a deliberate, interruptible
  commitment — not a menu click", so it reuses fortify's channel whole and inherits the stagger and
  grab interrupts and `CONSTRUCT_NOISE` — docs/03's 30, "a beacon all day" — rather than inventing a
  number. **C**, not a rung on E's ladder: moving home by accident is worse than one more key, and E
  stays "act on what is in front of you". The 40-tick clock is fortify's ordinary one; a camp's real
  labour cost is the deferred slice, and until then establishing is cheap in time and loud in noise.
- **The night band follows home, on a region only.** The owner's answer. `SimCamp.sync_map` sits
  beside the fortify and vehicle syncs in `world.restore` because `spawn_edges` is derived rather
  than serialised. On a district it is a no-op and the perimeter scan runs unchanged, which is what
  keeps every measured band valid; on a region it moves the band to the camp's cell so a camp two
  districts away does not leave pressure arriving where the player no longer is.
  `SimTileMap.region_cell_stride` exists for it — the other two region fields say what a region is
  made of, this one says where the joins are, which is what a runtime reader needs when the region
  content is out of scope.
- **`GATE_EXCLUSION` is 32 m, and on a 64-tile gate world that is half the map.** A probe asking "is
  this tile legal now that home moved" answers false there for the exclusion disc rather than for the
  rect, which produced one wrong reading while `check_m2_camp` was being written. The `READS` lane
  runs at the shipped 256 for that reason. Same family as the annex-corner probe that reads as wall:
  a measurement needs to be shown it is measuring what it thinks it is.

### What the flip made structural, 2026-09-10

- **A prediction written as fact cost more than the bug would have.** "Every night arrives empty
  with no error" was reasoned from `_edges_by_side`'s first filter and written into docs/23, two PR
  bodies and `HANDOFF.md` before anything measured it. It was wrong: `_border` walls one tile and
  the band is three, so the pool is *larger* on a region than on a district. The real fault was the
  **distance** — 215–432 m from the gate against 122–182 — which is a dilution rather than an
  absence and would have been much harder to notice in play. The fix was worth building either way;
  the lesson is that a failure reasoned from a code path is a hypothesis until a driver has run.
  **The gate measures the distance, not the count**, because the count was never the problem.
- **A map may name its own spawn band.** `SimTileMap.spawn_edges`, on the `streets`/`vehicles`
  precedent: a plain Array, never serialised, empty on every district, consulted by the director
  only when non-empty. A region writes the annex cell's own inner band, so night pressure keeps the
  distance every measured band was calibrated at. The other three districts deliberately do **not**
  contribute: pressure arriving from across the region is a design and balance question, not an
  oversight, and it wants the owner and a measurement rather than a default.
- **Population is the sum of a map's cells, never a function of its extent.** A region's seams are
  road and countryside and hold nobody, so a side reading counts ground with nowhere to live on it.
  The per-side functions stay pinned and untouched; the region reading is its own function.
- **The budget chose the district size, and the cost is named.** At `cellTiles` 256 the region
  measured **0.94× real time** — under its own clock — so by docs/00 pillar 6 it did not ship. The
  owner shrank the cells to 192: 400 tiles, **1.48×** against a district's 4.15×. What that gives up
  is stated rather than glossed: **a region's districts are no longer the 256 m the balance bands
  were measured on.**
- **The region is opt-in.** `--region=<id>` boots it; the default is still one district. 1.48× is
  above the clock with much less room than 4.15×, and the same container has measured the same
  district at 55 and 83 ticks/s on different days — so the margin is real but not comfortable, and
  making a region the default is a decision to take after playing rather than from a table.

### What the assembler made structural

- **Call the district generator; do not fork it.** `SimWorldgen.generate` assumes a square map whose
  edge it walls and whose whole area every pass scans. Rect-relative passes would have been a
  rewrite that moved every layout and invalidated every measured band. Generating each cell as its
  own district and blitting it in buys the strongest assertion available instead: **a cell's
  sub-rect is byte-identical to that district generated alone**, which proves the assembler moved
  *nothing* rather than proving it moved the right things.
- **Per-cell seeds keep every worldgen pass untouched.** A cell's seed is
  `derive_seed(region_seed, "region.<x>.<y>.<district>")` and *that* is what the existing
  `_stream(seed, "worldgen.<pass>")` chain derives from — so no pass changed, and swapping one
  cell's district re-rolls only that cell, which is what the procedural-expansion end goal will want.
- **Site the colony on the layout, never on the finished map.** The first assembler ranked candidate
  lots by street frontage read off the assembled region, and switching the dressing off moved the
  colony 45 tiles: `_rubble` heaves patches up through a street and `_street_frontage` counts paved
  neighbours. docs/30 already recorded this rule for a district — *"a colony sited off the trees
  would move when the trees were switched off"* — and it was broken at region scale by re-deriving
  the ranking one layer too late. **The rule generalises: anything that decides where something is
  built reads the layout, and only the layout.**
- **A manifest offset has a direction, and getting it wrong is silent.** `axis "x"` is a *vertical*
  street at column `at`; `axis "y"` a horizontal one at row `at`. A span offset with x and y swapped
  still lands on the map and still looks like a street manifest, and only the road paint and the
  path pass quietly go down the wrong lines. `check_m2_region.gd`'s MANIFEST lane walks every span
  to its own midpoint and refuses one that reads solid.

### What the generated water made structural, 2026-09-09

The pass that carves it, and the four things it taught. Each was found by a gate or a guard rather
than by review, which is why they are here rather than in a comment.

- **Water is layout, at 3.5, and the position is forced from both sides.** After the streets,
  because a bridge is *derived* from the street manifest and there is nothing to derive one from
  earlier; before the annex, the buildings and the loot, or the generator sites a colony in the
  river. It runs inside `layout()` so a re-site attempt re-runs it identically, which is what keeps
  `generate`'s retry loop a pure function of the seed.
- **An absent content block must cost no draw, not a discarded one.** `water` is optional and each
  of `river` and `lake` is independently optional, and a district declaring none creates no stream
  at all. That is the whole reason this landed without moving a single district authored before it,
  and it is the same argument `vehicles` and `terrain` already made.
- **"Is the map in one piece" is the wrong question; "what is the water responsible for" is the
  right one.** The first `water-crossable` clause asked whether all walkable ground was one
  connected component and failed a forest whose river was perfectly crossable -- trees enclose
  pockets constantly. Asked as a **difference** instead: flood once walking and once with the
  channel passable, and only ground the second reaches and the first does not is the water's fault.
  A gate that blames the wrong subsystem is worse than no gate.
- **Repair the terrain, do not retry around it.** One forced midpoint ford left a seed whose lake
  sat against the river's bend with a severed corner, and the generator then spent all 31 candidate
  lots re-siting a colony against a fault that had nothing to do with the colony. `_ensure_crossable`
  casts rays from a stranded tile and paves the shortest, bounded and drawing nothing.
- **A `protected` tile has to protect the *surface*, not only the tile.** The grass discs were the
  one dressing writer that never consulted `protected`, and got away with it until water existed:
  every protected thing until then was protected from having a tile stood on it, and the discs write
  a surface onto a Floor tile. A ford is a Floor. They turfed 49 of them. And the protection needs a
  **ring**, which the dressing taught rather than the design -- a ford stayed a ford while a stand of
  trees grew across the dry ground leading to it, which severs a district exactly as a missing
  crossing would.
- **The colony outranks the river.** There is deliberately no water filter in `annex_candidates`:
  `SimTemplates.stamp` writes the patch's own tiles over the whole footprint, so water under the
  colony is wiped rather than built around. Filtering was tried and left a 64-tile forest with zero
  candidates out of sixteen, because the annex is 26x26 and a river crossing a 64-tile map crosses
  everything.

### What wading decided, 2026-09-09

The owner's call that shallow and deep must be discernible, that you must be able to wade, and that
wading should wet you and lower your temperature. Three asks, one mechanic.

- **Wading needed no mechanic, only an assertion.** A ford is an ordinary `Tile.Floor` on the water
  surface, so it has walked since the surface existed, at the slowest and loudest numbers in the
  game. The honest thing was to gate what was already true rather than build it again -- and to say
  in the record that it was already true.
- **A ford soaks you at once; rain does not.** Rain has `wetAfterTicks` to soak through and a body
  standing in a river has nothing to soak through, so the wet state is set on the tick the body
  arrives. Everything else is the rain slice's: `wetUntilTick`, the same drying clock, the same
  fire bringing it forward, and the same `_colder` step that was already reading it. **A new
  mechanic here would have been the wrong answer to the same question docs/04 had already
  answered.**
- **Only the shallow half can wet you, and that is geometry rather than a check.** Deep water is
  solid, so no body is ever standing on it; the tile a body can stand on and still be in water is
  the bank or the ford. Nothing in the code asks "is this shallow" -- it asks what surface the body
  is on, and the answer falls out.
- **A value gap does not make two dark blues discernible; an edge does.** The channel darkening
  (`WATER_DEEP_SHADE` 0.30 → 0.42) was not enough on its own. What reads is the **shoreline**: every
  deep tile draws a lit rim on each side whose neighbour is not also deep. An edge says where the
  channel stops, which is the same thing as saying where a foot goes -- and a ford cut through the
  channel is outlined on both sides, so a crossing is visible before you are standing in it. Drawn
  off the water's own tile rather than as a fringe rule over every ground beside it, so the land's
  edge pass is untouched.
- **The channel is bounded from below as well as above.** The ford is held under value 0.3866 by
  the pawn-ramp contrast guard and the background is `#15141f` at 0.122, so the channel lives in a
  corridor: dark enough to read as depth, light enough not to read as a hole in the map. Both ends
  are named constants for that reason.

### What the yard decided

- **A new district type fills the last enum slot, and that disarms two gates.** `industrial` was the
  one location docs/12 named that nobody had written, and two of `check_loot.gd`'s negatives used it
  as their example of an unwritten table. Authoring it made both pass vacuously. One now names a
  table off the enum entirely; the other exposed a genuine gap -- with all five authored, the "has
  no content entry" branch is unreachable through the enum -- so it is proved against an authored
  set with one removed, which is what deleting a shipped table while a district still names it would
  look like. **A negative that leans on a slot being empty stops being a negative the day somebody
  fills it**, and this milestone will hit that again.
- **A district type is a data entry, and the fourteenth terrain knob is what made that true here.**
  The grass discs were hardcoded at half a block, so the first yard read as a suburb with sheds on
  it. `grassShare` defaults to 0.5 -- the historical value -- and is safe for the same reason the
  forest slice's thirteen were: it changes an **argument** to a draw and never how many draws
  happen. Without it, "adding a district type is a data entry" would have been false for any
  district that is not green.
- **Streets 4 wide, deliberately.** `VEHICLE_MIN_WIDTH` is 4, so a district declaring a `vehicles`
  block on 3-wide streets would be a socket nothing reaches -- the town centre and the forest are
  the measured precedent for leaving the block off entirely.

### What it made structural

- **A surface's int is an atlas row, so the painted rows sit after the last surface.**
  `Appearance.ground_row_for` returns a surface int *as* a `GroundRow`, which is what makes the
  ground atlas cheap. `GroundRow.Sidewalk` was 5 and `Surface.Water` arrived as 5, so before the
  re-index **a river drew as pavement** — silently, with `godot:m2` green, because no assertion
  connected the two enums. Water is row 5 now and the two paints moved to 6 and 7;
  `check_water.gd`'s ROWS lane asserts the two enums agree and that the paints sit outside the
  surface range, so a seventh surface cannot repeat it. The atlas PNG grew a row and had to be
  regenerated, which is what `sprites:check` is for.
- **Deep water takes none of the floor's furniture.** The channel is one flat fill: no road paint,
  no ground-atlas cell, no fringe. Each of those passes would otherwise draw a kerb, a dash or a
  grass edge into the middle of the river, and the fringe one needed `Tile.Water` adding to the
  ground-rows cache's exclusion list to stop it. The *ford* keeps all of it, because a ford is a
  floor — and that difference is what makes a crossing visible before you step in.
- **The deep colour is derived, not authored.** One water tint, darkened by `WATER_DEEP_SHADE`,
  the way a wall's face is lifted out of its cap: two authored colours would drift apart under a
  regrade.
- **A brightness ceiling nobody predicted.** The first water tint (`#55636b`, value 0.42) was
  refused at import by `tools/sprites/palette.py`'s `guard_against_ground`: it made water the
  brightest ground in the game, and the `fatigue_drab` pawn ramp then cleared it by 0.067 against
  a `GROUND_CONTRAST` of 0.10 — a colonist on the bank would have read as a hole in the river. The
  shipped tint is `#424f5c` at value 0.361. **A new ground is bounded from above by the darkest
  pawn ramp**, which is a constraint on every future surface and was found by a guard rather than
  by a screenshot.

**First cuts taken without the owner**, each one constant and each listed in `HANDOFF.md` the way
the driving and weather numbers are: the ford's ×0.45 speed and ×1.8 noise, the water tint
`#424f5c`, and `WATER_DEEP_SHADE` 0.30. The ten-day playtest is what they are for.

**What this does not change.** The five existing surfaces and their calibrated numbers; the
pathfinder and the shadowcast, both untouched; the three shipped district types, which declare no
water and are byte-identical; and the frozen TypeScript oracle, whose `Tile` stops at `Tree = 5`
and already lacked `Door = 6` — the oracle is not a party to the tile enum, though it does still
validate the map schema, whose tile and surface maxima grew.

## The second gear catalogue, and the four slots nothing fitted, 2026-09-09

The owner asked for more items — usable, weapons, and the rest — and shaped the slice in two
answers: **breadth plus the empty attachment slots**, and **a generated overlay for everything
held**. Twenty-five bases landed. The catalogue half is the 2026-09-06 slice again and needs no
new reasoning; four calls that are not obvious are written down here.

- **Four attachment slots were declared by shipped weapons and nothing in the world fitted them,
  and the fix is data, not code.** `haft` was named by six melee bases, `furniture` by three
  firearms, `limb` and `string` by the bow, and no shipped attachment fitted any of the four —
  a dead socket of exactly the shape this milestone keeps paying for, sitting open since
  attachments landed. `SimAttachments.SCALABLE` already permitted every field the five new
  attachments needed, so nothing in the module changed: the long haft, the recoil pad, the heavy
  limbs, the fast-flight string and the long barrel are five JSON objects. That is docs/10's
  "adding a new attachment slot type is a data edit plus a line in the slot-compatibility table"
  collecting on its promise, in the direction where the table already had the line.
- **The gate asks both directions now, because it only ever asked one.** `check_m2_attach`'s
  CONTENT lane has always asserted that every attachment reaches a host — a `fits` naming a slot
  no base declares is refused. It never asked the reverse, and the reverse is where the four dead
  sockets lived. **HOSTS** asserts every slot a shipped base declares has something that fits it.
  **SCALES** asks the same question of the code side: every field in `SimAttachments.SCALABLE`
  must be scaled by some shipped attachment, which caught `melee.reachMetres` and
  `ranged.rangeMetres` — both listed since attachments landed, both multiplied by nothing. Each
  lane was run against the content with one attachment removed and named exactly the socket that
  reopened, so neither is a gate that cannot fail.
- **The revolver does not jam, and every other firearm does.** `ranged.jams` is authored per base
  and the chance is derived from condition, never authored (the 2026-09-06 entry). A snub
  revolver with `jams: false` is the first firearm to decline it, and it is a real mechanical
  claim rather than flavour: a revolver has nothing to stovepipe, which is the same reasoning the
  flag's docstring already gives for the bow. It pays for it in rounds and reload — six, and the
  slowest of any handgun here — so "the gun that never fails you" is not also the best gun.
- **Dog food is the first food priced in mood rather than in hunger.** docs/04 says quality
  matters, not just quantity, and every shipped food has agreed with its own hunger number. A tin
  that keeps forever, fills a third of the bar and costs twelve mood is the first entry where the
  right call is sometimes to eat it anyway — which is the decision the mood field exists to
  create, and it needed no code because `food.mood` has been read since the block landed.

**Deliberately not in this slice**, named rather than left looking finished: attachment condition
(docs/10's "suppressors wear out fast" is still open, and the five new ones wear no faster than
the five old); armour attachment slots (docs/10 gives body armour plate/lining/pocket and headgear
face/light mount, and no armour base declares `slots` at all — `attachment` has no `armor`
multiplier table, so that one is code); the five ranged **affixes** docs/10 names, which stay
unauthored because `noise_emission` and `condition_loss` resolve to nothing outside the stat
registry and authoring them now would ship five dead affixes to fix four dead slots; and named
items, which need a fifth tier in `SimItems.TIERS` and a fixed-roll path.

## Gunsmithing: a weapon is an assembly, 2026-09-09

`godot/sim/modules/attachments.gd`, `godot/sim/modules/items.gd`,
`godot/content/items/parts.json`, gated by `npm run godot:m2:attach` and `npm run godot:m2:upkeep`.
The owner's direction of 2026-09-09, answering four questions at once: full gunsmithing rather than
stat-sticks, every weapon assembled from real parts, the firearm slot vocabulary widened, and the
work done at a bench.

- **The base template is the receiver, and `defaultParts` is what makes that true.** A base names
  the parts it comes built with, keyed by slot, and `spawn_item` fits them on the way out — so the
  service pistol in a drawer is holding a barrel, an action and a magazine, each an item with its
  own condition. This was chosen over rewriting content so that receivers are a separate class of
  base: it gets the behaviour with a data edit, and every weapon that does *not* come apart simply
  declares nothing. Melee is authored conservatively on purpose — a fire axe is a head and a haft
  and always was; a kitchen knife is one object.
- **`assemble` is called from `spawn_item`, not subscribed to `item.spawned`.** Assembly spawns
  entities, and a handler doing that during delivery would nest `deliver` inside `deliver` —
  the determinism bug `spawn_item`'s own comment records having already paid for.
- **And it draws no randomness, which is asserted rather than assumed.** Each part is spawned at an
  explicit `"scavenged"` tier, skipping `roll_tier` and returning before `roll_affixes` draws. If
  it did draw, every weapon placed in a district would shift the `loot` stream for everything
  placed after it — a worldgen change no gate about attachments would have noticed. The **QUIET**
  lane compares the stream's own position between a world that spawns ten assembled rifles and one
  that spawns ten bare ones, and its true negative is ten spawns that *do* roll a tier.
- **`structural` is the flag that makes swapping a part a repair.** A structural part is one the
  weapon is made of; `SimItems.assembly_condition` takes the worst of the host's condition and
  every structural part's, and the profile builders and `jam_chance` both band off that. So a
  tired action is what stovepipes a gun, and fitting a sound one restores it **without touching
  the repair ceiling** — `SimItems.repair_item` lowers the ceiling because something was mended,
  and here nothing was. An optic is not structural: as it wears it simply does less, which
  `effect_scale` already said. A part can be structural *and* declare multipliers; a long barrel
  is both.
- **`muzzle` and `internal` are new, and the suppressor moved.** docs/10 gave firearms
  optic · barrel · magazine · furniture, which meant a can and a longer barrel competed for one
  slot — and "a stock, a sight and a longer barrel at once" is exactly what the feature was asked
  for. The suppressor now fits `muzzle`; `internal` holds the action, where the springs that
  decide a jam live. Every gate lane that fitted a suppressor to a `barrel` was re-pointed rather
  than loosened.
- **Receiver masses came down by what their parts now carry.** `item_mass_kg` counts fitted parts,
  so without this every weapon in the world would have got heavier the day this landed —
  encumbrance, movement speed, the whole campaign — for no design reason. An assembled weapon
  weighs what it was authored at and a stripped one weighs less, which is the right way round. The
  **MASS** lane pins the pre-assembly figures in the gate file rather than reading them back off
  the content, on `check_worn.gd`'s `EXPECT_ORDER` precedent.
- **Wear reaches the part that did the work, and that needed the profile to know its own item.**
  `_weapon_for_attacker` guessed by walking `["primary","secondary"]`, so a knife took every
  gunshot's wear and the pistol beside it never degraded at all. Both profiles now carry `source`
  and four channels name the acting weapon: `weapon.fired`, `weapon.reloaded`, `attack.connected`,
  `weapon.jammed`. What wears a part is content — `wearsOn` picks words out of `WEAR_EVENTS` —
  because the `barrel` slot holds parts that do not wear alike.
- **A worn part does less, never something worse.** `effect_scale` interpolates each declared
  multiplier toward **1.0** by the part's condition. Symmetric, so a buff and a cost both wash out
  and nothing in the fold has to know which it was holding; the polarity question belongs to the
  screen. `pow(declared, k)` composes more prettily and was rejected: one multiply is cheaper, and
  legible in a gate's error message.
- **`detach` re-homes or refuses.** It used to leave the part with no `stored`, no `position` and
  no slot, which is not "the caller decides" but "the part is gone". The ladder is the carrier's
  pack, the carrier's feet, beside a host on the ground, the container the host sits in — and a
  refusal when every rung fails, so no path through it loses a part.
- **v29 refuses a v28 save.** A v28 save holds weapons with empty slots, and neither reading is
  honest: treating "no `attachments` component" as unblocked makes the required-slot rule
  unenforceable the moment a barrel breaks off, and assembling on load invents items the save
  never had.
- **Measured, not theorised:** a throwaway driver fired a pistol 160 rounds. The assembly reaches
  "worn" at about 100 shots and "failing" at about 200, and the *action* is what gets there first
  (rate 1.2, on `shot` and `jam` both) — so a gun that starts jamming is fixed by swapping the
  action, which is the loop this slice exists to create. `npm run godot:bench` is unchanged and
  inside every budget with ~28 extra part entities per eleven weapons. Driver deleted.

## The weapons catalogue: a weapon has heft, and a light is a light, 2026-09-10

The owner asked for a suppressor-capable submachine gun, more attachments, and more weapons, and
shaped it in four answers: the SMG chambers 9mm with a .45 conversion kit; per-weapon handling
speed gets built; more firearms, melee and bow/crossbow variants but **not** throwables; and
firearms gain an `underbarrel` slot carrying the weapon light docs/10 has promised since
attachments landed. Most of what followed is the gear catalogue for a third time and needs no
reasoning written down. Six calls do.

- **Rate of fire is a weapon's, and it is melee's shape rather than a new one.** docs/09 states the
  ladder as "raise → steady → fire → recover → (reload)" and its own table says a crossbow's rate of
  fire is "much slower" — which was true of the reload and of nothing else, because the three rungs
  were constants in `ranged.gd` that every firearm shared. `ranged.weight` is content-declared and
  **required**, exactly as `melee.weight` is, and `SimCombat.raise_ticks` / `steady_ticks` /
  `shot_recover_ticks` sit beside `windup_ticks` and `recover_ticks` because a weapon's clocks are
  combat's arithmetic and not one module's private calibration. docs/10 rule 4 wants melee and
  ranged to have equal item depth; this is the axis where they did not.
- **One `handling` multiplier over all three rungs, not three scalable fields.** Three would each
  need a polarity sign, a word, and — the SCALES lane being what it is — its own shipped part in
  the same commit. More decisively, the bench prints one prose row per changed field and "comes
  up / settles / recovers" is three rows a reader cannot tell apart without the digits the HUD ban
  forbids. A part that should steady *without* hastening scales `cone`, which is what the padded
  stock already did.
- **The calibration is behaviour-preserving where it can be.** The pistol and the revolver stay at
  1.0 and their eight/four/eight is unchanged, so every gate fixture and every pinned number that
  used a pistol still measures what it measured. Everything else spreads outward from there, and
  the SMG at 0.85 is the first weapon whose identity *is* its handling.
- **A second matched conversion set, on purpose.** The .45 kit is the rimfire kit's shape again — a
  barrel and a magazine that agree with each other and with nothing else — rather than a second
  mechanism. Once "resolved by agreement, not by order" exists, a second instance is content, and
  content is where the depth should come from. It fits the Service Pistol as well as the SMG, which
  is emergent and was not designed for.
- **One writer owns carried light, and the flash is a guest.** `light_source` had two writers on a
  survivor and no rule between them: the muzzle flash overwrote the component and then deleted it
  when it expired, guarded on the magnitude still equalling the flash — which the overwrite had
  just guaranteed. A mounted light would have gone out permanently on the first shot, behind a
  guard that reads as careful. `refresh_carried` is now the only thing that sets or clears carried
  light; the flash takes the brighter of itself and what is carried, and expiry *falls back* rather
  than removes. **Two writers to one component is the shape to distrust**, and it is the same
  family as docs/30's `static var` entries: a value quietly not what you stored.
  Finding it cost nothing and would have cost a session later, because the gate that catches it has
  to fire the gun — every cheaper assertion about the light passes with the bug in place.
- **The light module was carrying a broken copy of a solved problem.** Its private content accessor
  put the fallback scan *inside* a `has(type_id)` guard, and `ContentLoader.load_tree` keys its
  tree by path and never by type, so `light_reach_of` returned null for every item in the game: the
  candle, the electric lamp and the oil lantern had each declared a `light` block since the module
  landed and **no carried light had ever lit anybody**. `items.gd`'s `content_entry` says in its own
  comment that other modules "should not each grow their own copy of it", and this was the bill for
  ignoring that. It is the thirteenth dead socket of the milestone and it was found only because
  the weapon light needed the same resolver. **Carrying a lamp now costs visibility**, which is what
  it was always supposed to cost, and that is a real change to night play rather than a repair.
- **A slot a required part lives in is not one accessories can share.** The plan had a crossbow
  crank in the `string` slot; `string` is a *required* slot with a structural default on both the
  bow and the crossbow, so a crank occupying it would leave the weapon with no string and
  `blocked_reason` would refuse to fire it. The required-slot rule created this constraint when it
  landed and nothing had run into it until now. It is worth stating rather than rediscovering:
  `barrel`, `internal`, `limb`, `string`, `head` and `haft` are structural addresses, and an
  accessory wanting a home needs a slot of its own — which is what `underbarrel` is.
- **Four melee, not ten, and each against a measured gap.** Melee shipped fifteen bases and the
  temptation with a "more weapons" brief is breadth. The shipped table was read first: nothing sat
  below the kitchen knife's weight, nothing paired damage at or above fourteen with stagger at or
  below five, only the improvised spear reached two metres, and nothing did reach-without-damage
  past the baton's range. Four gaps, four weapons. A fifth would have been flavour, and docs/10's
  "items are found, not chosen" is worth less the more of them there are.

**Deliberately not in this arc**, named rather than left looking finished: throwables, which are a
new weapon class with a thrown arc and an area effect; the *aimed* half of the weapon light, which
is a radius around its holder and not a beam, and the optic-in-the-dark half, which needs the cone
to read the light field; the five ranged affixes, still blocked on stats that resolve to nothing;
armour attachment slots, still code before content; and **the aim-cone arm penalty** — `ranged.gd`
widens the cone when the worse arm is under 25 and a healthy sided arm is 20, so every survivor has
been shooting with the one-ruined-arm penalty applied permanently since limbs were sided. That one
is in docs/23's defect list rather than fixed here: correcting it tightens every survivor's cone in
every firefight, which is a balance change wanting its own slice and its own measurement, not a
quiet ride beside a change about rate of fire.

---

## The crate we did not draw, 2026-09-10

Decided by the owner, 2026-09-10, at the end of a session that measured an external art generator
(the SpriteCook MCP) against this project's own specs across six target families. The evaluation is
`.scratch/simplyzombies/issues/15-spritecook-evaluation.md`; this entry is the call taken at the end
of it, and it amends "Art we did not generate" above rather than restating it.

- **The authored tier now holds machine-generated art, not only commissioned art.** That entry
  opened the tier for an artist working to the brief in `assets/sprites/README.md`. Its first two
  occupants are instead produced by a model and post-processed into the spec — cropped, scaled so
  the larger bounding-box dimension lands on `appearance.size * 32`, centred, and re-outlined to
  `#161614`. Nothing about the tier had to change to accept them, which is the point: the tier was
  specified by what art must *measure*, not by who drew it, so a machine that hits the numbers is
  admitted on the same terms as a person who does. What the brief buys is unchanged, and so is the
  refusal of a bought pack.
- **Procedural art was retired to make room, and that is the real cost.** `build.py` refuses a key
  claimed by both tiers, so authoring `prop_container` and `prop_container_searched` meant deleting
  `props.py`'s `_crate` and both its entry points. This is the first time the generated tier has
  *shrunk*: "Art we did not generate" closed by saying the generated tier was still 151 of the 151
  keys and the source of record for every tile. It is now 172 of 174, and two tiles are not in it.
  The deleted generator is in git history and the crate it drew is in this document's own record;
  what is gone is the ability to re-render those two keys from code.
- **One three-quarter prop among four flat ones, accepted knowingly.** The other props are the
  older flat top-down art; docs/23 is right that only the renderer half of the props slice landed.
  So the district now has one prop drawn to the *decided* style and four drawn to the superseded
  one. That is a visible inconsistency and it was taken deliberately rather than discovered: the
  alternative was holding the art until the whole prop family migrates to feet-anchored
  three-quarter, and the owner chose to land the one.
- **What the measurement actually supports, stated narrowly.** The generator's output was
  shippable *here* and nowhere else tested. `check_authored.gd`'s `_rule_places` bars
  `ground_atlas`,
  every `PAWN_KEYS` entry, every `TREE_KEYS` entry and every vehicle from the authored tier, so
  props were the only family this could have applied to at all — the rubble ground cell that
  matched its row tint exactly and tiled at 1.01x the interior step cannot be delivered as a file
  at any quality. The general finding is that the generator succeeds in inverse proportion to how
  structural the spec is: a mean, a stdev, a footprint and an outline colour are all things a
  transform can move toward, and a hand on column 7.6 or a brick course on period 8 are not.

**What this does not change.** The published skeleton, the canvas table, the anchor rule and the
flip; `sprites:check`'s pixel-exact comparison for the 172 keys still generated; the standing bans;
and the open piece "the first commissioned body, and the three gates it widens", which is about a
`rig` and is untouched by two keys of kind `tile`. *(That piece landed 2026-09-11 — the entry
below, and docs/23's record.)*

## The reference treatment, 2026-09-11

Decided by the owner, 2026-09-11, in the session that landed the first commissioned body. The
owner supplied first a screenshot of a colony sim and then a written Dungeon Settlers style spec,
with the instruction "apply it but keep our current theme" — which raised a question the art could
not answer for itself: how much of a reference style a project adopts when some of its clauses
collide with gates that are already settled.

- **Two clauses were already met, which is worth recording because it nearly became an
  amendment.** The spec asks for "defined, dark selective outlines (dark brown, navy, or deep
  charcoal **rather than pure black** `#000000`)". `#161614` is (22, 22, 20) — deep charcoal, not
  pure black — so the OUTLINE bound satisfies that clause as written and did **not** need moving.
  The spec asks for chibi proportions of 2 to 2.5 heads; the published skeleton's 28 px figure
  with a 12 px head at `HEAD_CY` is 2.3. An earlier reading of the same reference from a
  screenshot alone had judged the outline a *collision*; reading the written spec corrected that.
  The lesson is the ordinary one: a style read off a picture at sprite scale is a guess, and the
  guess here would have amended a bound that did not need it.
- **The rest is taken as treatment, not as palette or outline.** What is adopted is the shading
  clause — "clean 2-to-3-tone shading ramps per colour family with minimal dithering" and "soft
  interior clustering to prevent visual noise" — plus the readable silhouette and the earthy
  family, which `palette.py`'s warm families already are. What is **not** adopted: the
  *selective* half of the outline clause (partial outlining, where our gate wants a full one),
  the "high-saturation accent colours for uniforms, tools and status badges", and the 3/4
  perspective, since bodies here are face-on and flip. `palette.py`'s `muted` family caps
  saturation at 0.30 against the ground's own ceiling, with `check_road_look.gd`'s palette lane
  holding the other half. **No gate was amended**, which is the decision.
- **The treatment is applied by code, not by prompt.** Three passes on the delivered PNG —
  despeckle, a three-tone-per-family ramp whose steps are the mean of their own members, and a
  clamp to the palette families — described in docs/23's record. A prompt asking for clean ramps
  produced a sprite with seventeen colours; the passes produced six. Saying it in the prompt is
  not the same as doing it, and the deterministic half is the half that can be re-run.
- **Why not the fuller adoption, stated as a cost rather than a preference.** Taking the
  *selective* outline or the accent saturation means moving a bound for one new sprite while the
  eight rigs that already meet it stay as they are — a roster reading as two styles until every
  one is re-authored, which is not one session's work. Note the treatment alone already left the
  roster in a milder version of exactly that state, which is why "the ramp, applied to the whole
  roster" is now a named piece in docs/23 rather than a line in a record. A gate loosened to admit art is the shape this project has refused
  before. The owner may still take it; the point of recording it here is that it would be a
  deliberate multi-session arc with a re-measured palette table, not a clause inside a sprite
  commit.
- **What we take from a reference is the treatment, never the sprites.** Consistent with "Art we
  did not generate": the art is made to this project's own spec. The reference informs how a
  garment is shaded and how a head reads; no pixels come from it.
- **The reference's HUD stays refused.** It draws a name plate and a health bar over every pawn.
  The health-bar ban and the prose HUD are untouched, and this entry is not an opening to
  revisit them.

**What this does not change.** The published skeleton, the canvas table, the anchor rule, the
flip, the `#161614` outline, the palette families, `sprites:check`, and the standing bans. The
one structural change the slice did make is in the tier, not the style: `kind` is now read by the
renderer-side `Appearance.authored_rig_keys()` as well as by the gate, because three gates need
"which authored keys are bodies" and one parse with three readers beats three parses.

## The decoupled paperdoll, 2026-09-11

Decided by the owner, 2026-09-11, from a supplied "Visual Architecture & 2D Sprite Engine
Specification" — a ZERO Sievert-style decoupled paperdoll — read against what this project
actually ships. It is the largest reversal in the art record so far and it reverses decisions
this document took three times, so what each one becomes is written out rather than implied.

**What the spec asks for.** Legs animate cyclically on the movement vector (eight directions,
four frames: contact, down, passing, high; backpedal is reverse playback when
`dot(move, aim) < -0.2`). Torso, head and weapon rotate 0–360° to the aim, with a Y-flip when
aiming west so the weapon is never upside down — flipping the whole root is forbidden, because
it would flip the legs. Layers re-sort by aim sector. Every slot sits on a fixed canvas with a
normalized pivot. A four-tone palette, a single dark outline that is not pure black, and **no
dark lines inside the silhouette**. Per-weapon socket metadata: grip, foregrip, muzzle.

### The ten decisions

1. **Full 360° continuous torso rotation.** This reverses "Bodies stand up" (the Dungeon
   Settlers look, 2026-09-03) — *"nobody rotates, the player included"* — which had itself
   reversed "Only the player rotates" (2026-09-01). It also reverses the character overhaul's
   narrower clause (2026-09-09) that a view is *"a fourth picture, never a transform"*. The
   flip is not retired: it becomes the Y-inversion the spec asks for, on the torso group alone.
   `check_topdown.gd`'s FLIP lane becomes a ROTATE lane — **amended, never deleted**, and it
   pins the new arrangement exactly the way the old one pinned zero transforms.
2. **Everyone rotates, not just the player.** All eight generated rigs and whatever is
   commissioned later. The player's torso follows the aim; a survivor or raider follows its
   target or the threat it is reacting to, else its heading; a zombie follows its heading,
   because a zombie has nothing to aim. This is the half of 2026-09-01's "only the player
   rotates" that was costed and refused then — the cost was *"rotation support and equip
   overlays re-authored on the rotated rig"*, and the slot split is what pays it.
3. **The head is seen from above and rotates with the torso.** Crown, hair and a brow; no eyes.
   Identity comes from hair colour, headgear and silhouette. This abandons the face-on big-head
   read of "Overcast or torchlight" (2026-09-08) and supersedes the overhaul's "a face is four
   pixels" before it shipped. It is the clause that costs the most character per body and it
   was taken deliberately: a face drawn from above is a lie at any angle but one.
4. **The canvas goes back to 32×48, and every slot gets its own.** This reverses the 2026-09-08
   squash, which said in this document that the 32×48 canvas *"was superseded rather than
   resized, because a proportion is a re-authoring and not a crop"* — the same sentence applies
   in reverse and the re-authoring is the work, not a regret. Slots: legs 32×24 pivot
   (0.50, 0.35); torso 32×32 (0.50, 0.55), the chest and the rotation pivot; head 24×24
   (0.50, 0.70) at the neck base; one-handed weapon 24×16 grip (0.20, 0.50); two-handed 40×16
   (0.25, 0.45). **This is the fifth canvas convention in five weeks and the churn clause of
   2026-09-03 named the reason there had been four: "free rotation, which forced a square,
   centre-anchored, radially shaded canvas".** Per-slot pivots are the answer to exactly that —
   the pivot is a property of the slot now, so rotation no longer forces one square canvas on
   everything, and the radial shade comes back *per slot*, which is what that clause objected
   to only when it was per canvas.
5. **The generator learns the rules first, then splits.** The four-tone model, the
   no-internal-dark-lines rule and the socket measurements land in the existing one-canvas
   assembler and every rig regenerates; the split into per-slot canvases follows. Stated cost,
   because it is real: the 172 generated keys regenerate **three** times across the arc and
   `APPEARANCE_OK`'s GREY lane is re-measured three times. The alternative — fold the tone
   rules into the split — saves one regeneration and shows nothing on screen for four
   sessions. The owner chose the visible improvement first.
6. **The outline stays `#161614`.** "The reference treatment" (2026-09-11, above) measured the
   supplied spec's own outline clause — *"dark brown, navy, or deep charcoal rather than pure
   black"* — against ours and found it already satisfied. The new spec repeats the clause and
   the finding stands. No gate is amended for it.
7. **Aim is decoupled in the sim, and priced hardcore.** A second heading, `aim`, carried
   beside `facing`: the feet go where you walk, the torso and head go where you look. The sim
   accepts an aim that differs from the heading **only at Walk pace or slower**; at Jog and
   Sprint the aim snaps to the heading. This reverses the rule recorded in `world.gd`'s own
   comment — *"you do not track a target over your shoulder at a jog. That is the hardcore
   rule, not a compromise"* — and amends docs/28's "facing is the same heading aiming reads,
   which is why it is specified here rather than in two places", which becomes two headings
   specified in one place. **The price is a real one and it had to be built rather than
   assumed**: `_refresh_cone` already pins a moving shooter's cone to `WIDE_HALF`, and the
   clamp cannot exceed it, so a twist term added under that clamp would have been a dead
   socket — the twist widens the cone *past* `WIDE_HALF` through a second cap, which is the
   only shape in which the price exists at all. Vision follows the head. Saves are **refused,
   not migrated**, per the standing pre-1.0 rule; `SAVE_VERSION` bumps and an absent `aim`
   reads as `facing`, which is what keeps every existing fixture describing a body whose aim
   is its heading.
8. **The sim reads the muzzle.** The shot ray, the noise position and the muzzle-flash light
   originate at the weapon's rotated muzzle socket rather than at the body's centre. Content is
   data the sim may read, so this is not a boundary breach — but the sockets do **not** live
   under `appearance`, which is presentation's block; they are their own top-level content, and
   the renderer and the sim read the same numbers through one helper so the drawn muzzle and
   the fired muzzle cannot disagree.
9. **The commissioned rig is retired now and re-commissioned after the split.**
   `player_body_authored` (2026-09-11, PR #130) is one face-on 32×40 picture. Decision 3 takes
   its face, decision 4 takes its canvas, and decision 1 takes the arrangement it was drawn
   for, so almost nothing of what it carried survives. It is deleted and `player.body` points
   back at the generated rig; the player is re-commissioned as slot layers once the slot
   canvases exist and their gates are mechanical. **The tier and its gate are not retired**:
   the authored manifest, the union roster, the envelope-unchanged clause and the new interior
   and tone lanes all stay, judging zero authored rigs correctly until the new one lands.
10. **A muzzle inside a solid tile falls back to the body centre.** A body flush against a wall
    aiming into it has its muzzle inside the wall; the shot originates from the body instead —
    today's origin, so that case is balance-neutral by construction. The hardcore alternative,
    *refusing the shot* ("the barrel is against the wall") is one line to flip and is recorded
    here as not taken: it would change NPC engagement at doorways, which the sight gate already
    fixtures, and move the balance tier with it. It can be reopened as its own measured slice.

### What this does not change

The flat top-down projection and 32 px a tile at 2× (reaffirmed a fifth time). The feet anchor
and `FOOT_DROP_PX` — the root pivot is still the ground contact and the contact shadow still
hangs off the same number. **The peripheral-anonymity clause**: a glimpsed body is still an
anonymous disc that bails before any heading is read, and the ROTATE lane proves that the aim
is read *after* the bail, which is a stronger statement than the old lane made. The health-bar
ban, the digit ban and the prose HUD; the refusal of bars, icon rows and name plates — the
supplied spec's status badges are refused on the same grounds as every previous reference's.
Drawn enemy vision cones stay on docs/28's cut list: the aim cone remains the player's alone.
The condition chart keeps its own body model and its own canvas. "The torch" stays a separate
sim slice and gains the aim pivot as the origin its cone was always going to need.

### What it supersedes that was still open

"Art we did not generate" (2026-09-09) held three fixture-round candidates — the harder rig,
the weight-shifted walk and the four views — *"until it is known whether commissioned bodies
are coming"*. One came, and these decisions answer the question that hold was waiting on, so
the hold lifts. The four-views piece is absorbed outright: a rotating torso is every view.

**Previous:** [23 — Roadmap](23-roadmap.md) ·
**Next:** [31 — Godot Rebuild Roadmap](31-godot-rebuild-roadmap.md) ·
[Doc index](../README.md#documentation)

---

## The round in the chamber, 2026-09-12

The owner opened the alpha item roster — *"food, medicine, ammo, ammo types (configure for guns
too), attachments, bags"* — and the one piece of it that was not a data edit was ammunition types.
Four answers, and this entry is the first two.

**A round is multipliers over a caliber, not ballistics of its own.** The alternative on the table
was the faithful one: the round carries damage and noise outright and the weapon contributes only
range, handling, magazine and reload. It was refused because it re-authors all thirteen shipped
firearms and re-opens the entire ranged balance table to ship a feature about *choice*, and because
the multiplier form already exists here and is already understood — `attachment.ranged` is the same
grammar, `SimAttachments.SCALABLE` is the same whitelist, and docs/30's own note on it ("an
attachment declares what it multiplies, and the module names none of them") transfers word for
word. Nothing in `ranged.gd` knows what a slug is.

**`ranged.ammo` keeps its meaning and `ranged.caliber` is added beside it.** The round a weapon
*prefers* and the set it will *take* are two facts, not one, and splitting them is what makes the
slice additive: a survivor carrying only the round their weapon names picks it on the first pass, so
every shipped weapon's authored numbers, every parity fixture and all four balance seeds see exactly
the sequence they saw before. `M2_AMMO_OK`'s DEFAULT lane pins that as numbers — a service pistol
still makes 180 and still does 18 — rather than as "nothing crashed". Folding the two into one list
was considered and refused: it would have made "which round a shotgun reaches for" a function of a
sort order in code rather than of content, and it would have made the five conversion parts'
existing `overrides.ranged.ammo` dead.

**A conversion part moves both, and the gate is what says so.** `caliber` joins `OVERRIDABLE`
beside `ammo`, and all five conversion parts declare the pair. A part that moved only the round
would build a pistol that prefers something it cannot chamber — the pick would fall through to the
old caliber every time, so the conversion would *appear* to work and quietly fire the wrong
ammunition, with no error and no wrong number. Nothing in `attachments.gd` can see the sibling key,
which is why the claim lives in `check_m2_ammo.gd`'s CONVERT lane and is proved by deleting one.

**The whitelist is its own, and smaller than the attachment one.** `SimRanged.AMMO_SCALABLE` is
`damage · noise · flash · rangeMetres · cone · recoverable` — every field `_fire_shot` reads *after*
the round is spent, and no others. `magSize`, `reloadTicks` and `handling` are read before a round
is ever chosen, so a round scaling one would be a multiplier authored in content that nothing could
read: the dead-socket shape, in its most invisible form. Reusing `SCALABLE["ranged"]` would also
have routed rounds through `effect_scale`, which walks a multiplier toward 1.0 by the *part's*
condition — a slug is spent, not worn, and softening it because the box of shells was scuffed is
not a rule anyone would have chosen.

**The round's effect belongs to the shot, not to the gun.** `_fire_shot`'s `weapon` argument is the
live `rangedWeapon` component. The multipliers are resolved into a local and applied at each read
site; written back into that dictionary they would scale the weapon permanently, compounding once
per shot. The one field re-clamped rather than merely multiplied is the cone, to the bounds
`_refresh_cone` itself uses: `WIDE_HALF` is what the cone means at its widest — a sprint, a ruined
arm, a body out of breath all stop there — so birdshot reaches the cap and stops. Widening past it
is reserved for the aim slice, which needs it for a different reason and says so.

**No `SAVE_VERSION` bump.** `rangedWeapon` is an ordinary component saved wholesale and never
rebuilt on load, so a save written before this slice restores a weapon with no `caliber`, and the
empty-caliber path is exact-id matching — which is what that weapon did when it was saved. The
precedent is the same component's own: `weight` and `handling` were added to it without a bump for
the same reason. What makes it honest rather than hopeful is that the fallback is *gated*:
`M2_AMMO_OK`'s LEGACY lane erases the caliber off a live weapon and asserts it still fires the round
it names and still refuses a same-caliber one. A branch nothing asserts is a dead socket with a
better story.

**What shipped is the mechanism, not the choice.** With buckshot and slugs both in the pack the
pick order decides, and the player's only way to fire the slug is to carry nothing else. The
fallback is sorted by base id rather than taken in carry order, so at least the answer does not
move when a bag is tidied — but *choosing* is a verb on the inventory sheet and is named in
docs/23's what's-left rather than half-built here. So is the magazine: `FireState.Reload` refills
`mag` from `magSize` and consumes nothing, so a magazine can hold mixed rounds and switching loads
is instant. That is the cheapest consistent story and it is written down rather than discovered.

## The cartridge on the label, 2026-09-12

The owner's third and fourth answers, and the second is an amendment to a standing ban, which
CLAUDE.md says must not happen quietly.

**Rounds are called what they are called.** `.308 Winchester Match`, `12 Gauge Buckshot`,
`9x19mm Parabellum`. The alternative was the plain-language naming the rest of the roster uses —
"Rifle Round (Soft Point)" — and the owner took the real designations knowing the cost.

**The cost: the digit ban gains an item-name clause.** `check_inventory.gd` scanned an item's `name`
in two places — the quick strip, which is on the player HUD, and the inspect pane — and refused any
digit in either. This was raised before the decision rather than discovered after it, and the owner
decided to amend rather than to name around it. The reasoning that decided it: a roster of twenty
rounds named around the ban would be twenty rounds a player cannot tell apart, which is a worse
failure of [clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) than the digit
is. Clause 4 prohibits collapsing *uncertainty* into a number. A cartridge designation is a proper
noun; it says what the thing is, not how much of it there is or how good it is.

**The clause is narrow and it is one predicate.** `_name_is_allowed` refuses a name that is nothing
but a quantity — "12" is a count with no noun, which no cartridge designation is — and both lanes
call it rather than each growing their own copy, for the same reason the file already keeps one
`_carries_a_digit` so DESCRIPTION and INSPECT cannot disagree about what a digit is. Two copies of
an exemption is that mistake with the answer inverted.

**What is still banned, and is asserted to still be banned.** `description` (the DESCRIPTION lane
walks all 164 shipped bases), every other value in the inspect pane, `condition`, and every line
`check_hud.gd` reads. The lane proves all three directions on fabricated views: a cartridge name
passes, a bare quantity is refused, and *the identical string is refused the moment it is a
description instead* — which is what "scoped to one field" means and is the half that would have
rotted silently if it were only written in a comment.

**It also fixed something.** `item.ammo.9mm` shipped as "9mm Round" and would have failed the STRIP
lane the first time a pistol round reached that lane's fixture — a latent red that had simply never
been run. The eight shipped rounds were renamed in the same commit.

## The readers ran out before the content did, 2026-09-12

The owner asked for more items, and the census that went looking for where to put them came back
with the reason there was nowhere obvious. This entry records that finding and the four answers
taken on it, because the answers set the arc's size and three of them are not reversible cheaply.

**The finding.** The roster's problem is not that it is small. It is that it is **unread**.
Nineteen item ids are hardcoded inside `godot/sim/` — `ANTIBIOTICS_ID`, `PAINKILLERS_ID`, the
literal `"item.wrap.cloth"` that is the entire clothing-warmth system, `item.scrap.metal` in two
separate files as the only substance that can build anything, one hardcoded spawn that makes every
raw food in the game cook into the same meal — and each of them is a category that cannot grow by
one item without a code change. Underneath that sit **four items that already ship, already sit in
loot tables, and cannot be used for anything**: the rigged floodlight has no placement verb, the
empty jerrycan has nothing that fills it, the battery feeds nothing because lights never burn down,
and the cloth mask is mechanically identical to a bike helmet against a bloater's cloud because the
contamination roll never looks at what anyone is wearing. Adding content without readers would have
grown that pile rather than the game.

**Eight readers, not four.** The four survival readers — warmth, the cooking and boiling
transforms, light burn-down, and a build material that is not scrap — plus four that add something
an item can *do* that nothing does today: deliberate noise, teaching, comfort that is not food, and
a filter the contamination roll consults. The case for the second four is that each sits on a
system that is already finished and already gated and has simply never been given an item: the
attention field's only item-priced emitter is firing a gun, and the skill web is a complete
content-driven XP system with zero item content in a game where skills die with the person.

**The orphans are adopted, not deleted.** Deleting the four unusable items was offered and refused.
Each is instead made live by the slice that owns its reader — the battery by light burn-down, the
jerrycan by a siphon verb, the floodlight by a placement verb, the mask by the filter scalar. The
reasoning: unreachable content is a bug in the reader, and deleting the content hides the bug
rather than fixing it. This is the same call docs/23's defect list makes about the four dead
sockets the review sweep found and did not remove.

**Roughly 350 bases.** From 164. The owner chose the largest of three offered targets knowing it is
about twelve sessions rather than one, and the arc is ordered so that **stopping after any slice
leaves the tree honest** — every reader lands before the content that needs it, no slice
half-builds a system, and a stop halfway is six recorded landings rather than six loose ends.

**What this does not change.** The standing bans, all of them, including the item-name digit clause
amended earlier the same day, which is not widened again by anything here. One balance re-baseline
still closes the arc rather than one per slice. Every new key still lands with the assertion that
something reads it and the reverse assertion that everything readable is reached — with eight new
keys coming, `check_m2_gear.gd`'s `READ_KEYS` list is what makes that automatic, and a key that
does not join it is a dead socket by construction. And the arc adds **no new `class` value**: every
new category fits `tool`, `material` or `consumable`, specifically so the three-place enum sync
between the schema, `item_glyph.gd` and `items.gd` never has to happen.

## Two placeable items, two opposite answers (2026-09-12)

The light slice stands a floodlight up as furniture and gives no verb to take it down again. The
noise slice, four slices later, makes every one of its eight devices pick back up: E lifts a placed
firecracker or siren into the pack and it goes down again on a fresh fuse. Both were put to the
owner and both answers are deliberate, so the inconsistency is a decision rather than a drift.

The reasoning the owner gave for the split is what each thing *is*. A floodlight is a rigged
installation — the content calls it rigged — and the cost of standing one up is that you have
committed the thing to that street. A noisemaker is the opposite: its entire use is that you place
it somewhere you are not, and an air horn you can only ever spend once is a consumable with extra
steps. The asymmetry is the point, and `check_m2_noise.gd`'s LIFT lane asserts the multi-use half
while docs/23 names the floodlight's one-way trip as a restriction somebody will be surprised by.

**The alarm and the noisemaker stay free.** The what's-left entry wanted `fortify.gd`'s two world
singletons turned into things you had to have carried there first, and the owner chose new items
only. The mechanical reason is worth recording because it will come up again:
`check_m2_materials.gd`'s PINNED lane asserts both singletons **by name and by cost**, so giving
them an item to spend turns a shipped gate red. That makes it a rebalance — and a rebalance owes a
before-and-after run on the same driver, which a content slice riding beside it does not pay for.
Repricing them is named in what's left with that run attached, rather than smuggled in here.

## Armour reaches people by being found, not by being issued (2026-09-12)

Coverage had stopped blows since the armour slice, and nothing in the game had ever put a vest on
anybody: no starting kit carried armour, and NPCs equipped found gear only as a fallback when the
pack was full. Offered a starting kit, a wear-what-you-find rule, or both, the owner took **the
rule alone, with no starting kit**. A colony that finds nothing stays bare, and that is the
intended outcome rather than a gap to patch later — the same reasoning as every other scarcity in
the hardcore contract.

**The claim on the Dress job is load-bearing, and it is not tuning.** Colonists walk as far as
`HOME_RADIUS_TILES` — forty tiles — for a garment, which is the same distance Haul already walks
for a tin, so the rule arrived with a cost in colonists. Measured on one tree with nothing
differing but the claim: without it seed 90210 wipes entirely and `survivors_end >= 1` turns the
balance gate red; with it that colony survives and seed 404 pays instead. Anyone removing the claim
to make `_dress_job` match `_rearm_job` again will turn the chain red, and the two rules differ on
purpose: **re-arm fires only for somebody with empty hands and is rare, while a better garment is
lying around constantly**, so two colonists crossing the district for one vest is the common case
rather than the edge one. `_rearm_job` not taking a claim is a latent version of the same bug; it
is simply rare enough not to have been paid for yet.

**The harness has two arms because the shipped rule made the old one impossible.** Once colonists
wear what they find, "the fast tier as it stands" is not a bare colony any more, so the control had
to be *made* rather than assumed: both arms boot the same seed with the same armour at the
colonists' feet and differ only in whether `SimJobs.WEAR_FOUND_ARMOR` may run, and the harness
equips nobody. The owner paid roughly doubled fast-tier runtime for that control (4m30s → ~11 min)
rather than dressing the existing arm, because a comparison with no control is what let armour
mitigation ship inert and unnoticed in the first place. Two armour seeds, not four: the four-seed
figure was taken by hand and agreed within 0.1%, and the direction is structural rather than
statistical.

## Readers first for the web, 2026-09-13

The owner asked for more skills — weapons, crafting, and something for the NPC followers at camp —
and the census that went looking for where to put them came back, as the roster's had the day
before, with the reason there was nowhere obvious. This entry records that finding and the calls
taken on it, because they set the arc's size and its order.

**The finding.** The web's problem is not that it is small. It is that most of what it could point
at is **unread**. The modifier registry names twenty-three stats and the sim resolves fifteen of
them; of the seven an actor's own web can reach today, four are the melee and ranged numbers and
the rest are carry, damage taken and stamina. Eight stats are resolved by nothing, and four of the
fifteen shipped nodes target two of those — `healing_rate` behind both Medicine nodes,
`repair_cost` behind both Craft nodes — so a survivor who drifts into Medicine or Craft buys nodes
that change nothing and the screen shows them lit. "Followers at camp" has less than that: no
leadership attribute (aptitudes are STR, DEX and CON), no relationships, and exactly one place in
the game where one survivor's number reaches another, the pantry's best-living-colonist read.
Adding nodes without readers would have grown that pile rather than the game.

**Readers first, one per piece.** Each piece of the arc wires one stat into the sim with its own
lane and then ships the nodes that reach it. `godot:m2:web`'s READERS lane makes that mechanical:
every id the registry defines must be resolved by a function body under `godot/sim/`, or be named
on one of two lists with its reason — `AWAITING_READER`, which the arc empties one piece at a
time, and `EXCUSED_DEAD`, the five no piece reaches. Both lists are meant only to shrink, and the
lane refuses a resolved stat that is still excused.

**The five dead stats stay, excused by name.** `noise_propagation`, `structure_decay`,
`temperature`, `condition_loss` and `bleed_on_hit` are resolved by nothing and no piece here
reaches them. Striking them was offered and refused for now: two are still written by shipped
affixes, so striking them edits affix content and moves the fingerprints `godot:check:mods`
pins, which is a decision of its own. A named excuse is honest where a silent registration was
not.

**NPC reach is colony-reach nodes in existing regions.** A seventh region — Leadership, Camp —
was offered and refused: it needs work that pays it and nothing does, a manual, a focus and drift
rules, and touches nine enumerations across code, content, gates and docs, all for a stat the sim
has no consumer of. The pantry already shows the shape that works: a node whose stat is read across
the colony from whoever holds it best. So a ward rate speeds every treatment at camp while the
medic who owns it is home, and someone to lean on damps an argument for the survivor standing
beside them. docs/08's cut of a second, colony-wide progression layer stands — these are personal
nodes with reach, not a research tree.

**Minors and keystones; no notables.** A keystone is a rim node of cost three or more carrying its
drawback as a second, negative modifier in the same node, under one source, so owning it and
losing it are one act each; the auto-spend passes never buy one, because docs/08 says a keystone
is chosen. A notable — a node that changes a behaviour rather than a number — would be the first
`has_node` read inside the sim and a new mechanism per node, each with its own gate; that is an
arc of its own and is not this one. Three of docs/08's named keystones are adapted rather than
copied: "recoil" is the recover rung the fire state already has, so the cold shot pays in recovery;
the quiet ones' firearm ban is a behaviour and becomes an accuracy cost; the field surgeon's cost
is a permanent mood modifier.

**Earned, not unspent.** Three reads treated `SimSkills.points` — what is still *banked* — as
skill: the deep-wound suture floor, the sepsis roll's relief, and the modification bias. Every node
bought made a survivor read as less skilled, which the focus slice named as an honest half and left
alone. With the web widening it would have got worse with every piece, so all three read
`SimSkills.earned` now — banked plus what the owned nodes cost. The behaviour change is real and
one-directional: an Auto survivor reaches the suture floor and the full Craft bias three earned
points earlier than before. A fixture that hand-writes points and owns nothing is unchanged.

**One re-baseline, at the close.** As the roster arc did: every piece moves a number a campaign
can feel, and four seeds before and after each of nine pieces is an overnight job apiece.

## The pause lifted: procedural people, raiders and zombies, 2026-09-14

On 2026-09-01 the owner grew the boot colony to three and paused new NPCs and roster growth so
the survival loop could be flipped on and measured with the colony held still. Thirteen days
later the owner opened a plan to "procedurally generate new NPCs, raiders, and of course zombies
on the map" and answered the questions the plan turned on. This entry records those answers,
because between them they lift a standing pause and widen the milestone in one direction docs/18
had put in Milestone 3. The plan itself is
`.hermes/plans/2026-09-14_procedural-population-arc.md`; the pieces are docs/23's group of the
same name.

**The pause is lifted.** The sentence in `CLAUDE.md` and `AGENTS.md` that said "new NPCs and
adjacent feature scope stay paused" is amended in this commit rather than deleted, because the
half of it that was a decision — three at boot — still stands. What changes is that the roster
may grow again, and how it grows is content and a generator rather than a fourth JSON under
`survivors/uniques/`.

**"Procedural" means three things at once, and the census says which the tree already has.**
The owner chose all three readings: *individuals vary* (each raider and zombie a distinct body —
kit, aptitudes, look, features, condition), *bodies appear by new paths* (strangers met on runs,
roaming bands, zombies inside buildings, not only the gate and the district edge), and *more kinds
as content* (docs/14's stalker, runner, armoured and heavy; docs/18's raider roles). Survivors
already have the first — `SimRecruits.roll` has drawn a name, traits, a backstory, an age and a
look since the pipeline landed — and only ever arrive by the gate on three fixed days. Raiders
have none of the three: two archetypes, every body identical, one entry path. Zombies have the
second at the edge and in the boot scatter, and the mix is three ids and three constants in
`SimRoster.pick_type` rather than content. So the arc is mostly readers and paths, not pools.

**Survivors: strangers in the district, and a settler group with its own camp.** Offered the
gate beats made richer, strangers hidden in buildings, or both plus another group, the owner took
the widest. docs/18's factions stay Milestone 3 *as a system*: what this adds is one more string
in `SimAllegiance`, a camp sited off the layout, and bodies that hold it — no standing, no
reputation, no trade. The seam docs/30's raiders entry said factions would widen is the one they
widen.

**Zombies: each body differs, docs/14's kinds, and dormant bodies inside buildings.** All three,
by the owner. Variance is content (`variance: {tints, body, crawlers}` on the type) and the
picked values are stored on the body so the draw loop grows a pass-through and not an id branch.
New kinds ship tinted on the shambler's rig until art exists — a silhouette is `sprites:check`
work and its own piece. Armour on the dead closes docs/23's open "Armour on anything that is not
a survivor", because `armor_coverage_of` already reads the target's equipment with no faction
filter and a zombie that wears a vest resists with no new arithmetic.

**Three structural calls, offered with a recommendation and taken as recommended.**

- **A raider carries a `raider.person` record, never `identity`.** `identity` is read by five
  things — the draw path's "is this a survivor", `_succession_pick`, the job scheduler,
  `is_person`, and the director's unique-death lull — and a raider with one becomes a possible
  heir. A person record beside the `raider` component gives them a name, an age, features and
  a look that reach the chronicle after a death and nothing else, which is also what the
  hardcore contract's information clause wants: a tint varies who a raider is, not what they
  carry.
- **Dormant zombies are a manifest written at world generation and spawned at boot**, the
  `map.vehicles` precedent, not a lazy spawn on approach. A lazy spawn would make the population
  a function of where the player walks, which is docs/17's "the director is not a spawner"
  reversed at the level of a building, and the balance harness could not count it. The manifest
  costs one indoor scan per building and the density gate can pin it.
- **Zombies first, then raiders, then people.** The zombie slices are the cheapest, they
  re-baseline the harness in three known steps, and the dormant slice builds the
  indoor-placement helper that strangers and the settler camp both reuse. Raiders come before
  settlers because the third side is a seam the individual-raider slice first touches, and a
  seam is gated before anything stands on it.

**What this does not change.** Three at boot. `GRACE_NIGHTS` stays at 7 and its flip stays
the owner's, blocked on the over-cap placement in HANDOFF's item 5. "An outpost that draws
raiders" stays the owner's and is not folded into the roaming-band slice. The horde entity stays
Milestone 3B. Every ban stands: a generated raider's name is never on the HUD, a stranger's bite
is as hidden as a gate recruit's, and the condition view gains no field. `survivors_end >= 1`
is not relaxed for any slice; where a seed wipes, the levers are content numbers.

**The first cuts each slice will take** — dormant density, body variance, crawler share, the
new kinds' weights and waves, stranger beats, raider jitter, a looter's haul, the roaming
chance, the settler count and distance — are named in the plan beside their slice. Each lands
in this file with the slice that takes it, in the dated form the playable-state entries set,
so the owner reads one entry per number rather than a list here that would drift.

**The mix's two calls, 2026-09-14** (the "mix is content" slice, docs/23's *Roster & the mix*).
The plan said the weighted pool is "sorted by id"; it is sorted by id **descending**. Ascending
lists bloater, screamer, shambler and would have handed roll 0 a bloater, which draws the same
distribution but a different body, and every shipped campaign's zombies come off those rolls.
Descending lists shambler, screamer, bloater — the order the three constants were written in — so
0–79 is still a shambler, 80–91 a screamer, 92–99 a bloater, and the slice's byte-identity claim
is about what spawns and not merely about how many numbers were drawn. The second call is
`weight: 0`: the schema's `minimum` is 1, as the raider schema's is, but `pick_type` **skips** a 0
rather than clamping it to 1 the way `SimRaiders.pick_type` does. A shipped type that can never
appear is a dead entry rather than a balance knob, so the minimum stands; the skip exists because
a fixture tree taking a kind off the table is the only way a gate can show the number in the JSON
is read at all, and `check_m2_roster.gd`'s SILENCED lane is that proof. The two helpers differ on
purpose, and the divergence is written where both can be read.

## A body asleep in a building, 2026-09-14

The arc's third slice, and four calls that were mine to take inside it. The shape was the owner's
already (a worldgen manifest, not a lazy spawn — the entry above); these are what building it
turned up.

**The pass sits after the attempt loop, not inside it.** `SimWorldgen.generate` runs layout, the
annex stamp, the buildings, the doors, the vehicles and the sites inside a loop that can re-site
the colony on another lot and run the whole thing again. Either place would have been
deterministic — each attempt calls `layout` again and gets a brand-new tilemap, so a refused
attempt's records go in the bin with the map that holds them. What decides it is what the pass is
measuring: "far from home" reads `gate_a`, `gate_b` and the annex rect, and all three move every
time the loop re-sites. A pass inside the loop answers the question about a colony that was then
thrown away; a pass after it answers it about the colony the player wakes up in, and does the work
once. The dressing that follows cannot invalidate a record — `_dress_occluders`, `_dress_terrain`,
`_rubble` and `_paths` each return early on an indoor tile.

**The first cuts: 0.35 and 2, and the sheds were added.** A residential template (the seven houses
and the two cabins) declares `dormant: {chance: 0.35, max: 2}`; the three sheds declare
`{chance: 0.35, max: 1}`; everything commercial, civic and industrial declares no block at all,
which reads as zero. The annex is a map patch rather than a building template and never appears in
`map.buildings`, so there was nothing there to set to zero — it is excluded geometrically. The
sheds were not in the plan's first cut. They are there because with residences alone the 64-tile
miniature every gate boots placed **no bodies on any of the four balance seeds**, so both the moved
pins and the re-baseline would have measured nothing; a body in a lock-up is also squarely in
genre. The shipped 256 district carries **19 / 12 / 18 / 14** bodies on those seeds against an
80-body outdoor scatter. All five numbers are first cuts and the owner's to move.

**Dormant bodies count against the director's live cap.** They are shamblers standing in the
district from tick 0, `world.components.query(["shambler"])` counts them, and excusing them would
have meant a second definition of "how full is this district". The 256 world's first dusk now
stands at 99 live against a cap of 128 and still reads `grace`. Five assertions in three gates —
`check_m2_district.gd`, `check_m2_director.gd` and `check_worldgen.gd` — read
`wanderers_for(n) + map.dormant.size()` rather than a constant. The third was not on the list of
pins this slice expected to move and was found by the chain rather than by reading: its
twenty-two-world sweep boots `district.forest_edge` at 128, where the cabins are the residences.

**A door being opened does not wake anybody, and neither does a smell.** The first is the plan's
own first cut and it stands: an opened door is a noise or it is nothing, and a door hook would be a
second way into the field for one event. The second was meant to be a wake channel and is not, and
the reason is measured rather than argued. `heard` is corrected for the body's own groan — "a body
cannot hear below its own noise" has been in `shambler.think` since the playable state — and
`smelled` has no such correction, while scent is designed to accumulate rather than decay in
seconds. On seed 20260805 at 256, a sleeping shambler's own residue puts **1.0** in its own cell on
tick 20, the first `SCENT_EMIT_INTERVAL`, against a wake threshold of **0.00556**
(`scentFloor` 0.005 / `scentSense` 0.9) — 180 times over, rising to ~40 by t+2000 — and every
one of the nineteen bodies on that map woke on its own smell on tick 21. No constant offset fixes
it, because the steady state is not a constant; the neighbourhood gradient does not either,
because a body that has lain somewhere all game *is* the local maximum and `uphill_scent` at its
own cell is null. So a dormant body wakes on noise or on contact, and residue is still laid in
every state (docs/14) exactly as before.

**What that leaves open, for the owner.** The asymmetry is older than this slice: because
`smelled` has no own-scent correction, it is true for **every** zombie on **every** tick, so
`_drift_upscent` is called for every wandering body and finds no gradient at its own cell. It is
harmless today and it is still not what the code reads as, and a scent channel that could tell a
survivor's trail from the body's own bedding would give the dormant state a second sense. It is
not folded in here because it changes what every shambler in the game does, which is a balance
change wearing a bug fix's clothes.

## One web, and the captives, 2026-09-14

The owner asked for NPC skills, for raiders to carry skills too *"for when the player or the
colony captures them to recruit or enslave"*, and whether the NPC web should be the player's. The
survey behind this entry found three things the questions assumed otherwise: every colonist —
Mara, Ellis, each generated recruit — already carries the player's web and spends it along their
focus, so "give NPCs skills" was landed before it was asked; raiders carry nothing and there is no
capture, only docs/18's post-slice design of one; and the player's own web was auto-spent with no
surface to change it. Four decisions, taken together.

**One web for everybody.** docs/08 says every survivor starts at the same centre node and the web
dies with the person, and nothing in the docs ever proposed a second one. A separate raider web
would double every layout, autonomy and reader gate and hand a recruited captive a translation
problem; a separate NPC web would put two shapes on the one K screen. Raiders differ in what they
*arrive with*, not in the web: an archetype's `skills` are **node ids, granted at spawn with no
points spent**, and not region points, because a raider has no focus row and points would be
spent by the Auto path and the surplus pass, never by the author — a biography is nodes.
`SimSkills.endow` is the one path into a web that does not pay, and it is spawn-only content.

**Raider skills are live during the raid.** The alternative — points that only matter once the
body is captured — is a number nothing reads during the fight, which is the dead-socket pattern
this milestone has paid for eleven times. The same `resolve` on the actor's own scope makes a
gunhand's steadier breath read through the cone refresh and a scav's surer grip through the swing
with no new plumbing, so the band gets harder in the way the content says. Raiders **earn** like
anybody (a shambler put down pays Melee or Ranged, spent along the Auto path, and a person killed
pays nothing because the handler wants a `zombieType` on the victim); the alternative was a
`raider` read inside skills.gd, which is exactly the special case "one web" exists to remove.
`skillWeb` is now the one colonist component a raider carries, and the raider gate's LEDGER lane
asserts it positively beside its four exclusions rather than leaving the list to widen.

**A captured raider can be recruited or put to work.** docs/18 designs the recruit half — a
prisoner eats, needs the quarantine room, can be offered a place, "arriving with real skills" —
and the owner added the other: a held captive can be made to work. This is the first mechanic
here that needs a tone stance, because no document states one; the nearest line is docs/18's cut
of player-initiated raids "at the vision level", which stands. The stance, so the arc has a
boundary before its first slice: a captive is **held, fed, guarded and offered**; forced labour is
a price on the captive's mood and on the mood of colonists whose traits object, and an unguarded
captive is a body that can leave, so the offer stays the honest path by construction and not by
sermon; nothing is sold, tortured or bred, and the colony still never takes the offensive against
another settlement. The standing pause on adjacent feature scope is amended by this decision and
no other: the boot colony stays three, and a recruited captive is mid-game growth outside that
pause. docs/23's what's-left names the six slices.

**The player chooses their own nodes by default.** docs/08 says keystones are build-defining and
"remain player decisions even for NPCs you otherwise ignore" — and the one survivor who is always
you could not make one, because `_focus_of` read the absence of a job row as Auto. The fix is a
**predicate, not a row**: `_focus_of` answers Manual for `world.player` and for any `controlled`
body. A row attached at boot would have needed a second writer at succession, where
`world.player` moves onto a body that keeps its own focus word and is hidden from the work grid
by design; the predicate reads the two facts that define the player, in the file that already
reads them for drift. "One field cannot disagree with itself" (the Focus entry above) still
holds, because the player has no field. Three gates that had granted the player points and
expected the sim to spend them were re-fixtured onto a colonist or onto the command, which is the
honest shape anyway: a lane that proves a modifier applies "when the node is owned" should own it
the way a player does.

## Each dead body differs, 2026-09-15

The fourth piece of the procedural-population arc, and the calls inside it that were mine rather
than the plan's.

**The numbers are first cuts, for the owner.** Body **±15%**, crawlers **5%**, both on
`zombie.base` so every kind inherits them, and a five-entry palette of near-whites there with a
four-entry greener one on the bloater. The spread is the one worth arguing about: at ±15% a
shambler's torso runs 51 to 69 against an authored 60 and its head 21 to 29 against 25, which is
about one melee blow either way — enough that two bodies in a doorway are not interchangeable, and
not enough that a kind stops being one kind. The schema caps it at 0.3 for that reason rather than
leaving it open. 5% crawlers is one body in twenty, which at the shipped 256-tile district is four
on a map and at the 64-tile miniature the gates boot is one or none; that is the frequency a thing
should have if seeing it is supposed to mean something.

**The tint is a modulate, so the palette is pallor and not costume.** A zombie's `appearance.tint`
has always multiplied over its sprite, and the rolled colour goes through the same path, so a dark
entry in `variance.tints` would not give one body a dark coat — it would dim the whole body,
including the parts the artist lit. The five shipped entries sit between `#ffffff` and `#d6d2c8`.
If this ever wants to say something louder than pallor it needs a second sprite, not a darker hex.

**How it reaches the renderer: a pass-through, and deliberately not a lookup.** The rolled tint is
stored on the existing `zombieType` component and `main.gd::_draw_entities` hands it to
`Appearance.for_entity` beside the type id, which prefers it to the content block's when it is not
empty. The alternative — a per-body content id, the way a colonist's `identity.look` points at an
entry in `colony/looks.json` — was considered and not taken: a colonist has six looks and a zombie
would need one content entry per body, which is a registry that grows with the population rather
than with the design. So the *value* travels and the *palette* stays in content, and the draw loop
still contains no branch on an id. The key is always present on the component, `""` for a kind that
names no palette, so a save round-trips one shape.

**`bodyMax` scales with `body`, and that is not an implementation detail.** `HURT_BELOW` is 1.0, so
any integrity under its maximum is Hurt. Scaling the integrity alone would have made every
smaller-than-average body Hurt from the tick it spawned — slower by `_torso_factor`, an NPC
break-off candidate, and wrong in the condition prose — and scaling the maximum alone would have
done the same to the larger ones. There is exactly one normaliser, `SimHealth.part_state_of`, and
this keeps it telling the truth. The legs of a rolled crawler are zeroed *after* the maxima are
taken, so a body born legless is `Unusable` against a real maximum and reaches the same
`crawlFactor` path a body whose legs were shot out reaches. No second locomotion path was added.

**Its own stream, and the pin that proves it.** The rolls come off `zombieLook` and never off the
rng `spawn_zombie` is handed, which is `placement` at boot and `director` at night. The gate pins
the `placement` state at the end of `SimBoot.playable(20260805, 64)` to a literal captured from the
tree before a line of this existed, and pairs it with the assertion that `zombieLook` exists and has
moved — the pin alone would pass just as happily against a slice that had been deleted.

**What the measurement could and could not say.** The four fast seeds came back **byte-identical**
before and after, and that is a result rather than a missing one: a body's size changes what it can
absorb and nothing about how it moves, the FAST tier records nought to one colony kill a campaign,
and the single crawler it rolled in four campaigns was placed too far out to reach anybody inside a
2000-tick dusk window. The durability change is real and belongs to the FULL tier and to the
256-tile district, where the same 5% is four crawlers on a map instead of one. Neither was run for
this slice, and the record says so rather than implying the change is free.

**What this does to gate fixtures, and the rule going forward.** A body spawned through
`SimRoster` is no longer a standard body: it is its own size, and one in twenty is already
crawling. That is the point of the slice and it is also a new way for a gate to go red against
code that is correct — `check_m2_lethality.gd`'s HEAD-ONLY did, on seed 89, reading the torso's
×0.5 compounded with `crawlFactor` as ×0.125. The fix is not to take the roll away from gates; it
is the convention `check_m2_contact.gd`'s `_no_struggling` already set — a fixture that measures a
*named* body pins it back to the type's authored numbers and says in a comment which half is under
test. Every other gate in the chain was run individually, past the first failure rather than
stopping at it, and none of the rest needed it: they either count bodies, measure sight, or kill by
taking a head to zero, all of which are indifferent to a body's size. A gate written from here on
that asserts an absolute integrity — "a torso at 20 of 60 is BadlyHurt" — needs the same pin, and a
gate that asserts a *state* needs nothing, because a state is a fraction of a body's own maximum
and that is exactly what this slice keeps true.

## Four raiders are four men, 2026-09-15

The fourth slice of the procedural-population arc, and the first of its raider group. Two
archetypes shipped and every body of one was the same body: same aptitudes, same kit, same look,
no name. Now each is a person. What follows is the calls this took; the shape of the record is
not one of them.

**A `person` record and never an `identity`, and that is the owner's, not mine.** It is written
into the arc plan the owner approved on 2026-09-14 ("Raiders carry a `raider.person` record, never
`identity`; five readers of `identity` would otherwise see a raider, one of them succession"), and
this slice implements it rather than re-deciding it. The five were read before a line was written
and they are `main.gd`'s "is this a survivor" in the entity pass, `SimJobs.work_view`,
`SimAllegiance.is_person`, the director's unique-death lull and `SimRecruits._succession_pick`.
The last is the one that matters: it hands the player's body to the nearest body carrying `needs`
or `identity`, so a raider with an identity would be an heir standing at your wall. The gate's
NO-IDENTITY lane asserts the negative *and* its converse — a raider given an identity by the lane
itself **is** picked, which is what makes the absence of the component load-bearing rather than
coincidental.

**The jitter is ±1, and it is a first cut.** Each archetype's `aptitudes` may now be a
two-element `[min, max]` rolled per body, and the two shipped entries are their old numbers plus
and minus one, clamped into `SimAptitudes`' 3..8: scav `str [5,7] dex [4,6] con [4,6]`, gunhand
`str [4,6] dex [5,7] con [4,6]`. A raider is not budget-checked the way a colonist is, so the
triple no longer sums to fifteen and does not have to. ±1 was chosen because it is the smallest
width that can be measured at all and because a wider one is a balance change dressed as
individuality; the measurement is in docs/23's record, both columns, same driver.

**Odds go on the extras, never on the arms.** A kit row may carry a `chance`, rolled per body, and
the gate refuses an archetype whose every weapon row is behind one — a band that walked
pedestrians at your gate on some seeds and raiders on others would be a raid that varies in the
one way it must not. A row that declares a chance spends exactly one draw whatever the odds are,
so editing a `0.5` to `1.0` does not move the stream under every later raider; a bare row spends
none, which is what keeps an archetype that declares no odds byte-identical to the way it spawned
before.

**The look pool is kept tell-free by construction, not by care.** `content/colony/raider_looks.json`
holds one flat `looks` list and the draw happens on `raiderLook` with no idea which archetype
asked, so a scav and a gunhand can and do wear the same one; the gate spawns sixteen of each and
requires the two sets to overlap, and refuses two disjoint sets through the same predicate. An
archetype that declared looks of its own would partition the pool at the source and is refused
too. The rule underneath, written down because the next raider slice will want it: **what a raider
is wearing may vary between bodies but never between archetypes; what they are holding is the
archetype.** Worn gear draws on the pawn, so a cap only the scavenger could be wearing would
answer "which one has the gun" across a street — the certainty docs/01 clause 4 refuses. A weapon
in a hand is visible by design, because you can see what a man is carrying. The gate compares the
worn rows of every archetype, odds included, and requires them identical.

**A raider look declares no tint, and that is a measurement rather than an omission.**
`raider_drab` is at the floor of the palette's ground-contrast guard already — tools/sprites'
`palette.py` calls it "as dark as the drab can go and still read as a body rather than a hole in
the street" — and a tint is a multiply, so any wash can only darken it. Measured over the real
pixels: the shipped rig composes to a median luma of **0.3831** against a street floor of
**0.3796**, which leaves **0.0035** and permits nothing darker than a factor of 0.991 — a wash
within one per cent of white, which is a look the renderer reads and nobody can see. So the four
look entries all resolve the one body, the look id is the hook a per-body picture attaches to when
the art exists, and the per-body variation a raider actually shows today is **what they are
wearing**: a canvas cap at even odds and a school bag a little under, on both archetypes. The
numbers are printed by the gate's LOOKS lane every run, so the day the rig is re-authored lighter
the headroom is on the line where it is decided.

**What the chronicle says, and when.** A raider's name reaches the player in exactly one place and
only once they are dead: `One of the raiders was Ada Kovac, a debt collector once, grey and still
walking; a split lip, bad teeth.` Not "%s is dead" — a colonist's death and a raider's must not
read the same way in the same column — and nothing at all while they are standing there, because
a band at the wall is anonymous by contract. The sentence is `SimRaiders.person_clause`, built the
way `SimSurvivors.person_clause` builds a colonist's, and it is deliberately the reader for
*every* field of the record: the name, the backstory's line and the age band's prose looked up in
content at read time (so editing a line changes what an existing save says, with no migration),
and the features as what a look at the body shows. A field of that record with nothing to read it
would have been the dead socket this milestone has paid for eleven times. It is digit-free because
the chronicle is on the HUD. The line is long — a little over a hundred characters in the corner
column — and if the owner finds it busy on a raid night, shortening it is one call in
`_line_of` and no change to what is recorded.

**Two new streams, and the old one pinned.** The person, the kit odds and the aptitude jitter draw
on `raiderRoll`; the age and the look on `raiderLook`, which is `SimPeople.roll`'s own split and
not this slice's to reorder. The director's `raid` stream is untouched, and that is pinned rather
than asserted: the gate holds the stream's state after `_emit_band` places four against literals
taken from the pre-individuals tree with a throwaway driver on two seeds, and proves the pin can
fail by spending one more draw.

## The stalker and the runner, and what "zero code" turned out to mean (2026-09-15)

The fifth piece of the owner's procedural-population arc, and the one that was written as an
experiment rather than a feature: docs/14 closes with **"adding a zombie type is one JSON entry
with zero code, provided its behavior composes from existing tags"**, and nobody had tested it,
because the three kinds that ship were each landed alongside the code that made them work. The
stalker and the runner were picked to test it because docs/14 itself sorts them onto opposite
sides of the qualifier — "stalkers and armored zombies compose from tags that exist or nearly do
… screamers and runners need sight".

**It held, with one half of one kind left out, and the half is named below.** Two files under
`godot/content/zombies/`, `zombie.schema.json` untouched, and **not one line under `godot/sim/`**
— `git diff` over that directory is empty for this slice, which is the claim stated as something
checkable rather than as a feeling. Even the two type ids live in `check_m2_roster.gd` rather than
beside `TYPE_SHAMBLER` in `sim/modules/roster.gd`: a `const TYPE_STALKER` in the sim would have
been the first line of code the claim cost, and there was no reason to spend it.

**What did not compose: the runner's "sustained pursuit".** docs/14's runner row is "Fast,
sustained pursuit", and the *fast* half is one number in `locomotion.speed`. The *sustained* half
is `SimShambler.COMMIT_TICKS`, a module constant shared by every kind, and there is no content key
for it — a runner that gives up exactly when a shambler does is what shipped. Adding one would
have been a new content axis inside a slice whose whole purpose was to find out whether the
existing ones were enough, so it was not added. docs/23's record says which half shipped, and the
honest reading of the experiment is that the qualifier in docs/14 is doing real work: **the
roster is cheap, and a kind whose defining trait is a duration is not a roster entry yet.**

**The numbers, and where each came from.** docs/14's sensory table is words — Low, Moderate,
High — and the shipped three already fix the dialect: High is 0.9, Moderate 0.4, Low 0.1–0.2. So
the stalker is `{noise 0.9, light 0.4, scent 0.4}` and the runner `{noise 0.9, light 0.9, scent
0.4}`, both read straight off that table rather than off the arc plan, which had called the runner
"light-led" and left its ear out. Speeds are the plan's first cuts and agree with docs/14's prose:
the stalker at **1.0** is "faster" than the shambler's 0.8, the runner at **1.4** is "fast". One
thing the reader should know about 1.4: a human sprint is 3× a walk (`SimLocomotion.SPRINT_SPEED`),
so a runner cannot be walked away from and *can* still be sprinted away from while the stamina
lasts, which is a softer reading of docs/14's "Not outrunning it" than the table implies. It is
left where it is because a first cut that has not been played is not a place to spend a second
guess. The stalker's "investigates aggressively" is `wander` 0.45 and `mill` 0.5 against the
shambler's 0.35 and 0.25 — existing keys, no new mechanism.

**Waves 1 and 3, which is where docs/14 puts them**, not where a flatter schedule would. docs/14
has the stalker in the first mutation wave beside the screamer and the runner in the third; the
compressed schedule is `1 + wave × WAVE_DAY_STRIDE`, so the stalker arrives on **day 3** and the
runner on **day 7**, both inside the ten days the campaign harness runs. Weights are the plan's
cuts, **10** and **6** against the shambler's 80 — the runner low on purpose, because it is the
kind most likely to change a night. The balance measurement did not ask for either to move.

**The MIX lane's pinned sequence was re-pinned, deliberately, and the distinction matters.** That
literal — fifty day-7 draws of seed 20260805 — was captured by the mix slice, whose claim was
that making the mix content changed *nothing about what spawns*. This slice changes what spawns on
purpose: two kinds join the pool from day 3 and day 7, so the day-7 sequence must move, and a
re-pin that left it unchanged would have meant the new kinds were never in the pool at all. What
survives the re-pin is what the pin is for: days 1 and 2 are still untouched (the shambler-only
short-circuit, QUIET), and from here any *unintended* movement is red again. What the re-pin costs
is a claim, and the replacement for it is a new lane rather than a promise — SHARES draws two
thousand day-7 rolls and holds every kind inside ±25% of `weight / summed weight`, computed from
the resolved entries rather than from a number copied into the gate, so the shipped mix is still
proved to be the mix content asks for.

**They look exactly like a shambler, and that is a gap with a name.** Both declare
`appearance.sprite: zombie_shambler`. A new sprite key is `sprites:check` work — Pillow, a byte
comparison of generated PNGs, and the CPython float trap in CLAUDE.md — which is a different kind
of slice from this one, so it is a named follow-up in docs/23's what's-left rather than something
smuggled in here. What does tell one body from another today is the per-body tint each kind rolls
from its own `variance.tints` palette (the variance slice's pipeline, ashen for the stalker,
flushed for the runner), and that is pallor, not a silhouette: in a crowd at 2× you cannot tell
which one is fast. `check_appearance.gd` records the gap where a reader will meet it, as a third
`ROSTER_SHARED` group whose comment says it is a gap and not a decision.

## A third side, 2026-09-15

The allegiance seam, the first slice of the procedural-population arc's settlers group, and a
small one on purpose: the settler pieces that follow need a side that is not the colony and not
hostile to it, and this lands that side and the proof it works before anything stands on it.
`godot:m2:allegiance` is the gate. What follows is the calls this took.

**The table is kept symmetric by the lookup, not by discipline.** `HOSTILE_PAIRS` declares each
hostile pair **once** — raiders against the colony, raiders against the settlers — and
`factions_hostile` tries a pair both ways round before answering, so there is no second direction
to write and no way to edit the list into a table where the colony is at war with the raiders
while the raiders are at peace with the colony. A dictionary of rows would have needed both halves
kept in step by hand, which is the bug the brief named. The gate asserts the property anyway
(SYMMETRY, over every ordered pair) and proves that assertion can fail by running the identical
walk against a lookup that deliberately answers one way round only; it also refuses a table that
is all war or all peace, because either is perfectly symmetric and says nothing. The zombie short
circuit did not move: it is still the first thing `hostile` does, before any faction is read, for
the reason the file has always given — a shambler carries no allegiance component, so `faction_of`
would call it a colonist and the colony would stop defending itself.

**`is_colony` means one of yours, which stopped being the same question as "not an enemy".** It is
one line, `faction_of(world, entity) == COLONY`, and it has exactly one reader outside the gate:
`SimRecruits._succession_pick`. That scan took an `identity` as proof of colony membership, which
was true right up until a third side existed — a settler carries an identity, so the player dying
at a stranger's fence would have woken up in the stranger's body. A settler is still a *person*
everywhere else and `is_person` was deliberately not touched: a zombie chases them, a screamer
raises the alarm about them, and being a person is what makes you edible while being the colony is
what makes you an heir. The change also means a raider is now refused an inheritance twice over
rather than by the accident of carrying no identity, which is why `check_m2_raiders.gd`'s
NO-IDENTITY negative gained a step: it asserts the raider given an identity is *still* refused,
and that the same body given the colony's allegiance is picked, so the refusal cannot quietly
become a scan that refuses everybody.

**docs/18's factions are still Milestone 3, and this is not them.** It is one string, three
values and a table of which pairs fight. No standing, no reputation, no trade, no diplomacy, no
way for a side to change its mind about you. The raider schema's `allegiance` is now a `$ref` to
a single `$defs/faction` allowing `raiders` and `settlers`; `colony` is deliberately not on that
list, because an archetype declaring it would be a colonist spawned outside the roster with no
needs and no place on the ledger. The Godot content validator does not resolve `$ref` and the
frozen oracle never reads `content/raiders/`, so that enum's reader is the gate — checked against
the code's own constants and against every shipped archetype, which is the dead-socket rule
applied to a schema rather than to a component.

**Nothing spawns a settler yet, and the gate is the only thing that exercises the value.** That is
the condition under which a gate quietly stops proving anything, so every lane carries its true
negative in the same fixture as its positive, and each was run red on purpose before it was
trusted. No balance measurement is owed: no settler exists in any shipped spawn path, the table
answers exactly as `!=` did for the two factions that do, and nothing here draws from an RNG
stream — which was proved rather than asserted, against the raid-stream pins and the R1 parity
fixture.

## A stranger in a building, 2026-09-15

The second of docs/07's three recruitment routes — "a scavenging encounter" — and the seventh
slice of the procedural-population arc. Until now the colony could only grow one way: somebody
turns up at the gate on days 8, 12 and 16 and is gone by dawn. Now somebody is also sheltering in
a building out in the district, and comes out when they see you. `godot:m2:strangers` is the gate.
What follows is the calls this took.

**The acceptance is the rung that already exists, and building a second one was the mistake on
offer.** A stranger wears the same `recruit {waiting: true}` tag a gate recruit does, so
`SimFortify`'s E ladder finds them through `SimRecruits.waiting_in_reach` and takes them in
through `SimRecruits.accept` — the same call, carrying the same hidden-bite roll at the same
`TRANSMIT_P`. Nothing in `strangers.gd` accepts anybody. That is what keeps the bite hidden: there
is exactly one place in the sim where a recruit can turn out to be carrying something, and a
second acceptance path would have been a second place to forget to roll it. No field on the
`stranger` component says anything about the bite, nothing is published about it, and the module
never asks.

**The colony is told nothing, at either end.** A gate recruit publishes `recruit.arrived` and the
chronicle writes *Someone is waiting at the gate.* A stranger publishes nothing when they are
placed: they are two hundred metres away in a house nobody has been in, and a line about them
would hand the player a fact nobody in the colony has (docs/01 clause 4). The same at the other
end — the chronicle's existing lines are *The stranger at the gate has gone* and *So-and-so has
walked out*, and both are false about somebody who was never at the gate and whose name the colony
may never have learned. So `recruits._tick_leave` now publishes whatever reason the `leaving`
record names (`mood` by default, which is every caller that came before) and the chronicle skips
`stranger` outright. What you learn about a stranger is what you saw. No new prose was written,
and `godot:check:hud` is untouched and green.

**Sight decides the approach, and it is the real sight system.** They come out when a colony body
is inside their *own* observer's line of sight — walls and range, cast from their eyes, which
`SimRecruits.spawn_generated` has always given them. A distance check would have been four lines
and wrong in the way that matters: the point of hiding in a building is the building, and somebody
who walks out through a wall to meet you across it is not sheltering, they are homing. The gate's
negative is exactly that case — a colonist the same distance away with a wall between is not
approached and not even noticed — and the code was run with the sight test deleted to prove the
lane can say so. `line_of_sight` rather than `detail`, and that is the one place this is
deliberately *less* strict than a colonist's attention: `detail` narrows by the facing cone,
and somebody hiding in a room is watching the room rather than holding a heading. The range is the
honest one either way — it closes in at night and in fog, so a stranger notices you across a lit
room and not across a dark district.

**Once they have seen you they walk to where you were, not to where you are.** The `stranger`
component carries a goal point that is refreshed while the colonist is in sight and kept when they
are not — a remembered position and never a track, the same rule `sightings.gd` keeps and the same
reason: a body that followed somebody it cannot see would be a lie the player could read off the
screen.

**One stepper for everybody who walks and is not on a job.** `SimRaiders._walk` was a private
grid-A* stepper doing exactly what a stranger needs, so it moved to `SimWalk.step(world, ent, rec,
goal, speed)` and both callers reach it, each keeping its own record dict. Copying it was the
cheaper edit and the wrong one: two walkers that start identical drift the first time either
learns something — a surface cost, a crowd, a door that is locked rather than merely shut — and
then a raider and a stranger disagree about what a wall is. `speed` is a parameter rather than a
field on the record, because a raider's comes off its archetype through `move_speed` modifiers
every tick and a stranger's is one constant, and writing it into the record would put a derived
number in the save. `SimJobs._walk` is deliberately not folded in: it carries the reservation, the
arrival test the job's own state machine reads, the stance and the encumbrance, and pulling that
apart is a refactor of the scheduler rather than a shared helper.

**Two rules in `recruits.gd` had to learn what a stranger is, and both were regressions waiting to
happen.** The gate beat refused to fire while *any* `recruit` component existed, and the dawn
leave despawned *every* waiting recruit — so before this slice a stranger hiding in a house on day
5 would silently have cancelled the day-8 gate beat and died at the first dawn. Both now go
through one predicate, `_waiting_at_the_gate`, so the two cannot come to disagree about what a
stranger is, and the gate holds both halves of both: day 8 fires over a hidden stranger and is
still blocked by a gate recruit; one dawn takes the gate recruit and leaves the stranger. Each was
run red on purpose by putting the old `query(["recruit"])` back.

**They arrive in daylight, and that is the one call here that a measurement forced.** The beat
first fired on whatever tick of the beat day the world happened to be running — dawn in a real
campaign, and **dusk** in the balance harness's compressed tier, which jumps to each day's dusk
and steps a window. A stranger placed at dusk is placed into the night the director is filling,
and on seed 31337 both of them were killed and **turned** inside the window they arrived in: two
shamblers the district gained that the director never placed, and a live count of 33 against a cap
of 32, which is `check_m2_balance.gd`'s standing invariant and not something to widen. A throwaway
driver (deleted) put the number on it — `PEAK live=33 cap=32 of which turned-from-a-person=2` —
before anything was changed, which is the only reason the guard is a day rather than a guess. So
the arrival has a time of day, the way the dawn leave already did, and it is the honest rule as
well as the cheap one: somebody sheltering in a building comes out when they see a colonist, and a
colonist is out in the district during the working day. The gate's DAYLIGHT lane runs the same
beat day at dawn, day, dusk and night and requires exactly one of them to place anybody.

**The first cuts, all the owner's to move.** Beats on days **5, 10 and 14**, between the gate's 8,
12 and 16 rather than on them, so the two routes into the colony are felt as two rather than as a
busy week. At most **two** live at once, because finding one should be an event and a district
with one in every other house is a population. They are placed at least `SimDirector.GATE_EXCLUSION`
(32 m) from both gates and clear of the annex — the dormant bodies' own distance rather than a
second constant, since it is already the answer to "far enough from home that this is something
you went out and found". They wait **three days** and then walk out. And they share
`SimRecruits.CAP`: the colony still tops out where it did, because a second route in with a cap of
its own would have doubled the ceiling, which is a balance change smuggled in beside a feature.
None of the five moved under measurement — the before/after run in docs/23's record leaves
`survivors_end` unchanged on all four fast seeds — so they are first cuts in the honest sense:
numbers that have been checked for harm and not yet chosen for feel.

**Save:** `SAVE_VERSION` 31. A v30 save has no `stranger` component, no `stranger` flag on the
recruit tag and no `world.strangers.spawned`, and each is wrong on its own — restored, every
stranger already placed would read as somebody at the gate (cancelling the next gate beat, and
despawned at the first dawn), and every stranger beat the campaign had already paid for would fire
again.

## Armour on the dead, and the half of the heavy that had nowhere to go, 2026-09-15

The armoured-and-heavy slice of the procedural-population arc. `godot:m2:armored` is the gate and
docs/23's record carries the evidence; what follows is the calls this took.

**A zombie may wear things, and that is the whole of the armour mechanic.** `armor_coverage_of`
already read the target's `equipment` without asking whose body it was, and `armor_damage_factor`
already multiplied by it inside `damage_part`. The defect docs/23 carried was never about
arithmetic — it was that no zombie had an `equipment` component to read. So the fix is a `worn`
list on the type and four lines in `spawn_zombie`: an inventory, `equip` per id, `lootKit`. The
alternative considered and refused was a coverage number on the zombie entry itself, which would
have been a second way to say what an `armor` block already says and a second thing to keep in
step with it.

**Which armour a dead body may wear: only what the loot tables already ship, and only two pieces.**
`item.vest.scrap` and `item.helmet.bike`. The reason is the loop rather than the balance: gear a
corpse drops is gear the colony can use, and a piece the district cannot otherwise produce would
make the armoured kind a *source* of something new instead of a harder version of a fight. Two
rather than a full kit because a zombie body is head/torso/legs — gloves, boots and trousers cover
parts it does not have, and putting them on would be flavour with no reader. This is a first cut
and is written down as one: a later slice may give the kind a rolled kit, and the gate reads the
declared list rather than a literal, so it will follow.

**The armoured body is a shambler's body.** Tempting to make it tougher underneath as well; refused
on docs/14's rule 5 — a new type invalidates a strategy, not a stat. What makes it "resists light
weapons" is that a vest and a helmet are on it, which the player can see coming off the corpse and
can wear themselves. A kind that was *also* bigger would be two mechanics under one name and the
armour would be untestable inside it.

**Weights 8 and 4, both wave 2.** docs/14 puts armoured and heavy in the second wave and
`WAVE_DAY_STRIDE` makes that day 5, inside the ten days the harness runs. The weights are first
cuts sized against the shipped ladder (shambler 80, screamer 12, stalker 10, bloater 8, runner 6):
the armoured one sits with the bloater at 8, and the heavy is deliberately the rarest thing on the
table at 4, because it is the only body that is straightforwardly harder to kill and rarity is the
cheapest lever to pull back if it turns out to be too much. No seed wiped, so neither was pulled.

**The breach half did not ship, and that was the right outcome rather than a shortfall.** The arc
plan proposed `breach: {factor}` on the heavy, read wherever `fortify.breached` damage is dealt.
There is nowhere to read it. `SimFortify._presses` returns a **count of bodies per tile** and
`_press` spends `pressure_of(n)` on it; no entity reaches that arithmetic at any point, so a
per-attacker factor has no possible reader. Writing the key anyway would have been the twelfth dead
socket, and building the reader means rewriting pressure as a weighted sum — which moves every
shipped fortify number and every balance figure below them, and is a slice with its own gate. So
the heavy that shipped is a big slow body and not yet docs/14's "wrecks structures fast", the
schema has no `breach` property, and the gate's BREACH lane says so and skips while *measuring* the
reason: one heavy and one shambler break the same board on the identical tick, and two shamblers
break it in a third of the time. The lane goes red the day anything declares the key without a
reader, which is what makes a skip worth keeping.

**The MIX pin was re-spent, for the second time in one day.** `check_m2_roster.gd`'s fifty-draw
day-7 literal is a byte-identity claim that belonged to the mix slice — which changed what content
could *say* about the composition and nothing about what spawns. A slice that adds kinds changes
what spawns by design, so the sequence must move; a re-pin that left it alone would mean the new
kinds were never in the pool. What the pin still buys is that any *unintended* movement is red
from here, and days 1 and 2 stay byte-identical through the shambler-only short-circuit. SHARES,
now over seven kinds summing to 128, is what replaces the claim the re-pin spent, and the
`placement` stream pin in `check_m2_variance.gd` is unmoved — nothing here draws on a stream a
campaign is made of.

## What a raider came for, 2026-09-15

Raider roles, the second slice of the procedural-population arc's raider group. docs/18 has always
said a raid is a business — "target stores first, people second, and will withdraw once loaded;
retreat when losses outweigh the haul" — and until this every raider walked at the gate and fought
until a clock ran out, so that sentence had no reader. `godot:m2:raiders` is the gate. What follows
is the calls this took, none of which the plan made.

**Both shipped archetypes stay fighters, and the roles arrive as new archetypes.** `raider.scav` is
weight 4 of 5: it is four fifths of every band this repo has measured, and re-roling it would turn
every raid in every campaign into a robbery in a one-line content edit — a balance change wearing a
content edit's clothes. So `scav` and `gunhand` declare `fighter` explicitly and behave exactly as
they did, and the new behaviour arrives as `raider.looter` (Bagman, weight 2) and `raider.lookout`
(Watcher, weight 1). The cost of that choice is real and is the honest one: the weighted draw moves
from 4:1 to 4:1:2:1, so band *composition* changes on every seed, and that is measured rather than
asserted. The alternative — new archetypes at weight 0, so nothing moves — would have shipped two
dead sockets, which is the thing this milestone has paid for eleven times.

**A looter takes three things, and only what is on the floor.** Both are the plan's first cuts and
both are the owner's to move. Three item *entities*, not three stacks and not a packful: on a
stockpile of tins and bottles that is a night's meals rather than a pantry, and it is small enough
that the first campaign to lose some of it is an annoyance rather than a wipe. Containers are out of
scope on purpose — opening a cupboard is a search job with its own timing, noise and content hooks,
and a raider doing it would be a second implementation of the Scavenge job rather than a role. What
a looter carries out is **despawned** when it leaves the district, because an item whose `stored`
points at a despawned body is in nobody's hands and on no floor: it would neither come back nor be
gone. Killed on the way out, it drops the lot.

**A lookout stands twelve metres out.** Far enough outside every reach in the content tree that no
halt, no wall-following detour and no arrival tolerance produces it by accident, and close enough
that the watcher is still a body in the district — a zombie sees them, the colony can shoot at them,
they make the same noise anyone else does. It turns the band for home at the **first** loss, where
the shipped rule waits for half the band to fall, and it writes that decision onto the other bodies'
components rather than publishing an event: handlers drain at the end of the step, so a band told to
leave by an event would take one more step towards the colony first, and on the tick a watcher sees
the first man fall that step is a blow landing.

**A role is invisible, and that is the information rule rather than an omission.** Nothing about
dress, sprite, look or name says which body came for your pantry, exactly as nothing says which one
has the pistol: the new archetypes wear the identical worn rows at identical odds (the gate's
NO-TELL lane walks every archetype, so it caught the question before it could be asked), draw from
the same archetype-blind look pool, and resolve the one shared body. What gives a looter away is
that it walks *past* you towards the stores, which is behaviour a player has to read and is earned.
The HUD says nothing about any of it.

**The looter takes before it fights.** The halt that makes a raider stop and fight is asked after
the looter's armful, not before, because the stockpile is where the colonists are: a looter that
reaches the shelf is inside somebody's reach before it is inside the tins', so with the order the
other way round it would stand over your pantry fighting and never touch it. The window is narrow —
something of yours in arm's reach, or arms already full — and it costs the body nothing
defensively, because `npc_combat.gd` swings from where a body stands and never reads a velocity.
What the order has **not** bought yet is a robbery: on four forced raids the band is met five to
thirteen metres short of the stores and `looted` reads 0, which docs/23's record states plainly
rather than dressing up.

## A band that is not coming for you, 2026-09-15

The crossing slice: the director's Encounter lever, and the first band in the game that is not
aimed at the colony. Five calls, each of which could honestly have gone the other way.

**Fifteen per cent, at dawn, on its own stream.** The chance is the plan's first cut and the
owner's to move; what is not arbitrary is where it sits. Below the raid's twenty because the two
share `RAID_LIVE_CAP` — every band crossing at dawn is a band the dusk draw cannot send — and at
dawn rather than dusk because a band that walks in at dusk is a band you meet in the dark at your
gate, which is a raid whatever its objective record says. One that crosses in daylight is something
you can see coming and decide about. `"raidRoam"` is its own stream for the reason
`"directorNight"` and `"raid"` are: `check_m2_raiders.gd` holds `"raid"`'s byte sequence against a
literal taken on the pre-individuals tree, every measured band in docs/23's record is a function of
it, and a second decision threaded into it would move all of them. It shares `RAID_FIRST_DAY`
rather than owning a second schedule, because two first days would mean the grace docs/23 measured
was only ever half a grace.

**The objective is a loot site, at least `GATE_EXCLUSION` from home.** A `map.sites` record rather
than a tile of open ground, because a site is a place somebody would cross a district *for* — the
band's line is drawn between two things that exist in the fiction. The exclusion is the same 32 m
and the same meaning `_legal_tile` gives an entry tile, asked of `SimHome.near_any` so a camp
counts as home too: a band whose objective were your own doorstep would be a raid that had been
told to call itself something else. Measured before it was written — at 64 tiles the four balance
seeds keep 1, 1, 3 and 1 sites that far out, at the shipped 256 they keep 64, 69, 66 and 57 — so
`no-site` is a real refusal rather than the usual answer, and a district with nothing far enough
away says so and sends nobody instead of falling back on the gate.

**The far edge is the opposite side, nearest tile to the objective, drawn with no randomness.**
`_emit_band` is the raid's emitter too, so a draw here would move `"raid"` the moment an objective
was passed; nearest-to-goal is deterministic and needs none. A district whose opposite edge has no
legal tile gets the nearer flank, and one with no second usable edge at all hands back (-1, -1),
which `SimRaiders` reads as "leave the way you came" — a band that crossed as far as it could and
turned round, which is what such a district physically is.

**What the roles do while crossing, which is the call this slice had to make rather than inherit.**
Both halves are decided against the *objective* rather than against the colony.

A **looter** loots the place it crossed for and never your pantry. A band that crossed a district
for a pharmacy and took nothing out of it is the contradiction; a looter that walked past its own
objective to rob a colony it was not visiting would make the whole lever a raid with extra steps.
So `_worth_taking` branches: a raid asks `_is_stores`, a crossing asks whether the thing is lying
at its site. What it carries out is despawned with it, exactly as a raid's haul is, so a site the
colony had not reached yet is now three things poorer — docs/12's scavenging squeeze arriving as
somebody else rather than as a timer.

A **lookout** does not halt while crossing. `LOOKOUT_METRES` is a watcher on the treeline *outside
your gate*: it is a distance from a colony, and a band with no colony to watch has nothing to stand
off from. A lookout halting twelve metres short of a cupboard is that clause read literally and
meant nowhere. What does travel is the other half of the same role — the first man down still turns
the whole band for the exit, because that is a fact about the band's arithmetic rather than about
the colony, and it is docs/18's "retreat when losses outweigh the haul" applied to a crossing. So a
watcher in a passing band walks with it and decides when it breaks off.

**It is an Encounter, not a second horde, and docs/17's opening claim is what that means.** The
director "is not a spawner": it does not place a horde at your gate, and where zombies arrive stays
the attention field's business. A crossing does not touch that. It places nobody near the colony —
the entry tile gets `_legal_tile`'s existing exclusions and the objective gets the same 32 m — it
takes a slot out of the raid budget rather than opening a second one, and it fights only what
`SimAllegiance.enemies_of` puts inside `HALT_METRES` of its own line. A colony that is nowhere near
that line never meets it. The pressure it adds is armed people between you and your scavenging,
which is something the player can walk into or walk around, rather than something delivered to the
wall.

**And the player is told nothing.** `director.roam` carries its reason for rule 5's sake — a lever
nothing can observe is the one docs/17 forbids outright — but it reaches no chronicle line and no
HUD clause, exactly as `director.raid` does not. Where a band is going, and that it is not coming
for you, is something you find out by watching it, which is the information rule rather than an
omission.

## The settlers' camp, 2026-09-15

The seam from "A third side" got bodies. Six calls were taken here, and every one of them was
taken because a measurement or a gate said the obvious answer was wrong — none of them from an
argument.

**96 metres was the plan's first cut and it is 32, because 96 cannot be satisfied where the gates
run.** `SimWorldgen.far_buildings(map, 96)` returns **zero** buildings on all four balance seeds
at the 64-tile size every gate and the FAST balance tier boot — the district is 64 m across, so
the rule is not strict, it is unsatisfiable, and a camp that exists only on the shipped 256 would
be a feature the chain never sees and a balance claim with nothing in it. At
`SimDirector.GATE_EXCLUSION`, 32 m, the same four seeds hold 0 / 1 / 3 / 2 qualifying buildings at
64 and 44 / 55 / 44 / 43 at 256: the camp is real where the gates run, and the one seed with
nowhere legal fires the gate's skip line for real rather than in theory. The second reason is the
one `far_buildings`' own comment already gives — *a second copy of "far from home" is a second
answer* — and the dormant pass, the director's packet legality and now the camp all take the one
number. It is also the number the strangers slice independently landed on for the same question
a merge earlier, which is the strongest evidence available that the district has one answer to
"far from home" rather than three.

**The camp does not share a house with a sleeping body, and another gate is what said so.** The
dormant pass and the camp both draw from `far_buildings` at the same `GATE_EXCLUSION`, so they
compete for one set of houses. With no third filter the camp was sited on top of a sleeper, and
`check_m2_dormant.gd`'s ASLEEP lane went red — "body 46 woke on its own after 200 ticks with
nothing near it" — because people breathing beside something that wakes on scent wake it. The
other gate was right and this slice was wrong, so the siting moved and no assertion did.
`map.dormant` is layout, written in the pass that places the buildings, so reading it keeps siting
inside the layout rule above. It is also the rule people would actually follow: you do not make
camp in the room with the body in it.

**Three settlers became two and then went back to three, and the round trip is the useful part.**
At three, `check_m2_balance.gd` went red on seed 31337 — "exceeded the live cap on 76 ticks
(max 33)" — and a throwaway driver put the arithmetic on it before anything was changed:
`peak=33 cap=32 boot_zeds=23 placed=6 turned=4`. A settler who is bitten, dies and turns is a
zombie `SimDirector.LIVE_CAP` never placed and cannot refuse, which is the same accounting gap
the strangers slice hit from the other direction. Cutting the count to two turned the number
green, and it was a symptom fix: the *cause* was the shared house above, surfaced one gate later.
With the sleeper filter in, the settlers stop dying, `turned` falls to 0 on that seed, and three
settlers peak at 27 / 27 / 28 / 30 against a cap of 32 — so the plan's first cut came back. **The
lesson is the one CLAUDE.md already states and this slice paid for anyway: a number that makes a
gate green is not the same thing as a diagnosis.** **The gap itself is not closed and is not this
slice's to close:** nothing anywhere reconciles a turned body against the director's budget, so a
colony losing several people to infection in one night can still push the district over its own
cap. Two slices in a row have now paid for it, which is why it is written down here rather than
only in a record.

**A settler is a raider's faction handling with a survivor's identity, and the two components it
deliberately lacks are the whole design.** `identity` **yes** — a raider is denied one because
succession would make a band at your gate a queue of heirs, and the allegiance slice's `is_colony`
closed that door, so the settlers can have their names, their backstories and `person_clause`'s
prose. `needs` and `jobPriorities` **no**, and not as an omission: those two components are
exactly what the colony's books are keyed on. `check_m2_balance.gd`'s `_survivors_alive` counts
`needs` + `body`, `jobs.gd` queries `jobPriorities` + `identity`, and `npc_combat.gd`'s intake is
`needs` or `raider`. Each of the three was read before the decision rather than assumed, and the
gate asserts the first structurally, textually and empirically.

**Siting reads the layout and only the layout, which this file has now recorded three times.** The
camp is chosen from `far_buildings`, filtered by the dormant manifest and placed by
`indoor_tiles_of`, so it asks `map.buildings`, `map.tiles`, `map.indoors` and `map.dormant` and
nothing about vehicles, loot, rubble or props. Switching the dressing off cannot move it, which is
the rule the region assembler broke by re-deriving a ranking one layer too late and moving the
colony 45 tiles.

**The camp has no behaviour, and saying so is the point of the entry.** Nothing mills, nothing
returns at dusk, nothing fights back — `npc_combat`'s intake asks for `needs`, which a settler
does not have — and nobody can be recruited. A camp today is three bodies standing in a building
that breathe into the noise and scent fields and are eaten. The ten-day measurement says exactly
that: `survivors_end` is unchanged on every seed, `over_ticks` against the live cap is 0 on all
four, and on the two seeds that site a camp at 64 tiles the camp costs the colony nothing and
loses nobody. That quiet is a fact about the tier rather than about the camp — the FAST tier runs
2,000 ticks of each dusk and nothing walks the district in between — so what it measures is what a
house full of living bodies costs a district, not what meeting one is worth. The latter is the
ten-day human playtest's question, and the next slice is what this table re-measures against.

## What the settlers do, 2026-09-15

The camp got a day, and the arc that began with the allegiance seam is finished. Five calls were
taken, and the first one is the one the entry above said this slice would have to answer.

**A third query by name, not a widened intake and not `needs` on a settler.** `npc_combat`'s roster
was "everybody with `needs`" plus "everybody with `raider`", and a settler has neither on purpose.
Three options, and the two refused are the argument for the one taken. Giving a settler `needs`
would have undone the camp slice in a line: that component is what `check_m2_balance.gd`'s
`_survivors_alive` counts, so a camp would have walked onto the colony's ledger, and `jobs.gd`
queries `jobPriorities` + `identity`, so the scheduler and the work panel would have followed.
Widening the first query to something every body carries — `position`, `body`, `allegiance` on its
own — would have changed *which bodies this module schedules for everybody*, colonists included,
which is a change to how every NPC in the game fights, made in passing, to get three people in a
house to swing a knife. So the roster gained a third query that asks for the settlers faction by
name: it adds exactly the bodies it names and nothing else, it is the same move that added the
raiders to the same function a slice earlier, and it is the only one of the three a reader can
judge at a glance. The ledger did not move, and the gate still says so structurally, textually and
empirically.

**The leash is a guarantee because the plan is vetted, not because the goal is.** A settler mills
inside `CAMP_RADIUS` of the camp's centre, and the obvious implementation — draw a goal inside the
circle — is not enough: a grid path between two points inside a circle can bulge outside it to get
round a wall, so a lane written against the goal alone would have had to forgive a bulge it could
not bound, which is a lane that cannot fail. Instead the whole plan is thrown away unless every
waypoint is inside the leash, and a body walking the straight segment between two waypoints that
are both inside a circle never leaves it. That is what lets the gate assert ten metres outright.
It is also load-bearing rather than decorative, and the sabotage pass is what proved it: widening
the goal draw to three times the leash left the lane **green** at 3.77 m, because the wide goals
were simply refused; only dropping the waypoint test as well put a settler 12.18 m out.

**The willing one wears the strangers slice's tag and not its component.** `recruit {waiting,
stranger}` is what the E rung finds, so recruiting a settler runs down `SimFortify`'s existing
ladder into `SimRecruits.accept` — one acceptance path in the tree, one hidden-bite roll on it, and
no second rung. The `stranger` *component* was deliberately not given: `SimStrangers` would steer
them (two systems writing one velocity), they would burn a slot in its `LIVE_CAP`, and after
`STRANGER_DAYS` they would walk to the colony's gate to be despawned — somebody leaving their own
camp to vanish. `accept` now attaches `needs`, `jobPriorities`, `skillWeb` and the colony faction
when they are absent, which is a no-op for every body that came before and is the moment a settler
stops being one.

**`settlement.fell` is published, and the chronicle is refused as its reader.** The reader is the
module's own retirement of the camp, which is what stops the scan finding the same empty camp on
every remaining tick. The chronicle was the obvious alternative and it is the wrong one: it is what
happened to the colony *as the screen can say it*, and a camp two hundred metres away being
overrun is not something anybody in the colony saw. A line about it would hand the player a fact
nobody has — clause 4, and the same refusal `SimStrangers._give_up` already makes over a stranger
who walks away. What tells you the camp fell is walking out there.

**The FAST tier cannot see this slice, so the measurement moved to daylight.** The tier jumps to
`Clock.DAY_ENDS` and runs 2,000 ticks, which is entirely dusk — and at dusk a settler is home and
standing, so every column on every seed came back byte-identical before and after. That is a fact
about the tier and not a null result, and rather than report it as one the same driver was run at
the armour tier's working-day fraction: the two campless seeds stay identical, and on the two with
a camp two more bodies die and thirty to fifty more grabs happen, with `survivors_end` unchanged on
every seed and each camp losing one of its three over ten days. The over-cap invariant did not
trip (peaks of 24 and 22 against a cap of 32), but **the gap behind it was exercised for the third
slice running**: the settler lost on seed 31337 was diagnosed rather than assumed — no identity, no
allegiance, no corpse, which is `_turn_with_kit`'s signature — so a bitten settler died, turned,
and became a zombie the director never placed and cannot refuse. Nothing reconciles that against
the budget yet, and three slices have now paid for it.

## The alpha shell, 2026-09-16

The owner asked for an audit of the game and a plan to an early alpha that a stranger can play,
with the building delegated to other models and the planning and the review kept with one. Three
code-grounded surveys (what a player can do, the health of the tree, the balance evidence) found
the same thing from three sides: **the systems are far more complete than the loop, and nobody
has ever played it.** Every playtest the docs mention is prospective; the only campaign evidence
is the FAST tier, a 64-tile, dusk-only, four-seed proxy that asserts survival rather than measures
it; the director is silent for seven of ten nights; and the game itself has one scene and no
shell — no title, no pause menu, no run-over screen, no autosave, and a `main.gd` of 2,200 lines
that owns input, boot, save and drawing together and is driven by no gate. The owner's answers
are the decisions below; the pieces are docs/23's what's-left group of the same name.

**What "early alpha" means here** is a capability list rather than a date: move and interact with
the environment and drive a car; find loot, wield a weapon and fire it; fight zombies and raiders;
make a camp and recruit; open the inventory and read the body; open the skill web. Every item
already exists in code. The alpha's work is to prove each is reachable in play, fix what blocks
it, and wrap it in a shell a stranger can use — not to add systems.

**Net first, split second.** `main.gd` is split only as far as the shell needs — input out, the
run's lifecycle out — and only after one executing gate boots `main.tscn` and drives it with
synthetic input. Drawing stays where it is, because sixteen gates read `main.gd` as text and
following sixteen needles is a slice with no player-visible payoff. The gate drives events
through the viewport (`push_input`), not by calling `_input` directly, so a moved handler is
still reached rather than left a dead socket.

**Camp keeps C; the stance ladder moves onto Ctrl.** The audit found C bound twice — the camp
arm and the walk stance both fire on every press, so standing up from a crouch started moving
home. Offered a new letter for camp, the owner kept C for the deliberate commitment and moved the
ladder: Ctrl+Z prone, Ctrl+C crouch, Ctrl+S stand, Ctrl+V jog, Shift still the sprint latch.
Ctrl+W is never bound because the browser owns it. Ctrl-modified keys leave the movement set, so
Ctrl+S does not also step back.

**The day stays four real hours.** Shortening the clock or adding a sleep-to-dawn was offered;
the owner left it for the ten-day playtest, which is the only judge of most first cuts. That
makes raiders (day 8, a fifth of nights) and the gate beats late-game content inside a session, and
the owner chose the **dev menu** as the reach: F8 gains a raider band and a stranger, behind the
same `debug.spawn` command, invisible to a player. The strangers and settlers of the
population arc reach earlier on their own (a stranger beat on day 5, a settler camp from boot),
and the walkthrough records which of the bar's items each path proves.

**The shell.** A title over the already-booted world (the smoke and the HUD gates assert a world
one frame after instantiation, so the title is a state, not a deferred boot): new run, continue
when a save exists, quit. Esc with nothing open pauses to a menu; P stays the soft pause. The
run-over screen halts the sim and speaks the chronicle's last lines. **New run boots the fixed
default town** (seed 20260805) from every screen; the random reroll goes with F2, which is
**deleted**. **Quit to title autosaves first**, as the window's close request does; autosave also
writes at each dawn, and on the web build at dawn only. A volume row, the first thing in the tree
to reach `AudioServer`. No digit anywhere on the shell.

**Three calls the shell made while it was built, 2026-09-16.** Not reversals of anything above —
answers the paragraph did not have to give, written down because each is the kind of thing a later
session would otherwise re-decide differently. **"No digit anywhere on the shell" reaches past the
shell's own panel**: the quick strip draws during ordinary play whether or not the sheet is open,
which is exactly what it is for, so over the title it was six belt slots and their key numbers
under a menu. The strip, the HUD, the corner doll and the dashboard are all peeled outside a run,
by the same transition that raises the menu. **New run from an untouched title plays the world
that is already standing**, rather than booting a second identical one — it *is* the fixed default
town, and the decision above is about which town, not about how many times it is built; one flag
tells an untouched title from one you quit back to, and from the pause menu or the run-over screen
it is a real reboot. **Escape peels by focus**, not by a chain of `elif`s that re-derives the
order: `_focus()` already names the screen in front, and the second copy of that order was wrong —
a settings sheet over an open skill web closed the web underneath it.

**The HUD keeps its prose model and takes the chrome.** Two cards in `ui/chrome.gd`'s skin, a
"you" and a "world", the arrays every `check_hud` lane reads untouched; a contextual action line
that names E, T and H only when a sim read model already says what is there — the sim decides
the verb, presentation names the key. The design is frozen from mockups with the owner before
code. The full "top rung of E" read is named as a follow-up rather than folded in, because it
splits `_use_context` under `check_vehicles`' needles.

**The HUD design, picked the same day: Option A, two cards.** Four artboards went to the owner
over a screenshot of the shipped screen — today's bare corner text, a **one-plate bar** that
gathered everything into a single strip along the bottom, a **brackets-only** treatment that kept
the corners where they are and drew nothing but chrome ticks around them, and **two cards**. The
owner took the cards. The reasoning, in the order it decided the pick: it is the **cheapest
against `check_hud`**, because the columns stay the arrays every lane already reads and the card
header is chrome rather than a line — the one-plate bar would have rebuilt `_left` and `_right`
into a single ordered list and put six green lanes through a rewrite for a layout change; it is
the **most legible over busy tiles**, since a filled panel at alpha 0.86 is the only one of the
three that gives every clause a background rather than relying on the street being dark where the
text happens to fall — the one plate showed the most map and wrapped a long sentence badly inside
a third of a bar, and brackets-only was closest to what already ships and gained the least; and
the cost, taken knowingly, is that it puts **the most chrome on the street** — two panels and a
bar where brackets-only would have put none. Geometry, shipped:
cards at the `MARGIN` (24) corners, minimum 472 wide for "you" and 496 for "outside", height
`HEADER_H + lines × LINE` plus a skirt, growing in both directions with their content; the action
bar 1296×48 centred at `view.y − MARGIN − STRIP_CLEARANCE − BAR_H`, its clauses at `FONT_SIZE − 2`
with the key in `Chrome.ACCENT`, and the key hint at `SMALL_SIZE − 2` in `Chrome.TEXT_DIM` in the
tail. The bar takes chrome's own 14 px bracket rather than the mockup's 12, because a second copy
of the bracket arithmetic in `hud.gd` is exactly the drift `ui/chrome.gd` exists to prevent. The
artboards, the canvas file and both screenshots are the record, under
`.hermes/plans/2026-09-16_alpha-hud/`.

**The desk is for any agent.** `AGENTS.md` gains a section written for whichever assistant picks
the project up — Claude, ChatGPT, Astra, Sol — with the claim mechanism being the branch name and
the routing table being the map, and no ledger, because a ledger is the drift this repo retired.

**Named for later, so no alpha slice builds across them.** Two voice pieces the owner wants after
the alpha: the player's own microphone as a noise source in single player, and proximity voice
for PvPvE with multiplayer. The seam is decided now: the sim never reads a microphone. A platform
capture measures loudness and pushes a command, the way a shout is a command, so it is recorded,
replayable and saved like every input and the parity and two-world gates are untouched.
Calibration is content; it ships off by default. docs/23's Milestone 3A and 3C carry the two
entries.

## The release package, 2026-09-17

The owner asked, with the alpha bar proved end to end, for a release on GitHub that can be
downloaded and launched like an executable. Decided: **a `Release` workflow run by hand with a
version, or by a pushed `v<version>` tag**, never on a branch push — a release is a deliberate act and CI already publishes the web build
on every green commit. **Windows first**, because that is what was asked for and what CI's
`godot-exports` job already boots on a real Windows runner; the web build rides in the same
release as a zip for anyone self-hosting. **Pre-release by default and `v0.x` versions** until
the ten-day playtest says otherwise — an early alpha should not look like a 1.0 on the releases
page. **No code signing**: the notes say SmartScreen will warn once; buying a certificate is the
owner's call, not a workflow's. **Nothing new is judged**: the workflow reuses the export smoke
the CI job runs, and a release is only ever cut from a ref CI already passed. A Linux build and a
macOS build are named in docs/23's what's-left rather than folded in — Linux is cheap and can
follow; macOS is blocked on a signing identity, which is a decision and a purchase.

## What the owner asked for after the shell, 2026-09-17

Four asks from playing the alpha shell, each answered by the owner the same day from a short
list of offers; the pieces are docs/23's "After the shell" group and land one at a time, serial
on `main.gd`.

- **Sight persists on the sim's own clock, and the cone does not widen.** The ask was *"the
  player looks away, but the image is still there for a while — at least the last known
  position — less jarring"*. The offer taken: **afterimage and remembered map, angles unchanged**
  (widening the 60° / 190° eyes was offered and refused: `daylight_eyes` is the same code the
  dead see with, so it is a balance number and would re-baseline the record). The afterimage is
  the last picture drawn of a body, frozen — flip, gear, tint as they were the frame it was last
  in focus — standing on the **sim's** remembered position (`SimSightings`), never on the body's
  live one, and it fades out over exactly `FRESH_TICKS` so the picture is gone the moment the
  HUD stops saying "a moment ago"; the mark then fades over `RECENT_TICKS`. One clock, two
  readouts: `main.gd`'s private `MEMORY_TICKS = 60` is deleted, because a presentation
  constant that disagreed with the prose's bands was the jar. A body only ever glimpsed has no
  picture to freeze and fades as the anonymous disc — the peripheral-anonymity clause survives
  by construction, not by a check. `SimSightings` now records **every body, with a kind**, and
  the two readers that meant "hostile" (`clause`, `freshest_within`) ask for hostiles by name,
  so nobody shoots at where Mara was. The remembered map is a per-observer `explored` bitset,
  merged only on the ticks a shadowcast recasts; tiles in it draw dimmed and desaturated and
  **nothing that moves is ever drawn on one** — that is docs/23's "the remembered map, dimmed"
  piece, absorbed here with the gate change it specified.
- **Bare hands are a weapon that counts as no weapon.** Offered: a weak punch; a shove that
  staggers and never damages; fists as good as a kitchen knife. Taken: **the weak punch**.
  `SimCombat.BARE_HANDS` — reach 1.0 m, weight 0.6, damage 4 (a head takes three, a torso
  fifteen), stagger 6, speed 1.3, recovery 0.8, stamina 0.7, the ordinary connect noise — is
  set on every survivor whose hands are empty and comes back the moment a weapon is unequipped,
  so `F` and the click always do something. It carries `unarmed: true`, and **`SimMelee.is_unarmed`
  is the one predicate**: the re-arm job, the balance gate's ARMED assertion and anything else
  that used to ask "is there a `meleeWeapon`" ask it instead, so a colonist with fists still
  walks to the bat on the ground and a campaign that boots a fist-only colonist is still refused.
  The numbers are first cuts and sit in HANDOFF's list.
- **The mouse reaches the sim's vocabulary, and walk-here is a command the stick cancels.**
  A right-click on the street opens the same drawn word menu the inventory sheet uses, and the
  rows come from `SimContext.verbs_at`, which asks the modules' own predicates — a row is present
  iff the sim would accept the command behind it (`work_panel.gd`'s rule; nothing greyed, nothing
  explained). Walk-here was offered as out of scope and the owner **took it**: `walk.to` puts a
  `walkTo` on the controlled body and `SimWalk` — the stepper raiders and strangers already use —
  carries it at the `move` command's own speed (`World.move_speed_of`, extracted so there is one
  copy); **any `move` command removes it**, so a key press always wins over a click, and arrival or
  no route removes it too. A click on a colonist looks at them (selection) and never orders
  them — a click that ordered a person would be the micromanagement cliff docs/23's Risk 1 is
  measuring, and the menu must not pre-empt that measurement.
- **Spoken words over a focal body are not a name plate.** Name plates are refused three times
  in this file, and this entry does not amend that: a bubble carries **what a body just said**,
  authored per trigger in `content/speech/`, never who they are, never a number, never anything
  the hardcore contract hides (no line says "I'm bitten"). It draws only over a body drawn at
  Focal this frame and over the player — a glimpsed body gets no bubble, exactly as it gets no
  facing — and it is sim state (`saying`, with a horizon), so a save carries it and a gate can
  ask. Zombies get sound-words on the edge into pursuit and on the screamer's alarm, which reveal
  nothing the noise itself did not; colonists mutter the band `needs.hud_clause` already speaks,
  on a rolled, rate-limited clock (`MUTTER_EVERY`, `MUTTER_P`, first cuts in HANDOFF), so a
  bubble is flavour and never a status readout.

## The outpost pack, adopted, 2026-09-17

The owner asked for the hand-made outpost asset pack (`godot/art/simplyzombies/`, its own
`README.md`, `STYLE.md` and `manifest.json`) to be incorporated into the live renderer, **and to
overwrite the generated art it replaces** — the reverse of "Art we did not generate"
(2026-09-09), which chose commissioned-to-spec over a bought pack. Four questions came with it,
and the owner answered each from a short list of offers the same day.

1. **Bodies are four-directional, with the walk cycle.** The pack's survivor and shambler ship
   four idle views and a four-frame walk each way, not a rotating torso. This **supersedes**
   decisions 1, 3 and 4 of "The decoupled paperdoll" (2026-09-11) — full 360° torso rotation, the
   head seen from above, and per-slot canvases with normalized pivots — none of which a
   four-direction sprite set has any use for. **Decisions 7 and 8 stay open**: aim as a second
   heading, priced at a walk, and the sim reading a muzzle socket, are unaffected by how a body is
   drawn and remain undecided pieces in their own right (docs/23's what's left).
2. **Every human draws on the pack survivor body; the screamer and the bloater keep their
   generated rigs.** The pack ships one survivor and one shambler, and every human in the game —
   the player, Mara, Ellis, the colonist template, the raider — moves onto the one pack survivor
   body, differentiated by wearables and tint the way the generated eight already are; the
   shambler zombie kind moves onto the pack's shambler the same way. The screamer and the bloater
   are not in the pack, so of the generated tier's eight rigs only those two survive as generated
   art, and nothing about either changes. A colony of identical pack survivors is the shipped
   shape until the pack (or a fixture round) grows more human bodies, not a bug in this decision.
3. **Walls are y-sorted modules, standing on the run's south edge.** This **supersedes** "walls
   gain thickness ... draws inside its own footprint" (the Dungeon Settlers look, 2026-09-03) and
   **absorbs** "the wall face hangs south" (docs/23's what's left, added 2026-09-08): the pack has
   no per-tile thick-mass wall to draw inside a footprint, only wall/fence/door/window pieces
   meant to stand on a run's edge and sort against the bodies crossing it, which is what the
   south-face amendment was already asking for. One rule replaces two.
4. **Sockets now for effects, east-west vehicles and the non-status cursor icons; report-only for
   the rest.** Held weapons, utilities, decals, and the pack's six status icons (health, hunger,
   thirst, stamina, temperature, wound) get no socket in this arc — the six status icons **stay
   refused**, under the icon-row ban the HUD's prose already stands on, not merely deferred. The
   crosshair and the interaction hand are not status and get a piece (docs/23's "The cursor").
   Held weapons, utilities and decals are named in docs/23's "The needs-assets report" piece
   rather than decided here, because none of the four questions this entry answers reached them.

**This amends "Art we did not generate" (2026-09-09), rather than reversing it.** That entry's
whole premise was that commissioned art meets the project's geometry because it was drawn to it;
the outpost pack was drawn for this project too and independently **meets the same published
numbers**: height 28, soles on row 39, shoulders 20 on row 25, head 12 on row 18 (measured off
`textures/characters/survivor_s.png`, a 32×48 canvas) — the identical figures `check_authored.gd`
already holds `player_body` to. So it **is** commissioned art in that entry's sense, and its
geometry stays gated the same way. What does not carry over is the **colour** half of the spec:
the `#161614` outline, the twenty-colour cap and the generator's highlight-share ceiling are
properties of the four-tone assembler in `tools/sprites/`, and the pack was never drawn against
them — it reads by its own near-black (but anti-aliased, not flat `#161614`) outline and 130–240
opaque colours a figure. `check_authored.gd`'s TONES and HIGHLIGHT lanes stay scoped to
`kind == "rig"`, never to a pack body's `kind`, which is the mechanical form of "geometry gated,
colour not" — a later slice that judges a pack rig's geometry adds it there without adding it to
either colour lane.

**This amends the Dungeon Settlers look's tree rule.** "A tree is ... one tile wide" (2026-09-03)
was a rule about *canopies*, chosen because a canopy wider than its trunk would hide a body east
or west of it with no depth rule to answer that. The pack's nature sprites are not all one tile
wide, and the rule that already answers a hidden body — "the tree fades, never the body" (the
same entry, the very next clause) — answers this case too: a canopy may now be wider than its
trunk tile, because whatever it would hide fades through it rather than behind it. The opaque,
solid `Tree` tile and the feet-anchored, y-sorted trunk are unchanged.

**Named for a later slice, not decided here:** the three shipped car footprints — sedan 2×5, van
2×6, truck 2×7 (the main-area entry above) — will shrink to **sedan 2×3, van and truck 2×4** when
"The cars are the pack's, east-west" lands, because the pack's vehicle art is drawn at those
footprints. North-south driving keeps the generated art at today's footprints until that slice,
so nothing shrinks in this commit.

**What this re-affirms, named because this is the entry an artwork swap would otherwise have to
re-litigate:** the health-bar ban and the digit ban; the prose HUD; the refusal of bars, icon rows
and name plates; 32 px a tile at 2×; the flat top-down projection; `FOOT_DROP_PX` and the feet
anchor; the peripheral-anonymity clause; and `godot/sim/`'s total ignorance of any of this —
`Appearance` is the only reader of `authored.json`, and no sim module gained one.

**What this makes structural.** The authored tier gains a **reproducible** `source`: `path`
(under `godot/`), optional `crop`, optional `pad` — crop then pad, never repainted or resized,
`godot/art/simplyzombies/STYLE.md`'s own rule for its mechanical steps, applied to how this
project draws from it. `tools/sprites/build.py` can now *write* an authored key, not just check
its existence, and `--check` holds a sourced key to decoded pixels the same way it holds a
generated one — `sprites:check` re-derives the art from the pack on every run, so a hand-edited
PNG that drifted from its source is a red build, exactly as a hand-edited generated PNG always
was. A **family** (`members`, several sourced keys sharing one canvas under a key that is not
itself a file) is the shape later slices need for many pictures under one declaration — a walk
cycle's frames, a garment's four sides — and lands now, proven by fabrication in
`check_authored.gd`'s MANIFEST lane, ahead of the slice that uses it for real. The READS lane's
`reads` now accepts **any** content id that declares the key, not only the most recently loaded
one — the old comparison was last-writer-wins, a latent bug rather than a rule anyone chose, and
this closes it before a pack body shared by two content entries could trip it. **Adoption is a
deletion, applied slice by slice**: `tools/sprites/README.md`'s standing rule that hand-made art
retires the generator code that used to draw the same thing held for the two containers in this
commit (`props.py`'s crate functions were already gone, from the first authored art in 2026-09-10)
and applies again to every generated key a later slice in this arc replaces.

## The UI Field Kit, live, 2026-09-25

On 2026-09-25, with the UI Field Kit delivered and sitting unused since 2026-09-20 (docs/23's "UI
asset delivery" record entry), the owner decided to take the whole kit into the live game:
textures for the chrome, glyphs, the four OS cursors, and the four UI animations — nothing held
back for a later pass.

**The font becomes VT323** — bundled, SIL Open Font License, `OFL.txt` travels with it — with the
engine's own fallback font behind it for the glyphs VT323 does not carry (Cyrillic, most Greek).
Corrected when the slice landed: this entry first said the fallback carried → ▲ ▼ ↔, and it does
not — neither face has them, so they draw through the operating system's fallback on desktop and
as boxes on the web, exactly as before; the FONT lane names them in `FONT_NO_FACE`, and the bench
arrows move to kit glyphs with the shell's rows.

**Both outliers are reskinned.** Speech bubbles move into the kit's tooltip frame; the vehicle
dashboard's housing moves into kit frames too, its dials, lamps, letters and charge bar still
hand-drawn on top of it.

**Kit pieces that conflict with a standing decision stay unused, each named with its reason, and
the new gate lists them:** `button_disabled` and `slot_disabled`, because a verb is present or
absent on this HUD and never greyed; the three scroll pieces, because the sheet has no scrollbar;
the three tab styles, because no screen is tabbed; checkbox and radio, because the one switch
this game has uses the toggle; `glyph_lock`, because there is no lock mechanic; and
`glyph_rotate`, because the owner did not take it.

**What this supersedes:** `ui/chrome.gd`'s header comment, "Everything is drawn (no textures),"
and "The alpha shell"'s 14 px bracket on the action bar (2026-09-16, above) — the bar now takes
the kit's own frame rather than a second copy of bracket arithmetic.

**What this re-affirms**, named because a skin swap is exactly the kind of change that would
otherwise have to re-litigate it: the prose HUD; the health-bar and digit bans; no status icons —
`glyph_condition` is a header ornament only, never a status readout; no bars, no name plates, no
greyed rows; and the busy loop still never encodes progress — it does not read time left.

**Reduced motion defaults off**, a presentation preference in `ui/prefs.gd`, not a difficulty or
accessibility flag the sim reads.

**Why the runtime builds `StyleBoxTexture`s in code (`ui/kit.gd`) rather than loading the kit's
`.tres` files:** no `.import` files are committed and headless CI never imports, so every kit
`.tres` resolves null in the gates, and a `preload()` of one would stop `chrome.gd` compiling for
every gate that boots `main.tscn`. The two-path loader `presentation/appearance.gd`'s `resolve()`
already uses — `ResourceLoader` first, then `Image.load` plus `ImageTexture` — is the precedent.
The kit's `manifest.json` and its `.tres` text, read as text rather than loaded as resources, are
the spec the new gate compares the code's margins, hotspots and frame rates against.

**The kit's four OS cursors and the outpost pack's open "The cursor" slice (docs/23's what's
left) are one table, not two.** The kit supplies arrow, hand, move and blocked; the outpost
pack's crosshair and interaction-hand icons join the same `ui/cursors.gd` install rather than a
second cursor system, and that slice stays open.

**The chrome draws at 2×, and its centre tiles** — follow-up decisions the owner made the same
day, once the first slice had put the kit on screen at its native 1×. The approved mockups
(`previews/inventory-approved.png`, `previews/hud-approved.png`) read at twice the kit's native
pixels, which is also the 2× the world's 32 px tile is drawn at, so the frames looked thin
beside both; `ui/kit.gd` now scales every chrome texture 2× with nearest filtering once, at load,
and doubles every margin, while its `NINE` table keeps the manifest's native values so the gate
still compares against the manifest and the `.tres` unscaled. And the kit's `.tres` files stretch
(they set no axis mode), which across a tall panel smeared the centre's fine noise into soft
blotches and vertical streaks, so the built styles tile the centre on both axes. **The edges are
decided per style** — a third decision the same day, made from 3× crops of both modes. One
`StyleBoxTexture`'s axis modes cover its edge strips as well as its centre, and neither mode suits
every frame: tiled edges repeated a fragment of every corner bracket along the border as a row of
tick marks, and stretched edges lengthened a dashed line's dashes and every bracket arm lying in
them. So the dashed and noisy frames — `slot_empty`, the six panels and the divider — tile their
edges (`Kit.EDGE_TILED`), and the bracketed ones — the buttons, the other slots and the keycap —
stretch theirs as the `.tres` means. **Where a corner piece runs past the kit's margins, the
margins widen** — the buttons' and slots' brackets first, then, by a fourth decision the same day,
the panels' corner highlights, which the tiled edges had repeated as a small tick down the pause
dialog's rim. Each such style draws at margins widened just enough that its whole corner piece sits
in the corner, where a nine-slice draws it 1:1 (`Kit.WIDENED_MARGINS`, measured from the pixels);
`panel_danger`'s red rim wobbles and breaks along its whole length, so its margins are set by eye
(a top margin one wider, holding the amber fleck at the top of its right rim). Every departure from
the kit's own files is named in the gate — `OWNER_SCALE`, `CENTRE_MODE_DEVIATION`,
`EDGE_DEVIATION`, `MARGIN_DEVIATION` and `MARGINS_BY_EYE` in `check_ui_skin.gd` — rather than left
for a later reader to take for drift. One style is held
back from the 2×: the keycap, which sits inline in a line of text, where the HUD mockup draws it
with a hairline amber rim that 2× would double around a single letter; it is named in
`Kit.NATIVE_STYLES`. Glyphs draw at their native size (`Kit.GLYPH_SCALE` 1): a 2× glyph is taller
than the 16–20 px line it labels.

## The whole outpost pack, 2026-09-25

The owner asked on 2026-09-25 for "the whole outpost pack" to be used in the game, and answered
the questions that ask raised the same day. This entry extends "The outpost pack, adopted"
(2026-09-17, above) rather than replacing it: its four decisions stand, and the arc is still the
slices docs/23's outpost group names, landing one at a time with their gates.

**Decision 4's report-only half is reopened for four families.** The pack's twelve held weapons
(drawn in the hand of a four-direction body, below); the furnishing props, as scenery that never
touches balance and never becomes sim state, and the container kinds keyed by loot table; the
nature extras — bush and reeds on outdoor tiles, rock, stump and log as dressing; and the pack's
art for things the game already has (the barricade, the work lamp, the stove). Each becomes a
named piece in docs/23's outpost group before it is built. **What stays in the report**, because
drawing it honestly needs a sim fact that does not exist: the decals (a blood pool, a footprint, a
bullet hole or a scorch is a thing the sim would have to record first), the effects with no impact
point (sparks, dust, splinters, splash, explosion), and anything that would be a new mechanic
(generator, rain collector, spike trap). **The six status icons stay refused**, under the same
icon-row ban the prose HUD stands on — "the whole pack" does not quietly amend a standing ban, and
the owner was asked and did not reopen it.

**The ground takes the pack's own grade.** The pack's tiles are brighter and more saturated than
the warm-dark table (grass, dirt, water and wood all past the 0.30 ground-saturation cap
`check_road_look`'s PALETTE lane holds), so either the lanes move or the art is repainted at draw
time. The owner chose the pack: the ground lanes are re-pinned to a measured pack table, the old
warm-dark table becomes the case they refuse, and the slice lands with a before/after screenshot
pair. This supersedes docs/23's open "The grade: overcast day, warm night" as far as the ground is
concerned and folds in HANDOFF's water-saturation item.

**A four-direction body wears the pack's gear only.** The 47 generated equipment overlays are
drawn face-on and cannot fit a body that turns. The pack's four-direction vest, helmet, gas mask
and backpack are worn; held weapons draw at a hand point per view; every other clothing overlay is
retired until four-sided art exists. The owner accepted the named gap that follows: an equipped
jacket shows nothing on the body until then — the inventory and inspect text still say it is worn,
so nothing the player needs is lost, only a picture.

**Raiders share one tint.** With one shared pack rig a raider would be indistinguishable from the
player's own people at focal range. One raider tint, the same for every raider, makes a raider
read as a raider without telling the two archetypes apart, which `check_m2_raiders`' NO-TELL lane
requires.

**The walls get a picture round first.** The pack has no north-south run, no south-west or
south-east corner, no timber or block material and no east-west door or window. One closed
building is rendered two ways — the corner piece's leg cropped for north-south runs against
today's generated faces — and the owner picks from the screenshots before the walls slice lands.
Timber and block keep their generated faces either way.

**Cursors split by place.** Over the world while playing: the pack's crosshair, and the pack's
interaction hand over something the player can see and act on — never over something unseen,
which would be information through a wall. Over any panel or menu: the UI kit's four pointers.
Both live in `ui/cursors.gd`'s one table, as "The UI Field Kit, live" already said.

## Zombies turn, walk and fall, 2026-10-02

The owner asked to work on zombie and corpse poses, make several zombie variations, ensure the
zombies animate, use the work in the game, and merge it into GitHub. This completes the existing
"A silhouette per kind" and Focal corpse-art pieces; it does not widen what a peripheral glimpse
reveals.

The first set supplies workwear, commuter and raincoat common zombies, plus stalker, runner,
armoured and heavy silhouettes. Each has four directional idle poses and a four-frame walk cycle
in each direction. Existing velocity and the simulation tick choose and advance the frames;
full entity ids select cosmetic variants and matching corpses without a new random stream.
The heavy gets a 40×48 picture and matching picking bounds. Human corpses share four ground
poses; every zombie family gets two. Corpse pictures lie below standing actors and omit upright
gear and facing marks. A dead human's actual inventory remains unchanged.
Settled art does not replace the living afterimage cache or change the simulation's sight memory;
otherwise a newly seen corpse could be painted at the zombie's older remembered living position.

Zombie death still drops its kit and despawns the actor. A saved cosmetic history of the most
recent 256 deaths retains the original id, position, type, tint and tick for rendering; it adds
no scent, collision, loot or population. Save v33 accepts this optional history and loads old
saves with it empty. The armoured art uses a bare head and unarmoured shirt, with the actual
helmet and vest composed by the existing equipment renderer, so armour appears once and comes
off when the items drop.

This pass supplies locomotion and settled corpses, not attack, hit, falling, rising, animated
idle or crawler-specific poses. Screamer and bloater art remains outside the set. Original
sources and generation instructions are preserved beside the reproducible native exports;
`godot:check:zombie_art`, authored geometry and sprite reproduction judge their game readers.

## Wall picture mapping, 2026-10-03

The owner chose **A2, shape-matched pack corners**, from the closed-building comparison in
`.hermes/plans/2026-09-27_walls-picture-round/`. The existing generated timber and block faces
and the current unseen-wall roof coverage stay as they are. The bounded implementation covers
supported rectangular brick and plaster perimeters, with generated fallbacks; its gates and
runtime captures are recorded in docs/23. The mapping is not a decision to extend roofs over
unseen perimeter walls.

## The whole interface, 2026-10-03

After asking for the CI repair and parallel follow-ups to be merged to main, the owner asked
for an overhaul of **all UI**, including the paperdoll: modern, bespoke, good-looking and
comfortable to manage, while retaining hardcore play. They requested a plan and an opportunity
to shape it before proceeding through the overhaul.

Their reference choice was **"Tarkov detail + Project Zomboid practicality, with cleaner
management"**. They then clarified that Project Zomboid is the main practical reference,
Tarkov and Zero Sievert supply hardcore/tactical character, and the result must mesh with
the existing **Dungeon Settlers** art direction.

For the paperdoll they explicitly chose **"A stylized anatomical diagram with equipment
arranged around it"**. A dressed portrait or live 3D avatar is not the selected direction.
The diagram can be reauthored while preserving the ten existing semantic body regions and
the truthful condition read model. Equipment around the figure must represent the actual
twelve slots, not only those shown by an illustrative mockup.

This opens replacement of the old UI Field Kit's visual treatment, compulsory VT323 type,
fixed panel composition and D2 chart proportions. Earlier visual decisions remain history
and the current implementation baseline; they are not a requirement to preserve the look
the owner has now asked to replace. The Dungeon Settlers world direction, scarce-information
contract, health-bar ban, simulation authority and existing legal actions remain in force.

The precise palette, typography, responsive composition and grid-plus-fast-list proposal
are **recommendations**, not additional owner decisions. The generated anatomical concept
is illustrative and has not been accepted as a final layout. No pause-policy or inventory
capacity change was requested. [The design brief](32-ui-overhaul.md) develops the proposal;
[the roadmap](23-roadmap.md#ui-overhaul) alone carries implementation order and status.

## The alpha calls, 2026-10-19

The owner answered the alpha plan's design questions on 2026-10-19. Each answer is recorded here, and the
work it sets is in [what's left](23-roadmap.md#whats-left-in-milestone-2).

**Colony scope for the alpha: colonist orders and the NPCs that already exist, nothing more.** Asked how
much RimWorld the alpha carries, the owner said: "For now maybe colonist orders and just the fact that there
are NPCs. very basic." Blueprints, stockpile zones and bench crafting are parked until after the alpha, and
farming stays out. **How to apply:** a colony feature that is neither an order nor a colonist already in the
sim waits.

**The in-game day is one real hour at 1x.** The owner answered "mimic Project Zomboid for this." It is a
balance change: every per-day rate is rescaled with it. It is not built. Until it is, a day is four hours at
1x (`godot/sim/time/clock.gd`). **How to apply:** the first piece of work on the clock is a re-baseline,
measured with `godot:m2:balance` before and after.

**Aim is cursor-driven, and the body follows.** The cursor is the aimer. The weapon is held toward it and the
character turns to follow, as in Project Zomboid. This is the owner's answer to the aiming question, and it
replaces the plan's four-view-body default. It is not built.

**Blood and bullet decals persist, for everything, and follow the normal visibility rules.** Every bleed, hit and shot leaves a decal, whether or not the player saw it happen. Decals are drawn under the same visibility and fog rules as any other world detail, so none shows through a wall. This is the owner's "everything" read with the scarce-information rule (CLAUDE.md, standing bans) kept intact. The orchestrator set this reading on 2026-10-19, and the decision card was closed on it.

**The inventory keeps the grid and gets a full bespoke redesign.** The owner likes the grid, finds it plain
and close to a Tarkov-style layout, and asked for a redesign that looks unique and bespoke. The work belongs
to the UI overhaul group (docs/32, which lands with the UI overhaul PR). Whether a list view sits beside the grid is not
decided.

**HANDOFF.md and AGENTS.md are retired.** The owner asked for one file. The owner-decision list moved to [docs/33-owner-decisions.md](33-owner-decisions.md), so CLAUDE.md stays short. The routing table stays in CLAUDE.md, and `scripts/check-routing.mjs` reads it there. Old "HANDOFF item N" citations keep their numbers.

**Gates per commit: the touched gates locally, the full chain in CI.** The owner left this to the
orchestrator ("whatever you think is best"), and the orchestrator chose it. CI's `godot-m2` job already runs
the full chain on every pull request and every push to main, so no workflow was added. CLAUDE.md's Verifying
section states the policy. A change to a shared sim module or the save format still runs the full chain
locally before its commit.
## The inventory's look, 2026-10-20

Asked on 2026-10-19 (the alpha plan's Q5) about the inventory, the owner kept the grid -- "I
like how it's very much like Tarkov" -- and said it "looks very plain" and has to look "super
awesome and like unique, bespoke even". The grid-plus-fast-list proposal above was accepted
in the same answer: a list beside the grid, with the grid still the authority on capacity.

Three directions were drawn at 1920×1080 with the repository's own item icons (canvas
webbing, a salvage locker, a hard case). On 2026-10-20 the owner picked **B, the Salvage
Locker**, on a decision card: brushed steel, rivets, masking-tape labels, recessed cells and
plates tinted by item class, at the world's 2× pixel density. The mockups are under
`.hermes/plans/2026-10-19_inventory-redesign/`.

This settles the inventory's surfaces only. Typography, the anatomical diagram and the rest of
the interface remain the recommendations "The whole interface" describes; VT323 is still the
baseline face, not a renewed decision. The health-bar ban, the digit ban and the scarce-
information contract are unchanged.
## The one-hour day, 2026-10-19

The owner answered the alpha plan's Q2 with the Project Zomboid option: one in-game day is one real
hour, not four. `SimClock.DAY_SECONDS` is 3600, so `DAY_TICKS` is 72,000 (was 288,000). Dawn and
dusk are 7.5 minutes each, the day is 30 minutes, the night 15.

Every value that depends on the day falls into one of three groups. The question for each is what
it is measured against.

1. **Calendar** (the story's clock): the director's beats, the day-8 recruit, raid nights and lulls,
   the strangers' three-day deadline, roster waves, skills' daily drift, the night's length
   (`0.25 * DAY_TICKS`), and the seasons (`seasonDays` 5). These follow `DAY_TICKS` and compress:
   day 8 is eight real hours away, not thirty-two.
2. **Body and world pressure, written in days**: multiplied by four, so the pressure per real minute
   is what it was on the four-hour day. Hunger empties in 8 days (was 2), thirst in 4 (was 1), rest
   drains over 3 (was 0.75 of a day), relief in 2 (was 0.5). Starvation kills after 4 days (was 1),
   dehydration after 1 (was 0.25). Raw food spoils in 8 days (was 2), cooked in 4 (was 1); the 48
   `spoilDays` in `content/items/kitchen.json` and `supplies.json` were multiplied, zero stays zero.
   Wound recovery: scratch 8 (was 2), laceration 24 (was 6), deep wound 64 (was 16); per kind,
   fracture 168 (was 42), sprain 20 (was 5), burn and frostbite 56 (was 14), heatstroke 28 (was 7),
   concussion 24 (was 6). Wind re-rolls every 4 days (was 1), in `climate/temperate.json` and the
   `weather.gd` default. A corpse's scent ages after 4 days (was 1), `recruits.gd` `CORPSE_OLD_TICKS`.
3. **Night-relative literal ticks**: the exposure clock that turns a cold night into a deep band
   (`EXPOSURE_TICKS`, 18000 to 4500, and the frostbite, cold, heatstroke and heat death doses that
   are multiples of it), the campfire's burn (36000 to 9000, "half a night"), and every lamp, candle
   and torch `burnTicks` (divided by four). The shipped burn times are judged against the night
   (`check_m2_light_burn.gd`), so they move with it: a full lamp still lasts the same number of nights.
   Left unchanged, these would make a clear night's cold unreachable: the cold clock clears at dawn,
   and a night is now 15 real minutes.

Left as literal real-time ticks, not scaled: weather spell lengths (clear, rain, storm, snow, cold
snap, heat wave, in `weather.gd` and `content/weather/*.json`), noise `durationTicks` and `delayTicks`,
comfort `ticks`, the noisemaker's 12000, the wet body's `dryAfterTicks` and `dryByFireTicks`, the
sedan's range, the goodwill from a meal (36,000), grief and argument decay, and the infection timers
(latent, onset, progression and critical, 60 to 72 real hours from bite to turn; the owner moved
these onto in-game hours on 2026-10-21, see "A bite turns in days" below). These keep their
real-minute length, so in in-game days they stretch four times: a cold snap is 4 to 12 days, not 1
to 3, and a bite takes 60 to 72 days to turn, not 15 to 18.

Judgement the owner may want to reverse: the weather spells and infection are real time, so their
in-game length grew four times. Dividing them by four would restore their in-game length and make
them four times as fast per real minute.

Gates changed to the new values: `check_m2_needs.gd` (raw spoil 8 days, the pantry clock now
computed rather than the literal 576), `check_m2_weather.gd` (its walks are sized in the four-hour
day's ticks, since spells are real time), `check_weather.gd` (its `DAY_TICKS` probe reads
`SimClock`), `check_m2_balance.gd` (comments). Parity (`godot:test`) is untouched because the
walking skeleton does not read the clock.

## Livable time, 2026-10-19

Alpha plan A5, on the one-hour day. The clock's state is in words on the HUD: "paused", "normal
speed", "fast", "asleep, fast-forwarding", "asleep, zombie near, normal speed". Digits stay off the
player HUD (`check_hud`), so the step is named, not counted. The speed ladder is 1x and 3x. 10x is
out until the sim tick is under budget (plan A3); `SimFortify.speed_after_events` still drops a 10x
run on an alarm for when it returns. While the player sleeps with no living zombie within ten
metres, the loop runs at 3x. A grab, a hit or an alarm wakes the sleeper through the sim, and the
step returns to the user's own. The stop is the living zombie within ten metres (`THREAT_METRES`,
docs/02's contact distance), which is checked before the sim's own wake. The plan's "every colonist
asleep" clause is not built: only the player's sleep counts.

Gate: `godot:check:play`, lane CLOCK (`_the_clock_says_its_speed_and_sleep_skips`). It counts ticks
per frame at each step, asleep and near a zombie, and a dead zombie does not stop the sleep.

## The idle breath, kept, 2026-10-20

**Decided by the owner**, on a decision card from the A7 thread: standing bodies breathe. The
question had been on the owner's list since the 2026-09-09 fixture round, where one pixel of
pelvis at a quarter of the walk's rate was drawn and deliberately left out of that day's answers.
A7 built it as the alpha plan's default before the answer came, so the call is the one that
shipped: a second idle picture per view, one pixel of chest raised for the survivor and lowered
for the dead (a sag, which also keeps the rest views already at their canvas's tallest inside
it), at one picture a second on presentation time, staggered by id so a crowd does not breathe
as one. It is data, not code: `breath_fps` per family in `godot/assets/sprites/authored.json`,
where `0` holds the rest view. The zombie breath is a mechanical row shift of the pack's pixels,
like the zombie walk in-betweens, and goes with them when the action-animations work redraws
those frames. Recorded in docs/23's A7 record; gated by `godot:check:zombie_art` MOTION and
`godot:check:authored`.

## A bite turns in days, 2026-10-21

**Decided by the owner**, on a decision card from the A24 balance thread ("Bite in days"): the
infection timers run on in-game hours, so a bite turns in about 2.5 in-game days (latent 12 hours,
onset 12 to 24, progression 24, critical 12), as docs/06's timeline says, and hunger and thirst
stay as the one-hour day set them (hunger empty in 8 in-game days, thirst in 4). This reverses the
"infection is real time" half of the judgement in "The one-hour day" above: left on real time, a
bite took 60 to 72 in-game days to turn, so none could turn inside a ten-day run, which the
playtest driver found on its first pilot. The weather spells and noise stay on real time. The
change is `godot/sim/modules/infection.gd`'s `HOUR_TICKS`, built before the answer as the card's
default and kept; gated by `godot:m2:lethality`, `godot:m2:stats`, `godot:m2:treatment`,
`godot:m2:medicine`, `godot:check:respond` and `godot:m2:filter`.

## Building noise, and kneeling near a zombie, 2026-10-21

**Engineering calls, taken in the building-noise pass** (the coordinator's tuning ruling: numbers
are the coordinator's, a new mechanic is the owner's). Neither is a new mechanic; both move a
number an existing rule already had.

- **Construction is 15, not 30** (`SimFortify.CONSTRUCT_NOISE`, docs/03's table). At 30 the
  colony's own Construct work drew 7 zombies to within 15 m of the annex by tick 12,000 on seed
  31337, against 1 with Construct off. At 15 it draws 2. A build still carries down the street; it
  no longer carries across the district.
- **Self-aid waits until no zombie is within `RELEASE_METRES`** (treatment rule R10, which read
  `SWIPE_METRES`). The claw's reach let a colonist who had just broken free kneel 1.5 to 2 m from
  a zombie that was still chasing them. They were re-grabbed within a dozen ticks, and each
  break-away pushed them further from home: sixty cycles on seed 31337, dead 60 tiles out. The
  rule's own point ("fight or run first, kneel when clear") now means clear of a pursuer, not
  clear of a claw. A held survivor still presses (R1), so the press a re-grab interrupts re-opens
  under the hold. `godot:m2:contact`'s FLIGHT-CANCELS-PRESS was rewritten to say so.
- **The 6 m break-off covers a colonist with no errand too** (`SimJobs._exposed_idle`, taken in
  the follow-up PR). The A24 rule sent a colonist home from a zombie only while they were out on
  Haul, Scavenge, Water, Bury, Dress, Rearm or Doctor, so one standing idle outside the annex, or
  walking to a need, waited for the grab. The same radius and the same walk home now apply to
  anyone outside home's walls except a guard, a colonist under the player's order, or one part way
  through a channel. This widens who an existing rule reads, not what it does, so it is an
  engineering call and not a new mechanic. Its two companions keep the walk home from being
  undone: a need that can wait no longer ends it, and a wash with nothing to wash in no longer
  claims the tick.

## Water at the well, 2026-10-21

**The owner's water question, answered by the card's default.** docs/33 asked where a colony's
water comes from over ten days, with three levers: a starting empty bottle per colonist, a
player's verb at the well, or more water in the loot. The ten-day runs after the building-noise and
idle-colonist PRs put it on the critical path: on seeds 31337 and 404 the colony was down to one
survivor, the scripted player's successor, by day 3, whose thirst reached 0 by the end of day 5
with nothing to drink carried or stocked, and both died on day 6. The colony's Water job could not
help them (colony job rules skip the controlled survivor), and loot water only moves the same death
later. The coordinator ruled the well verb the smallest build that reaches the survivor who is
dying, put it to the owner on a card with that default, and had it built as the default.

- **E at a water source** (`SimNeeds.well_offer`, `use_well`, the `well` rung of
  `SimFortify.rung_of`): drink while a full drink still fits, then fill a carried empty bottle;
  a top-up with no bottle to fill is still a drink while at least half of it lands, and past that
  the well offers nothing. Drink your fill, then fill your bottles. The half-drink floor ends a
  visit: the first build offered a drink to anyone short of full, and the playtest survivor stood
  at the well pressing E 29,544 times, each press rolling the illness.
- **Raw water is the untreated bottle's own `drink` block** (thirst 50, illness 0.15): a mouthful
  at the well quenches and sickens exactly as a bottle filled there does, so neither door is the
  cheaper one. Nothing is spent from the pack.
- **The river's bank sources are the same verb**, named "the river" on the bar where the source
  stands on the water surface.
- **The scripted survivor** (`godot/playtest/ten_day.gd`) walks to the nearest source and presses E
  when nothing drinkable is carried or stocked, the way a player would.

Gated by `godot:m2:needs` WELL through the real `use.context` command on a booted district's well,
with the right-click menu (`SimContext.verbs_at`) asserted to carry the same row.

## Every colonist starts with a bottle, 2026-10-22

**The owner's pick on the water card.** The card asked how a lone survivor gets water once the
loose drinks run out, with three options: drink at the well (the default, built as #180), every
colonist starting with an empty bottle, or more water in the loot. On 2026-10-22 the owner tapped
the second. It is built on top of the well, not instead of it, because a bottle is only water once
somebody fills it at the well; the card's wording ("tap another option to switch") is read as
"add this", since taking the well verb away again would put the survivor the well reached back on
a day-6 death of thirst.

- **The player, Mara and Ellis each boot carrying one `item.water.bottle.empty`.** The uniques
  carry it in their content `kit` (`godot/content/survivors/uniques/`); the player has no content
  kit, so `SimBoot.playable` hands it over beside the annex knife. A recruit who joins later brings
  only their own backstory kit.
- **What reads it:** a colonist's Water job (`SimJobs._water_work`) takes the carried bottle to
  the well and stocks the pile with it, and the player at the well is offered the fill
  (`SimNeeds.well_offer`).
- **Not built:** more water in the loot, a well inside the annex wall, a rain barrel at home.

Gated by `godot:m2:needs` BOTTLE: three colonists, one bottle each, both readers offered it, and
both offers gone once every empty is taken away; the lane was run red against main first.

## The playbook, and AGENTS.md as a pointer, 2026-10-23

**The owner asked for a playbook "for ALL other agents to access and know what's going on".**
The 2026-10-19 alpha calls retired `AGENTS.md` because the owner wanted one file, and two status
files had drifted apart. This request is read as keeping that rule for the repository's rules
while giving the project around it a home:

- **`CLAUDE.md` stays the one place the repository's rules live,** with the routing table that
  `check:routing` judges, the standing bans, and the no-model-names rule.
- **docs/38, the playbook, holds how the project runs.** That covers who decides what, how a pull
  request reaches `main`, the merge and branch rules, the shared folder, the art review, and
  which owner calls are open. Until now these lived only in the project chat and project memory,
  out of reach of an agent that starts from the repository. The playbook links to docs/23,
  docs/30, docs/33, docs/34, docs/35 and docs/37 rather than copying them, and carries no commit
  hash and no status list.
- **`AGENTS.md` returns as a pointer only.** Codex, Cursor and other tools look for that file
  name, so it exists, and it says to read `CLAUDE.md` and then the playbook. It carries no rules
  and no status, which is what made the old one drift. No gate holds it to that; the discipline
  is the convention. If it ever gains a rule, move the rule into `CLAUDE.md`.
- **Model routing is described by role, not by name.** The owner assigns models by role
  (coordinator, working threads, planning, irreversible steps and art). The names stay out of
  the repository under the rule that nothing pushed names a model. They live in the project's
  memory and the owner's own project-chat instruction.

**How to apply:** a fact about the build goes in the doc that owns it (docs/23 for status, docs/30
for a call, docs/33 for an open owner question). A fact about how the project works goes in
docs/38. Neither file is copied into the other.

## The Colony screen, 2026-10-23

**UI overhaul, slice 2: the second bullet of docs/23's UI overhaul group, read against docs/32's
roster row** ("persistent identity, readable job groups, explicit priority controls and Focus
choices; details open from the selected person") **and its call for "truthful current
activity".** No owner card was needed: each call below is either in the brief or an engineering
reading of it.

- **The job columns stand in four groups:** care (patient, doctor, rest), home (cook, water,
  clean), build (construct, repair, haul) and field (scavenge, guard, bury). The order is display
  only, and that is truthful because `SimJobs._pick` breaks a priority tie by the job's name,
  never by column position. A column with a consumer that no group names still shows, in a last
  "other" group, so a job added to the sim cannot be hidden by the table.
- **The six job columns nothing does are named in the footer** ("not yet anyone's work") rather
  than only hidden, so the grid neither promises them nor looks like it is hiding work.
- **Each row says what that colonist is doing now,** from a new read model, `godot/sim/work_read.gd`.
  It says what the sim is acting on (the job's kind, the need a Seek walks for, an order, sleep, a
  grab, a crisis, a sulk) and nothing else: no destination, no duration, no count, no digit. It
  shows for a colonist out of sight. These are the player's own people, and knowing that Mara is
  out scavenging tells the player nothing about where she is or what is near her, so clause 4 of
  the hardcore contract is not touched. Two lines would tell what is near her, so neither is said
  out of sight: a grab reads "held by the dead", and the walk home that a zombie within reach
  starts reads "heading home" ("staying in" once she is home and waiting it out), only while the
  player sees her. Out of sight the line stays what the colony would believe: the job under the
  grab, or the errand the walk home broke off, which the Retreat job keeps as `was` for this line
  alone. Every phrase is eighteen characters or fewer, so it fits the row whole at 1280x720. The
  haul order's line does not name the item, because an item's name may carry a digit under the
  cartridge amendment.
- **Focus is six chips you press,** not a word you click round a cycle. The line under them says
  what the pointed-at Focus puts first, read off `SimJobs.preset` so it cannot drift from the sim.
  With no chip pointed at, it describes the colonist's own Focus by that preset only when their
  row is that preset; an authored or hand-edited row is called "a row of their own".
- **A right click counts a priority down** (never, 4, 3, 2, 1, never), the reverse of the left
  click's walk. Before, a right click on a cell did nothing.
- **A row is two lines** (name with its Focus stamp, then the "now" line). Who they are moved to
  the drawer, where the whole clause is wrapped instead of cut with an ellipsis at the row's
  width.
- **Picking a colonist on Colony picks them for the game,** the same selection a click on their
  body in the street makes, so the HUD and Skills follow; "their skills" opens Skills on them,
  stamped viewing. The screen opens on whoever the game has picked, and on nobody when that is
  the player (it used to pick its first row without telling the game). The bar over Colony still
  says "everyone": the screen is the colony's, the drawer names the one picked, and Skills puts
  that name on the bar.
- **The drawer holds still.** Each of its blocks (the Focus line, who they are, what they know)
  is as tall as the most any colonist on the roster needs, so picking another colonist or pointing
  at a chip never moves what is under it. With Ellis on the roster that is three lines for who
  he is at 1920 and 1280.
- **Amber means one thing:** the picked person's brackets, the Focus in force on the drawer's
  chips, and a skill you can click to learn. A row's Focus stamp is never amber, manual included;
  the word says it. "Never" in a cell is the dim ink, not the faint one, which was under 3:1 on a
  well.
- **A long roster scrolls, and says so.** Under the last row drawn, a strip counts the rows
  scrolled away each way ("4 more below · wheel"); it is not there when every row is drawn. A
  colonist picked in the street past the fold scrolls the roster to their row, so the drawer never
  names somebody with no row bracketed.
- **Colony and Skills hang from one line,** 16 px under the bar, so switching between them does
  not move the top edge; the web stays centred across.
- **Every line on the screen is VT323 at 25,** its pixel-exact size, with two exceptions: the
  column heads would take the ladder's 20 where twelve heads at 25 do not fit the window, which
  does not happen at 1280x720 or 1920x1080 (both draw them at 25), and the legend on the tape row
  is the locker header's note size, 20.
- **The web's region fans break for their words.** Its 2 px rim stops an art pixel short of a
  region word or "start" rather than running through "endurance" and "survival".

## Builders break off from a zombie, 2026-10-23

**The coordinator's tuning call, JT informed.** Trace 99 (ace75bb1, seed 99) showed the early wipe:
colonist 113 stayed on Construct at the annex wall with one to three zombies one to three metres
off, and died on the job. Construct was not in `SimJobs.DANGER_KINDS`, so the break-off that sends
Haul, Scavenge and Water home never fired for a builder.

The first try, adding Construct to that list alone, did nothing. The annex lot (`annex_rect`)
includes a two-tile yard of floor round the house, and a window is boarded from that yard, so
`_outside_in_danger` counted every builder as home. A real tick with a zombie at 3 m stayed on
Construct.

The call that stands:

- **For Construct, outside means outside the house walls.** `SimJobs._inside_walls` takes the box
  the lot's walls, windows and doors draw and tests the builder's tile against it. The yard is
  outside that box, so a builder boarding from the yard with a zombie within `DANGER_METRES` walks
  home. A builder inside the house keeps building.
- **Every other kind keeps the lot as home,** yard included. Haul and Scavenge at the yard are
  judged as they were.
- **No window is refused for a zombie near it.** A first version refused any window with a zombie
  within `DANGER_TARGET_METRES` (10 m), as a Haul item is refused. It broke `godot:m2:needs`: a
  builder boarding from inside the house with a zombie outside the window left the job for a bed,
  rested beside the zombies in the room and died. Boarding from inside is safe; only the walk out
  is not, and the rule above covers that. The cost: a builder walks back out to a window after
  each Retreat hold (`RETREAT_HOLD_TICKS`) while the zombie is still there. Open call, see docs/23.

Gated by `godot:m2:jobs` BUILDER: a zombie 3 m off the yard breaks the job off, 20 m off does not,
a builder inside the house is not broken off, and the walk home holds for `RETREAT_HOLD_TICKS` and
the builder goes back to the wall after it. The lane was run red against the lot-as-home rule first.

## The torch is a cone, 2026-10-24

**JT's two calls, taken as the plan's defaults.** The torch lights a wedge, not a round pool, and
only a zombie in its light is drawn toward it (cards in the planning thread, 2026-10-24).

- **Only the beam pulls.** `SimShambler._lean_to_light` asks `SimLight.lights_tile` before a beam
  source pulls: a zombie inside the wedge, or inside the spill round the holder's feet, leans to
  the light; one behind the holder does not. A round light (a lantern, a campfire, a flash) is
  unchanged.
- **The wedge is the content's `light.beam`, capped at a right angle.** A hand torch throws 22°
  either side of its carrier's facing. The facing is read every tick from the holder, and turning
  moves the wedge without recasting the round shadowcast (gated by `godot:m2:torch` TURN).
- **A spill of 1.5 m round the source is lit whatever way the beam points.** A torch lights the
  ground at the holder's feet and a zombie at arm's length; that is the spill's only purpose.
- **Light sources carry `beam` only when they have one.** A round light's `light_source` is the
  same `{magnitude}` it was, so every save that holds one is byte-identical.

Still open: the screen draws the wedge from the sim's cone only after the beam-on-screen slice (B3).
Until then `LightLook` draws its own wedge from content, which is the half `godot:m2:torch` READS
skips out loud. (Closed by "The torch on screen", below.)

## Weapon assembly starts with the hands, 2026-10-24

The three-features plan (C1) made the bench's screen reachable away from a bench, for one reason:
a magazine and a sight are changed by hand (`fieldSwap`), and a gun that has one should open where
you stand. Calls taken without the owner:

- **The question is one predicate.** `SimGunsmith.may_open` (at a bench, or `field_work`) is what
  the `modify` verb and the open command both ask, so a verb cannot be offered for a gun the
  command refuses.
- **A screen opened by hand stays open where you stand** while there is still a part to change
  by hand, and closes when there is none. Walking away from a bench still closes the bench screen,
  as `SimContainers` closes a box, for a gun with nothing to change.
- **`modify` in the item menu pushes `bench.open`.** It was offered at a bench and pushed nothing,
  which the dead-socket rule forbids. Gated by `godot:m2:bench` FIELD and `godot:check:inventory`.

## The draft key on X, 2026-10-24

**JT picked the draft toggle for a colonist: X.** With a colonist picked on the street, X holds them
where they stand and takes them off work; X again sets them free. The menu keeps "hold here" and
"go here" as they were, so a right-click move still says whether it keeps the draft. The sim decides
the command (`SimOrders.draft_command`); the key pushes it.

**How to apply:** the draft is the `hold` order on the colonist's own tile. A new draft-like verb
goes through `orders.gd`, not a second flag.

## The night's reach on screen, 2026-10-24

**JT's card, both changes (the default).** A campfire lights 8 m in the sim, not 20. Its drawn pool
keeps the 20 m look it had, so the lit pool stays about 6 m across and the screen does not lose the
fire. Survivors see at least 3.5 m after dark with no light, through a `night_eyes` key on their
observer (zombies and raiders do not get it). Noon is unchanged. A save from before the key gets it
on restore, as give_eyes would have set it, so no version bump (coordinator, 2026-10-24).

**How to apply:** a survivor's sight floor is `SimLight.NIGHT_EYES_FLOOR_M` in `sim/vision/light.gd`,
not a light, and the drawn eye disc reads it through `sight_metres` like the sim does; a look that
should match the sim's reach reads `pool_reach_of`, never the raw sim number.

## A dropped part fits only an empty slot, 2026-10-24

The drop on a weapon is the fit and nothing more (C3). Calls taken without the owner:

- **A drop never swaps.** An occupied slot takes no part from a drop; the grid placement is the
  answer, and swapping stays with the assembly screen, where a choice is made on purpose.
- **The hands rule holds for a drop too.** A part the survivor cannot change by hand is not fitted
  by a drop away from a bench, even into an empty slot. `SimGunsmith.drop_slot` asks `may_work`,
  the question the open command and the attach command already ask.

## The assembly screen is a screen, 2026-10-24

The three-features plan's C2 rewrote the bench as an assembly view on the Salvage Locker. Calls
taken without the owner, all presentation:

- **It washes the window and keeps its clicks.** The bench already held the keys (its focus
  refuses the street's), but the old panel was a rect over a live street, so a click beside it
  swung at whatever was there. The new one covers the window, dims it, and spends a click off its
  frame on nothing.
- **Enter does what the lit button says.** The footer shows "take off" when the picked part can
  come off and "fit" when a candidate has the keys; the one Enter would press wears the accent
  and an Enter keycap. On an empty slot Enter crosses to what fits it.
- **A click on a candidate fits it at once,** as the old list did. Every fit is undone by the
  next click, so a confirm step would be a second press for nothing.
- **A required slot wears a "needed" tape, rimmed in rust while it is empty,** and a plate with
  something in the pack that fits wears an amber dog-ear. Both are the read model's answers
  (`required`, an offer for the slot), never a guess on the screen.

## Haul's walk runs on the nearest item, 2026-10-24

The tick's P0 slice (docs/22, "P0, the colony sample"). Calls taken without the owner, all sim-side
and behaviour-preserving:

- **The zombie walk is deferred, not removed.** `_haul_work` still asks `_danger_at` of every
  candidate it would pick, and of nothing it would not; it asks it of the nearest one first, and
  of the rest in distance order only when that one has a zombie near it. Same answer, pinned by
  `godot:m2:tick`'s ORDER lane and a serialize hash equal to main's.
- **Dress and Repair were left alone.** Dress asks `_is_better_armor` of every ground item and may
  erase a stale claim as it goes, so its order is part of what it decides; cutting it needs a
  memo, which is a behaviour question for the coordinator, not a loop cut. Repair's double scan of
  the stockpile happens only when a worn item sits on the pile, which starts a job rather than
  recurring each tick, so it was left alone too.

## Menus and the E prompt speak one grammar, 2026-10-24

The action bar's E clause names what E does, in the words the right-click menu uses for the same
row. It used to lead with the look-at, so a boarded window put its state under the key ("E —
intact") while E boarded it. The states still reach the screen, on the survivor's lines; the key's
clause is a verb or nothing. One source for the words, `SimContext.reach_words`, walking
`_use_context`'s ladder, held to `verbs_at` by `godot:check:context`'s BAR lane.

The menu's header names what was clicked and nothing more: a colonist by name, a thing by its kind,
any zombie as "a zombie". With the menu open the arrows are the menu's, never a step, and Enter
does what the ringed row says; the ring opens on the first row, which is the bar's E clause
whenever the clicked thing is the one in reach.

**How to apply:** a new E rung gets its words in `reach_words` and its row in `verbs_at` in the
same commit, and BAR gains a case for it. A state is never an E clause.

`reach_words` reads three of `SimFortify`'s underscore helpers (`_door_in_reach`,
`_door_would_toggle`, `_on_river`), as `verbs_at` already read the first: they are the ladder's own
predicates, and a copy here would drift from `_use_context`. Renaming one breaks the BAR lane, which
is the point.

## The torch on screen, 2026-10-24

The three-features plan (B3) put the sim's cone on screen. JT's card "torch seen from behind"
stands: behind the holder, past the spill, the screen is dark because the sim is. Calls taken
without the owner:

- **The screen's beam is the sim's.** `LightLook.light_texels` sets a beam's bit only where
  `SimLight.lights_tile` lights the tile, and `source_beam` and the beam's facing are read from
  the light index (`source_at`), not from content. One answer for the zombies, the holder's sight
  and the picture.
- **A beam lights every tile it falls on** (`SimLight.BEAM_EDGE_M`, 1 m). Through tile centres alone
  the lit tiles are a staircase: one row wide for the first two metres, then three, then five. The
  screen can only draw inside lit tiles, so the drawn beam was that staircase too (the first cut's
  shots in the project's `planning/night-torch/`). With the margin, every point of the beam, drawn
  from the hand, is inside a lit tile, so the drawn beam keeps the straight edges it had before B3.
  The margin is half a tile's diagonal plus a hand's breadth off the body's point. The cost: the
  sim lights a little more at the beam's edge, so a zombie a little outside the 22° half-angle is
  pulled when it stands on a tile the beam crosses. The far diagonal (45° at 5.7 m) stays dark.
- **A carrier with no facing throws round.** The B2 plan said so and the light index did not do it:
  `SimLight.refresh` now keeps a beam only for a source with a `facing` component. Every person
  has one, so nothing that ships changes.
- **The beam leaves the hand.** The wedge's apex is the hand holding the light, on the frame the
  body was drawn on (`LightLook.hand_metres`, `Appearance.frame_hand`), so a torch in the secondary
  hand lights from that hand and not from the soles. A headlamp or a clip light is in no hand, so
  its beam starts at the body's point.
- **The disc at the hand is the sim's spill** (`SimLight.SPILL_M`, handed to the shader as
  `spill_m`), and the beam's edge now softens inward from its half-angle instead of outward past
  it, so the drawn beam ends where the sim's half-angle does.
- **Seen from behind, the beam starts on the ground under the body** (art review). Facing north the
  hand is in front of the body and the beam runs up the screen through it, so a beam from the
  hand's height showed first above the head and read as a headlamp. It starts at the hand's side
  at the body's ground point instead.
- **A beam over a pool keeps the pool's colour** (art review). Brightness stays the brighter of the
  two, max and never sum, as the sim keeps it; the colour is the two tints weighed by how bright
  each is there, so a torch across a campfire's ground stays warm under the white. Two round pools
  still show the brighter's own hue (the A10 review's rule), and a pixel only one light reaches
  keeps its tint exactly.

**How to apply:** a change to how a beam is drawn changes `lights_tile` or the shader's wedge, never
a second presentation answer. Gated by `godot:check:light` BEAM and `godot:m2:torch` CONE and READS.

## Stockpiles are in scope, 2026-10-24

JT's 2026-10-23 answer to the alpha plan's Q1 moved orders, blueprints, stockpiles and crafting into
scope, and the 2026-10-19 "parked until after the alpha" line no longer holds for stockpiles. JT's
2026-10-24 "yes" started the stockpile and hauling feature, and this is its first slice (S1, the zone
as tiles in the sim). Calls taken without the owner:

- **The zone is a record on the player, made at the first mark.** `stockpile: {"tiles": {"tx,ty":
  true}}`, keyed by the String `"tx,ty"`. Until anybody marks anything there is no record, and the zone
  is the annex's indoor floor, so an unchanged colony and every save from before this slice read as
  they always did. No `SAVE_VERSION` bump, the `was` and `night_eyes` precedent. The record sits on the
  player rather than a new entity, so no entity id after it moves.
- **Marking is explored-only, indoors or out.** A tile the player has never seen cannot be marked.
  Indoors and out are both allowed: the card default, which keeps the camp's ground open to a pile
  if the player wants one there.
- **Only open floor can be marked.** A wall, deep or ford water, a door, a low tile, a tree or a
  scrap barricade is refused. The plan named the first four; the rule is floor only, and it is
  stricter than the plan.
- **A tile walled over leaves the zone and comes back when opened.** A zone is a choice about ground,
  and a barricade on it is not a stockpile tile while it stands.
- **Caps are 400 tiles.** The zone holds at most 400 tiles, and one `on` rectangle covers at most 400
  tiles. Both refuse whole, so a drag too large is a no-op and the screen may split it. An `off`
  scans the zone, not the rectangle, so clearing a large area is always safe.
- **Beds stay on the annex floor.** `_free_indoor` asks `is_annex_floor`, so moving the stockpile
  never moves where a bed goes.

## Hauled items spread over the stockpile, 2026-10-24

The stockpile plan's S3 slice (`claude/project-thread-spo`). Until now every hauled item and every
cooked meal went down on the first free annex tile in row-major order, so a colony's whole pantry
stacked on one tile. JT's 2026-10-24 "yes" covered the plan, and its card defaults are built here.

- **The drop point is the emptiest free tile of the nearest patch.** A patch is a group of zone
  tiles that touch edge to edge. The nearest patch with a free tile takes the item, and inside it the
  tile with the fewest items wins, ties to the nearest to where the carrier stands, then row-major.
  Six items dropped one after another land on six tiles. Nothing is refused for room: a full pile
  keeps taking items, evenly, the way a hauler would stack them.
- **A pile marked beside a camp is the camp's stash.** A camp has no indoor floor, so the default zone
  stays the annex and a camp never stocks anything by itself. A pile the player marks beside a camp is
  its own patch, and a colonist standing near the camp stocks it. The drop reads positions, not camps.
- **The drop point is chosen once per haul and kept on the job.** A carrier re-choosing each tick
  from wherever they stood would turn back and forth at the line between two patches. The point is
  recorded as `dropX` and `dropY` on the job and is chosen again only when it stops being a free zone
  tile (walled over, or a bed or fire put on it). An old save's job has no keys and chooses on its
  next carry, so there is no version bump.
- **A meal lands nearest the fire it was cooked at,** not the cook's feet. The fire is where the food
  was made, and a cook may be standing somewhere else when the job completes.
- **The raider looter reads the zone.** `_is_stores` and `_loot_goal` ask `is_stockpile_tile` and
  the zone's tiles, so a marked outdoor pile is looted the way the annex is. The `SimHome.rect` test
  is gone from both.
- **The day half of the colony moves.** Spreading puts the drops where the carriers walk, so a day's
  walks inside the annex change. This is the plan's stated cost, not tuned here. It surfaced the
  documented doorway deadlock (docs/23, "Two walkers hold each other in a one-tile doorway") on
  `godot:m2:jobs`'s guard lane, which passes on main. The lane was not loosened. Main's watch fix
  (the entry below, #210) cleared it: Guard's arrival bound, not a walk yield, was the cause.

## A watch stands on its post, 2026-10-24

- **A watch stands on its post, and a walker does not yield to another (2026-10-24).** The known
  issue filed as "two walkers hold each other in a one-tile doorway" was a stop rule. Bodies never
  block each other in this sim: `_integrate_movement` tests walls only, and a body removed from the
  gateway leaves another's trajectory identical. So the yield the issue asked for would not have
  changed the failing lane. What did change it is that Guard arrived at the walk's `REACH` (1.5 m)
  from the post, so a watch from the west stopped at (29.05, 30.5). The fix gives Guard its own
  arrival bound, `SimJobs.GUARD_REACH` (1.0 m), and nothing else moves: every other job still
  arrives at `REACH`, and `SimJobs._walk` is unchanged. The STAND lane in `godot:m2:jobs` is the
  true positive (red on the old bound, from the west), and it asserts the stop is within
  `GUARD_REACH` plus 2 art px (1/16 m, one tile being 32 px). The GUARD lane keeps its gateway measure
  and is not loosened. A bound of 0.5 or 0.75 m was tried first and flips the FAST balance wipe on
  seed 20260805 red; 1.0 keeps the band. That is a bound picked for the balance gate, so the
  record says so.

## Marking the stockpile on screen, 2026-10-24

Slice S2 of the stockpile and hauling plan: Z picks up a brush, a left drag marks a rectangle of
stockpile, a right drag clears one, and the zone shows on the ground. JT approved the feature and
the card defaults are built (drag tiles, not crates; any explored ground, indoors or out). Calls
taken without the owner:

- **The brush is a focus, not a flag.** `mark` sits in `input_map.gd`'s `FOCUSES` just before
  `street`, because the mouse means something else under it (the left button paints instead of
  attacking, the right one clears instead of opening the menu) and the focus table is where "what
  fires here" is written. Under it: walking, the stance ladder, the sprint latch, pause, the two
  speed keys, F1, Z and Escape. No swing, shot, E, camp or screen. Picking it up does not stop a
  walk, and a refused key under it does not either.
- **Ctrl+Z stays the prone rung.** Z is its own `BINDINGS` row with `ctrl: false`, and the match arm
  checks the modifier, the camp key's C and Ctrl+C precedent.
- **Escape puts the brush down, and a second Escape is the menu.** Escape speaks to the thing in
  front, as everywhere else.
- **The bar names the keys as keycaps.** The plan's sentence ended "Z to finish"; the bar draws every
  key it names as a cap, so the line is "Marking the stockpile: drag to mark, right-drag to clear"
  then a Z cap, an Esc cap and "put the brush down" (both keys do; art QA asked for Esc to be named,
  so a lead clause may now name two keys as "Z / Esc — ..."). A drag the sim would refuse whole
  (past the tile cap) says "Too much ground for the stockpile: let go and nothing changes" and
  previews nothing. No digit either way.
- **The preview is the sim's answer.** `SimStockpile.preview` returns the tiles a mark would add or
  take back, or that it would be refused; `mark` now applies exactly that answer, so what the drag
  draws is what the release changes. A mark that changes nothing no longer writes a zone record.
- **The roof wins.** An indoor zone tile under a roof shows the roof, with the brush up or down. The
  plan drew the zone on every explored tile; a wash over shingles read as paint on the roof, so
  indoor ground is marked from indoors, where the roof is off. The preview follows the same rule.
- **Under the props, over the baked floor.** The wash is drawn after the ground and the marks on it
  and before the props and bodies, so a bed or a crate stands on the stockpile. It does lie over the
  baked flat furnishings (the DECOR layer), because a per-frame pass cannot go under a bake; at rest
  the wash is light enough that a table under it still reads.
- **Masking tape, in strips.** The rim is the Salvage Locker's tape with its shadow one art pixel
  inside, on outer sides only, laid six art pixels on and two off from each tile's corner. A solid
  line along a wall read as a skirting board. The drag's preview is one solid strip, amber to mark
  and a lighter rust to clear, so a patch not made yet never looks laid.
- **The rim is held to 3:1, the line for a graphic rather than text.** On every ground the district
  has, live, at rest and marking, and both preview colours. The pale tape alone is under 3:1 on
  dirt and the sidewalk, so the shadow carries it there. A remembered tile's rim is pulled through
  `Palette.remembered` with the ground under it and is not held to 3:1: the remembered map is dim on
  purpose.
- **The pointer is the arrow under the brush.** A crosshair over a zombie would offer an attack the
  brush does not make.
- **A mark let go while paused shows as pending.** The sim takes a command on its next tick, and a
  paused world has none, so a drag released under P drew nothing until play resumed. main.gd keeps
  each released mark with the tick it was pushed on and draws it in the preview's look until the
  tick moves. It is pending, not laid: the zone itself does not change until the sim says so.
- **The overlay is drawn from a kept batch.** Painting the 320-tile default zone fresh every frame,
  one rect per piece of tape, cost about 8 ms a frame on the bench box. The zone is read again only
  when `SimStockpile.signature` moves; what it paints is batched into row-run fills and one
  `draw_multiline` per colour, in tile-grid coordinates offset to the screen as they are drawn; and
  the batch is rebuilt only when a zone tile's state (explored, seen, roofed), the brush or the zoom
  changes. The drag's preview and the pending marks are small and drawn fresh.

- **The cap is 1000 tiles, up from S1's 400.** The default zone (the annex floor) is 320 tiles, so
  400 left about 80 to mark anywhere else, which is not "any explored ground". The coordinator's
  tuning call, taken here. The cap bounds the zone query the Haul drop asks every tick a hauler walks
  with an item (`SimStockpile.tiles`), which cost 2.1 to 3.4 ms at 320 tiles and would have been
  about 9 ms at 1000; the query is rewritten to parse each key once and sort natively, and now costs
  0.67 ms at 320 and 2.1 ms at 1000 on the bench box, under what 400 cost before. A drag's preview
  over a full 1000-tile rectangle costs about 5 ms to answer, so the screen asks it once per change of
  the rectangle, not per frame.
- **The wash is stronger at night.** The night pass darkens the wash with the ground, and at the day
  alphas the zone all but vanished on the board floor by firelight (art QA). The wash leans from its
  day alphas (0.16 at rest, 0.26 marking) to night ones (0.34, 0.55) as the ambient falls, and the
  STOCKPILE lane holds it, by firelight on every ground, at least as plain as the day wash at noon.
  The rim is left as it is: its 3:1 is judged on the unlit ground, as every ground graphic's is, and
  under the night pass it falls with the ground's own detail (about 1.9 to 2.5:1 by firelight in the
  lane's model). Drawing it over the night would make it glow.

**How to apply:** what the brush may change is `SimStockpile.preview`'s answer, never a second one on
screen; how it looks is `presentation/stockpile_look.gd`. Gated by `godot:check:play` MARK,
`godot:check:memory` STOCKPILE, `godot:check:hud` ACTION, `godot:m2:stockpile` PREVIEW and
`godot:check:shots` (`stockpile_mark`, `stockpile_rest`, `stockpile_night`).

## The stockpile on the Colony screen, 2026-10-24

Slice S5 of the stockpile plan. JT's card 4 default stands: the Colony screen reads the stockpile as
a word per group and up to three names, never a count. Calls taken without the owner:

- **The colony knows its own stockpile.** The summary reads what lies on the stockpile's tiles now,
  not what anybody saw there. A colony keeping its own stores is what a colony manager knows, the
  same footing as the "now" line's job words; it says nothing about where anything is, and nothing
  outside the stockpile (a loose tin in the yard, what a colonist carries) is counted. The feature
  review checks this against the scarce-information rule.
- **The water group reads "drink".** The plan named it water, but sodas, beer and coffee fall in it
  by the content's own `drink` block, and "water: a few, Can of Beer" would read wrong. Purification
  tablets go with it, as what makes water drinkable.
- **Groups come off fields the content already carries.** First match wins: a `food` block, a
  `drink` block or `purifies`, a care field the treatment code reads, an `ammo` block, a weapon
  class, armour or a container you wear, then tools, materials, attachments and other containers,
  then other. No content key was added.
- **The block takes the drawer's place.** Measured at 1280x720, a ninth block under the drawer costs
  the roster rows it needs. With nobody picked the drawer shows the stockpile; with somebody picked
  a "the stockpile" button shows it in their drawer, with "back to" their name. The drawer keeps one
  height for both, so pressing the button never moves the grid.
- **A name that does not fit is passed over, not cut.** Names stand most numerous first, and one
  too long for what is left of its column is skipped so a shorter one after it may still stand; a
  stocked group never reads as a word with no name, because the first is cut, marked, when none
  fits whole.
- **The read model lives beside `work_read.gd`, not in the stockpile module.** Two other slices
  were editing `stockpile.gd` at the same time; a read model that asks `SimNeeds.stockpile_items`
  follows the zone just as well.

**How to apply:** a change to what the Colony screen says about the stores changes
`StockpileRead.summary`, never the panel. Gated by `godot:check:play` STOCKPILE and
`godot:m2:stockpile` SUMMARY.

## Taking from the stockpile, 2026-10-24

Slice S4 of the stockpile plan: the loot window fed the stockpile, with take and put away. The
owner's cards were built at their defaults (the window lists the patch you can see; words, not
counts). The calls below are engineering calls taken in the slice.

- **E opens the stockpile where it used to pick up a stockpiled item.** Standing in the zone, when
  the loose item E would pick up lies on the zone and no cupboard is in reach, E opens the window
  (`SimStockpile.e_opens`, the rung before the pick-up in `SimFortify._use_context`). An item off
  the zone is still picked up, and a door, a bed or a fire beside an empty pile keeps E, so the rest
  of the ladder is unchanged. An empty patch opens on E as the last rung, so there is a window to
  put things away into. The words are "go through the stockpile" on the bar and first in the menu
  (`SimContext.reach_words`, `verbs_at`), the way a cupboard is "open the cupboard".
- **The window lists what the player sees from where they stand, not what they face.** The test is
  walls and range (`SimVisibility.line_of_sight`), or a lit spot past the dark's reach
  (`detail`). It is not the facing arc: the body faces the pointer, and the pointer is on the
  window, so an arc would change the list as the mouse crossed it. An item behind a wall or out of
  the night's reach on the same patch is not listed and cannot be taken.
- **Nearest first, and the window says when the pile holds more.** The sim lays the nearest items
  into the cells the screen gives it (`stores_view`), biggest first so a pack is not shut out by
  tins, and the grid's header reads "and more besides" when something seen did not fit. Walking
  across the pile shows the rest; "take all that fits" takes from the whole list.
- **A put lands in view.** `stockpile.put` uses S3's rule (`drop_tile`: the emptiest tile, then the
  nearest) over the tiles of the player's patch the player can see. On the emptiest tile of a big
  pile, out of sight, the thing put away would drop off the list the moment it was put.
- **The window is a sim state.** `stockpileOpen` on the player, set by E, the menu or
  `stockpile.open`, taken off by `stockpile.close` (Escape), by stepping off the zone, or by opening
  a cupboard. A cupboard opened in the stockpile takes the window. A save from before the slice has
  no such component and loads with the window shut; there is no version bump.
- **The window never drops over the action bar.** `set_loot` puts a box too tall to clear the bar
  over it, which at 1280x720 cut the bar's sentence in half under the window. The stockpile's grid is
  sized to clear it instead: eight by three at 1280x720, ten by six at 1920x1080. A pack, four cells
  tall, does not fit the 720 grid; the header says "and more besides" and the sheet's column (Tab,
  seven by six) holds it.
- **A take drops the item's claim.** A cook's claim on a raw (`reserved`) goes with the item when
  the player takes it, so the cook's job cannot finish on a tin in the player's pocket.

**How to apply:** what the window may take or put is the sim's answer (`SimStockpile.take`,
`put`, `in_sight`), never the panel's. Gated by `godot:m2:stockpile` TAKE, `godot:check:inventory`
STOCKPILE, `godot:check:context` BAR and `godot:check:shots` (`stockpile_window`).

## The overcast day, as a grade, 2026-10-24

The three-features plan's B5, paying for the day half of "Overcast or torchlight" (2026-09-08):
cool, desaturated daylight under a grey sky, the night left warm, the void lifted off blue-black.
The owner was shown before/after pairs of the day street, a room, dusk and the night on a decision
card ("keep / softer / stronger / drop the day half") with keep as the default built. The calls
taken without the owner, clause by clause against what the 2026-09-03 warm grade said:

- **It is a grade of the finished picture, not a regrade of the palette.** The plan, written from
  docs/23's 2026-09-08 bullet, asked for two palette families keyed to the phase and the five
  palette lanes (PALETTE, TEXTURE, ACCENT, WALL, GREY) re-pinned. Since 2026-09-26 most of the
  screen is the outpost pack's own art -- the ground, the walls, the props, the pawns, the cars --
  which no palette entry reaches, so a palette regrade would have cooled the generated half of the
  street and left the pack half warm, and could not follow the phase without a rebake. One
  screen-space pass, `presentation/day_grade.gd` with `day_grade.gdshader`, treats both alike and
  reads the sky every frame. The five palette lanes keep their tables untouched: they pin the
  *source* colours, which did not move, and the grade has its own measured table in the new gate.
- **"Warm, and cool only where the dark is" becomes "cool by day, warm by night".** By day every
  pixel is pulled toward its own grey (68% of its colour kept in the lit middle, 20% in the darks,
  eased over luma 0 to 0.25), given a cool gain (red 0.97, blue 1.03) and veiled 10% toward an
  overcast grey (#5c5e60). The warm surfaces lose warmth, every colour that is not cool loses
  saturation, and the glass and the outline -- the cool exceptions the warm grade kept -- stay the
  coolest things on the street.
- **The night is not graded at all.** The weight is `smoothstep(NIGHT_AMBIENT, 1, ambient)`: 1
  under a full day's sky, 0.5 at mid-dusk, exactly 0 at night, when the grade draws nothing and
  the frame is the light map's picture bit for bit. At mid-dusk the night's multiply already holds
  the frame, so the grade's grey is barely measurable there (the `dusk_street` pair's chroma moves
  6.2 to 6.4 at 1280×720 and 7.3 to 7.0 at 1920×1080): the weight is the claim, not a visible
  half-strength look. The grade sits under the night's multiply
  and its glow, so a pool's hue and a flame are laid on after it: the pools, the fire and the
  torch stay the one saturated thing after dark, which is the night half of the 2026-09-08
  sentence and was already true.
- **The void lifts to a dark grey through the same pass,** #15141f to #1c1c20 by day, rather than
  by moving `Palette.background`, which the night also reads. It stays the cool near-black the
  district sits in at night.
- **No readable word is graded.** Every HUD control is on a CanvasLayer above main's canvas
  item; the grade reads the screen before any of it draws. Translucent panels show the graded
  street through them, which is what translucent means. The words main writes into the world --
  the speech bubbles and the pawn tag -- are recorded during `_draw` and painted on a child item,
  `_world_text`, at draw index 999: over the grade (998) and under the night (1000), so the night
  still dims them exactly as before and the day never greys them. The art review's round 1 made
  this a slice fix rather than a follow-up: readable text under 4.5:1 is fixed where it is found.
- **A zombie's sound-word is lifted to 4.5:1.** It drew in the kit's dim text, 3.3:1 on its plate
  over the pavement before any grade. It now draws `Chrome.TEXT_DIM` lifted 40% toward
  `Chrome.TEXT` (`main.gd`'s `bubble_ink`), 4.89:1 over the worst ground and still quieter than
  speech. The kit's own `TEXT_DIM` is unchanged everywhere else.
- **The stockpile's rims are held under the grade.** The stockpile (S2) landed before the grade
  and its rims were measured in their source colours. Under the noon grade the rest rim on dirt
  fell to 2.83:1 and both drag-preview rims fell under 3:1 on the indoor floor. The rims change,
  not the bar: the tape's shadow is drawn at the tape's own alpha (`STOCKPILE_SHADOW_SHARE` 0.9 to
  1.0), the mark preview's rim is its own lighter amber (`STOCKPILE_ADD_RIM` #e6b158, the fill
  stays the kit's ACCENT), and the clear rim is lighter (`STOCKPILE_CLEAR_RIM` #f09070 to #f2a185),
  each 15% toward white. `godot:check:memory`'s STOCKPILE lane now holds every rim at 3:1 in the
  graded picture too, and refuses a graded measure that lowers no rim.

**How to apply:** a word drawn into the world goes through `_world_text_ops` and
`_paint_world_text`, never a `draw_string` of main's own (`godot:check:grade`'s WORDS lane counts
them). A tune of the grade changes `day_grade.gd`'s six constants, re-measures
`check_grade_look.gd`'s DAY_TABLE and re-shoots `day_street`, `interior` and `dusk_street` in the
same commit, and re-runs `godot:check:memory`, whose STOCKPILE lane measures the rims through
`DayGrade.grade`. A palette change does not touch the grade, and the grade touches no palette
lane but that one. Nothing draws over the grade except the world's words, the night, the glow and the HUD.
## Nowhere to put it, 2026-10-24

The stockpile review's first two findings, taken as engineering calls while the owner's card
(may the zone be emptied at all?) is open; the card does not gate the work and the default built
is the honest one.

- **A thing that will not stow stays where it lay.** A Haul or Repair pickup that finds no room in
  the pack puts the item's `position` back and stops. Taking it off the map first and leaving it
  there was the one path by which an item left the game with nobody holding it.
- **Full hands are a hold, not a retry.** The colonist whose pack refused is not offered Haul or
  Repair for `SimJobs.HANDS_FULL_TICKS` (600 ticks, the Retreat hold's length): the `handsFull`
  record on the colonist, absent by default, so no save version moves. Without it the same item was
  walked to and refused every tick.
- **An empty zone is allowed and honest.** With no stockpile tile anywhere, Haul offers no item and
  the haul order row is absent (`SimStockpile.has_any_tile`), and a cooked meal lies at the fire's
  own tile. Nothing is refused, nothing is lost; the colony simply stops stocking until a tile is
  marked. Whether the clear should be refused instead, or the bar should say what it means, is the
  owner's card.

**How to apply:** no sim path may remove an item's `position` without putting it somewhere -- a
pack, a tile, or a despawn. `godot:m2:stockpile` EMPTY and FULL hold the two paths found.

## The release plan and the content arcs, 2026-10-26

Decided by the owner, 2026-10-26, from a proposal in the coordinator's chat. Four calls, each
recorded once here; the plan itself is [docs/38's "The release plan"](38-playbook.md#the-release-plan)
and the pieces it opens are in docs/23's what's left under "Content arcs".

- **The projection stays flat top-down.** An isometric view in Project Zomboid's manner was
  asked about and declined. The reasons, in the order they weighed: the sim is projection-blind
  and would not move, but occlusion management (wall extrusion, the cutaway over the player, the
  per-frame depth sort) was deleted whole in the 2026-09 reversal and would come back whole;
  about forty-six of the look gates pin flat-projection facts; and every shipped picture -- the
  outpost pack and the generated tier both -- is drawn flat, so nothing reuses. This is the third
  time the question has been settled (the isometric start, the top-down reversal, and now), and
  it is settled the same way as docs/00's reversal argument. Depth on walls and furniture, where
  wanted, is an oblique treatment inside the current projection, never a new one.
- **Release goes in five stages.** Named in docs/38: alpha closed (it loops), alpha open (it
  survives), the art pass (it looks finished), beta (people and the world), and 1.0 (breadth).
  Multiplayer is off the track and is 1.x unless the owner pulls it forward. The art pass runs
  beside the balance stage, not after it.
- **Four content arcs open.** More zombie kinds (seven to fourteen), raider doctrine and
  archetypes (four to nine), realistic firearm customization on the existing assembly model, and
  bespoke melee customization on the same model. The owner's words for the weapons: *"you can
  customize every aspect of the weapon, change out barrels, different calibers, etc., but it needs
  to be realistic"*, and for melee: *"a baseball bat, but you can put nails in it, or a hockey
  stick, put a knife on it, a scythe ... organic and nice and a little bespoke."*
- **Readers before content, pictures a stage behind.** Every arc lands its readers first (the
  three stats that resolve against nothing come before any new part), and the art for a new
  kind, part or frame is scheduled one stage behind its sim piece, so no picture ships before
  the thing it shows exists.

**How to apply:** a new zombie kind, raider archetype, part or melee frame is a piece in docs/23's
"Content arcs" group before it is a branch. A stat on a part needs a reader in the same slice or
it is not authored. A conversion between calibers is allowed only where the realism table in
docs/10 says so; the coordinator writes the table and the owner vetoes.

## The floodlight comes back down, 2026-10-26

The 2026-09-12 call in "Two placeable items, two opposite answers" made the floodlight one-way on
purpose: standing it up commits the thing to that street. The owner took the planted-floodlight
piece up on 2026-10-26 and chose to build the way back (approved in the coordinator chat), which
supersedes that call.

The floodlight is still a rigged installation and still costs the street. What changes is that the
commitment can be taken back: `light.unplant` lifts the lamp within the plant's own reach into the
pack with its fuel carried, and refuses, leaving it standing, when the pack has no room. The
noise devices keep their answer and the alarm and noisemaker stay free, as that call left them.

**How to apply:** a planted light has a way back, so a gate or a record that calls the floodlight
one-way is out of date. `godot:m2:light_burn` UNPLANT is the lane that holds the take-down.

## Colonists look after themselves, 2026-10-26

The autonomy half of the comfort and books slices, taken as engineering calls inside the piece; the
piece itself is the owner's standing item ("nobody seeks comfort, or reads, on their own").

- **Comfort ranks like Dress, above the columns; Read ranks below all of them.** A low colonist
  stops to smoke before he works, the way an unarmed one re-arms and a bare one dresses. Read is
  only the empty day's fallback, so it can never beat Water or Construct.
- **Autonomy spends only while no comfort is standing.** `take_comfort` accumulates toward the cap
  and the player verb has no such gate, because a player chooses the moment. Without this gate a low
  colonist smokes the whole pile in consecutive ticks. The gate is in `jobs.gd`'s `_tick_one`, not in
  the mood rules.
- **"Low" means any band worse than content** (`SimNeeds.mood_band != "content"`), so miserable and
  breaking colonists take comfort too. Nothing is compared against a threshold of the tick's own.
- **A comfort is used where it lies.** One unit comes off a stack and the rest stays on the pile for
  the next colonist; a reusable comfort is used and left whole. The first cut carried the whole
  stack into the pack. The pack's room no longer matters, so the full-pack refusal went with it.

**How to apply:** a new autonomy kind that walks outside goes into `DANGER_KINDS`, and an idle
fallback goes below every ranked column in `_pick`, not in `_tick_one`.

## Three walls, one substance each, 2026-10-26

Engineering calls taken on the buildables slice. None rebalances a shipped verb, and none moves a
pinned lane. The numbers they set are first cuts, named in the record as unmeasured.

- **A wire fence stops the body and not the eye.** The timber wall and the stone course block sight
  as the barricade does; the fence is the one raised wall the shadowcast sees through. The sim
  already distinguished the two halves (a door is solid and opaque by its state, a board is opaque
  until its stage), so the fence is one more overlay kind with its own answer, not a new mechanism.
- **A recipe names one substance.** The table is verb to kind, so the fence is wire alone and not
  wire with fixings. A recipe that wants a pair is a shape change and goes to the owner first.
- **Walls are not singletons.** `can_build` is the barricade's ground rule without its window-side
  rule, and more than one wall may stand. The scrap barricade's one-of-a-kind check stays as it was.
- **A wall waits for an empty tile.** `can_build` also refuses a tile holding a body, a loose item,
  a water source, a bed, furniture or a container, in the predicate and again when the channel
  ends. The first cut asked about the ground only and would have walled a survivor, a well or a
  dropped rifle into a solid tile.

**How to apply:** a new raised wall is a `RECIPES` row, a `BUILD_TICKS` row, a `BLOCKERS` row, a
`STAGE_COST` row, and one answer in each of `SimTileMap.is_solid`, `opacity_at`,
`shadowcast._overlay_opacity` and the presentation's overlay arm. WALLS in `godot:m2:fortify` is the
lane that proves the answers agree, and it must go red when any one of them is sabotaged.

## The tourniquet, and the limb it costs, 2026-10-26

docs/05 names three ways to stop a bleed -- pressure, tourniquet, bandage -- and two existed. The
tourniquet is built as a fourth thing the pressure channel does, not as a dressing grade (docs/23).
The rule is the smallest honest one, taken without a tuned curve:

- **It holds the whole limb for a window, and then the limb goes.** A tie on an arm or a leg holds
  every open wound on that part shut for `SimWounds.TOURNIQUET_TICKS`, 2400 ticks: two minutes of
  a one-hour day. When the window runs out the part goes to `DESTROYED`, the floor an amputation
  leaves, and the lasting word `tourniquet` says why.
- **The clock is the time on, not the state of the wound.** A wound a hand has already clotted still
  spends the window. The limb is what is being starved, and a hand on the wound does not feed it.
- **No new number.** The cost is a limb docs/05 already has, not a graded ischaemia with a movement
  or swing penalty. A penalty curve nobody has measured is a balance claim this piece does not get
  to make, and whether a tie should ever be survivable at all is the owner's call, not a default.
- **Loosening in time is free.** It is a channel of `TOURNIQUET_LOOSEN_TICKS` (20). Once the window
  has closed there is nothing left to loosen and the verb is refused `not-tied`. The bleed resumes
  on any wound still open.
- **A lost limb is closed with its wounds (the default taken).** When the window runs out the
  part goes to `DESTROYED` and every wound on it is dropped with it, so a stump does not bleed: a
  forgotten tie costs the limb and nothing more. The first cut left the wounds `bleeding: true`,
  which let the bleed come back on a limb that no longer existed. Whether the bleed should come
  back is the owner's call (docs/33, card 17); the lane for either answer is one line.
- **The item is spent on the tie.** A tourniquet is used up on the leg it goes on; a loosen does not
  give it back. A reusable one would be a second spend path and a return to the pack, and is not
  built.
- **Arms and legs only.** A hand or a foot is refused `not-a-limb`. That is the sided-limb set
  `SimWounds._is_limb` already keeps for fractures and sprains, and the brief's own words.

**Not in this piece, on purpose:** the self-aid context offers pressure and dressing only, so a
colonist does not tie one on themselves. The player has two ways to the verb: the care pane, and the
item's strip key, whose `supply_plan` picks the bleeding limb when a torso bleeds beside it
(`godot:m2:treatment` TOURNIQUET OFFERED). The loot line came later, in "The tourniquet is
findable".

**How to apply:** a tie that a hand has already clotted is still a limb on the clock. Do not end the
window when the wound does, and do not make a tie survivable without an owner decision. The
TOURNIQUET lanes of `godot:m2:treatment` hold the rule.

## The tourniquet is findable, 2026-10-26

The tourniquet shipped with no loot table naming it, and `godot:m2:gear` CATALOGUE did not notice:
its `READ_KEYS` lacked `tourniquet`, `bandageTier`, `attachment` and `recipe`, so a base carrying
only one of them was never judged. The keys are in, and the lane now sees the tourniquet.

- **One line in `loot.medical`, weight 8, no count.** That is the sterile dressing's weight (8 of
  274 before, 8 of 282 now), taken as a default so the lane could go green and the item could be
  found at all. It is the table that already carries dressings, and no other table was touched.
- **The ten-seed balance table was not re-run for this line.** A loot line moves campaign outcomes
  and the claim of workflow step 5 is a measurement, not a guess. The weight is a placeholder with
  a name on it; docs/33 card 18 puts it to the owner.
- **A made part is exempt from findability, narrowly.** The 25 improvised attachments carry a
  `recipe.kinds` block and are built by `item.improvise`, never rolled. CATALOGUE exempts a base
  with that block and no other attachment, and counts them in its line so the exemption stays
  visible.

**How to apply:** a new key that makes a base do something goes into `READ_KEYS` in the same slice
as the key, or the dead-socket check cannot see it.

## The hand-cut rule, as changed, 2026-10-26

The melee frames piece shipped Glass Shards with a `handCut` flag: a glass blade on a bare grip
cut the hand that held it. The first cut opened a new Laceration on the right hand on every
swing, hit or miss, even on a hand that was already destroyed, and a Laceration never clots on
its own. A survivor swinging a glass-studded bat at a crowd bled out of the weapon, and a miss
cost as much as a kill.

- **One Scratch per swing that connects.** The wound is kind `cut`, severity Scratch, so it clots
  on its own (`CLOT_TICKS`). It is written after the strike has found a body, beside the
  `attack.connected` event, and a swing that finds nobody costs the hand nothing.
- **A hand that is gone is not cut.** The wound is skipped when `hand_right` is absent from the
  body or already at `DESTROYED`.
- **A wrap still stops it, and nails never cut.** Both are unchanged; only glass declares
  `handCut`.

**How to apply:** a self-inflicted cost on a swing belongs where the swing connects, and is a
wound that closes by itself unless the design wants the player to treat it. `godot:m2:attach` CUT
holds the rule: a connecting swing scratches, and a miss, a wrapped grip, a destroyed hand and a
nailed bat do not.

## The wooden bat is found in industrial yards, 2026-10-26

The melee frames piece added `item.bat.wood`, so that the bat the nails need exists. A bat nobody
can find is a dead socket, so it needed a loot line, and the line is a balance claim.

- **One line, `loot.industrial`, weight 5.** The first cut put the same line in `loot.residential`.
  That moved the ten-day balance campaigns: seed 90210 lost its colony in the fast tier and
  `godot:m2:balance` refused it (`M2_BALANCE_FAIL`). The same line in `loot.industrial` passes
  (`M2_BALANCE_OK`).
- **The ten-seed table was not re-run for it.** The balance gate's own seeds judged the line, which
  is a floor and not a table of outcomes. A weight of 5 of 434 is a placeholder with a name on it,
  and the bat's yard is a default taken because residential was refused, not a measured best home.
- **No card was opened.** The weight is a first cut under the standing rule for tuning numbers
  (docs/38: agents decide numbers that come out of a measurement); a bat is a club that does what
  the aluminium bat does, and it adds a way to reach nails, not a stronger weapon.

**How to apply:** a loot line for a new base is judged by `godot:m2:balance` before the commit, and
the record says which gate saw it and which table did not.

## Melee frames, and parts that are made, 2026-10-26

The first stage of the melee arc (docs/38, "The content arcs"; docs/23's record). The calls taken
inside it, none of which rebalances a shipped weapon:

- **Every melee base declares a `family`.** Club: steel pipe, aluminium bat, wooden bat, demolition
  sledge, claw hammer, police baton, golf club, and the Siren's Bell and Tetanus Special. Blade:
  kitchen knife, rusted machete, fire axe, camp hatchet, butcher's cleaver, splitting axe, ice pick
  and the cavalry sabre. Polearm: the improvised spear, the barn pitchfork and the Long Argument.
  Tool: crowbar, pipe wrench and sharpened shovel. A family is a word on the base and nothing else;
  it moves no number.
- **`appliesTo` names who a part is for, beside `fits` for the slot.** Absent or empty means any
  base. Otherwise the host's `family` or its own id has to be named, and both tests hold before a
  part goes in (`SimAttachments.plausible`, asked by every offer, so a refused part is never put
  on the bench as a choice). A ranged base carries no family, so a part naming only families goes
  on nothing ranged. The nails name `item.bat.wood` alone; screws, bolts and glass name the wooden
  hosts (the bat and the claw hammer, whose haft is wood), so a steel pipe and a baton refuse them
  although both have a stud slot.
- **Fitted parts are made, which departs from docs/10's "found, not crafted".** The melee arc is
  the one exception, by the owner's brief ("a baseball bat, but you can put nails in it"): a part
  is built from what the survivor carries, one unit of each material kind its recipe names, by
  `item.improvise`, which checks every refusal before it spends anything. Bench work unless the
  part is `fieldSwap`. docs/10 now says so, and the gear gate's CATALOGUE exempts exactly a base
  with a `recipe.kinds` block from the findability rule, and says how many it exempted.
- **Three slots widen the melee bases: `stud`, `guard` and `weight`,** each declared only where it
  is plausible. The aluminium bat takes weight and no stud; the pipe takes stud and weight; the
  sabre takes a guard. `weight` and `connectNoise` became multipliers because they already had
  readers; no stat was authored without one.
- **Glass cuts the hand that holds it, and the rule changed in review.** See "The hand-cut rule,
  as changed": one Scratch per swing that connects, not a Laceration per swing.
- **The wooden bat is a twentieth base,** so the bat the nails need exists. Where it is found is
  "The wooden bat is found in industrial yards".

**How to apply:** a new melee base declares a `family` and its slots; a new part declares `fits` and
`appliesTo`, and a part made from materials declares `recipe.kinds`. A part without a reader for
its stats is not authored.

## The dead stat readers, 2026-10-26

The first piece of the firearms arc (readers before content, docs/38). `noise_emission`,
`condition_loss` and `repair_cost` were declared stats that resolved against nothing, so the ranged
affixes that named them moved no number a gun reads.

- **Each stat is read in the item's own scope.** The way every affix is scoped, so a quiet hand on
  one pistol does not quiet the next one holstered. `SimItems.noise_emission_of` scales the noise
  a shot or a melee connect publishes, and `condition_loss_of` scales the wear a host or a fitted
  part takes, both by the profile's `source`. A bare hand or a zombie's body has no source and
  reads 1.0, so everything not carrying one of these affixes is byte-identical to before.
- **`repair_cost` was already read** (by the repair verb, since 2026-09-13). The piece added the
  ranged proof that an item's own factor reaches it, and no code on that path.
- **`long_nights` is left inert on a ranged weapon, on purpose.** Its stat, `swing_stamina`, is read
  only by the melee profile. What stamina a shot should cost is a design call and not a reader, so
  the piece names it and does not fix it. `ruin` is half live for the same reason: its
  `condition_loss` half is read, its `melee_damage` half only by melee.
- **Not measured.** Affixes are rolled into loot, so a campaign that rolls them sees different wear
  and noise. The ten-seed table was not re-run and no campaign claim is made.

**How to apply:** a stat authored on a part is read in item scope in the slice that authors it, or
the web gate's READERS lane names it as awaiting a reader. `godot:m2:ranged` QUIET-SHOT and
RUIN-SHOT, and `godot:m2:attach` SWING, WEAR and REPAIR, hold the readers.

## Raider doctrine, 2026-10-27

The first of the four pieces in the 2026-10-27 batch (docs/23's "Raider doctrine" record entry
has the gate lanes). Four calls were taken while it was built.

- **The draw has its own stream, `raidDoctrine`.** The content-arc bullet said "off the raid
  stream". It is not. The `raid` stream's sequences after `_emit_band` are pinned in
  `check_m2_raiders.gd`'s STREAMS lane, and every campaign measured on it depends on them; a
  doctrine draw on that stream would move every band's size and side on every seed. The draw runs
  after the band is placed, so a band that never arrives spends nothing.
- **First-cut weights.** Days 8 and 9: probe 50, raid 50, siege 0. From day 10: probe 30, raid 45,
  siege 25. Days 8 and 9 never draw a siege; a ten-day campaign sees doctrine on three nights at
  most. These are first cuts, not measured, and the ten-seed table is owed the re-baseline.
- **The siege, as the owner picked it (docs/33 item 19, 2026-10-27: "Wait, then storm the wall").**
  A siege band holds at a ring of legal floor 2 to 4 tiles outside the walls box, strikes whatever
  comes within its reach while it waits, and then storms the wall and gate exactly as a raid band
  does. The ring is the nearest legal tile to the band's entry, deterministic and draws nothing.
  The wait is `SimRaiders.SIEGE_WAIT_TICKS`, 6,000 ticks: two in-game hours, a day being 72,000
  ticks and 24 in-game hours. It is a first cut. It is counted from the tick the band reaches its
  ring, the way the withdrawal clock is counted from arrival: a fight within reach halts the body
  before the storm is checked, so the storm never lands mid-fight, but the ticks still count, and
  a fight that outlasts the wait is followed by the storm on the first quiet tick. After the storm
  the usual withdrawal rules apply: the half-strength clause and the arrival clock. The first pick
  drafted for this item (goes home at dawn) was replaced before merge and is not built. The camp by
  the water is not built.
- **No ring means a raid, not a band at the edge forever.** The first draft had a siege with no
  walls box to hold outside stand where it came in. That band would never run a clock, never
  withdraw, and count against `RAID_LIVE_CAP` for the rest of the run, which is a district whose
  raids quietly stop. The end review changed it: a siege whose `_siege_site` finds no ring is
  marked storming on its first read and is a raid from then on. For the same reason a lookout in
  a siege holds on the ring with the band rather than standing off twelve metres from it; its
  stand-off is from the gate, after the storm.
- **Probe widens the lookout's rule, it does not add one.** The first loss turns every body of a
  probe. The lookout's own rule is unchanged and still reads the role.
- **Trade is not built.** docs/33 item 16 is still the owner's, default no. `trade` is not in the
  doctrine list, so a record that names it reads as a raid.
- **The night shapes share three words.** `probe` and `siege` are also the names of director
  night shapes (`SimDirector.NIGHT_NAMES`). A night shape and a band's doctrine are drawn on
  different streams and mean different things: a night is the packet of zombies, a doctrine is how
  one band of people moves. Read the constant's module before you read the word.

**How to apply:** a new doctrine is a word in `SimRaiders.DOCTRINES`, a branch in `_approach`, a
weight row in `SimDirector`, and a lane in `godot:m2:raiders` that breaks it on purpose. A draw
that moves a pinned stream is a bug, however small the change looks.

## The barrel governs, 2026-10-27

The barrel's numbers come from three words, not from a multiplier typed onto each barrel. Calls
taken:

- **Vocabulary.** `length` is `stub`, `short`, `carbine`, `full`, `long`; `quality` is `rough`,
  `service`, `match`; `material` is `mild`, `steel`, `chromed`. Each word's row is a first cut,
  in `godot/sim/barrel.gd`. An unknown word is refused and the weapon will not fire, because a typo
  must not be indistinguishable from a plain barrel.
- **Wear goes through `wearRate`, not `condition_loss`.** The plan said material should feed the
  `condition_loss` stat. `wearRate` is the part's own wear knob and the path `wear_parts` already
  reads, so the material word multiplies it and the wear path is untouched. `condition_loss` stays
  the affix stat it was built as. Quality multiplies the same knob (`QUALITY_WEAR`, `match` 1.4):
  the shipped match barrel keeps its authored 1.4 wear as a match bore on plain steel, not as a
  barrel of soft metal, so `mild` keeps meaning what the vocabulary says it means. No shipped
  barrel is `mild`.
- **Conversions keep the caliber's share.** The rimfire and .45 barrels change the round as well as
  the bore, so their damage, noise and wear stay as a share the words multiply. Moving that share
  into a word would have needed a fourth axis for the caliber, and the plan did not name one.
- **Six barrels, not five.** The plan named five shipped barrels. `item.attach.barrel.long` is the
  sixth, and it is rewritten to words with the rest.
- **Long is louder, not quieter.** The plan's LENGTH lane said the long barrel is quieter. The shipped
  long barrel is 1.12 times the noise of standard, and the 5% rule holds the shipped numbers. The
  lane asserts the shipped ordering: short above long above standard.
- **Mass stays a literal.** The plan asked for length to drive `massKg`. Nothing folds mass on a
  part today, and `_an_assembled_weapon_weighs_what_it_always_weighed` pins the authored masses. Length
  drives `handling` through the existing fold, which is where "swings like nothing" lives.
- **The falloff's first cut.** A slow round keeps its muzzle fraction of damage at full reach,
  starting from 60% of reach. Only a barrel under 1 changes anything, so a standard weapon's shot is
  byte-identical to before.

**Not measured.** The balance numbers are in the PR's Measured section. The ten-seed table was not
re-run and no campaign claim is made.

**How to apply:** a barrel's numbers are its words' product, so a new barrel is a new word or a new
row, not a new multiplier. Any change to a row moves every barrel that uses that word, and
`godot:m2:attach` BARREL SHIPPED says which shipped barrel moved and by how much.

## Melee wear, 2026-10-27

The sim half of "Specific melee wear" (docs/23's record). Three calls were taken in building it,
all first cuts, and they are recorded here so a later pass can move them.

**The wear word is `hit`, not `struck`.** docs/23 had the studs wear through `struck`, the
target-side word the plate piece will use. `hit` already fires on the attacker's weapon at the
moment it connects, which is when a stud, an edge or a lashing wears. So the stud and lashing rolls
ride the existing `hit` channel (`SimAttachments.shed_on_connect` on `attack.connected`), and
`struck` stays free for the plate.

**The numbers.** `shedChance` per stud on a connecting swing: nails 0.03, barbed wire 0.05, glass
shards 0.06, screws 0.01, rebar 0.02, bolt studs 0.01. The screws and bolts are the ones that
"stay in better", so they shed least. A lashed head comes off at `LASH_SHED_CHANCE` 0.025, one
connect in forty. The lashed heads are `item.attach.head.lashed_knife`, `lashed_spike` and
`pitchfork`: the three heads with cordage in their recipe. The gate measures 70 nails out of 2000
rolls (band 40 to 80) and 54 heads out of 2000 blows (band 30 to 72). Both bands sit about 2.5
sigma either side of the expected count, so a seed does not decide them.

**An edge is its own number.** A blade's edge is an `edge` component, `{current, ceiling}`, apart
from the item's `condition`. The item's condition still wears on every hit for every melee weapon,
as it did before. The edge loses 0.025 a connect, scaled by the same `condition_loss` the item wears
by, so twenty connects leave a fresh blade at 0.5. Damage multiplies by `SimItems.edge_factor`,
which keeps `EDGE_DAMAGE_FLOOR` 0.8 at fully dull. The floor is 0.8 and not the condition floor of
0.55, because the item's own wear already takes damage down to 0.55 and two floors compound to
about 0.30. A club has no edge and takes none. A blade that was never dulled has no `edge`
component and reads keen, so a save from before this piece loads unchanged and `SAVE_VERSION` does
not move.

Hone (`item.hone`, with `actor` and `item`) puts the edge at its ceiling and lowers the ceiling by
0.02, floor 0.5, the way repair lowers its own ceiling. Refusals come back as `not-a-blade`,
`keen` (already at its ceiling) and `no-whetstone`, checked in that order, so a keen blade keeps the
stone in the pack. One whetstone is spent per hone (docs/33 item 21 is the owner's call on that).

**Gate and stream.** The lanes live in `godot:m2:attach`, not `godot:m2:swipe`: swipe is the zombie
claw gate and its header pins the claw alone. Every roll is on the new `meleeWear` stream, and only
a part that declares `shedChance` or `lashed` draws from it, so a weapon with neither draws nothing.
STREAM holds that: a run of wear rolls moves `meleeWear` and leaves melee, swipe, ranged and test
where they were. CONNECT is the dead-socket lane: a real swing through the tick loop reaches the
roll. Broken on purpose, with the connect subscriber replaced by a pass, it goes red with "no nail
came out".

**A head with nowhere to land stays on.** `_fly_off` puts the head at the swinger's feet, and
a swinger with no position (nothing shipped swings without one) sends it down `detach`'s ladder
instead: the carrier's pack, the host's own tile, the host's container. The ladder runs before
the head is unlinked, and when it refuses the head stays fitted, so no path through a flying
head loses one. The LASH lane's FOOTLESS assertion holds it: a spear carried by nobody, lying
nowhere, swung by a body with no feet, keeps its head through two thousand rolls.

**The owner's pick, 2026-10-27.** JT answered the card on what a shed stud and a lashed
head do: the stud is gone, and the head drops at the swinger's feet as its own item. That is
the default this entry built, so no code changed for it. The whetstone's spend is still open
under docs/33 item 21.

**Measurement, 2026-10-27.** The full local `godot:m2` chain did not finish on 35cd8703.
Shard 1 of 4 passed. Shard 2 was killed three times by container restarts, at gates 16, 12 and
16, with no FAIL printed before any kill, so it was not re-run. CI's four-shard `godot-m2` run on
35cd8703 is green and stands in for it. `godot:m2:balance` printed its three FAST seed lines on
both trees but no `M2_BALANCE_OK`, for the same reason. Seeds 404 and 31337 match main exactly;
seed 20260805 moves by one grab and one staggered, which the shed studs and dulled edges explain.
Bench `--runtime-tick`, three interleaved runs per tree: shipped-tick mean 11.30 ms on main
against 11.34 ms on head, colony-tick mean 14.33 ms against 14.13 ms. Both fail the budget lines
the same way (docs/22's recorded debt), and head is within run noise of main.

## The bloodhound, 2026-10-27

Zombie kind eight, content only: `godot/content/zombies/bloodhound.json`, with no line under
`godot/sim/`. Where each number came from:

- **`sensory.noise` 0.** A sense of 0 is the deaf case, and `shambler.gd` already reads it as
  hearing nothing (`noise_sense > 0.0`). No sim line was needed.
- **`sensory.light` 0, which is the owner's 2026-10-27 call.** `sight_reach` is the observer's range
  times the square root of the light weight, so 0 gives a reach of 0, and `_seen_target` returns
  null at a zero reach. The lean toward a lamp (`_lean_to_light`) is weighted by the same number, so
  it is off too. Contact pursuit (`_contact_target`, `CONTACT_METRES`) is not sight and still
  catches a body that walks into it.
- **`sensory.scent` 1.0.** docs/14's tracker row reads "Extreme". The shipped top is the shambler's
  0.9, "High", and the schema's range is 0 to 1, so 1.0 is the first value above 0.9 the schema
  allows. The first cut is the ceiling, not a tuned number.
- **What 1.0 buys, and what it cannot (the review's finding).** `scentSense` is read in one place:
  the smell threshold, `scentFloor / scentSense`, which is 0.005 at 1.0 against the shambler's
  0.00556 at 0.9, a nose a tenth wider. The turn toward scent is `_drift_upscent`, weighted by the
  constant `SCENT_BIAS` (0.35) and never by the sense, and it runs only in the Wander arm, at
  wander speed. Seek is entered only through `heard` or a seen target; with noise 0 and light 0
  the bloodhound has neither, so it never Seeks and its `speed` 1.0 is used only in Pursue, after
  contact. So the kind that ships is a shambler without ears or eyes, a tenth keener in the nose
  and a quarter faster once it has you, not a body that walks a trail home (docs/14's tracker).
  That is the composing key the brief said to name if one was missing: a scent-led Seek, or a
  per-type scent bias, in `shambler.gd`'s think loop, which is sim work on a shared module and
  waits for its own piece ("The bloodhound's nose as a seek", docs/23's what's left). The
  SCENT-ONLY lane holds what was built; it does not claim the kind out-hunts the shambler.
- **docs/14's table against the content.** The tracker row reads noise Low, light Low, scent
  Extreme. The content is 0, 0, 1.0: deaf by the what's-left bullet's own words, blind by the
  owner's 2026-10-27 call. The table row is a stage behind the content until the sight card is
  taken.
- **Locomotion: speed 1.0, wander 0.35, mill 0.25, crawl 0.25.** Speed is the stalker's 1.0, a
  little above the shambler's 0.8. The rest are the shambler's, so the difference is what it
  follows, not how it walks.
- **Wave 3, weight 6.** docs/14 puts the tracker late, and wave 3 is day 7. The weight is the
  runner's, the kind most likely to change a night. Both are first cuts.
- **Look.** It reuses `body_zombie_workwear` and its corpses with its own tints. No picture is
  drawn, so it is a gap until the art arrives (docs/38's rule: pictures a stage behind).

Gates:

- `godot:m2:district` SCENT-ONLY. One body on a blank 24 m map, walking west, 120 ticks. A scent
  source 8 m east turns it east (dx +0.19 against -0.30 with no source). A noise 2 m west, with no
  scent, leaves it on exactly the path it walks without the noise, and the shambler control hears
  that same noise and seeks for 10 ticks. The lane also reads the spawned body's `noiseSense` and
  `scentSense` against the content. Broken on purpose: a content `noise` of 0.9 turns READ red.
- `godot:m2:roster`. MIX re-pinned on purpose. The day-7 sequence now covers eight kinds, so the
  pinned literal moved. The shipped-tree floor for shambler draws moved from 110 to 100 of 200: the
  shambler's share falls from 80 of 128 to 80 of 134, which takes its expected count from 125 to
  about 120, and a fixed 110 would fail a mix that is still what the content asked for. The HEAVY
  fixture now flattens the bloodhound to 1 as it does the other kinds. SHARES: 84 drawn against 90
  expected, inside the band. KINDS resolves it and its senses reach the component.
- `godot:check:appearance`. The bloodhound joins ROSTER, and ROSTER_SHARED puts it in a group with
  the shambler, since it draws the same file.
- Ran green: `godot:check:zombie_art`, `godot:check:worn`, `godot:check:authored`, `godot:validate`,
  `godot:smoke`, `npm test`, `format:check`, `check:routing`.

Balance, same machine, FAST band (four seeds, ten days): `M2_BALANCE_OK` on main (4fc24469) and on
this head. Every line matches except seed 404's grabs (163 on head, 160 on main) and the GRABS total
(360 against 357): the bloodhound arrives from day 7, and on that seed its grabs are the difference.
Deaths, survivors, kills, raids and breaches are unchanged on all four seeds.

The ten-seed table was not re-run. It is owed by the post-arc re-baseline.

- **The owner confirmed it on 2026-10-27.** Docs/33 item 20 was answered on its card: the bloodhound
  sees only at contact range, which is what this piece shipped with `sensory.light` 0. Normal sight and
  fully blind were the alternatives and are not built.

## How pieces reach main, and who reviews the art, 2026-10-27

A review of the playbook (docs/38) and of how threads are spawned, with three calls the owner took
on cards the same day. The changes are in docs/38's "How work flows".

- **Pieces built side by side merge one by one, each as it goes green.** The alternative that had
  been running was every piece on `main` and, once they conflicted, one integration pull request
  carrying all of them (#221 to #227, then #228 with 34 commits). That ran CI and the art review
  twice for the same work, and one blocker in the bundle held seven pieces. Most of the
  conflicts were the tails of docs/23 and docs/30, which a merge of `main` settles. An
  integration pull request stays for two pieces that conflict in code.
- **The coordinator spawns the art reviewer, from a fixed brief, and the reviewer makes its own
  shots.** The playbook had the reviewer check the thread's exports, briefed by the thread that
  made them, with the decisions so far: a brief that can steer what it is meant to check. #228's
  first round already shot the base and the head itself, which is what is now required. The
  report names both commits, and a push after the verdict voids it. A different model for the
  reviewer was offered and not taken: the independence is in the brief and the shots.
- **A piece that touches a shared sim module or the save format is built on the strongest tier.**
  Those pieces have broken at runtime after a clean merge (#205); they are few, and the full
  local chain was already the rule for them.

Taken without a card, as engineering: the thread that wrote a pull request never merges it; a
fix to someone else's open pull request is a pull request onto its branch, since a thread's git
proxy refuses any other ref (#230 onto #228); a confirmation pass after round 3 raises only
blockers; a thread's brief names the parts of docs/23 and docs/30 it needs, because neither file
can be read whole at the start of a piece.

**How to apply:** follow docs/38's steps 2, 4 and 5 and its art review paragraph. Model names stay
in the project's memory, never here.

## The bench makes parts, 2026-10-27

The melee arc's M1 piece (docs/23's record, "The bench offers improvised parts"). Calls taken
without the owner, all inside the screen the bench already had; the second then became the
owner's own:

- **Only an empty slot lists recipes.** The bench makes into an empty slot and swaps only what you
  carry, the rule `improvise` already enforces (`not-plausible` on a filled slot). Offering a make
  on a filled slot would mean the screen deciding to take the old part off first, which is a
  second command the sim never asked for.
- **The rows the survivor cannot make are listed,** dimmed, with what they need in words and no
  lit button. The owner decided this on 2026-10-27 (it was docs/33 item 22, put on a card with
  this as the default, and the default was taken). The alternative, listing only what can be
  made now (the pack menu's "absent, never greyed" rule), would be one filter in
  `SimGunsmith._recipe_rows`. A recipe the host could never take is not a row at all:
  that is the plausibility rule, not a missing material, and listing it would teach nothing.
- **Missing material names every kind that is missing.** The command still stops at the first
  (`no-material:<kind>`, which gates and events read), but a row that says "needs an ingot" and,
  once the ingot is found, "needs cordage" is a screen hiding half the answer.
- **The material words are a code-owned table, `SimFortify.MATERIAL_NOUN`,** beside the
  vocabulary, for the reason `SLOT_NOUN` is: content cannot see the kind list. Each noun reads
  after "needs" on its own ("scrap metal", "timber", "an ingot", "electronics").
- **Makeable rows first, then by name,** so at 1280x720 the column opens on what can be done now
  and scrolls to the rest.
- **The amber corner was left meaning "something you carry fits".** A makeable recipe does not
  raise it. Whether the corner should also mean "something can be made here" is a discoverability
  question for the art review or the owner, not a silent change of a settled mark.

**How to apply:** a new improvised part is a content entry with `recipe.kinds`, `fits` and
`appliesTo`, and the bench offers it with no screen change. A new material kind needs a noun in
`MATERIAL_NOUN`, or `godot:m2:bench` RECIPES goes red.

## Hone on the pack, 2026-10-27

The screen half of "Melee wear, 2026-10-27": the pack offers `hone`, and the inspect pane says how
keen a blade is, in a word.

- **The verb asks the command's own predicate.** `SimItems.hone` checked its refusals and spent in
  one function, so a menu could only guess whether it would work. Its checks moved into
  `SimItems.hone_refusal`, which spends nothing; `hone` asks it first and `verbs_for` asks the same
  function. The whetstone check reads the carried items rather than `needs.gd`'s private
  `_carried_base`, which is fenced for this piece. Offered worn or not: a knife in the hand hones
  as well as one in the pack.
- **The edge bands are first-cut words.** "keen" at 0.75 of the edge and up, "dulling" from 0.4,
  "dull" below (`SimItems.EDGE_BANDS`). They read the edge's current share, not its distance from
  the ceiling, because the word says how well the blade cuts, which is what `edge_factor` reads.
  Two consequences, accepted for now: a blade barely off its ceiling still reads "keen" while hone
  is offered on it (the stone is the player's to spend), and a blade honed down to the 0.5 ceiling
  floor never reads "keen" again, which is the honest state of a worn-out edge. At 0.025 a connect
  a fresh blade turns "dulling" after about ten blows and "dull" after about twenty-four.
- **One state line, two words.** The pane draws the edge word for a blade or the fuel word for a
  lamp under the condition, in the condition's shape ("edge dulling", "fuel guttering") and on its
  colour scale. No shipped item is both; the edge is asked first so a future one would still draw
  one line. Drawing it found `inspect_view`'s `fuel` undrawn: the word had been built and gated
  for the digit ban with no reader in `godot/ui/`. The STATE lane now asserts both.
- **No context-menu row.** `SimContext.verbs_at` lists what can be done to the thing under the
  cursor in the street; it lists nothing for a held item, so hone has no place there.
- **"burning steadily" became "burning well" (the art review).** At 1280x720 the lines beside the
  picture have 180 px, and "fuel burning steadily" is 210, so the lantern's commonest state was
  drawn as "burning stea..." the day the line landed. The word moved, not the layout: the picture
  well cannot narrow without cropping a long gun, and the four fuel words now read "dark",
  "guttering", "burning low", "burning well", every one inside the room with its label.
  `InspectPane.side_width` is the one measure `draw_pane` lays the column out with, and the STATE
  lane's FIT half holds every edge band and every fuel word (read off a real lantern walked down
  its tank) to it at 1280x720, red on the old word.
- **The warning words read at 4.5:1 (the art review).** "dull" and "dark" drew in `Locker.DANGER`,
  the rim and hazard rust, at 3.4 to 1 on the pane's steel, and so did the condition's "broken"
  and "barely holding" beside them. Both scales now draw their warnings in `Locker.DANGER_INK`
  (#e07a4f, 5.2 to 1 on the lighter grain), the bench's word rust moved onto the Locker so the
  two screens share one value; `DANGER` itself is unchanged for the rims. FIT measures every ink
  on the condition and state scales, and the dim label, against `Locker.STEEL_GRAIN`, red on the
  old colour.

**How to apply:** a new verb on the pack gets a refusal function its command shares, never a copy
of the checks. Retune the edge bands in `EDGE_BANDS` with the HONE and STATE lanes' fixtures.

## The plate wears, 2026-10-27

"A plate that degrades as it stops blows" (docs/23's record). Armour parts used to declare no
`wearsOn`, deliberately: `hit` fires on the swinger's weapon. "Melee wear, 2026-10-27" kept
`struck` free for the target's side; this piece makes it real. Four calls, all first cuts.

**Where the wear is called.** In `SimHealth.damage_part`, right after the integrity write, through
`SimHealth.wear_struck_armor`. Every path that hurts a body arrives at that closure (a swing, a
shot, a shambler's swipe on `attack.connected`; a bite on `bite.landed`), so the plate wears from
all of them and there is one call per blow, never per tick. The blow is softened first, so it
meets the plate at the condition it was in, and the next blow meets the plate this one left. A
blow to a dead body or a part already at zero returns before it, so it wears nothing.

**Bites wear the plate.** A bite comes through the same closure as a swipe, and teeth on a vest
are a blow on a vest. One consequence, accepted: `infection.record-bite` runs after
`health.take-bite` (same order, ids sorted), so the transmission roll for a bite reads the
coverage that bite left. The difference is one blow's wear, at most 0.024 of a ceramic plate's
condition, which moves the plate's multiplier by about a thousandth.

**What wears.** The garment that stopped the blow: the one with the most coverage of the struck
part *as fitted*, the way `armor_coverage_of` composes the same walk (max, never sum, the
2026-09-12 call), and it wears only when that coverage is above zero, so an empty carrier, which
`blocked_reason` already makes worth nothing, wears nothing. A lined jacket under a carrier does
not wear on a torso blow, because the carrier stopped it and the jacket never stood in its way;
pull the carrier's plate and the jacket is what stops the next one, so its lining wears. Two
garments at the same coverage both wear. The end review caught the first cut wearing every
covering garment, so a jacket's lining paid for blows it never met; the COVERS lane now holds the
layered case both ways. Inside the garment, only the parts whose own `armor` names the struck part
wear (a `covering` argument on `wear_parts`; the weapon channels pass none and are unchanged).
Without that filter a blow to the arm would wear the chest plate, which never stood in its way.
The garment's own condition does not wear: nothing reads it (`armor_coverage` reads the parts'
condition through `effect_scale`, not the host's), so wearing it would be a dead socket.

**The numbers.** On top of `PART_WEAR_PER_EVENT` 0.002 a blow: the ceramic plate `wearRate` 12
(0.024 a blow, about 42 blows to broken: "it does not forgive a second hit"), the steel plate 4
(125 blows), the riot visor 4 (125), the aramid lining 2 (250). The visor is included though the
plan named plates and linings: it is the fourth part that carries armour, and leaving one
armour part unworn would be a rule with an exception nobody could learn. A plate worn through
comes off (`_wear_one` detaches at zero) and the carrier then stops nothing, which is the rule the
carrier already had; the PLATE lane holds that half.

**Measured.** `godot:m2:balance` on `main` at bd4807cb (melee wear and the raider doctrine in) and
on this piece, same machine, and once before that on #233's head with the same result: M2_BALANCE_OK
both, and every FAST and ARMOUR line identical, digit for digit (seed 20260805 2 deaths, 404 5,
31337 1, 90210 3; the dressed arm a 28.0% cut on both). Nothing moved because no scripted colonist
in those campaigns wears a part that declares `struck`: the dressed arm's riot vest
(`check_m2_balance.gd`'s kit) has no `defaultParts`, so nothing is fitted to it, and the plates and
carriers are findable loot the scripted survivors do not fit. So the piece changes a run only once a
player fits a plate, and REACHED is the lane that holds that the wear is reached when one is.
`godot:bench:runtime`, six and six interleaved: shipped-tick mean median 13.89 ms base against 14.40
head, colony-tick 17.30 against 18.63, both inside the 1 to 4 ms run-to-run spread on this machine
(the base alone ran 13.03 to 15.57 and 15.46 to 20.91). The wear is a few dictionary reads per blow,
and blows are a few a second at most.

**How to apply:** a new armour part that adds coverage declares `wearsOn: ["struck"]` and a
`wearRate`; `godot:m2:attach` WEARS holds the word to the vocabulary, `godot:m2:armor` STRUCK,
COVERS and REACHED hold the call. The ten-seed table was not re-run; owed by the post-arc
re-baseline.

## A weapon you named, 2026-10-27

The last piece of the melee arc (docs/38, "The content arcs"; docs/23's record). The owner took
both cards: three or more rebuilt parts (docs/33 item 23) and a typed name (item 24). The calls
taken inside the piece:

- **The count is derived, never stored.** `SimAttachments.modifications_of` counts filled slots
  whose part is not the base's `defaultParts` entry. A factory part, a part swapped back to the
  factory one and an empty slot count nothing, so taking the nails out and putting a second set
  in is still one change, and stripping a rifle to the receiver is none. Nothing is saved for it.
- **Three, not four, and why the card went back.** The plan's default read docs/38's "past three
  modifications" literally. The wooden bat has three slots and only the steel pipe among the
  twenty melee frames has four, so under four the nail bat could never be named. The card was put
  to the owner again with that fact, and the owner took three. A knife has two slots and stays
  unnameable; that is the answer's consequence, not an oversight.
- **A name stays when the parts come off.** Once given, the name is the item's until the player
  clears it, even if the weapon is stripped below three. A name is not a status the parts confer
  and lose; `nameable` decides only whether the field is offered.
- **The component is `givenName`, not `named`.** "Named" already means docs/10's hand-authored
  tier (`SimItems.is_named`, `NAMED_TIER`, the base's `named` block). A second meaning on the same
  word is how a check ends up asking the wrong question.
- **The given name is the whole name.** `item_name` returns it in place of the base noun and the
  affix words: "Old Faithful", not "Sturdy Old Faithful". The bench header, which said the plain
  base noun, says the given name when there is one.
- **The predicate moved into the sim, and asks for a letter.** `SimItems.name_is_allowed` is the
  item-name clause's one predicate, and the gate's `_name_is_allowed` calls it. It used to read
  "not every character a digit", which let "4 2" through; a name needs a letter now. This narrows
  the clause, and no shipped name changed (the DESCRIPTION, STRIP and INSPECT lanes are green).
- **The field is drawn, not a `LineEdit`.** The sheet is one drawn Control, the router reads keys
  in `_input` before any GUI focus could, and a themed `LineEdit` would have needed its own
  styleboxes and font override outside `Chrome`. So the field is the panel's own state (text,
  caret), drawn by `InspectPane.draw_field` in the chrome font at the title's ladder size (a rung
  down when the name is wide, scrolled so the caret shows), fed by `InputEventKey.unicode`, which
  the web build delivers too. No IME composition: a typed name is plain keys.
- **The field takes every key while it is open.** `input_map.gd` hands it every press, echoes
  included, before its own table: W types, Tab and the number row type or do nothing, Escape shuts
  the field and not the sheet. Up and Home put the caret at the start, Down and End at the end.
  A click outside the field puts it down unsent, the same as Escape; a click in it moves the
  caret. Ctrl alone and Cmd are shortcuts and type nothing; Alt types, because Option and AltGr
  are how a Mac and a Polish or German keyboard type é, ł and €.
- **Letters are what the face draws.** `SimItems.name_char_allowed` is a fixed list (Basic Latin,
  Latin-1, Extended-A, the euro, the dashes, the curly quotes, the ellipsis), not a font query:
  the sim reads no fonts, and a command or a save is held to the same rule as the field. Beyond
  it the engine's fallback draws Cyrillic in a smooth face that breaks the pixel look, and on the
  web build, which has no system fonts, an emoji is a box.
- **A given name is a proper noun in a sentence.** `SimItems.the_item` hands a sentence "the
  hunting rifle" or "Old Faithful", never "the old faithful", and every line that put an item in
  a sentence by lowering `item_name` asks it instead.
- **Enter asks first.** The field calls `SimItems.name_refusal` before it sends, says a refusal on
  the title bar in words, and stays open with the text in it. The command checks again.
- **The cap shows by refusing.** 24 characters (`NAME_MAX`). No counter, because a counter is a
  digit on the sheet. A name prefilled over the cap (a rolled weapon's affix words) starts the
  field empty rather than starting it already refused.

**Not measured.** Off the tick path; no NPC and no scripted campaign names anything. The ten-seed
table was not re-run.

**How to apply:** a screen that shows an item's name reads `SimItems.item_name`, never the base's
`name`, so a given name reaches it. A new check of the item-name clause calls
`SimItems.name_is_allowed`, never its own copy.

## Furniture decides the seat, 2026-10-28

The firearms arc's furniture piece (docs/23's record, "Furniture decides the seat"). The arc named
the shape: a folding stock fires from the car and a full stock does not. Two calls were taken inside
it, and both are first cuts a card can reverse.

- **Aim time and recovery were already read from furniture.** The stock and the foregrip fold
  `handling` into the same clock the ladder reads, so no reader was added for them. What the lane
  adds is the proof: a bare receiver and the standard stock sit at the old 11 ticks up and 11 back
  on the pump shotgun, the folding stock at 8 and 8, the foregrip at 10 and 10.
- **The seat is the weapon's to allow.** A seated body may fire only a weapon whose fitted parts
  declare `fireFromVehicle`. Taken as a call: a bare receiver is refused from a seat too. The arc
  names only the full stock, but a receiver with no stock at all is not a folding stock, and the
  refusal cannot be read as a stock refusal without a stock to refuse. Reloading from the seat stays
  allowed, because the rule is about firing.
- **Any vehicle counts, not only a cab.** A rider on a bicycle is refused the same as a driver in a
  car. The arc said "the car"; the mount is what the code can see, and a cab-only rule would need a
  second reader for the same fact.

**Why:** the seat is the one posture a stance does not name, so it needed a reader of its own. The
rule lives in the weapon's content, not in a per-weapon branch.

**Not measured.** The numbers are first cuts and were not re-tuned; no body or kind changed, so the
ten-seed table was not re-run. Gates: `godot:m2:aim` FURNITURE and READERS, `godot:m2:stance` SEAT.

**The clocks are item-scoped (the affixes thread asked, 2026-10-28).** Settle, recovery and reload
each read their item's share (`steady_ticks`, `recover_ticks`, `reload_ticks`, scoped over unscoped,
the `noise_emission_of` division) and the ladder reads it live, not from a profile field, so a
modifier takes effect without a refit. The three names are in `ITEM_SCOPED_READS` and registered in
`modifiers/stats.gd`, floor 0.1 like `swing_speed`. A bare gun's clocks are unchanged.

**How to apply:** a new part that should change what a seat allows declares it under the attachment
block, and the reader is `SimAttachments.fires_from_vehicle`. A new refusal for a seat goes through
`SimStances.seat_refusal` and the sentence in `SimAttachments.refusal_clause`, never a second check.

**The key is asked for, not assumed (end review, 2026-10-28).** A profile restored from a save
written before `fromVehicle` existed has no such key, and nothing rebuilds a profile until an equip
or a wear event, which a refused trigger never raises: a folding stock would have been refused its
seat for the rest of that run. Both seat readers, the trigger and the sentence, now go through
`SimAttachments.from_vehicle_of`, which reads the key when it is there and asks the fitted parts
once and writes it back when it is not. `godot:m2:stance` SEAT erases the key before the trigger
and holds the folding stock to firing and the full stock to its refusal.

## Internals wear, and the jam derives from them, 2026-10-28

The firearms arc's F3 piece (`planning/2026-10-28-firearms-readers.md`, section F3). Calls taken in
the piece, so a later reader can see why they are shaped this way:

- **Three slots, not one.** A slot holds one item, so the spring, the sear and the extractor each
  got a slot name (`spring`, `sear`, `extractor`). Every firearm base that defaults an action
  defaults all three, and the action keeps the name `internal`.
- **A worn-through internal stays fitted, and the gun is refused.** A barrel or an action at zero
  detaches, and a gun without its action stops, because `internal` is a required slot. A spring,
  sear or extractor cannot follow that rule: it is not required, so a detached one would leave
  `assembly_condition` and the gun would jam *less* for losing its sear. These three declare
  `staysWhenWornOut`, sit at zero and read "broken". The piece first had them jam on every pull;
  the end review's fix PR made a worn-through internal block the weapon instead,
  `SimAttachments.blocked_reason` answering `broken:<slot>` the way a missing action answers
  `missing:internal`, for two reasons the gates now hold. A jam is only a stoppage on a base whose
  content says it jams, so the revolver (`jams: false`) and any gun with a match action fitted
  fired on a dead sear for `assembly_condition_factor` 0.0: a round spent for nothing, and nothing
  said. And `SimRanged.can_fire` reads only `blocked`, so npc_combat gave a gun jamming on every
  pull its full envelope and walked a colonist into range of it, the open circuit docs/37 keeps
  finding. Refused, the gun fires nothing and spends nothing, the HUD's refusal sentence names the
  part that is worn through, the NPC envelope is zero and the colonist falls back to melee, and the table's
  "broken" row (1.0) stays total without any pull reaching it. `detach` still takes one out.
- **The mass is split, not added.** The old action weighed 0.20 kg with its springs and sear inside
  it. The action is now 0.12 kg, the three parts make the other 0.08 kg, and the tuned action, match
  action and magnum cylinder (which replace the action in `internal`) drop by the same 0.08 kg. An
  assembled firearm weighs what it weighed; `godot:m2:attach` MASS holds that number.
- **The parts are findable.** They sit in the `tables.json` parts bin beside the action, at weights
  4, 3 and 3. Findability is a gate rule (`godot:m2:attach` CONTENT), not a choice.
- **The band words read the assembly.** The inspect view and the grid view band an item by its
  assembly condition, as the jam already did, so a gun with a failing sear says "failing" and jams
  at the failing rate. Before this, the screen read the receiver alone and called a jamming gun
  sound.
- **The bench's key moves to the top row.** Three more slots put a second row of plates under a
  firearm's picture, and at 1280x720 the bench had no room left under the assembly for the key to
  its amber corner ("something you carry fits"), so `layout` placed it nowhere and the BENCH lane of
  `godot:check:play` went red at both windows. The key now takes the top row's free left cell, level
  with the sight's plate, on any weapon with a sight or optic over its picture, and stays under the
  assembly on a weapon with no top row. Which rows the weapon has decides it, never the window, so a
  rifle's key is in one place at both sizes rather than jumping when the window shrinks. A fourth
  column was the other way out and was turned down: at 1280x720 it leaves the candidates column a
  hundred-odd pixels wide. The BENCH lane now also holds the key inside the frame and clear of every
  plate (with the tape that hangs over its top edge), the picture, the column and the footer, its
  judge proved first on rects laid over the sight's plate, its tape's reach and the picture; and the
  same rifle with its sight taken away draws the key clear under the assembly, so the other branch
  has a reader too.
- **Not done here.** The named break-action (`item.named.deer_rifle`) has never had an action
  defaulted, so it gets none of the three; giving it internals is a content decision for the owner
  of that base, and it is not in F3's list.

**Why:** the owner's arc rule is that every number is a sum of the gun's parts, and a jam that
follows a part the player can see worn is the readable half of that rule. A jam chance that did not
move with the internals would be the dead-socket pattern docs/37 warns about.

**How to apply:** a new internal part declares `structural` and `staysWhenWornOut` and a `wearsOn`
list, and its slot goes on every base that defaults an action. A new internal that replaces the
action declares its own mass against the 0.12 kg action so an assembly keeps its weight.

**Measured.** The FAST tier of `godot:m2:balance` passes on c119866e: four seeds, ten days, the
shipped district. Survivors alive on day ten were 2 of 3 on 20260805, 1 of 3 on 404, 3 of 3 on 31337
and 1 of 3 on 90210, with 2, 5, 1 and 3 deaths. No before run on main was taken for this piece, so
the numbers are the after only; the gate asserts the bands and the placement sets, not the counts.
The internals change every spawned gun, so a before-and-after on the same driver is the number a
later balance piece should compare against.

## The ranged affixes, partly, 2026-10-28

The five ranged prefixes docs/10 names were planned as one data edit. Two of them are. Calls taken:

- **Two ship, three wait.** Trued (accuracy) and Blued (condition loss) are authored. Ported
  (recoil), Chambered (reload time) and Heavy-barrelled (weight and steady time) name effects that no
  stat carries, and Blued's "resists wet" has no stat either. Authoring them would need a new stat,
  and the batch plan said no new stat. So they wait for the owner's or the coordinator's call on
  adding stats, and docs/23 names them.
- **The split, coordinator call 2026-10-28.** No stat is added in #250. F4 (furniture as ergonomics)
  adds aim time, recoil recovery and firing stances now, so recoil and steady time become F4's stats.
  After F4 merges, a second PR off main adds Ported, Chambered and Heavy-barrelled on F4's stats, plus
  a reload-time stat if F4 did not add one. Blued's "resists wet" stays an open line in docs/23.
- **The gun's own accuracy is read through the item.** `ranged_accuracy` resolves on the shooter, so a
  barrel's Trued could not move the cone. `SimItems.accuracy_of` is the item's share of it, the same
  division `noise_emission_of` and `condition_loss_of` already do, and `_refresh_cone` multiplies it
  beside the shooter's value. A bare gun reads exactly 1.0, so no gun without an affix changes.
- **A stat with no item reader is refused by name.** `SimItems.ITEM_SCOPED_READS` lists the stats some
  reader resolves through an item's scope, and the RANGED lane fails any ranged prefix that moves
  another. It is a list a person grows with a reader, not an inference from the code.
- **The roll pool grows.** A ranged roll can now draw Trued or Blued, so the RNG draws for a modified
  or field-tested gun change. The FAST tier of `godot:m2:balance` judges that in the chain.

**Not measured.** The ten-seed table was not re-run. The change is off the tick path except the cone,
which is a no-op for a bare gun.

**How to apply:** a new affix on a stat that is not in `ITEM_SCOPED_READS` is refused by the gate
until a reader that reads it through the item exists and is gated to move.

## The oracle stat registry mirrors content stat ids, 2026-10-28

The frozen oracle's stat registry (`src/sim/modifiers/stats.ts`) takes the stat ids the shared content
can name, and nothing else. The content JSON is read by both runtimes, so the oracle's Ajv check has to
know every id a content file uses, or the oracle goes red on a content edit that is correct for Godot.
Call taken by the coordinator, 2026-10-28: register the ids, with their base and min, and no behaviour.
The sim logic is still never ported into the oracle. The three clock ids (`steady_ticks`,
`recover_ticks`, `reload_ticks`) are the first mirrored this way. The next affix PR that names a new
stat id registers it the same way.

## The ranged affixes, the rest of them, 2026-10-28

Ported, Chambered and Heavy-barrelled ship on F4's stats, per the coordinator's split. Calls taken:

- **Clocks, not stats of the gun.** Ported moves `recover_ticks` (the recovery after a shot) and
  `noise_emission`; Chambered moves `reload_ticks`; Heavy-barrelled moves `ranged_accuracy` and
  `steady_ticks`. Each is an item-scoped share read live by `ranged.gd`, so no rung is cached.
- **Double-edged where the docs give a cost.** Ported's faster recovery comes with more noise.
  Heavy-barrelled's accuracy comes with a longer settle. Chambered has no drawback in docs/10, and none
  is invented.
- **Weight is not a stat.** Heavy-barrelled's "more weight" would need an affix to move the profile's
  `weight`, which no affix path does. It is left out, not faked, and docs/23 names it.
- **Rounding is the rung's own.** At 4 settle ticks and 8 recovery ticks, a tier moves a rung by a tick.
  That is what the clock is; the balance table is where its reading is judged.

**Gate fixes carried from #250's review.** `_carrying` puts a prefix id in the prefixes list, as a roll
does. The refusal lane now tests `mood`, a declared stat no reader resolves through an item, instead
of the undeclared `reload_speed`.

**How to apply:** a new ranged affix moves a clock or a share that F4's readers resolve through the item.
A stat outside `ITEM_SCOPED_READS` is refused until a reader that moves it through the item is gated.

## The colony tick, without changing outcomes, 2026-10-28

Piece P4 of the nail-survival batch (`planning/2026-10-28-nail-survival.md` in the project files).
Three costs were named: the stockpile list asked about ten times over, the long job plan run whole
on one tick, and the 480 to 600 ms worst ticks of the day-one playtest logs. The calls taken:

- **The day-one spike was the walls box, not a plan.** A per-system driver over a whole day one on
  seeds 99 and 404 found every spike over 200 ms on one colonist in `jobs.ai`, on Retreat, with one
  short path find under it (0.6 to 2.9 ms). `_retreat_inside` asked `_inside_walls` once per tile
  of the lot, and each ask read every tile of the lot again to find the box the walls draw: about
  700 tiles squared, 206 to 222 ms on a quiet container, on the tick a walk home ran past
  `RETREAT_WALK_TICKS`. Under the playtest's parallel load that is the 480 to 637 ms in the logs.
  The box is now found once per call (`_walls_box`), which is the same answer by construction.
- **The box is kept on the world, checked against the whole tile array.** The danger rules asked it
  for every colonist in the lot every tick, 0.33 ms a reading. `_walls_box_of` keeps it in
  `world.walls_memo` and hands it back while the map is the same object, the lot is the same rect
  and `map.tiles` equals the copy it was built from. The box is a function of exactly those three,
  and the compare is one native call (0.003 ms a reading). A generation key was refused: gates edit
  `map.tiles` without bumping it.
- **The stockpile list is kept across ticks, checked against everything it read.**
  `SimNeeds.stockpile_items` keeps its answer in `world.stockpile_memo` and hands it back while the
  map's generation, tiles, indoor flags, overlays and anchors, the player, the zone record, the
  position, item-base and `stored` membership counts (`SimComponentStore.changes`, new) and the
  tile under every loose item are what they were. The last check is per item, so an item moved in
  place or by a replaced position is a miss, not a stale answer. That check is most of a hit's
  cost (0.16 ms against 1.4 for the fresh list with 272 loose items), and it was kept on purpose:
  an audit of every writer of an item's position was the alternative, and the next writer would
  not read the audit. `STOCKPILE_MEMO` off answers fresh every time.
- **The long plan was not split across ticks.** After the walls fix, the same day-one driver shows
  no job plan in the worst ticks: `jobs.ai` peaks at 22 ms once over two day-one runs under load, and the
  worst ticks left are a whole cast, one shambler pass or the scripted survivor's own walk-to plan.
  A split also changes outcomes: a body stands still while its plan finishes, and the plan that
  matters most is the walk home from a zombie, where a few ticks of standing is a bite. So it stays
  open in docs/23 with this measurement, for when a quiet machine says plans are the worst tick.

**How to apply:** a reader that asks the walls box for many tiles takes `_walls_box_of` once and
asks `_in_walls_box` per tile. A new memo here is trusted only while everything it read is
unchanged, and its lane in `godot:m2:tick` changes each of those things under it.

## The round you load, 2026-10-28

Piece F2 of the firearms readers batch: docs/23's "Choosing which round to fire" and "The magazine
remembers what you loaded", landed together because they share one record. Before it, a reload
refilled a counter, every shot drew its round from the pack, a magazine held whatever the pack
held, and the only way to fire a slug was to carry nothing else.

- **The record lives on the weapon item, not on `rangedWeapon`.** docs/23 named the `rangedWeapon`
  component as the home. That component sits on the actor: it is rebuilt from the item on every
  equip, removed on every unequip, and replaced without an unequip when a gun is drawn over another
  in the same hand. A choice stored there is forgotten the moment the rifle is slung, and rounds
  stored there vanish with it. So the weapon item carries `loaded {rounds, choice}`: `rounds` holds
  round base ids in firing order, the next shot first, and `choice` is a round base id or "". It
  rides the item through a holster, a drop, a dead raider's kit and a save, and it is still the
  item's own component, not a `{weapon: round}` side table. A fixture's weapon with no item keeps
  the same keys on its profile; `SimRanged._record` is the one place that decides. The live
  `mag` on `rangedWeapon` is kept equal to the record's size for the readers that count it.
- **One reload rule.** A reload empties the magazine back into the pool, then fills it from the
  pool: the chosen round first, the round the weapon prefers next, the rest by base id, until full
  (`SimRanged.planned_load`). Only the difference moves through the pack. That one rule is a
  top-up when nothing changed, a switch when the choice did, and a mixed load when the chosen round
  runs short (two slugs, then buckshot). A round that no longer chambers (a conversion since it was
  loaded) is not in the pool, so the next reload puts it back in the pack, and a pull with such a
  round at the front reloads instead of firing. Rounds that come out go onto a matching stack,
  then anywhere the actor can stow them, then at their feet. A reload that would change nothing is
  refused; it used to be allowed on a full magazine and cost a reload for nothing.
- **A round keeps its tier through the gun (the end review's finding).** The first cut stored base
  ids only, so buckshot loaded from a modified stack came back out of a switch as scavenged, and a
  reload could launder a worse round into a better one or the other way. The record now carries
  `tiers` beside `rounds`, in step: a round taken from the pack records the tier of the stack it
  came off, a shot pops both, and a reload returns the rounds it removes as stacks at their own
  tiers, keeping the rounds it leaves in with theirs. A record from before this (no `tiers`) reads
  every round as scavenged, the stack default. `godot:m2:ammo` TIER: modified buckshot swapped out
  for slugs comes back modified, and the slugs keep their own tier; red with the tier dropped on
  the way out.
- **Switching loads costs the reload.** The sheet's `load` verb on a round sets the choice and
  starts the reload; the magazine changes when the reload ends, not when the verb lands. If the
  reload cannot start (mid-aim, grabbed, a part missing) the choice stands and the next reload
  honours it.
- **A bow only remembers.** A bow (`magSize` 0) has no magazine: it nocks from the quiver on every
  shot, as before, and `load` on an arrow sets which one it nocks next.
- **A found gun holds a few rounds (the owner's call).** Built first as empty, the default of
  docs/33 item 26; the owner chose a few rounds on 2026-10-28. A gun a loot table rolls, on a shelf
  at boot or in a cupboard opened later, gets one to a third of its magazine, rounded up and five
  at most (`SimRanged.FOUND_MAX`), all of its preferred round at the stack default tier
  (`SimRanged.load_found`, called from `SimLoot.roll`, the one place both paths roll). These rounds
  are new to the world, which is the point of the call. The card said "rolled on the loot stream";
  they roll on their own stream, `foundRounds`, because a draw on `lootTable` would move what every
  later shelf in the district holds, and the call was about the gun, not the shelves.
  `godot:check:loot` FOUND holds the range, the round, the tier, the stream, the negatives (a bow,
  a knife, a stack of rounds) and that a found pistol fires its own round with nothing in the pack.
  A gun that is not rolled from a table (a gate's fixture, a boot kit, a trader's) has no record
  and arrives empty; the first trigger pull reloads it from the pack. A raider arrives loaded from
  their own kit (`SimRanged.load_held` at spawn), so a band's first shot is where it was, and a dead
  raider's gun keeps what was left in it.
- **Older saves load empty, with no version bump.** A v33 save has no `loaded` anywhere: every gun
  in it loads as an empty magazine with no choice, and the old counter is not trusted, so the first
  pull reloads from the pack, which holds every round the counter only pretended to.
- **The screen says what is loaded, in words.** The inspect pane's one state line, after edge and
  fuel: "load empty", "load slug" when every round in it is one kind, "load mixed" when not. The
  word is the round's content `ammo.word`, a short word with no digit, because a round's `name`
  may carry a digit under the one amendment and this line may not. `word` is required by the
  item schema, and `godot:m2:ammo` WORD holds every round to a word, no digit, and no two rounds of
  one caliber sharing one. "empty" draws in `Locker.DANGER_INK`. Nothing reaches the HUD.
- **"mixed" names no round, and the words are short (the shots).** The line beside the picture has
  180 px at 1280x720, about eighteen letters with the label. The first cut said "slugs, then
  buckshot" and was drawn "slugs, then..."; plural words like "standard rounds" and "broadhead
  bolts" did not fit either. So a mixed magazine reads "mixed" (the player chose the round, and
  "mixed" says it ran short), and the words are the trade's short ones: "ball" (9mm, .45),
  "standard" (.38, .22), "soft point" (.308), "buckshot", "slug", "birdshot", "hollowpoint",
  "subsonic", "match", "surplus", "+P", "bolts", "broadheads", and for arrows, which no magazine
  holds, "arrows" and "target tips". STATE FIT in `godot:check:inventory` measures every word
  read off the content, red on the first cut.

**Not measured here.** The ten-seed table was not re-run in this piece. What moves in a campaign:
a found gun now brings a few rounds of its own (more ammunition in every run, the owner's call), a
gun keeps its rounds when it is put away, and a gun from a fixture spends one reload before its
first shot. The FAST tier of `godot:m2:balance` judges it in the chain; the ten-seed re-run the card
named is handed to the balance thread, after the run already going on main.

**How to apply:** a reader of what is in a gun calls `SimRanged.rounds_in` or `load_words`, never
`rangedWeapon.mag`. A body that should arrive with a loaded gun calls `SimRanged.load_held` after
its kit. A gate that fires a gun it has just armed loads it first (`load_held`), or its first pull
is a reload.

## A closed house at dawn, 2026-10-28

**The call.** The day-one wipe is the alpha blocker, and P1's diagnosis put 125 of 130 colonist
bites on days 1 to 3 inside the house, from the south gap, plus two run-ending player bites from a
boot wanderer placed 2.5 m and 4.5 m from the lot. Two fixes, no owner card: the gap is closed, and
the boot keeps the dead out of a ring round the annex.

**The correction to P1.** The annex's south gap was not doorless. `_write_doors` doored both gate
anchors and left the third tile of the gap (local x 14 on row 19 of `district_alpha.json`) as
floor, so the gap was two doors and one open tile. Probed on 87750e3a at 256 on seeds 2024, 404 and
99: the wall row reads Window, Door, Door, Floor, Window on all three. The fix is a bug against the
Doors decision of 2026-09-07 (the gate is a door, and the dead never open one), not a new rule.

**Why it is in `_write_doors`, not content.** The generator stamps the annex from a template, and a
content edit would fix one template and leave the next. `SimWorldgen.gate_gap` walks the row from
`gate_a` towards `gate_b` through floor and door tiles, and returns the run only when wall-line tiles
(Wall, Window, Screen) close both ends. An open end, a road or a run with nothing to close it is left
alone. The gap stays three tiles wide, all doors, so no one-tile doorway is made and the deadlock of
two walkers in one (2026-09-07's note on the doorway) does not return.

**Why the gap is doored after the dressing, not in `_write_doors`.** The first cut doored it with
the gate anchors, before the dressing, and the review's side-by-side boot of main and the branch
found every map's trees, thickets and grass moved, at 64 as much as at 256, on every seed sampled
(about fifty tiles at 64 and two to three hundred at 256; on seed 8080 at 64 a tree landed under a
wanderer's roll and moved the wanderer too). The cause is `_dress_terrain`'s grass pass, which
draws one jitter from the `terrain` stream per outdoor Floor tile and warns in its own comment that
a tile taken out of that walk shifts every tile decided after it: the gap's third tile was one such
Floor, and a Door written before the dressing took its draw away. `_door_the_gap` now runs at the
end of `generate`, after the dressing, where the tile is still the Floor main dressed around (the
annex's reserve is protected, so nothing is ever planted on it). Checked by hashing `map.tiles` and
every positioned entity on main and on the branch at 64 and 256 on seeds 20260805, 8080 and 2024:
the one tile that differs on any of the six maps is the gap's third, Floor to Door.

**Why `BOOT_CLEAR_METRES` is 10.** A first cut from P1's table: the two bites came from boots within
5 m of the lot, and 10 m is twice that, which clears the rolls P1 measured without tuning to any
seed. It is a number to measure against, not a balance claim. The ten-seed table on the merged main
is the test.

**Why the ring applies only where it fits.** The scatter draws from a 48x48 box at 64 and a 240x240
box at 256. The grown annex is 46x46. At 64 that is 92% of the box, so the ring would re-roll nearly
every draw and the 64 boot would stop being the one every gate measures. The ring applies only when
the grown rect covers at most half the box: at 256 it covers under 4%, at 64 it does not apply, and
the 64 wanderers stand where they stood (checked by hash of their positions on main and on this
branch, ten seeds; entity ids move, positions do not, because the door entities spawn before the
scatter).
The annex refusal stays hard: a try inside the annex is never placed. When every try lands in the
ring, the first try outside the annex is placed, and the try count stays fixed so the campaign is a
function of its seed.

**What moved.** The wanderers of every 256 world: the re-rolls change the `placement` stream's
draw count. Nothing else: every map's tiles but the gap's third, every colonist, station, item and
dormant body, and every 64 wanderer are where main put them (the hashes above). The ten-seed table
re-runs on the new main once P2 and P3 have both merged, and the 87750e3a row is the "before".


## The hand-loaded round, 2026-10-28

Piece B2 of the 2026-10-28 batch: docs/09's "late-game hand-loading is possible and produces worse
ammunition: reduced power, higher jam chance", the one ammunition promise the slice could not
express. Card 27 (what a hand-load costs and where it is made) was posted with its default built;
JT then picked option B, spent brass, which piece B3 carries (docs/33, card 27). The calls taken here,
each recorded because each one could have gone the other way:

- **The misfire is added to the band, never multiplied.** `ammo.misfire` is a chance a round adds to
  the weapon's jam chance in `SimRanged._jammed`. A multiplier on a sound gun's band of 0.0 is still
  0.0, and a hand-load has to bite a sound gun, so a round's misfire is the one adder in the ammo
  block. A round never lowers the chance, so the coupling from "The round you load" holds: a weapon
  the screen calls "failing" jams at least at that band's rate. A factory round has no misfire, so a
  sound gun on factory rounds draws nothing from the `ranged` stream, as before.
- **`jams: false` holds.** The .38 revolver never jams, so a hand-load in it never misfires. The
  .38 hand-load is shipped anyway, because the caliber is chambered and the recipe is content; its
  misfire is simply not read by a gun that does not feed.
- **No rimfire hand-load.** Rimfire cannot be reloaded: its priming sits in the rim, so the case is
  spent once. The .22 has no recipe and `handload_refusal` answers `no-handload`. No arrow or bolt
  hand-load: the brief covers centrefire firearms only.
- **First-cut numbers.** Each hand-load is `damage` 0.85 and `cone` 1.15 over the factory round and
  `misfire` 0.03. The recipe is one ingot and one charcoal for a yield of 6 for 9mm, .38 and .45, 5
  for rifle and 4 for 12g. These are first cuts that no balance run has measured.
- **Last in the fallback order.** With no choice, a weapon reaches for every factory round of its
  caliber before any hand-load of it, in `SimRanged._fallback_order`, which `_pick_round` and
  `planned_load` both use. A player who chose the hand-load gets it. A content round with no recipe
  sorts as it did, so no existing magazine or pick moves.
- **The predicate, in order, and nothing spent on a refusal.** `handload_refusal` answers
  `not-a-firearm`, `not-carried`, `no-handload`, `no-bench`, `needs:<kind>` and `no-room`, and the
  menu's verb and the command both ask it. `no-room` is asked of the pack without moving anything: a
  stack fits a carried stack of the same round with room, or a free cell in a container the actor
  reaches. The command stows the rounds before it consumes any material, so an answer that was
  wrong costs nothing but a refusal.
- **The menu and the command can disagree about room.** `no-room` is a predicate, not the stow
  itself. If the two ever disagree, the command refuses with nothing spent, but the menu may have
  offered the verb. The gate does not exercise that disagreement; it is named here so a later
  reader does not take the predicate for a guarantee.
- **The gates.** `godot:m2:ammo` holds MISFIRE, WORSE, RECIPE and ORDER, and the CONTENT lane's
  findability rule, which accepts a hand-load a shipped gun chambers and still refuses a fabricated
  round with no recipe and a hand-load for a caliber nothing chambers. `godot:check:inventory` holds
  HANDLOAD: the verb is offered only with a bench and the materials, and the pane's button makes four
  12g hand-loads and spends the ingot and the charcoal. Every verb button sits inside the pane at
  1280x720.
- **No `SAVE_VERSION` bump, and no new component.** A hand-load is a stack of an existing kind of
  item; the magazine record is unchanged. `godot:m2:save` is in the chain and unchanged by it.
- **No new stat id.** Neither `misfire` nor `handload` is a stat, so the oracle's registry in
  `src/sim/modifiers/stats.ts` is not touched.
- **Refusals are published, not worded.** `item.handload_refused` carries the reason; the panel does
  not yet say it in words, the same as `item.load_refused`. Naming the refusal on the screen is a
  follow-up, not this piece.
