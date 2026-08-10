# 01 — The Hardcore Contract

*Why this exists: difficulty here is not a slider, it's the thesis. Every system downstream inherits
the rules on this page, so they're written once, up front, as a contract the rest of the design has to
honor.*

---

## The seven clauses

### 1. You are weak, permanently

| Situation | Intended outcome for an average survivor |
|---|---|
| 1 zombie, open ground, melee | Winnable, costs stamina, small chance of a scratch |
| 3 zombies, open ground | Probably fatal. Run. |
| 1 zombie, cornered indoors | Dangerous — no room to back off between swings |
| 6+ zombies, any circumstance | Fatal without a door, a chokepoint, or a vehicle-grade advantage |

A survivor at the far end of the [skill web](08-skill-web.md) in
[Field-Tested gear](10-items.md) moves those thresholds by roughly one band — not by an order of
magnitude. They can fight three. They still die to eight.

**Design rule:** no combination of gear, web nodes, and traits may make a group of zombies trivial.
Any build that does is a balance bug, not a reward.

### 2. Actions take time, and time is where you die

Nothing is instantaneous. Reloading, bandaging, barricading a window, climbing a fence, opening a
stuck door, hauling a corpse — all have wind-up and follow-through, and all are interruptible.

The mechanic this creates: **commitment**. You don't die because you made a bad decision; you die
because you made a reasonable decision and the situation changed 1.5 seconds into a 3-second action.
Every action's duration is tuned as a risk window, not as a pacing knob.

### 3. Mistakes compound

Injuries are not a health bar that regenerates. A [fractured leg](05-health-injury.md) means you can't
outrun anything for a week and a half. Blood loss means you're weak tomorrow. Exhaustion degrades
aim, melee accuracy, and mood simultaneously.

Critically, **an injured survivor eats without working**. The cost of a bad night is paid in food for
days afterward, which pushes you into scavenging sooner, which is how the second bad thing happens.
Failure cascades are the intended texture.

### 4. Information is scarce and unreliable

- **No health bars.** Not for survivors, not for zombies, not for structures. Condition is read from
  descriptive text and animation: *"she's favoring that leg"*, *"the barricade is splintering"*.
- **No enemy counts.** You hear a lot of them. You don't get a number.
- **Diagnosis is a skill.** A survivor with no medical training misreads wounds. A trained medic gives
  you a confident answer sooner, and is therefore one of the most valuable people you can develop.
- **A bite can present as a scratch.** This is the most important sentence in this document. You will
  sometimes not know whether the person sleeping inside your walls is infected. See
  [infection](06-infection.md) for the full uncertainty model.

**Design rule:** any UI that would collapse this uncertainty into a number is prohibited, including
"helpful" tooltips and mod-facing debug overlays enabled by default.

### 5. The world gets worse regardless of how well you play

The [decay clock](13-world-decay.md) is independent of your performance. Play brilliantly and the
power still fails, the canned goods still expire, the nearby houses still empty out, and the virus
still mutates into something that runs.

This exists to kill the mid-game plateau. In colony sims the classic failure state is *comfort* — you
solve food, you solve defense, and the game becomes chores. Here, solving something buys time, never
permanence.

### 6. Death is permanent; the save is single-slot

No save-scumming. One save file, written continuously, and quitting does not roll anything back.

When your controlled survivor dies, you **succeed into another** (below). When the last survivor dies,
the run is over and the save is closed out into a run summary.

### 7. There is no victory

The default game has no win condition. You survive until you don't.

An **optional escape endgame** exists for players who want a finish line: assembling a working
[vehicle](25-vehicles.md), the fuel to run it, a [route scouted](24-world-and-scale.md) through the
region, and enough people alive to be worth leaving with. It is deliberately expensive, it requires
deep engagement with [world decay](13-world-decay.md) and [factions](18-factions.md), and taking it
ends the run. Most runs
will not reach it. It is not the "good ending" — it's an alternative to dying, and the game does not
frame it as winning.

---

## Succession: what happens when you die

Your controlled character dies like anyone else. Then:

1. **The camera hands over.** You take control of another living survivor — chosen by you if there's
   time to choose, otherwise the nearest one. The save continues.
2. **Their web is gone.** Every point that character earned dies with them. There is no inheritance.
3. **Their gear is on the corpse**, wherever it fell. Which is usually inside the building full of the
   horde that just killed them.
4. **The colony reacts.** Losing the person the others followed costs morale across the board and
   clears their configured work priorities. Relationships to the dead survivor trigger grief in the
   people who had them (see [survivors](07-survivors.md)).

In [multiplayer](27-multiplayer.md) these four points apply per player, unchanged. The one addition
is that the survivor handed over must be **unclaimed** — nobody is given a survivor another player is
controlling — and a player with none available spectates rather than respawning. The run still ends
only when the last survivor dies.

### The recovery run

Point 3 is a designed centerpiece, not an inconvenience. Your best weapon, your best armor, and every
attachment you invested in are lying on a body in the worst place on the map, and the noise of your
death drew more of them there.

Going back is optional, usually unwise, and frequently the way the *second* survivor dies. The docs
treat this as the signature moment of a run and content is authored to support it: corpses persist,
gear stays on them, and the attention field remembers what happened there.

In [multiplayer](27-multiplayer.md) the recovery run becomes a *contested* one: another player can
reach the corpse first, through the same horde, for the same gear. Nothing is added to make that work
— the corpse, the gear and the noise that drew the horde there are already the whole prize.

## Sandbox settings

A Zomboid-style settings layer exists so the defaults can be brutal without the design being
unplayable or untestable.

| Preset | Purpose |
|---|---|
| **Standard** | The intended experience. Everything on this page as written. This is the balance target. |
| **Harsher** | Faster decay, larger hordes, scarcer antibiotics, no succession (death ends the run). |
| **Sandbox** | Everything exposed: horde density, decay rates, infection lethality, loot abundance, whether zombies sprint, succession on/off. |
| **Builder** | Low threat, for players who want the colony sim. Explicitly not balanced. |

**Design rule:** Standard is what gets tuned, discussed, and reported on. The others are consequences
of exposing parameters, not separate balance targets. Nothing may be designed such that it only works
on a non-Standard preset.

## Fairness rules

Hardcore must not mean arbitrary. The design owes the player:

- **Every death is explicable.** The player must be able to reconstruct what killed them from
  information that was available. Deterministic simulation (see [architecture](19-architecture.md))
  means we can verify this from a replay.
- **Warning before consequence.** Hordes are audible before they're visible. Infection has symptoms
  before it has a corpse. Structures visibly degrade before they fail.
- **No unwinnable starts.** The director guarantees an opening grace period; generated starting
  positions are validated for basic survivability.
- **Uncertainty is never a lie.** Ambiguous information is genuinely ambiguous — the game does not
  show you something false. A scratch that might be a bite really might be either.

## Cut list

- **Difficulty scaling to player skill** beyond what the [director](17-director.md) does explicitly.
  Silent rubber-banding violates the fairness rules.
- **Death penalties beyond losing the character** (no meta-progression debt, no run-over-run
  handicap).
- **Injury permadeath for NPCs from non-combat sources** (no dying of a stubbed toe) — decay and
  hordes supply enough pressure.

---

**Previous:** [00 — Vision](00-vision.md) · **Next:** [02 — Core Loop](02-core-loop.md) ·
[Doc index](../README.md#documentation)
