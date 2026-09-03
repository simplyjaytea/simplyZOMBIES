# 00 — Vision

*Why this exists: to state what the game is in one page, so every later document can be checked
against it. If a proposed feature doesn't serve a pillar below, it doesn't go in.*

---

## The pitch

You control one survivor in a dead town. You can recruit others, and together you fortify a place to
sleep. Every comfort you build — a fire, a light, a generator, a gunshot — is a signal, and the dead
follow signals. The better you live, the harder they come.

You will not win. You will last a while, and then something will go wrong, and the story of how it
went wrong is the game.

## The six pillars

**1. You are prey.**
Not a hero, not a soldier, not eventually a god. One zombie is dangerous. Three is probably fatal. A
fully-developed veteran is *competent*, never invincible. Every design decision that would make the
player feel powerful gets checked against this pillar first.

**2. Comfort is the currency of danger.**
The [attention field](03-attention.md) is the spine of the whole game. Warmth, light, cooked food,
electricity, gunfire, more people, unburied corpses — all of it emits noise, light, or scent, and the
horde walks up that gradient. Survival and tower defense aren't two systems glued together; they're
the same system read from two directions.

**3. Investment, not headcount, is what you lose.**
Survivors are unlimited and [procedurally generated](07-survivors.md). New ones arrive knowing
nothing, owning nothing, and eating immediately. What death actually costs you is the hours you sank
into someone — their [skill web](08-skill-web.md) and the [gear](10-items.md) you built onto them.
That's what makes [infection](06-infection.md) hurt.

**4. The world decays on a clock you don't control.**
The grid fails. Water stops. Food rots. Tools break. Scavenging sites empty out and push you further
from home. The virus mutates and the horde gets worse on its own schedule. Every stable equilibrium
you build has an expiry date, and that's what stops hour forty from being a farming simulator. See
[world decay](13-world-decay.md).

**5. Everything is a module.**
The design changed substantially four times before a line of code existed, and it will change again.
The tick loop and the attention field are the kernel; every other system plugs in and can be pulled
out. See [architecture](19-architecture.md) and [extensibility](21-extensibility.md).

**6. Performance is a feature, not a phase.**
This design asks for a [continuous drivable region](24-world-and-scale.md), hordes in the hundreds, a
propagating stimulus field, and a colony of individually-simulated people — in a browser. That only
works if performance is a constraint the design obeys rather than a cleanup task at the end. Frame
budgets are enforced in CI and **a feature that breaks budget doesn't ship until it's fixed**. See
[performance](22-performance.md).

## Genre, honestly

Four influences, and what each one contributes:

| Influence | What we take | What we leave |
|---|---|---|
| **Project Zomboid** | Lethality, slow deliberate actions, injury depth, imperfect information, permadeath | Its map scale; the isometric view; z-levels and everything that needs them |
| **RimWorld** | Colony job priorities, pawn traits and relationships, the storyteller/director, **the flat top-down view and pawns that read at a glance in it** (the read Dungeon Settlers shares, whose upright pawns and warm dark palette the art follows since 2026-09-03; Zero Sievert's grounded palette was the model before) | Its comedy tone; its readiness to let you snowball |
| **Tower defense** | Building fortifications that channel and kill, bait and routing as skill expression | Fixed wave timers and a build-phase/fight-phase split |
| **Path of Exile** | Gear-as-build, rolled affixes, materials-as-currency, no classes | Its power curve, its speed, its economy |

> **Reversed:** the Project Zomboid row previously left *"its map scale and its 3D isometric
> fidelity"*. The map scale still stands and always will. The projection does not, and the reason it
> was rejected turns out to be an argument about something else: what makes PZ's isometric view
> expensive is **z-levels** — multi-floor buildings, stairs, roofs — which
> [the roadmap](23-roadmap.md#deferred-z-levels) defers with a costed rationale, and which nothing
> here needs. The projection on its own is a change inside `render/` that the simulation cannot
> observe, and walls that stand up are what make a district read as a place rather than a floor plan.
>
> What keeps the reversal honest is that the *fidelity* half is still refused. No second floor, no
> stairs, no rooftop you can stand on. A wall has a height because it is drawn, not because anything
> can be above or below it, and [the planar assumptions](23-roadmap.md#deferred-z-levels) the roadmap
> lists are all still planar.
>
> **Reversed again:** the previous paragraph claimed *"walls that stand up are what make a district
> read as a place rather than a floor plan"*, and the view is now flat top-down (RimWorld, Zero
> Sievert). What that claim missed is that RimWorld's districts read as places with no standing
> wall anywhere in them — mass, colour, and a bevel carry the read, and pawns are legible in a way
> an isometric figure never was. What the standing walls actually bought was occlusion, and
> occlusion had to be *managed*: a fade heuristic for walls that covered the player, stub-height
> walls when indoors, a depth sort over every visible tile. Top-down deletes all three outright
> rather than tuning them. The parts of the original argument that were load-bearing survive
> untouched: the projection is still a change inside the presentation that the simulation cannot
> observe (this sentence has now justified the change in both directions), and the z-level refusal
> stands and gets cheaper — a flat view does not even tempt you to draw a second floor.
>
> **Amended (2026-09-03):** the view stays flat top-down; what changed is the *read* inside it.
> The art now follows Dungeon Settlers rather than Zero Sievert: upright, face-on pawns that
> flip rather than rotate, walls drawn with a lit cap and a one-tile south face, interiors
> always in view, a warm dark-fantasy palette. The paragraph above is qualified, not reversed —
> a wall face drawn inside its own tile is not the occlusion machinery that was deleted: it never
> covers a walkable tile, no fade heuristic returns, and no *tile* is depth-sorted. Pawns, trees
> and vehicles are y-sorted as sprites, the entity sort the flat view has had since this
> reversal. docs/30's "The Dungeon Settlers look" entry carries the decisions and what each
> earlier one becomes.

## What this game is **not**

Stated because each of these is a thing the design will drift toward if unattended:

- **Not a power fantasy.** There is no build that trivializes the game. If one appears in playtesting,
  it's a bug.
- **Not a base-decorating game.** Building is defensive engineering, not interior design. Every
  structure earns its place by changing how the horde moves or how long people survive.
- **Not a story campaign.** There is no plot, no cure quest, no chosen one. The director generates
  situations; the player supplies the narrative.
- **Not a wave shooter.** Nights aren't a timer counting down to a fight. Most nights are quiet and
  tense. The bad ones are earned.
- **Not a squad tactics game.** You control *one* survivor directly. The others are people with
  priorities, not units with orders.
- **Not RTS-scale.** A large colony is a dozen people, not a hundred, and the cap is economic rather
  than numeric.
- **Not a driving game.** [Vehicles](25-vehicles.md) are range, capacity, and a
  [home you can move](26-mobile-bases.md). They are not a combat tool and handling is not the skill
  being tested.

## Scope honesty

This document set describes a game far larger than a first build. That's deliberate — it's a backlog,
not a promise. The [roadmap](23-roadmap.md) defines a vertical slice that proves the pillars with the
minimum content, and explicitly labels everything else post-slice.

If a decision must be made and this document doesn't settle it, the tiebreaker is pillar 1: choose the
option that leaves the player more afraid.

## Cut list

Deliberately excluded from the design entirely, not merely deferred:

- **A cure, or any narrative resolution to the outbreak.** Contradicts pillars 1 and 4.
- **Aircraft and boats.** [Vehicles](25-vehicles.md) are ground vehicles. Everything else is a
  different navigation problem for no additional design payoff.

> **Reversed:** multiplayer was cut here, in these terms: *"changes the pause model, the succession
> model, and the director's job. Not a 'later' feature — a different game."* All three consequences
> were correct and all three still hold — [multiplayer](27-multiplayer.md) changes exactly those three
> things, deliberately, in one place each. What was wrong was the conclusion: "a different game" is a
> reason to keep it out of the single-player design, not a reason it cannot exist beside it. It is
> therefore a **mode**, and the rule that makes the reversal safe is that no single-player mechanic may
> be weakened to accommodate it. The unlimited pause is the price, and it is scoped to single-player
> rather than deleted.
>
> **Base raiding by the player against other player colonies** was cut here too, and is now
> **deferred rather than reversed** — it needs survivors, base building, resources and the director
> before there is a colony to raid. [Multiplayer](27-multiplayer.md) is survivor-versus-survivor in
> one district; faction raids still go one direction, see [factions](18-factions.md).

> **Reversed:** vehicles were previously cut here on the grounds that they'd wreck the attention
> economy and the map scale. That was wrong on the first count — an engine is simply the loudest
> emitter in the game, which makes vehicles the spine's strongest expression rather than an exception
> to it. It was right on the second, which is why [world scale](24-world-and-scale.md) now exists as a
> document and why [performance](22-performance.md) is now a pillar.

---

**Next:** [01 — The Hardcore Contract](01-hardcore-contract.md) ·
[Doc index](../README.md#documentation)
