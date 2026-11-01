# simplyZOMBIES

A hardcore zombie survival colony sim. You lead one survivor and a handful of others through a
dead town, and every comfort you make is a signal the dead can follow.

**The better you live, the harder they come.**

It borrows from three games: RimWorld's colony and its work priorities, Project Zomboid's
unforgiving survival, and Zero Sievert's top-down pixel art.

## Play it

- **In a browser:** [play the latest build](https://simplyjaytea.github.io/simplyZOMBIES/). It is
  rebuilt from every change that passes the project's checks.
- **On Windows:** download the archive from the
  [releases page](https://github.com/simplyjaytea/simplyZOMBIES/releases), unzip it anywhere and
  run `simplyZOMBIES.exe`. There is no installer. SmartScreen may warn once, because the build is
  not signed.
- **From source:** see [Running it yourself](#running-it-yourself) below.

This is an early alpha. A later version may not read an earlier version's saves.

## How a run goes

You start at dawn on day one with two companions, Mara and Ellis, an empty bottle each and very
little else. A day lasts one real hour: half an hour of daylight, then dusk, then a short night
that is nearly black.

1. **Dawn.** Count what last night cost. Treat wounds, repair what broke.
2. **Day.** Scavenge the district while the colony works: hauling, building, cooking, tending
   the hurt. Fetch water from the well and keep everyone fed.
3. **Dusk.** Barricade, decide who keeps watch, decide whether tonight is worth a lamp.
4. **Night.** There is no wave timer. What comes is what your noise, light and scent earned you.
5. **Repeat** until something goes wrong, because it will. There is no winning, only lasting.

When your survivor dies, the run can carry on through whoever is left.

## What makes it different

- **Everything you do is a signal.** Noise and scent spread across the district, and light
  changes what can see you. Gunfire, cooking, a fire, a car engine, even a shout: the dead hear
  it and come.
- **The screen never shows a health bar.** You read your condition as words, body part by body
  part. A bite can look like a scratch, and you may not know who inside your walls is infected
  until it is too late to choose kindly.
- **Melee and ranged both cost you.** A swing spends your body and risks a bite. A shot spends
  ammunition you cannot make, and tells the whole district where you are.
- **Nobody has a class.** Survivors get better at what they do, through a skill web earned by
  practice and the gear they find.
- **Your colonists act on their own,** and you steer them: set work priorities, or tell one to go
  somewhere, hold a spot or haul something.
- **You see only what your survivor can see.** Walls block sight and bullets. What you saw a
  moment ago is remembered as a place and a rough count that goes vague as it goes stale.

## Controls

`F1` shows the keys in the game, and that sheet is always the most up to date. The same list:

**Move**

| Key | Does |
|---|---|
| `W` `A` `S` `D` | walk |
| `Shift` | sprint: fast, and loud |
| `Ctrl+Z` / `Ctrl+C` / `Ctrl+S` / `Ctrl+V` | crawl, crouch, stand, jog |

**Act**

| Key | Does |
|---|---|
| Mouse | aim: you turn to face the cursor |
| Left click | attack: fires a gun or bow if one is in hand, swings if not; on a colonist, selects them |
| Right click | what you can do with what is under the cursor: walk there, pick up, open, attack, first aid, and orders for a selected colonist |
| `F` | swing, or struggle out of a grab |
| `H` | pull someone out of a grab |
| `G` | fire |
| `R` | reload |
| `E` | interact: pick up, open a cupboard or a car, drink at the well, use a bench |
| `T` | first aid: a bandage if you have one, bare hands if not; press again to stop |
| `C` | make camp where you stand; `Shift+C` strikes it |
| `1` to `6` | use what is on your belt and in your pockets |
| `Space` | shout, heard across the district |

**Look**

| Key | Does |
|---|---|
| `Tab` | your survivor: gear, bags and injuries |
| `J` | the colony: who does which work |
| `K` | skills: what a survivor knows and could learn |
| `O` | light overlay: where lamps and fires reach |
| Mouse wheel | zoom |

**Time**

| Key | Does |
|---|---|
| `-` / `=` | slower, faster (normal or three times speed) |
| `P` | pause |
| `F5` / `F9` | save, load |
| `Esc` | close what is open; otherwise the menu: resume, save, load, settings, quit to title |

Sleeping fast-forwards the night, and stops when a zombie comes close.

## First person (experimental)

The title screen has a row, **first person (experimental)**, above quit. It opens the same district
and colony in a first-person view. `Esc` frees the mouse, and a second `Esc` takes you back to the
title. The top-down game is still the default: New run starts the top-down game, as before.

- **Look and walk:** the mouse turns you, `W` `A` `S` `D` walk, `Shift` sprints. `Ctrl+Z`, `Ctrl+C`,
  `Ctrl+S` and `Ctrl+V` go prone, crouch, stand and jog. Your eye height follows your stance.
- **Act:** `E` works on whatever you face: the ledger at the desk, a cupboard, shelf or chest, a door,
  or one of your colonists. A prompt at the bottom of the screen names what `E` will do. `LMB` or `F`
  swings, `G` fires, `R` reloads.
- **Talk:** `E` on one of your colonists in reach opens a short conversation: their name, how they
  feel, and what they are doing, in the words the Colony screen uses. Walking stops while it is up,
  and `Esc` closes it.
- **The ledger:** the work grid, with the skill web one button away. The Reports button lists what
  happened while you were away, in the chronicle's own words, and marks what is new. `Esc` goes
  back from Reports to the grid, and from the grid to the street.
- **Time:** `-` and `=` run the clock slower or faster (normal or three times speed), and `P` holds
  the world still. The clock keeps running while the ledger or a sheet is open, and your body stops.
- **Keys:** `F1` lists the keys the first-person view handles, and that list is the one to trust.
- **Save and load:** `F5` saves and `F9` loads, in a slot of its own, so the first-person save never
  replaces your top-down one.
- **When your survivor dies:** the camera moves to whoever is left. If nobody is left, the run ends
  and an end panel shows the last things that happened. `Esc` or `Enter` returns to the title.
- **Night:** the sky follows the day, and a carried torch lights a cone in front of you.

What you see: walls are drawn as the kit's wall modules, with boards over a boarded window. Shelves
are drawn as shelves, and things lying on the floor are drawn as their own models: tins, bottles,
tools, bags and the like. A held gun is built from the parts it has, so a fitted suppressor or optic is
in your hands; a bat or an axe is drawn whole. Survivors and colonists are drawn as people, and zombies as shamblers,
with their own clips for standing, walking, crouching, lunging and falling. Cupboards, tool chests and
wardrobes are still labelled boxes.

What is still placeholder: benches are being added. Your own arms and legs are not drawn yet; they
are the next piece, so you see your weapon and nothing of your body. There is no crosshair, by
design. Combat is interim: you aim with the mouse, and the sim decides hits on the ground plane, so
a shot does not yet travel the way you see it. Sound is minimal.

## Where it stands

The alpha is playable end to end: scavenging, needs, wounds and infection, a colony that works
and fights, a director that varies the nights, weather, vehicles, saving and loading. It is
still hard in ways that are being tuned: in recent ten-day test runs a colony usually lasts four
to nine days. Sound is minimal, and the interface is midway through a redesign.

## Running it yourself

The game is built with [Godot 4.7.1](https://godotengine.org/) (exactly that version) and needs
Node.js 22 for the project's scripts.

```bash
git clone https://github.com/simplyjaytea/simplyZOMBIES.git
cd simplyZOMBIES
bash scripts/setup-web-session.sh   # Linux: installs the pinned engine and npm packages
npm run godot:run                   # play
npm run godot:editor                # open the project in the Godot editor
```

On another system, install Godot 4.7.1 yourself, run `npm ci`, and point `GODOT_BIN` at the
Godot executable if `godot` is not on your `PATH`. The scripts refuse any other engine version.

## Contributing

The project is built mostly by AI agents working with its owner. Start with
[PLAYBOOK.md](PLAYBOOK.md): it is the entry point for anyone changing the code, person or agent, and
leads to the design documents, the roadmap and the checks every change must pass.
