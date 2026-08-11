# 28 — Visibility & Sightlines

*Why this exists: three systems need the same answer to the same question — can this observer see
that thing? The [light channel](03-attention.md#three-channels) needs it, the renderer needs it and
has never once asked, and [multiplayer](27-multiplayer.md) cannot ship its filtered view without it.
Answered once, it is a primitive. Answered three times, it is three subtly different bugs, and one of
them is a cheat.*

---

## What is built

The **primitive is built** — occluder classes, symmetric shadowcasting, arcs, the
recompute-on-change cache, and the renderer occlusion that closes the wallhack below. Its three
consumers are not all built: the renderer is, the light channel is not, and multiplayer is a
milestone away. What follows is still the specification; this section is the running tally.

| Piece | State |
|---|---|
| Occluder classes, opacity and solidity as two properties | **Built** — `src/sim/map/tilemap.ts` |
| Symmetric recursive shadowcasting, integer-only | **Built** — `src/sim/vision/shadowcast.ts` |
| Focal and peripheral arcs, nothing behind | **Built** — `src/sim/vision/visibility.ts` |
| Recompute on change, not on tick | **Built**, and measured: 690 shadowcasts across 600 ticks with 51 observers |
| Renderer occlusion | **Built** — 11 bodies drawn where 216 were in the viewport |
| Last-known position memory | **Half** — the renderer fades a mark where a body was last seen; the simulation has no per-observer memory and no prose yet |
| The light channel | **Not built.** Next |
| Zombies reading light | **Not built** — arrives with the channel, so sight and its one new stimulus land together |
| The multiplayer filtered view | Milestone 3, unchanged |

Three things were learned building it, and they are recorded where they contradict something:

- **Sight is a bigger change to how the game reads than to what it costs.** In a 2,000-body
  district the survivor sees 11 bodies where the renderer used to draw 216. The
  [open question](23-roadmap.md#open-questions) that produced is whether a district you cannot
  see is tense or merely opaque, and it needs a human at a keyboard.
- **Turning is free and walking is not**, which is the opposite of the intuition the arcs
  suggest. Arcs are a dot product evaluated per query; the shadowcast is cached per *tile*. So
  an observer spinning on the spot costs nothing at all, and one crossing a tile boundary pays
  the whole thing.
- **The frame benchmark now guards drawing less than it did.** Occlusion removed 95% of the
  entities it was measuring. That is the second time a mitigation has weakened this benchmark —
  [viewport culling was the first](22-performance.md#the-ci-benchmark-suite) — and it is
  recorded rather than quietly accepted.

## The wallhack was shipped, and is not any more

Honest disclosure first, because it is what this document was for.

`src/render/renderer.ts` drew every entity inside the camera viewport. It did not ask whether
there was a wall between that entity and the survivor, because nothing in the codebase had ever asked
what a survivor could see. In single-player that is a mild cheat against
[clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) — you are told where the
bodies are through a building, which is exactly the uncertainty the clause exists to protect.

In [multiplayer](27-multiplayer.md) it is worse than a cheat, it is a contradiction.
[Lockstep was rejected](27-multiplayer.md#why-not-lockstep) specifically because handing every client
the complete world state is an unfixable wallhack. A host that faithfully filters state down to what
a client may know, sending it to a client that then draws whatever it has through walls, has bought
nothing at all. **The filtered view is only as good as the visibility query behind it**, and there
isn't one.

So this was not a new feature bolted on for PVP. It was the missing half of three things already
committed to. **The renderer now asks**, through the one query below, and what it may not see it
does not draw.

## One primitive, three consumers

| Consumer | Question it asks | Status today |
|---|---|---|
| **The light channel** | Which cells can this emitter illuminate? | Specified in [docs/03](03-attention.md), unbuilt. **Ambient** light exists and drives observer range; *emitters* do not |
| **The renderer** | Which entities may this survivor be drawn as seeing? | **Built.** Asks `world.vision`, draws nothing it is not told about |
| **The multiplayer host** | Which entities and cells may this client be sent? | Promised by [docs/27](27-multiplayer.md#the-filtered-view), unbuilt |

**Design rule:** one visibility computation per observer per tick, at most, and no consumer computes
its own. A renderer that runs a second, cheaper line-of-sight check "just for drawing" will disagree
with the host's filter somewhere, and the place they disagree is the exploit.

## What an observer is

An observer is any entity that can see: survivors, NPCs, and — with a much worse profile — zombies.

- **Position and facing.** Facing is a heading, stored on the entity and part of save state. It is
  the same heading [aiming](09-combat.md) reads, which is why it is specified here rather than in
  two places.
- **A focal arc** — a narrow cone ahead where the survivor is actually looking. Detail here is
  reliable.
- **A peripheral arc** — wider, out to roughly the sides. Movement is noticed; identity is not. This
  is what produces *"something moved"* rather than *"a shambler, eleven metres, bearing north-east"*.
- **Nothing behind.** Being flanked is a real state, not a difficulty setting.
- **Range**, which is a property of light rather than of eyes. Daylight sees to the map edge; a dark
  interior sees as far as whatever the survivor is carrying, which is itself an
  [emitter](03-attention.md#light).

The arcs are deliberately not given angles in this document. They are the first thing that gets tuned
once there is something to tune them against, and writing a number here would make it look decided.
The build carries them **per observer** rather than as constants, for that reason and one more: a
survivor and a [screamer](14-zombies.md#first-wave-week-6) will not share them. What shipped is a
60° focal cone inside a 190° field of view for a survivor, and a shorter, wider, almost entirely
peripheral one for a shambler — starting points, in one place, still not decided.

**Range is a property of light, and half of that is now built.** The observer carries its *daylight*
range, and [the day/night cycle](02-core-loop.md) scales it by ambient light: the same eyes see 48 m
at noon and 12 m at midnight. Night is not a filter over the same view — the view is smaller, and
the screen darkening is a report of that rather than a second mechanism.

What is still missing is the *local* half: a lamp, a torch, a fire. That arrives with the
[light channel](03-attention.md#light), and it is the reason the night bottoms out at a quarter of
daylight rather than near darkness — there is currently nothing to carry and no counterplay to the
dark.

One consequence worth recording, because it looks like an implementation detail and is load-bearing:
**the effective range is rounded up to whole tiles, and that is what keeps dusk affordable.** Ambient
light changes every tick through a transition; the integer tile radius changes about thirty-six times
across the half hour, and the cache key is built from the integer. The sun going down costs
thirty-six shadowcasts, not one per tick.

## What blocks sight

Today the tile grid has exactly one non-floor value: `Tile.Wall` in `src/sim/map/tilemap.ts`. That is
enough to build the primitive and not enough to be right, so the occluder classes are named now to
keep the primitive from being rebuilt when [structures](15-base-building.md) arrive:

| Class | Blocks sight | Blocks movement | Examples |
|---|---|---|---|
| **Solid** | Yes | Yes | Walls, closed solid doors, [barricades](15-base-building.md) |
| **Transparent** | No | Yes | Windows, chain fence, a counter |
| **Screening** | Yes | No | Curtains, shutters, smoke, dense foliage |
| **Low** | Only for a body at [crouch or crawl](29-movement-and-stances.md) | No | Low walls, cars, sills, rubble |

**Opacity is not solidity**, and conflating them is the single most likely way to get this wrong. A
window stops a body and not a sightline. A curtain stops a sightline and not a body — which is the
whole reason [docs/03](03-attention.md#three-channels) lists shutters and curtains as light blockers.
The tile model needs two independent properties, not one enum with more values.

The **Low** class is what makes [crouch and crawl](29-movement-and-stances.md) mechanical rather than
cosmetic, and it is the only place a 2D map gets to have a height without
[z-levels](23-roadmap.md#deferred-z-levels) existing.

## Shadowcasting, and when it runs

Recursive shadowcasting over the tile grid, from the observer or emitter outward, bounded by range.
The variant built is **Albert Ford's symmetric shadowcasting**: a floor tile is revealed only when
its *centre* falls inside the scanned wedge, which is the condition that makes the relation
symmetric. The cheaper permissive variants reveal a tile when any part of it is touched, and they
are not symmetric — which the guard catches, because making the reveal permissive is one of the
mutations it was tested against.

Two properties matter more than the algorithm choice:

- **Symmetry.** If A can see B, B can see A. Asymmetric visibility is defensible in some games and
  indefensible in one where the other party might be a person with a rifle.
- **Determinism.** It runs inside `sim/`, on integer tile coordinates, with no floating-point
  accumulation across cells — same seed, same inputs, same visible set, per
  [architecture](19-architecture.md#determinism). Slopes are kept as rational `{n, d}` pairs and
  compared by cross-multiplication rather than divided into floats, so no platform is left free to
  round a wedge boundary its own way. The float in the system is the arc test, which is a single
  dot product against a heading and accumulates nothing.

  **The result is derived state, and deliberately not in the save.** It is a pure function of
  positions, facings and the map — all three of which the snapshot already holds — so storing it
  would create a second copy of a fact and a way for a save to disagree with itself. It rebuilds on
  the first tick after a load, exactly as the tile map regenerates from the seed.

**Recompute on change, not on tick.** An observer that has not moved to a new tile, not turned, and
whose surroundings have not changed sees exactly what it saw last tick.
[Performance](22-performance.md) already makes this claim for the light channel — *"recomputed only
when an emitter changes state or an occluder moves. Static most of the time."* — and the same caching
rule covers observers.

**Cached per tile, not per view**, which is what makes turning free: the arcs are evaluated against
the cached geometry at query time, so an observer that spins in place does not recompute anything.
Measured across 600 ticks with 51 observers in a 2,000-body district: **690 shadowcasts**, a little
over one per tick, and `crowded-and-watched` lands inside the budget of its sightless twin. The
number that should worry a future session is not that one — it is what happens when the observers
are *sprinting*, since a body crossing a tile every three ticks pays every three ticks.

**The cost shape is new, and it is worth saying so.** Every existing budget scales with entity count
against a *shared* field: noise propagation is one flood-fill no matter who is listening, and scent
diffusion costs the same whether the district holds thirty bodies or two thousand. Per-observer
visibility does not amortise that way — it is per observer, and in multiplayer it is per observer
*per client*. That is the same shape as
[roadmap risk 10](23-roadmap.md#risks), and it earns its own benchmark scenario held against the
budget of its sightless twin.

## The light channel, at last

With the primitive in place, light stops being special. [Docs/03](03-attention.md#three-channels)
says light propagates by line of sight only, decays instantly, and is blocked by any opaque
obstruction — which *is* a shadowcast from the emitter, with the emitter's
[magnitude](03-attention.md#light) as its range. The emitter table does not change. Nothing about
the field's structure changes. The channel that was waiting on an algorithm gets the algorithm.

One consequence to state plainly: light is the only channel where a wall is an absolute rather than a
penalty. Noise pays [18 m-equivalent](03-attention.md#scale-and-calibration) to cross a wall and
scent ignores walls entirely. Light does not attenuate through them at all. **That asymmetry is the
counterplay** — shutters work, and they work completely, which is what makes forgetting them
expensive.

## What the zombies see

The Light column of the [sensory profile table](14-zombies.md#sensory-profiles) is live, as of the
light channel. The first behaviour below is **built**; the second waits only on the screamer
existing. Neither makes a zombie smarter:

- **Light is a line-of-sight pull.** [Docs/14](14-zombies.md#baseline-behavior) already says so. A
  zombie that can see a lit cell ascends toward it; one that cannot, cannot, no matter how bright it
  is. This is why a floodlight behind a wall is safe and a candle in an open doorway is not.
  **Built**, and it is a third stimulus shape rather than a variant of the other two: noise is an
  impulse that commits, scent is a bias on a gradient, and light has no gradient at all, so it is a
  lean gated on the arc. One consequence worth expecting: being *lit by* a lamp is not the same as
  being able to *see* one, so a 35 m lamp lights the ground under a shambler whose 12 m eyes cannot
  reach the source, and it feels no pull.
- **The [screamer](14-zombies.md#first-wave-week-6) triggers on sighting a survivor**, which is an
  observer query rather than a field query. The screamer is the design object that makes the quiet
  branch mandatory, and it was unbuildable for want of exactly this. It is now buildable and
  deliberately unbuilt — its `alarm_on_sight` tag and 300-magnitude relay alarm would reshape how the
  district behaves, and landing it beside the channel it depends on would make both harder to
  judge.

**Design rule, inherited from [docs/14 rule 1](14-zombies.md#design-rules):** sight does not make
them tactical. They do not use cover, do not flank, do not break line of sight to reposition. Sight
is one more stimulus to ascend, and on contact it is pursuit, unchanged.

## Memory, not deletion

A survivor who watched three bodies walk behind a building does not forget them the instant the wall
intervenes, and the game must not act as though they did.

Each observer keeps a **last-known position** for what it has seen, with a sense of how stale it is.
The presentation is descriptive and degrades — *"three of them went round the back of the garage a
moment ago"*, then *"a while ago"*, then nothing. It is never a tracked marker, because a marker that
follows an unseen body is a lie and
[uncertainty is never a lie](01-hardcore-contract.md#fairness-rules).

This is also what keeps occlusion from reading as a bug. Bodies that pop out of existence at a wall
edge feel broken; bodies you *lose track of* feel like the game.

## What a client may know — a proposed answer to risk 9

[Roadmap risk 9](23-roadmap.md#risks) and [docs/27's first open question](27-multiplayer.md#open-questions)
are the same question: what may a multiplayer client be sent about the attention field? It is
checkpointed **before any transport code**, and this section is the answer put up for validation
rather than a decision already taken.

**Entities:** a client is sent only entities currently visible to one of its own survivors, plus the
last-known memory that client already holds. Nothing else crosses the wire. A client that never
receives a position cannot render one, cannot lag-switch one into view, and cannot be patched into
one.

**The field is filtered per channel, not by sight.** This is the part worth getting right, and it
falls straight out of the three channels being genuinely different:

| Channel | What the client may be sent |
|---|---|
| **Noise** | What its survivors could *hear* — cells whose magnitude reaches them, through the same wall penalty the flood-fill already applies. Hearing is not sight, and a survivor hears round corners |
| **Light** | What its survivors can *see*, which is precisely the visibility query above |
| **Scent** | The value at and immediately around its own survivors. Smell has no range to speak of and no direction |

So the filter is not one rule applied three times. It is each channel answering the question it
already answers, which is a good sign that the model was right.

**Name the cost.** The [debug overlay](03-attention.md) that single-player developers toggle with `O`
cannot exist client-side in a session, at any point, behind any flag. It is a map of where everyone
just was, and *holding* the data is the leak whether or not the client draws it. In a hosted session
the overlay is host-only. That is a real loss for debugging a multiplayer bug, and it is the price of
the whole model.

## Cut list

- **True 3D line of sight.** Requires [z-levels](23-roadmap.md#deferred-z-levels), which are
  deferred. The **Low** occluder class above is the cheap 90% and it is deliberate.
- **Sound occlusion beyond the existing wall penalty.** Noise already crosses walls attenuated by an
  18 m equivalent; running a second, geometric occlusion pass for audio buys realism the horde
  cannot perceive and the player cannot verify.
- **Rendered fog of war** — greyed tiles, explored/unexplored shading. The map is not the secret;
  what is *on* it is.
- **A detection meter, a stealth skill check, or an "eye" indicator.** Any of them collapses the
  uncertainty into a number, which [clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable)
  prohibits outright.
- **Drawn enemy vision cones.** Same reason, one step removed.

---

**Previous:** [03 — The Attention Field](03-attention.md) ·
**Next:** [04 — Survival Needs](04-survival-needs.md) · [Doc index](../README.md#documentation)
