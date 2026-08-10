# 28 — Visibility & Sightlines

*Why this exists: three systems need the same answer to the same question — can this observer see
that thing? The [light channel](03-attention.md#three-channels) needs it, the renderer needs it and
has never once asked, and [multiplayer](27-multiplayer.md) cannot ship its filtered view without it.
Answered once, it is a primitive. Answered three times, it is three subtly different bugs, and one of
them is a cheat.*

---

## The wallhack is already shipped

Honest disclosure first, because it changes what this document is for.

`src/render/renderer.ts` draws every entity inside the camera viewport. It does not ask whether
there is a wall between that entity and the survivor, because nothing in the codebase has ever asked
what a survivor can see. In single-player that is a mild cheat against
[clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) — you are told where the
bodies are through a building, which is exactly the uncertainty the clause exists to protect.

In [multiplayer](27-multiplayer.md) it is worse than a cheat, it is a contradiction.
[Lockstep was rejected](27-multiplayer.md#why-not-lockstep) specifically because handing every client
the complete world state is an unfixable wallhack. A host that faithfully filters state down to what
a client may know, sending it to a client that then draws whatever it has through walls, has bought
nothing at all. **The filtered view is only as good as the visibility query behind it**, and there
isn't one.

So this is not a new feature bolted on for PVP. It is the missing half of three things already
committed to.

## One primitive, three consumers

| Consumer | Question it asks | Status today |
|---|---|---|
| **The light channel** | Which cells can this emitter illuminate? | Specified in [docs/03](03-attention.md), unbuilt — the open Milestone 1 task |
| **The renderer** | Which entities may this survivor be drawn as seeing? | Never asked. Draws the whole viewport |
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
Two properties matter more than the algorithm choice:

- **Symmetry.** If A can see B, B can see A. Asymmetric visibility is defensible in some games and
  indefensible in one where the other party might be a person with a rifle.
- **Determinism.** It runs inside `sim/`, on integer tile coordinates, with no floating-point
  accumulation across cells — same seed, same inputs, same visible set, per
  [architecture](19-architecture.md#determinism).

**Recompute on change, not on tick.** An observer that has not moved to a new tile, not turned, and
whose surroundings have not changed sees exactly what it saw last tick.
[Performance](22-performance.md) already makes this claim for the light channel — *"recomputed only
when an emitter changes state or an occluder moves. Static most of the time."* — and the same caching
rule covers observers.

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

The Light column of the [sensory profile table](14-zombies.md#sensory-profiles) becomes live for the
first time. Two behaviours follow, and neither of them makes a zombie smarter:

- **Light is a line-of-sight pull.** [Docs/14](14-zombies.md#baseline-behavior) already says so. A
  zombie that can see a lit cell ascends toward it; one that cannot, cannot, no matter how bright it
  is. This is why a floodlight behind a wall is safe and a candle in an open doorway is not.
- **The [screamer](14-zombies.md#first-wave-week-6) triggers on sighting a survivor**, which is an
  observer query rather than a field query. The screamer is the design object that makes the quiet
  branch mandatory, and it has been unbuildable for want of exactly this.

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
