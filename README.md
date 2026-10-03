# simplyZOMBIES

A hardcore survival colony sim about the cost of living well during the end of the world.

You control one survivor in a dead town. You can recruit others, and together you fortify a place to
sleep. Every comfort you build — a fire, a light, a generator, a gunshot — is a signal, and the dead
follow signals.

**The better you live, the harder they come.**

## Download

The latest build is on the [releases page](https://github.com/simplyjaytea/simplyZOMBIES/releases):
unzip the Windows archive anywhere and run `simplyZOMBIES.exe` (no installer; SmartScreen may warn
once because the build is not signed). The same build runs in a browser from the project's Pages
site. Early alpha: a later version may not read this one's saves.

## Art pack

The [outpost asset pack](godot/art/simplyzombies/README.md) contains the delivered character,
environment, equipment and animated-effects artwork, with native PNGs, source sheets, atlases,
manifests and Godot SpriteFrames resources. View the
[asset catalog](godot/art/simplyzombies/previews/asset-catalog.png), or download and open the
[offline interactive preview](godot/art/simplyzombies/simplyzombies-production-preview.html).
The pack is checked in at `res://art/simplyzombies/` and is adopted into the live renderer
slice by slice, per [the roadmap's "Art & renderer — the outpost pack"
group](docs/23-roadmap.md#whats-left-in-milestone-2). The game draws the pack's
four-direction walking bodies, its worn gear and held weapons, its east-west cars, item icons
(floor, bags, quick strip and inspect pane), the ground, trees and nature dressing, heaps, the
bed, furnishings and containers, the barricade and work lamp, the muzzle flash, casing, blood and
campfire flame, and the crosshair and interaction-hand cursors. The approved A2 fitted wall
modules now cover supported rectangular brick and plaster perimeters, with room boards beneath
their transparent edges and generated fallbacks for other shapes and orientations. The latest
art pass also adds an exploded condition chart,
the workbench and three tall furnishings, a carried stove icon, and source-specific light colours.
See the [runtime captures](.hermes/plans/2026-10-02_art-completion/) and
[implementation record](docs/23-roadmap.md#the-record-by-system) for evidence and remaining limits.

Seven original zombie families now have directional idle and walking pictures and matching
settled corpses; humans share four corpse poses. Their
[sources and previews](godot/art/simplyzombies/zombie-poses/) preserve the generation and
extraction history alongside the reproducible game assets.

---

## UI kit

The [UI Field Kit](godot/art/simplyzombies-ui/README.md) contains 120 transparent PNG
exports, panel and control frames, equipment/action glyphs, cursors, four UI
animations, an atlas, and native Godot resources. See the
[sprite catalog](godot/art/simplyzombies-ui/previews/simplyzombies-ui-catalog.png),
[animation preview](godot/art/simplyzombies-ui/previews/simplyzombies-ui-motion.gif), or
[offline preview](godot/art/simplyzombies-ui/simplyzombies-ui-preview.html).
Run `godot/art/simplyzombies-ui/demo/demo.tscn` in Godot to try the native controls.
The live UI uses the kit's frames, font, glyphs, cursors and animations through the shared chrome
helpers, checked by `godot:check:ui_skin`. The reviewed inventory and ordinary work layouts
fit 1280×720 and 1920×1080, with scrolling for long condition lists, tall bags and larger rosters. See the
[layout comparisons](.hermes/plans/2026-10-03_ui-layout/) for the reviewed panels.

A complete [UI overhaul is being designed](docs/32-ui-overhaul.md): Project Zomboid-style
management, Tarkov/Zero Sievert tactical detail, and an anatomical equipment diagram that
fits the Dungeon Settlers-inspired world. The [all-screen audit](.hermes/plans/2026-10-03_ui-overhaul/audit/README.md)
also identifies remaining skill-web/bench clipping, long learning-text overflow and vehicle
HUD overlap. The [roadmap](docs/23-roadmap.md#ui-overhaul) describes the proposed delivery order;
these improvements are not yet implemented.

## The loop, in five lines

1. **Dawn** — count what last night cost. Treat wounds, repair walls, burn the bodies.
2. **Day** — you lead a scavenging run while the colony works. The people who fight best also build
   best, so you can't have both.
3. **Dusk** — barricade, post the watch, decide whether tonight is worth a lamp.
4. **Night** — there's no wave timer. What arrives is what your week's noise, light, and scent earned
   you.
5. **Repeat** until something goes wrong, because it will. There is no winning, only lasting.

## What makes it different

- **One attention system ties four genres together.** Noise and scent spread across the district;
  light changes what can see and be seen. Cooking, warmth, electricity, gunfire, and every extra
  person leave signals. Survival and tower defense are the same system read from two directions.
- **Nobody has a class.** Survivors will have bounded natural aptitudes, but no predetermined build.
  Who they become comes from the gear they find and modify plus a classless skill web earned by doing.
- **Bodies are cheap; people are expensive.** Survivors are unlimited and procedurally generated, and
  they arrive knowing nothing and eating immediately. What infection takes from you isn't a headcount,
  it's two months of investment.
- **A bite can present as a scratch.** You will not always know whether the person sleeping inside
  your walls is infected. Amputate, quarantine, spend the last antibiotics, or put them down — on a
  guess.
- **Melee and ranged are both good, permanently.** Melee spends your body and your infection risk.
  Ranged spends finite ammo and tonight's difficulty. Neither converts into the other.
- **The world decays on a clock you don't control.** The grid fails, food expires, sites empty out,
  the virus mutates. Every equilibrium you build has an expiry date.
- **A running vehicle keeps announcing you.** Engines emit noise while idling and more while
  driving; the continuing signal has a different cost from a single gunshot. Parked cars and bikes
  can be entered and driven; engine vehicles can be refuelled. Vehicle customization and a
  [home you can drive away from a siege](docs/26-mobile-bases.md) remain later work.

## Status

**Playable, and early — most of the vertical slice has landed.** Make noise and the district
converges; stay quiet and scent still brings danger eventually. Walls block sight, surfaces change
speed and footstep noise, and midnight closes bare-eyed vision to only a few metres unless you find
a light. Five movement stances trade time, stamina, visibility, and noise. Melee commits you to a
swing; ranged — a bow and a pistol — spends finite ammo and announces you to the district, and both
weapons wear with use and repair imperfectly. Shamblers, screamers, and bloaters walk a 256 m
district with a civic annex. Survivors have STR/CON/DEX aptitudes; they get hungry, thirsty, and
tired, their mood matters, and they work jobs — hauling, building, cooking, doctoring — you steer
through a priority grid. Recruits arrive, gear rolls affixes into a rotatable, nested grid
inventory, a director paces the nights, and you can fortify, save, and load. Wounds appear on a
descriptive body-part view rather than a health bar.

**You cannot shoot what you cannot see, and you do not forget what walked behind a wall.** A round
stops at a wall rather than passing through it, for you and for the colony alike. Bodies you have
seen are remembered for a while afterwards, as a place and a rough count that goes vague as it goes
stale — *"two of them, north-east, a moment ago"* becomes *"a few of them, north-east, a while
ago"*, and then nothing. Somebody who has lost sight of a thing coming for them can still put a
round where it was, which costs exactly what any other shot costs whether or not anything is still
standing there.

**Weapons take attachments, and they move between weapons.** A suppressor, an optic, an extended
magazine, a haft wrap, a spiked head — found rather than crafted, and fitted to any weapon with the
right slot. Finding a better pistol does not mean losing the suppressor you found for the last one.
A suppressed pistol is about as loud as a raised voice instead of a thunderclap, and costs you
accuracy for it.

**Losing somebody costs the people who are left.** Everybody in the colony feels a death; the ones
who watched it happen feel it considerably more, and it is worse again when the colony was the one
who had to do it. It fades over about a day.

**No two nights are the same shape.** The director draws a night rather than computing one — quiet,
a probe, a press, a siege — leaning on how loud your week has been and how long you have been left
alone, but never simply following from them. It cannot send three sieges in a row and it cannot
leave you alone for four nights running. And what arrives comes from wherever the district has been
hearing you, not always down the same street.

**The full injury loop is live.** Grabs, located bites, bleeding, pressure, bandaging, infection
and recovery have run in ordinary play since the owner's 2026-09-01 decision. You start with
Mara and Ellis; colonists struggle and defend one another, and `H` lets you pull someone free.
`T` applies first aid, including bare-handed pressure on your own wound while held. The decision,
measurements and gates are recorded in
[where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands).

**Godot 4.7.1 is the playable build.** The web export runs at `/` and the Windows artifact comes
from the same green commit; a failed CI publishes nothing. The TypeScript/Canvas oracle is
archived at tag `ts-oracle-final` for parity reference and rollback. See
[Godot rebuild](docs/31-godot-rebuild-roadmap.md) for transition history.

**[Play the latest main build](https://simplyjaytea.github.io/simplyZOMBIES/).** Every push to `main`
that passes CI automatically replaces this playable build; failed checks are never published.
The enforced performance job still measures the frozen TypeScript oracle. The new strict Godot
runtime measurements exceed their budgets; see [performance evidence](docs/22-performance.md)
for the workload and the remaining CI enforcement work.

```bash
bash scripts/setup-web-session.sh  # pinned engine and npm dependencies on a fresh Linux checkout
npm run godot:run    # Godot — the game (also: godot:editor)
# npm run dev        # TypeScript oracle via Vite (archived, reference only)
```

If setup reports that it cannot link the engine onto `PATH`, set `GODOT_BIN` to the executable
it prints before running the Godot commands. A headless machine also needs a display for play
or screenshots; see [environment setup](AGENTS.md#running-the-game-gui).

## Controls

The game opens on a **title** — new run, continue when there is a save, quit — drawn over the
district it is about to play. `Esc` pauses to a menu from there on, and the run ends on a screen
that says what happened to the colony.

**`F1` shows the keys in game**, and they appear when a run starts until you dismiss them — this
list is the same thing in text. The in-game sheet is the authority: it is held to
`presentation/input_map.gd`'s bindings in both directions by `godot:check:play`'s KEYS lane, and
this table is a third copy that no gate judges.

| | |
|---|---|
| **Move** | `WASD` walk · `Shift` sprint (fast, and loud — latches while held) · `Ctrl+Z`/`Ctrl+C`/`Ctrl+S`/`Ctrl+V` crawl, crouch, stand, jog |
| **Act** | `F` swing, or struggle out of a grab · `H` pull someone out of a grab · `G` or click — fire · `R` reload · `E` interact — pick up, open a cupboard or a car · `T` first aid (bandage if you have one, bare hands if not; again to stop — and while something has hold of you, your own bare hands on your own wound is still allowed) · `C` make camp where you stand (`Shift+C` to strike it) · `1`…`6` use what is on your belt and in your pockets · `Space` shout — heard across the district |
| **Look** | `Tab` gear and injuries (drag to move, right-click or `R` to rotate) · `J` work priorities · `K` the skill web · `O` attention overlay: noise, scent, sight, light · `M` raw developer sheets · scroll wheel zoom |
| **Run** | `-`/`=` slower, faster (1×, 3×, 10×) · `P` pause · `F5`/`F9` save and load · `Esc` the menu — resume, save, load, settings, or back to the title · `F1` the key list |

A day is four hours at 1×, so press `=` twice and wait for dark.

The view is flat top-down — RimWorld and Dungeon Settlers are the closest comparisons — and the
wheel zooms between a close-in read on your survivor and a wide look at the colony. In the
inventory, wheel over the survivor to scroll condition prose, or over bags to scroll bags;
in Work, the wheel reaches additional survivor rows. Humans and
the seven animated zombie art families use four directional views; screamers and bloaters retain
their face-on pictures. Walls carry a lit cap and a south face; a roof
covers a building until you can see inside it; the ground's surfaces meet in ragged edges rather
than on a grid; and trees and parked cars stand in the same depth sort as the people, so a
survivor walks behind a conifer and in front of a car. The HUD reads
in words rather than bars: what the district can sense of you sits in the top right, and a
survivor with nothing wrong takes up almost no screen.

**Current playable stack:** Godot 4.7.1 (Compatibility), typed GDScript. The archived
TypeScript oracle remains at tag `ts-oracle-final` with parity fixtures under `godot/parity/`.

## Roadmap

Tentative — [docs/23](docs/23-roadmap.md) is the authority on scope, order, risks, and current
status. Milestones close on their exit criterion, never on a feature count.

- ✅ **Milestone 0 — Foundations.** Deterministic tick loop, ECS, events and modifiers, validated
  content, versioned save/load, CI gates for determinism and performance.
- ✅ **Milestone 1 — The spine.** Noise, scent, and light/sight live in one attention field;
  shamblers follow gradients; stances, committed melee, grabs and breaking free; day/night.
- ✅ **Engine rebuild.** The game moved from TypeScript/Canvas to Godot 4.7.1 behind per-tick
  parity gates ([docs/31](docs/31-godot-rebuild-roadmap.md)), then cut over. Web and Windows builds
  ship from every green commit.
- ◐ **Milestone 2 — The vertical slice** *(underway — most systems landed)*: one district, generated
  survivors, needs and jobs, ranged parity, fortification, a pacing director, permadeath and
  succession, and the complete injury/uncertain-infection loop. Landed so far: lethality and
  turning, the zombie roster, ranged combat and sightlines, needs/jobs/recruits, mood consequences
  and grief, building, a director that varies its nights, save/load, the shallow skill web, loot
  tables and searchable containers, workbench modification, weapon attachments, the full injury
  table with pain, exhaustion and sepsis, basic melee combat, and the full
  wound-treatment-recovery loop. A zombie can grab, bite and infect in ordinary play, and wounds,
  bleeding, pressure, bandaging, rescue, recovery and infection all run — `GRABS_ENABLED` has
  shipped on since the owner's 2026-09-01 decision (see
  [where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands)). Still open — every
  piece named in [what's left](docs/23-roadmap.md#whats-left-in-milestone-2): camp development,
  the captive path, remaining skill and world systems, presentation refinements, runtime
  performance proof, and the balance grid plus a human ten-day playtest. Procedural people,
  the expanded item roster, the UI shell and weather already have implementation records.
  **Exit criterion:** survive ten in-game days,
  lose a survivor you cared about, continue through succession, and still want another run.
- ☐ **Milestone 3A — Survivor depth.** Relationships beyond the shipped grief system, the full
  skill web and six attributes, remaining weather effects, world decay, and further zombie depth.
- ☐ **Milestone 3B — World range.** The continuous drivable region and streaming, vehicles, mobile
  bases, and viable nomad play.
- ☐ **Milestone 3C — Multiplayer.** Authoritative host, filtered client views, voice as an emitter.
- ☐ **Milestone 4 — Breadth.** Factions and trade, storyteller presets, the escape endgame, and
  content volume.

## Working on it?

**`CLAUDE.md` is the engineer's entry point** — what the project is, the standing bans, how to
verify a change, and the traps. `HANDOFF.md` is the short version for picking the project up cold:
where it stands, what landed last, and which open questions are the owner's rather than the code's.
`AGENTS.md` covers environment setup and carries the
[routing table](AGENTS.md#routing-table): by kind of work and by system, what to read first, where
the code lives, and which gate judges it -- checked by `npm run check:routing` so it cannot drift.
[docs/23-roadmap.md](docs/23-roadmap.md) owns product scope, milestone order, risks, playtest
questions, and current implementation status; [docs/30-decisions.md](docs/30-decisions.md) records
what each completed chunk made structural, and [docs/31](docs/31-godot-rebuild-roadmap.md) owns the
(completed) engine transition.

## Documentation

The tables below are the authority on **reading order**. File numbers reflect the order documents were
written, so 24–26 sit under "The world", 28 sits next to the spine it serves, 29 sits next to combat,
and 30 sits with the technical set rather than all of them landing at the end.

### Foundations
| | |
|---|---|
| [00 — Vision](docs/00-vision.md) | Pillars, genre influences, what this game is *not* |
| [01 — The Hardcore Contract](docs/01-hardcore-contract.md) | Lethality, permadeath, succession, imperfect information, no win state |
| [02 — Core Loop](docs/02-core-loop.md) | The dawn/day/dusk/night ratchet |
| [03 — The Attention Field](docs/03-attention.md) | **The spine.** Noise, light, scent, and how the horde reads them |
| [28 — Visibility & Sightlines](docs/28-visibility-and-sightlines.md) | Sight, darkness, cover, and what the world may reveal |

### Survival & people
| | |
|---|---|
| [04 — Survival Needs](docs/04-survival-needs.md) | Hunger, thirst, rest, temperature, hygiene, mood |
| [05 — Health & Injury](docs/05-health-injury.md) | Located injuries, blood loss, bacterial infection, treatment |
| [06 — Infection & Turning](docs/06-infection.md) | Diagnostic uncertainty and the five responses |
| [07 — Survivors](docs/07-survivors.md) | The generator, traits, recruitment, work priorities, Focus |
| [08 — The Skill Web](docs/08-skill-web.md) | Classless progression earned by doing |

### Combat & gear
| | |
|---|---|
| [09 — Combat](docs/09-combat.md) | The melee/ranged parity contract, and aiming |
| [29 — Movement & Stances](docs/29-movement-and-stances.md) | Crawl to sprint: speed as a decision about the attention field |
| [10 — Items](docs/10-items.md) | Bases, affixes, tiers, named items, attachments, decay |
| [11 — Crafting & Modification](docs/11-crafting.md) | Materials as currency; the gamble at the workbench |

### The world
| | |
|---|---|
| [12 — Resources](docs/12-resources.md) | The taxonomy, and the three resources that carry the economy |
| [13 — World Decay](docs/13-world-decay.md) | The clock that ensures nothing stays solved |
| [14 — Zombies](docs/14-zombies.md) | Behavior, types, hordes, mutation waves |
| [15 — Base Building](docs/15-base-building.md) | Steering the horde instead of blocking it |
| [16 — Weather](docs/16-weather.md) | Weather as an attention modifier |
| [17 — The Director](docs/17-director.md) | Pacing, lulls, storytellers |
| [18 — Factions](docs/18-factions.md) | Human raiders as a different threat shape *(post-slice)* |
| [24 — World & Scale](docs/24-world-and-scale.md) | The continuous region, districts, roads, route trails *(post-slice)* |
| [25 — Vehicles](docs/25-vehicles.md) | Found, customizable, and the loudest thing in the game *(post-slice)* |
| [26 — Mobile Bases](docs/26-mobile-bases.md) | Interior modules, convoys, and viable nomad play *(post-slice)* |

### Technical
| | |
|---|---|
| [19 — Architecture](docs/19-architecture.md) | Layers, determinism, the kernel-vs-module rule, the Godot port path |
| [20 — ECS & Content](docs/20-ecs-and-content.md) | Component model, data-driven content, mod-ready loading |
| [21 — Extensibility](docs/21-extensibility.md) | Event bus, modifier pipeline, and the add-a-feature cookbook |
| [22 — Performance](docs/22-performance.md) | Tiered simulation, field propagation, scaling to a horde |
| [27 — Multiplayer](docs/27-multiplayer.md) | Authoritative host, survivor-vs-survivor PVP, voice as an emitter *(post-slice)* |
| [23 — Roadmap](docs/23-roadmap.md) | The vertical slice, milestones, risks, open questions |
| [30 — Decision Records](docs/30-decisions.md) | What each chunk of work made structural, oldest first |
| [31 — Godot Rebuild Roadmap](docs/31-godot-rebuild-roadmap.md) | Transition phases, parity gates, delivery, and cutover |
| [32 — UI Overhaul](docs/32-ui-overhaul.md) | Proposed visual direction, management flows, anatomical equipment diagram and all-screen acceptance |

## Reading order

New to the project? **[00](docs/00-vision.md) → [01](docs/01-hardcore-contract.md) →
[03](docs/03-attention.md) → [23](docs/23-roadmap.md)** covers the thesis, the tone, the central
mechanic, and what actually gets built.

Building it? Add **[19](docs/19-architecture.md) → [20](docs/20-ecs-and-content.md) →
[21](docs/21-extensibility.md)**, then **`CLAUDE.md`** and
**[where Milestone 2 stands](docs/23-roadmap.md#where-milestone-2-stands)** for where the code
actually is, and **[30](docs/30-decisions.md)** for why it is shaped that way.
