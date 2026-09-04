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
  look" below returns to a feet-anchored upright pawn, on a 32×48 canvas this time.)*

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
competing with it.

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
  sort returns.
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
  rebuild.

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
10. "Rain is ambience" — unchanged.
11. "The ground is a texture whose mean is the palette" — stands, extends to the edge sheet.
12. docs/00's depth-sort reversal — not reopened; the entity sort was always there.

**What ships today versus what is decided** is the distinction every reader of this entry needs:
the palette, pawn and wall slices landed the same day (their clauses close this entry), so the
table is warm, every body is a face-on pawn that flips, and a building draws its walls thick
and its roof where the survivor cannot see; the edges, the trees, the worn look and the
vehicles are still the old code, their comments say so, and each moves with its own slice.
Anyone reading a comment that describes the old direction should read this entry before
"fixing" it in either direction.

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

---

**Previous:** [23 — Roadmap](23-roadmap.md) ·
**Next:** [31 — Godot Rebuild Roadmap](31-godot-rebuild-roadmap.md) ·
[Doc index](../README.md#documentation)
