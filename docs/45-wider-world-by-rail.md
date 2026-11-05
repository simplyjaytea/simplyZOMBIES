# The wider world by rail: a design note

Draft, 2026-11-06. A design note, not a piece: nothing here is scheduled, sized or built. It opens
the planned piece "The wider world by rail" in
[docs/23](23-roadmap.md#whats-left-in-milestone-2), and it is written the way
[docs/42](42-ome-okutama-setting.md) is written: the real places it draws on, a fictional map, the
order of work, and owner cards with one recommended default each. The Kagase valley ships first
([docs/30](30-decisions.md#the-setting-cards-the-defaults-and-the-valley-is-the-first-of-several-2026-11-04)).

## 1. The owner's plan

> "defaults, send Kimi the Japanese buildings after the rifle. The end goal is to have other
> districts, and cities. Maybe even tokyo! To travel between them the user will have to take a
> train, they will have to repair the train, etc. That's just the plan."

So the end state is more than the valley: other districts, cities, and possibly Tokyo, reached by a
train the colony has to repair first.

This note does not schedule that. It does not size it, and it does not decide any rule a player would
notice. Those questions go to section 7 as cards. The valley ships first, with its own station, its
own town and its own first expedition, as docs/42 describes.

## 2. The real line to draw on

The JR Ome Line runs 37 km west from Tachikawa to Oku-Tama. Its upper half, from Ome to Oku-Tama,
is about 19 km. Beyond Ome it is single track with passing loops. It follows the Tama River up a
narrowing gorge, crossing the water on girder bridges and cutting through short tunnels. The
terminus station building dates from 1944 and is a lodge-style hall. A freight branch once ran from
Mitake to the cement works across the river, and a ropeway that served the same works has been
dismantled. These facts are from [docs/42](42-ome-okutama-setting.md#2-the-real-valley) and its
sources, and they are the only real railway facts this note relies on.

What the game takes from the line:

- **One track.** A single train on the upper section, with a passing loop at each station that has
  one. A train meeting another on the line is a scene the game does not have, and does not need.
- **The river beside it.** The line and the Kagase River share a valley floor, so every rail stretch
  is a stretch of water too. Bridges are the places where the river and the line meet.
- **Tunnel portals as edges.** docs/42 already makes the two tunnel portals the only ways out of the
  valley. The rail line is one of them.
- **The terminus as the gate.** Oku-Kagase, with its lodge hall, is where the colony's train is.

**What a stopped railway looks like after a collapse** is a design picture, not a fact claimed about
any real line. The first things a player should see on the platform: a set of carriages left at the
platform where the last train stopped, its doors shut, dust on the windows; the depot with its
roller door up and a tarpaulin over something; trees across the cutting above the station, bark
stripped; a level crossing whose barrier stands down and whose lamp is dark; signal posts with no
lamps; grass between the sleepers, and track buckled where a bridge approach has moved. Each is a
prop in the dresser's sense of [docs/42 section 4](42-ome-okutama-setting.md#4-building-types). The
stranded carriages are the train the colony repairs (section 4).

**Names.** The line is the Kagase Line, and its stations are the fictional names in
[docs/42 section 3](42-ome-okutama-setting.md#3-the-fictional-valley): Umezaki, Sawanobe, Mikumo,
Iwanosu, Kawahara, Oku-Kagase. The first destination is the next town down the line, past Umezaki.
Its proposed name is **Asahigaoka**. It is fictional, and it is checked against the real station
names before any content ships, as docs/42 requires.

## 3. The world model

**What docs/24 already says.** The region is one continuous coordinate space of 9 to 16 districts,
joined by roads, with no loading screens and no travel menus ([docs/24, the region](24-world-and-scale.md#the-region)).
That is the ideal. The alpha does not build it. docs/23 decided that the main area is several typed
districts in **one resident map**, with no streaming and no district-tier simulation, and that
Milestone 3B item 1 stays open and Risk 7 stays untouched ([docs/23, where Milestone 2 stands](23-roadmap.md#where-milestone-2-stands)).
The alpha's districts are 528 tiles a side with a 16-tile seam, not the 300 to 500 metres of road
docs/24 argues for; the amendment is measured, and the extent is a content number (`cellTiles`).

**The rail model.** Each destination is a region of its own, with its own resident map, generated
from its seed, so it is the same world every time ([docs/24, simulation tiers](24-world-and-scale.md#simulation-tiers-by-distance)
says the same of a district that is resolved from the seed). The train is the only link between
regions. There is no road seam between them and no district tier: a region is resident while the
player is in it and is not simulated while they are not. The valley's station is the gate out, and
the batch B station template ([docs/42, section 6](42-ome-okutama-setting.md#6-the-order-of-work), the
station in the first batch of art) is where the platform's transition trigger sits.

**What this avoids.** It avoids streaming, so Milestone 3B item 1 and Risk 7 stay where they are. It
avoids the district tier, so the tier that docs/24 describes stays unbuilt. It avoids the road seams
between districts, because the rail line takes that role.

**What it needs, and this is new.** A transition between resident maps: leave one map, load another,
and carry the colony across. Today a save carries only its seed (PLAYBOOK, "Known bugs": a save bump
refuses every v33 save, district saves included, because a save carries only its seed). A colony
that crosses to another region is state a seed cannot hold. The save format therefore has to change
before it freezes. The release plan freezes it at beta (PLAYBOOK, "The release plan", stage 4), so the
transition's save design has to land before then or migrate from the freeze onward.

**Towns and cities.** A town is a resident map of the same kind as the valley's: the existing
generator at its existing size, with its own pools. A city is not a town at a larger size. The
region's cells and the district types in docs/24 do not scale to a city, and a city is the first
destination that needs streaming, so **a city waits for Milestone 3B.** Towns do not.

**Tokyo** is the far end of the line, as the premise says. It is not a destination in this note. It
is a horizon (card 36). The one real place name allowed in game text is Tokyo, by docs/42 card 2.

## 4. The train as the colony's project

**The object.** A diesel railcar, one unit, is the first cut. The game does not model overhead wire,
so a diesel car is the honest choice for a line the colony has to bring back on its own power. It
starts as a stranded set at the Oku-Kagase platform (section 2), and it is repaired into a working
car at the depot.

**The parts list.** Four tiers, each a found item in a district. The default is the one that
matches the place the parts are made:

| Tier | Parts | Found in |
|---|---|---|
| I | Bodywork, glass, seats | Umezaki Ekimae: the shotengai and the konbini |
| II | Drive and brakes | Kawahara Yards: the machine shop, `building.workshop.unit` in docs/42's list |
| III | Fuel system and electrics | The Hikage Works warehouse |
| IV | Coupling, signalling and the depot's own spares | Oku-Kagase: the depot itself |

**What the sim can already price.** The pattern is a carried material spent at a site. The trip
alarm's pricing (one wire, spent in `fortify.gd`'s `_complete` only after the placement checks pass)
is on the branch that carries it, PR #349, and is not on `main` as this note is written.
The purifier refill is "a material, not a key" ([docs/30](30-decisions.md#the-purifier-refill-is-a-material-not-a-key-2026-11-04)).
A tier of the train is that pattern repeated four times, at a bench, with the item's own name and
no new currency. Readers that exist: the recipe table and the carried-item spend (`fortify.gd`), the
bench (`godot:m2:bench`), the vehicle condition and repair model (`godot/sim/modules/vehicles.gd`,
docs/25 "Condition, breakdowns, and repair"), and the item repair ceiling (`repair_cost`, in the
record of docs/23).

**The skill gate.** Repair already needs a skill: docs/25 says repair "needs parts, Craft skill,
tools, and ideally a workshop". The skill web exists (`godot:m2:web`). The gate is a Craft level,
which is a number to set by balance, not sized here.

**Fuel and power.** Fuel is finite and industrial-only ([docs/24, the fuel bound](24-world-and-scale.md#distance-and-the-expanding-radius)).
The vehicles module already holds a fuel spec per base, a refuel check and a burn per idle and per
move (`fuel_spec`, `refuel_problem`, `idle_burn`, `move_burn`). Readers that exist are the per-base
burn and the refuel action. Readers that do not are a route, a stop, and a burn per distance along a
line.

**Crew.** One driver, as a vehicle has one driver seat. A second colonist for signalling is a card
(section 7), not a default.

**What a run costs in days.** A day is one real hour (the owner's call of 2026-10-19; PLAYBOOK
states it, and `Clock.DAY_SECONDS` holds it). A run on the line is minutes of game time, so the cost is not the ride. It is the fuel, the parts' wear, a
day's food at the destination, and the time the colony is away from home. Section 5 says what happens
at home.

## 5. Travel as play

- **Boarding.** The player walks onto the car at the Oku-Kagase platform. It is a mounted seat, the
  same kind of rule a vehicle already uses (the `mounted` component, with a `cab` flag), so a body in
  the car is sheltered and a body on the platform is not.
- **The ride.** A timed transition with risk. Its length follows the line's distance, and the risk
  comes from the line's content: a blocked cutting with its fallen trees, a body on the track at a
  level crossing, a raider at a station. A stop on the line is a check against the crew's skill and
  the car's condition. The stop is the play; nothing about it is a cutscene.
- **Arrival.** The destination's resident map is generated from its seed, and the player steps off at
  its station. Colonists travel only if the player takes them; the rest stay at home.
- **Return.** The same ride back. The destination is generated from its seed again, so a destination
  the player did not change needs no save. A change made there does, and that is the save question in
  section 3.
- **Home while away.** Not decided. Card 37.

## 6. The order of work

As docs/42 section 6 lays out its order, each step with its gate, none sized:

1. **The station template.** `building.station.small` is in docs/42's first batch of new templates.
   Gate: the finishes `--check` and `npm run godot:check:buildings`.
2. **The stranded set as scenery.** A railcar prop on the Oku-Kagase platform and a depot with its
   door up. No mechanic. Gate: `npm run godot:check:buildings` and `npm run godot:check:fp_geometry`.
3. **The repair ledger.** The four tiers as content, spent at the depot's bench, with the Craft gate.
   Gate: the materials and bench lanes (`godot:m2:materials`, `godot:m2:bench`), extended by one lane
   each, and `godot:m2:web` for the skill.
4. **The first destination region.** Asahigaoka as a second region config with its own resident map,
   reached by a train that is not yet a transition. Gate: `godot:m2:region` and `godot:check:worldgen`.
5. **The transition.** Leave one resident map, load another, carry the colony across, and the save
   design that makes it possible. Gate: `godot:m2:save` with a cross-map round trip, and a true
   negative that loses a survivor on the way, which must fail the gate.
6. **More destinations.** Content only, once step 5 holds. A city waits for Milestone 3B streaming.
   Tokyo waits for the city.

## 7. Owner cards

Each has one recommended default. The default is built only when the owner picks it, and the cards
are numbered after the last card in [docs/33](33-owner-decisions.md#waiting-on-the-owner).

33. **How many destinations in the first cut?** Default: **one**, Asahigaoka, the next town down the
    line. Recommended: one until the transition works in play. More is content, and it waits on step 5.
34. **Does the train run on a timetable or on demand?** Default: **on demand**. The player calls it
    from the platform when the car is repaired, fuelled and crewed. A timetable is a later layer,
    and it would need the district tier that the alpha does not build.
35. **Can raiders use the line?** Default: **no** in the first cut. docs/24 says raiders use roads. A
    raider on the line would reach a destination's resident map without the player, and the alpha has no
    rule for that. Later, a raider may board at a station, as docs/18 may allow.
36. **Is Tokyo a destination or a horizon?** Default: **a horizon**. Tokyo appears on the line's map and
    at the far end of the premise, and no shipped piece makes it resident. The owner's "maybe even
    Tokyo" stays open for the city arc.
37. **What happens to the colony while the player is away?** Default: **frozen**. Home is not
    simulated while the player is elsewhere. On return, the days away are not replayed; the colony
    resumes where it stopped. Recommended: frozen. A later card can change it to a six-number home,
    which docs/24's district tier describes and the alpha does not build.
38. **Does the car need a second crew member?** Default: **no**. One driver, as a vehicle has one
    driver seat. A second colonist for signalling is a balance question, and it is open.
39. **Which tier of parts is the hardest?** Default: **Tier III**, the fuel system and electrics, found
    only at the Hikage Works warehouse. It is the valley's one industrial site, so the hardest part and
    the fuel question are found in the same place.

**Numbering.** Cards 33 to 39 are the numbers this note takes. The clothing layers note (PR #328,
docs/44) takes cards 28 to 32 and merges first, so these follow it.

## 8. Sources

The real line is sourced in [docs/42, section 8](42-ome-okutama-setting.md#8-sources). This note adds
no real-world railway claim beyond those sources. The region, roads and tier design are in
[docs/24](24-world-and-scale.md). The save format's limit is in PLAYBOOK's "Known bugs".
