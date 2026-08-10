# 27 — Multiplayer

*Why this exists: multiplayer was [cut at the vision level](00-vision.md#cut-list) and is now
reversed. A reversal that lives only in code is a lie the documents keep telling, so this document
states what changes, what it costs, and what it explicitly does not buy.*

---

## Why this reverses a cut

The [vision's cut list](00-vision.md#cut-list) excluded multiplayer in these terms:

> **Multiplayer.** Changes the pause model, the succession model, and the director's job. Not a
> "later" feature — a different game.

**All three of those are correct.** Nothing below disputes them. The pause model does change, the
succession model does change, and the director's job does change — this document changes them, on
purpose, in one place each.

What the cut got wrong is the conclusion. "A different game" was a reason to keep multiplayer out of
the *single-player* design, not a reason it can never exist alongside it. The precedent is
[vehicles](25-vehicles.md), reversed on the same list: cut for two reasons, one of which turned out
to be backwards. Here the reasoning is not backwards, it is **scoped** — which is why the answer is a
mode rather than a rewrite.

Two things also changed since the cut was written, and both are load-bearing:

1. **The kernel turned out to be netcode-shaped.** Not by intent — by determinism. `step(world)`
   takes no time argument, RNG comes from independent seeded streams, input is a command queue the
   sim consumes on its own tick, and CI already compares a state fingerprint between runs.
   [Architecture](19-architecture.md#determinism) built all of that for replays and bug reports. It
   is the same list a networked simulation needs, and it is already paid for.
2. **The attention field turned out to be a multiplayer mechanic.** A second player is a second
   permanent scent source that cannot stop emitting, a second set of footsteps, and — with voice —
   a second reason to make noise. Pillar 2 says comfort is the currency of danger. Company is a
   comfort. It should cost the same way everything else does.

The second [cut-list entry](00-vision.md#cut-list) — *base raiding by the player against other
player colonies* — is **deferred, not reversed**. See [what PVP is not](#what-pvp-is-and-is-not).

## Multiplayer is a mode, not a layer

**The rule:** every single-player rule in this document set stands unchanged. Where multiplayer needs
a different rule, the difference is stated here and nowhere else, and the original document is
annotated with a link rather than rewritten.

This is not tidiness. The alternative — softening the single-player rules until they also hold with
four players — quietly rewrites [the hardcore contract](01-hardcore-contract.md) and
[the core loop](02-core-loop.md) for the benefit of a mode most sessions will not use. The
single-player game is the one being tuned; multiplayer inherits from it and pays for its own
exceptions.

**Design rule:** no single-player mechanic may be weakened to accommodate multiplayer. If a mechanic
cannot survive a second player, multiplayer does without it.

## The authoritative host

One participant runs a **host**: the same `sim/` kernel, headless, with the same module list and the
same seeded streams. Clients send commands. The host ticks. The host sends each client a filtered
view of what that client is allowed to know.

It is a *host*, not a server: there is no second codebase, no server-side game logic, and nothing to
keep in sync with `sim/`. That is the whole reason this shape is affordable.

### Why not lockstep

Deterministic lockstep — every client running the same sim from the same seed and a merged command
log — is very nearly free here, and the state fingerprint already in CI would make an excellent
desync detector. It was rejected for one reason:

**Lockstep hands every client the complete world state.** With PVP that is an unfixable wallhack, and
it is a direct contradiction of [clause 4 — information is scarce and unreliable](01-hardcore-contract.md#4-information-is-scarce-and-unreliable),
which prohibits any UI that collapses uncertainty into a number. A client that *holds* the other
player's exact position has already collapsed it; whether the UI draws it is then a matter of
politeness. In a game whose entire spine is *not knowing where they are*, that is not a tolerable
trade.

Lockstep remains the right model for a pure co-op build, and nothing here forecloses it.

### Command ordering

Clients send `Command`s. The host merges them into one queue and orders them by **`(tick, playerId,
seq)`** before ticking.

The ordering rule is not a detail. The [modifier pipeline](21-extensibility.md#mechanism-2-the-modifier-pipeline)
already learned this lesson once: float addition is not associative, so an unsorted fold makes a
resolved stat depend on module import order. The network version is worse, because arrival order
depends on the internet. Sorting by a stable key is what keeps a session reproducible.

A command that arrives after its tick has been simulated is **dropped, not applied late**. Clients
are told, so the input can be shown as lost rather than silently swallowed.

### The filtered view

The host sends each client what that client may know. A client that never receives a hidden
survivor's position cannot render one, cannot lag-switch one into view, and cannot be patched into
one.

What "may know" means is **not settled** for the attention field, and that is the largest open
problem in this document — see [open questions](#open-questions). The field is world state, not
per-player state, and the debug overlay that visualises it is developer-only precisely because
[clause 4](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) says so. A naive
implementation that ships the whole grid to every client re-introduces the lockstep problem through
the back door: the noise field is a map of where everyone just was.

### Late join, reconnect, and version

Both reuse [the save model](19-architecture.md#save-model) rather than inventing a second
serialisation path: a filtered snapshot, then the command stream from that tick forward.

This has a free consequence worth naming. The save format already carries a version stamp and
already rejects stale saves cleanly. That check becomes the client/host version check — a client
built against a different kernel is refused at join, rather than desyncing twenty minutes in.

### Determinism survives

The host's run is still a pure function of its seed and the merged command log. A multiplayer session
is therefore still reproducible from a bug report, which keeps the first
[fairness rule](01-hardcore-contract.md#fairness-rules) intact:

> **Every death is explicable.** The player must be able to reconstruct what killed them from
> information that was available.

Being killed by another player is the case where that promise is most likely to be doubted, and it is
the case where a deterministic replay is most valuable.

## The three casualties the cut named

### 1. The pause model

[The core loop](02-core-loop.md#time-scale) currently says:

> Pause is unlimited and pauses everything. This is a game about deciding under pressure, not about
> clicking fast — the tension comes from irreversibility, not from APM.
>
> **Design rule:** any mechanic that punishes the player for pausing is prohibited.

**This cannot hold with more than one player**, and no clever scheme rescues it. Vote-to-pause makes
pausing a social negotiation; per-player pause is not pause, it is time travel.

**The resolution:** time control is host-owned. A multiplayer session runs at 1× and does not pause.
The single-player design rule is **scoped rather than deleted** — it still governs single-player
completely, and `docs/02` is annotated to say so.

Be honest about the cost: this is the exception that makes multiplayer a different game, exactly as
the cut said. Speed controls at 3× and 10× are also host-owned and default off, because the
[10×-auto-drops-on-threat-contact](02-core-loop.md#time-scale) rule resolves to "whichever player
found trouble decides the tempo for everyone."

### 2. Succession

[The succession model](01-hardcore-contract.md#succession-what-happens-when-you-die) hands the camera
to another living survivor and continues the save. With several players, "another living survivor"
is ambiguous — one of them may be a person.

**The resolution:** a player whose survivor dies takes over an **unclaimed** colony survivor. The
existing rules are unchanged and apply per player: the web dies with the character, the gear stays on
the corpse, the colony takes the morale hit, that character's work priorities clear.

If no unclaimed survivor exists, the player spectates until one is recruited or another player dies.
**Nobody is given a survivor another player is controlling**, and there is no respawn timer —
[the run ends only when the last survivor dies](01-hardcore-contract.md#7-there-is-no-victory), and
that is as true with four players as with one.

### 3. The director

[The director](17-director.md) estimates colony power and strain to pace pressure. Several players in
one district is straightforwardly more power, and if it is not read as such the director paces a
colony that no longer exists.

**The resolution:** the director reads combined power across all participating players, and the
[guaranteed lulls](17-director.md) and grace period are colony-wide rather than per-player — a lull
that only some players get is not a lull.

**Default for competitive play: the "Nothing Personal" preset — director off.** Not because the
director is wrong here, but because a pacing system tuned against single-player colonies has no
measured behaviour with adversarial players in the district, and shipping it on by default would mean
neither the balance nor the PVP could be reasoned about. Turn it on when it has been measured.

## The contested recovery run

This is the argument that PVP belongs in *this* game rather than being bolted onto it.

[The contract](01-hardcore-contract.md#the-recovery-run) already calls the recovery run the signature
moment of a run: your best weapon, your best armor and every attachment you invested in are lying on
a body in the worst place on the map, and the noise of your death drew more of them there. Going back
is optional, usually unwise, and frequently the way the *second* survivor dies.

**With another player in the district, someone else can get there first.**

Nothing new is required to make that work. Corpses already persist with gear on them, where they
fell. The field already remembers what happened there. Death already makes noise, and noise already
brings the horde — which means the corpse is guarded by the thing that made it. The only addition PVP
makes is a second person who wants what is on it, and who has to walk through the same horde to get
it.

Note what this does *not* do: it does not add a reward for killing another player beyond what the
world already contains. Their gear is on their body in a bad place. That is the whole prize, and it is
the same prize their own teammate would be going after.

## Voice is an emitter

In-game voice is not a chat feature here. **It is the third way a player emits into the noise
channel**, alongside walking and shouting.

### The registers

Three, anchored to [the existing noise magnitudes](03-attention.md#noise), where
`reach = magnitude ÷ attenuation` and attenuation is 0.7 per metre in open ground:

| Register | Magnitude | Reach | Notes |
|---|---|---|---|
| **Whisper** | 2 | ~3 m | Same room. Costs the field almost nothing |
| **Talk** | 8 | ~11 m | Conversational |
| **Shout** | 120 | 171 m | **The existing shout emitter, unchanged** |

Two of these three numbers are already in the game. Shouting at 120 is
[shipped](03-attention.md#noise) and is the loudest thing a player can currently do. Talk at 8 lands
on exactly the same magnitude as a connecting melee swing, which is a useful sanity check rather than
a coincidence: speaking normally should cost the field about what hitting something costs it.

**These are calibrated, not derived.** Whisper and talk were picked to sit in the right band relative
to walking (1) and sprinting (6), in the same spirit as `docs/03` being candid that the 90-minute
scent half-life was picked rather than derived. They are the first thing to tune when the mechanic is
played.

### Audible range equals emission reach

**The rule:** what a teammate can hear is exactly what a zombie can hear.

Voice attenuates on the same curve, through the same walls, over the same distance as the noise it
emits. There is no register that carries further to humans than it does to the dead, and no way to be
heard by a person without being audible to everything else in that radius.

This is the whole design in one line, and it pays for itself three times:

- **It needs no UI.** The player learns the mechanic by being answered, or not. That satisfies
  [the no-numbers rule](01-hardcore-contract.md#4-information-is-scarce-and-unreliable) without an
  exception being carved for it.
- **It makes silence a tactic rather than a setting.** Coordinating is a cost, and coordinating loudly
  is a large one.
- **It generalises something already shipped.** Shout is already the cheapest way to make a mistake
  on purpose. The registers make that a spectrum instead of a button.

### The transport split, and determinism

Audio does not go through the simulation. The split is the same one the project already uses for the
clock, which `sim/` is [forbidden from reading](19-architecture.md#sim--the-hard-rules):

- **The audio** rides a separate real-time transport (WebRTC), peer-to-peer where possible, spatialised
  by the client. It is non-deterministic, and nothing in `sim/` may depend on it.
- **The field effect** is a `speak` command carrying a **register**, not an amplitude. The client
  quantises its own microphone level into one of three buckets and sends that through the existing
  command queue, where it is ordered and logged like every other command.

A register is an integer, so it serialises, replays, and fingerprints exactly like `shout` does today.
A replayed session emits identical noise whether or not anyone's microphone is plugged in — which is
the property that keeps voice out of the determinism story entirely.

### Lying about your own microphone

A client that reports "whisper" while shouting gets a silent voice channel: full communication, no
field cost. This is the mechanic's one real exploit and it is stated here rather than discovered
later.

The honest options, in preference order:

1. **Host-side bounding from the audio stream** — the host observes received audio energy and refuses
   a register the stream does not support. Costs the host a decode it otherwise would not do, and
   is imperfect against a client that pre-attenuates.
2. **Accept it, and say so.** Voice cheating in a co-op-shaped game with a self-hosted host is a
   social problem, and the host is usually someone who knows the other players.

What is *not* an option is leaving it unwritten. A design that pretends a hole is not there is how a
hole becomes a feature.

## What PVP is, and is not

**Is:** survivor versus survivor, in one shared 256 m district. Friendly fire and looting the dead are
host flags; the default is co-op with both off. Everything that makes it dangerous already exists —
[the contract](01-hardcore-contract.md), the field, and the corpse where it fell.

**Is not:** colony-versus-colony raiding, which the
[vision cuts explicitly](00-vision.md#cut-list) and which this document **defers rather than
reverses**. Not out of caution — it is not currently buildable. It needs survivors, base building,
resources, items and the director, all of which are [Milestone 2](23-roadmap.md#milestone-2--the-vertical-slice)
and untouched. It gets designed when there is a colony to raid.

## Open questions

- **What may a client know about the attention field?** The largest open problem here. The field is
  world state; the noise channel is a map of where everyone recently was. Ship it whole and PVP has
  the lockstep problem it was restructured to avoid. Ship it clipped to what each survivor could
  plausibly sense and the client cannot draw the overlay the single-player build already has.
- **Does PVP survive contact with permadeath?** If dying to a player reads as cheaper than dying to
  the horde, PVP has weakened [the contract](01-hardcore-contract.md) rather than completed it —
  the exact opposite of why it was added.
- **Does voice-as-emitter play as tense, or as a mute button?** If never speaking is dominant, the
  feature removed a channel instead of adding one. Whisper's reach is the first dial.
- **Is one district big enough for PVP?** 256 m is forced by the noise calibration, and a shout
  already covers 171 m of it. Two players may struggle to *not* find each other.
- **Is a session with no pause still this game?** [The core loop](02-core-loop.md) argues the tension
  comes from irreversibility rather than APM. Multiplayer tests that claim directly, because it
  removes the pause and keeps everything else.

## Cut list

Deliberately excluded from multiplayer, not merely deferred:

- **Matchmaking, lobbies, and public servers.** Sessions are host-and-invite.
- **Persistence across sessions.** A multiplayer save belongs to its host, like any other save.
- **Anti-cheat beyond the filtered view.** The view filter is a design constraint, not a security
  product. A malicious host can do whatever it likes, and that is understood.
- **More than one district.** [World scale](24-world-and-scale.md) is Milestone 3 and does not need
  a networking problem layered onto it.
- **Text chat.** Voice is a mechanic here; a free, silent, unlimited-range channel next to it would
  make it pointless.

---

**Previous:** [22 — Performance](22-performance.md) · **Next:** [23 — Roadmap](23-roadmap.md) ·
[Doc index](../README.md#documentation)
