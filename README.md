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
[CLAUDE.md](CLAUDE.md): it is the entry point for anyone changing the code, person or agent, and
leads to the design documents, the roadmap and the checks every change must pass.
