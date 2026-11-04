# The Ome–Okutama setting brief

Draft, 2026-11-04. A brief, not the re-theme. It follows the owner's call of 2026-11-04
([docs/30](30-decisions.md#the-setting-is-japan-the-omeokutama-valley-2026-11-04)): the game is set
in Japan, inspired by the real Ome–Okutama valley at the far end of the JR Ome Line in western
Tokyo; every place name, business and brand in the game is fictional; the real layout, landscape
and architecture are the inspiration; the premise is "the last stop on the line out of Tokyo". The
planned piece it opens is docs/23's "The Ome–Okutama re-theme".

## 1. What this decides and what it does not

This document decides words and pictures. It names the fictional valley and its towns, maps the
four district kinds we already generate onto stretches of that valley, says what each of the 22
building templates becomes, lists the building types worth adding and the props they want, and
proposes a fictional name for every piece of content whose name is a place, a brand, a unit or a
Western thing. It also sets the order the work lands in.

It does not change a mechanic. Nothing here alters a need, a wound, a job, a loot table's odds, a
zombie, the weather's numbers or the generator's rules. Where a proposal would be a new rule a
player could notice (a new water source, how common a gun is, where the colony starts), it is not
decided here: it goes to the owner as a card in section 7 with one recommended default, per the
playbook's "Who decides what". The firearms question in particular already has its card in
[docs/33](33-owner-decisions.md) ("How common are firearms in a Japanese setting?", default: rare);
this brief fits the existing guns to that default and decides nothing further.

Two rules that hold through the whole re-theme:

- **Ids are stable; names change.** An `id` such as `district.residential_suburb`,
  `building.house.small` or `item.food.jerky` is a key that saves, loot tables, kits, gates and
  parity fixtures reference. The re-theme renames the `name` and `description` a player reads and
  leaves the `id` alone, unless the owner picks the id rename in card 5. Where a new id is
  needed (a new template, a new district), it is given here and is permanent once shipped.
- **Real places inspire; nothing real is in the game.** This document names real places when it
  says what inspired a thing. The content never does. No real station, shrine, brewery, cement
  company, retailer, railway or brand appears as in-game text, and the fictional names are chosen
  not to be the real ones with a syllable changed. The one real name allowed in game text is
  Tokyo, the city at the bottom of the line (card 2).

## 2. The real valley

The inspiration, from the lower town up to the lake. Figures are from the sources in section 8 and
are rounded; where sources disagree, the range is given.

### Geography, by stretch

The JR Ome Line runs 37 km west from Tachikawa to Oku-Tama. Its lower half crosses the flat
Musashino plain through suburbs; the stretch that matters here is the upper half, Ome to
Oku-Tama, about 19 km, nicknamed the "Tokyo Adventure Line" by the operator. Beyond Ome the line
is single track with passing loops, and it follows the Tama River up a narrowing gorge, crossing
it on girder bridges and cutting through short tunnels. The valley floor drops from about 190 m at
Ome to the river, and the ridges either side rise to 900 to 1,300 m, with Mount Kumotori, Tokyo's
highest point at 2,017 m, at the far end.

| Stretch | Real places | What it looks like |
|---|---|---|
| The lower town | Ome, Higashi-Ome, Miyanohira | A station town on the old Ome Kaido post road. Two-storey Showa-era shop-houses along a main street parallel to the tracks, a shopping arcade with roll-down shutters, hand-painted film billboards, a plum park, a railway park, a textile past (Ome-jima cotton). The hills close in to the north and south. |
| The low gorge | Hinatawada, Ishigamimae, Futamatao, Ikusabata | The valley narrows. Houses step up the slopes on concrete retaining walls. Riverside camps, a trout fishing area, small shrines, the Kanto Fureai hiking path along the water. |
| The brewery stop | Sawai | A sake brewery founded in 1702 sits on the river with a garden terrace; brewing water is drawn from a hand-dug well. Riverside noodle stalls, a footbridge, old timber kura storehouses with white plaster. |
| The shrine mountain | Mitake, Mount Mitake (929 m) | A bus runs from the station to a cable-car base; the cable car climbs to a summit village of about twenty households, many of them shukubo pilgrim lodgings, some thatched, some from 1776 and 1886. Stone steps (about 330) climb to a mountain shrine. Mitake Gorge below is a boulder gorge with a riverside path. |
| The upper gorge | Kawai, Kori, Hatonosu, Shiromaru | Fewer houses, more cedar. The Hatonosu gorge has a small suspension footbridge over a deep green pool; the Shiromaru dam (30 m high) backs a thin reservoir; the "Otama walking course" follows the bank between them. |
| The terminus | Oku-Tama (formerly Hikawa) | A mountain-lodge-style station building (1944). A cement works with its own limestone quarry sits across the river from the town, run-down but working, once fed by a freight branch from Mitake and a dismantled ropeway. The Nippara river joins the Tama under a suspension bridge. A visitor centre, an onsen, a few ryokan, a konbini, a school, a kōban. Population fell from 16,000 in 1950 to under 5,000 today, so many houses are empty. |
| The old road and the dam | Okutama Mukashi-michi (the old Ome Kaido), Ogouchi Dam, Lake Okutama | The old road walks 10 km up the gorge past wayside shrines, a disused waterworks railway (23 tunnels, 23 bridges) and rock faces to the dam, finished in 1957 after displacing 945 households and killing 87 workers. The lake is Tokyo's drinking water. A floating pontoon bridge crosses it. |

### Architecture, by type and era

| Type | Era | Shape and materials |
|---|---|---|
| Minka farmhouse | Edo to Meiji | One storey plus loft, heavy post-and-beam, deep eaves, kawara tile or (rarely now) thatch over tin; dark timber, white plaster infill, engawa veranda, stone footings, a kura storehouse beside it. |
| Shop-house (machiya type) | Meiji to early Showa | Narrow and deep, two storeys, shop at the street with a wooden shutter or glass front, living quarters behind and above; kawara roof, dark timber, copper or tin flashing gone green. |
| Showa shop-house | 1950s to 1970s | The same plan with a flat "signboard" false front of painted sheet metal or tiles over the timber, a roll-down steel shutter, a fabric awning, a glass display case. |
| Wooden two-storey house | 1960s to 1990s | The ordinary house: kawara or pressed-metal roof, mortar or sheet-siding walls, aluminium sash windows with amado storm shutters, a genkan step, a concrete-block garden wall with a tile cap, a carport. |
| Apāto block | 1970s to 1980s | Two storeys, external steel stair, flat or shallow roof, render; four to eight small flats. |
| Public buildings | 1960s to 1980s | Concrete frame, render, flat roof: the school, the community centre, the clinic, the town office, the fire-brigade shed with its siren mast. |
| Station | 1890s to 1940s, rebuilt | One-storey timber waiting room, a short platform with a tin canopy, a level crossing, a bike shed. The terminus is a larger lodge-style hall with a steep roof. |
| Kōban police box | Any | A one-room render box with a red lamp, a bicycle outside. |
| Konbini | 1980s on | Flat roof, glass front, bright canopy, vending machines, a small car park. |
| Shrine and temple | Any | A torii gate, stone lanterns, a water basin, komainu, a cedar grove, a small haiden hall on stone footings under a deep kawara or copper roof; a temple adds a bell frame and a graveyard of stone stelae. |
| Lumber yard and sawmill | 1950s on | Open-sided tin sheds on steel or timber posts, log stacks, a band saw shed, drying racks, a kerosene tank, a kei truck. |
| Cement works | 1930s on | Steel and concrete: kilns, silos, conveyor galleries, a quarry face above. The one truly industrial thing in the valley. |
| Infrastructure | Any | Concrete river revetments of stepped blocks, retaining walls on every slope, utility poles with transformers and dense wires, convex road mirrors, guardrails, concrete tunnel portals, a cable car. |

### Materials and colours, for the art lead

Grey kawara tile (not red), darkened cedar boards, sometimes charred (yakisugi), white or cream
mortar and plaster that has streaked grey, galvanised corrugated sheet gone rust-brown at the
edges, pale concrete block with a moss line at the base, aluminium sash frames, faded signboard
blues and oranges on Showa fronts, red torii and red kōban lamp as the only saturated accents.
Ground: wet grey asphalt, concrete, river cobbles, pale granite gravel in shrine precincts,
cedar-needle brown under the trees. Vegetation: cedar and cypress plantations in straight dark
rows with bare trunks, broadleaf scrub along the river, bamboo groves at field edges, plum and
persimmon trees by houses, moss on every north face. The palette is cool and low-chroma with
restrained accents, which is the docs/39 look already.

### Climate

Humid subtropical at the valley floor (annual mean about 10.6 °C at Oku-Tama, 12.3 °C at Ome).
Summers are warm and wet (August about 22 to 24 °C), with the June rainy season bringing mist on
the mountains and September the wettest month under typhoon rain; the river floods and the
revetments are what keep the towns. Winters are cold and clear (January about -1 °C up-valley,
sunny and dry at Ome); snow is uncommon on the valley floor and normal on the ridges. Annual
rainfall is quoted between 1,300 and 2,100 mm depending on the station. The existing climate
content (`godot/content/climate/temperate.json`, with rain, fog, snow, storm, cold snap, heat wave)
already covers this range; the re-theme changes its prose, not its numbers (card 10).

## 3. The fictional valley

All names below are invented. Where one coincides with a hamlet or a surname somewhere in Japan,
it does not refer to it, and none is a place on the real line.

| Thing | Fictional name | Inspired by |
|---|---|---|
| The valley and the region | **Kagase** (the Kagase valley) | The upper Tama gorge |
| The river | **the Kagase River** | The Tama |
| The railway | **the Kagase Line** | The Ome Line's upper half |
| The lower town, the station town | **Umezaki** | Ome and its Showa streets |
| Its hillside housing | **Hinatadai** | The slopes above Ome and Hinatawada |
| The brewery stop | **Sawanobe** | Sawai |
| The shrine mountain and its station | **Mikumo**, Mount Mikumo, Mikumo Shrine | Mitake |
| The gorge hamlet | **Iwanosu** | Hatonosu |
| The riverside yards | **Kawahara** | The lumber flats and the Hikawa works |
| The terminus town | **Oku-Kagase**, old name **Hikage** | Oku-Tama, formerly Hikawa |
| The cement works | **the Hikage Works** | The Okutama cement plant |
| The dam, the lake and the drowned village | **Kaminose Dam**, **Lake Kaminose** | Ogouchi Dam and Lake Okutama |
| The old road | **the old Kagase road** | The Ome Kaido and the Mukashi-michi |

### The map in words

Read it from the bottom of the valley upward, the way the train runs. Downstream is the city and
everything the colony left; upstream is the dam, the lake and the end of the road.

**Umezaki** is the last real town. The station sits on the main street, which is the old Kagase
road; the shotengai arcade runs beside it with its shutters down, two-storey shop-houses on both
sides, a konbini at the crossing, a clinic, the community centre, the kōban. Above the street,
**Hinatadai** steps up the south slope in terraces of wooden houses and a couple of apāto blocks,
with concrete-block walls and carports along narrow lanes. Below the street the river runs under a
road bridge. This is where the people were, so this is where the dead are.

The line and the road climb together through **Sawanobe**, where a brewery's white kura stand by
the water, past the **Mikumo** station and its cable-car base at the foot of the shrine mountain,
and into the gorge. Houses thin out. At **Iwanosu** a footbridge hangs over a green pool.

**Kawahara** is the flat where the valley opens for a kilometre before the terminus: lumber yards,
a sawmill, a machine shop, a co-op depot, a fuel stand, then the **Hikage Works** across the river
with its silos and quarry face. **Oku-Kagase** is the terminus: a lodge-style station, a street of
inns and shops, a school, a fire-brigade shed. Beyond it the old Kagase road climbs to the
**Kaminose Dam**; above the dam the lake, the cedar slopes, the forestry huts and nothing else.

### The four district kinds

The generator stamps four district types ([docs/24](24-world-and-scale.md)). Each becomes one
stretch of the valley. The `type` labels and ids stay (section 1); the names change.

| Today | Becomes | Stretch | What changes in the generator's terms |
|---|---|---|---|
| `district.town_center`, "Market Cross" | **Umezaki Ekimae** (the station front) | The lower town | Commercial pool draws the shotengai row, konbini, corner shops; civic draws clinic, community centre, kōban, station. Nothing numeric moves. |
| `district.residential_suburb`, "Fairfield Rise" | **Hinatadai** | The hillside housing | Residential pool draws tiled-roof houses, nagaya pairs, the apāto block; sheds draw carports and kura. Vehicles lean to kei cars and bicycles. |
| `district.industrial_park`, "Ordnance Way" | **Kawahara Yards** | The riverside yards and the works | Industrial pool draws the sawmill shed, works warehouse, machine shop, yard office; vehicles lean to kei trucks and vans. |
| `district.forest_edge`, "Blackpine Reach" | **Kaminose Shore** | The dam, the lake, the cedar slopes | Cabin pool draws forestry huts and a bunkhouse; its river and lake water (`water.river`, `water.lake`) are the Kagase and Lake Kaminose. |

The region `region.main_area`, "Ashgrove", becomes **Kagase**. Its 2x2 of cells can read as the
valley's axis if the cells are re-ordered so that x runs up-valley: the two lower-valley cells
(Ekimae and Hinatadai) at x=0, the two upper-valley cells (Kawahara Yards and Kaminose Shore) at
x=1, with the river's north-south axis in the forest district unchanged. That is a content edit
judged by `godot:check:worldgen` and `godot:m2:region`, listed in section 6.

```
            N
   +-------------------+-------------------+
   |  HINATADAI        |  KAMINOSE SHORE   |
   |  (residential)    |  (forest edge)    |
   |  houses on the    |  dam, lake, cedar |
   |  slope, apato,    |  slopes, forestry |
   |  block walls      |  huts   ~~~lake~~~|
   +-------------------+-------------------+
   |  UMEZAKI EKIMAE   |  KAWAHARA YARDS   |
   |  (town centre)    |  (industrial)     |
   |  station,         |  sawmill, works,  |
   |  shotengai, kon-  |  machine shop,    |
   |  bini, clinic     |  [start: yard]    |
   +-------------------+-------------------+
  <-- down-valley: the city        up-valley: the dam -->
      ====== the Kagase Line and the old road run left to right ======
      ~~~~~~ the Kagase River runs along the bottom edge ~~~~~~~~~~~~~
```

### Where the colony starts

The hand-authored start map `map.district.alpha` (26 x 26, two gates, a well, a player start)
becomes a **walled timber yard** on the Kawahara flat: a sawmill compound with a block wall, a
sliding steel gate on the road side and a yard gate on the river side, a hand-pump well in the
yard, log stacks, a drying shed, a yard office. A lumber yard is what the real valley has in
quantity, it explains a well and a wall without a prison or a base, and its timber is the
colony's first material. The recommended start is there (card 4). The premise line, "the last
stop on the line out of Tokyo", is literal: the survivors got off at Oku-Kagase because the train
went no further.

### Where the first expedition goes

Down the valley toward the city. From the yard the road and the line lead down through Kawahara
into Umezaki Ekimae, the dense commercial district where the loot is and the dead are. The city
itself is off the map, further down the line; the first expedition reaches the lower town and
turns back. Whether a "city fringe" district is ever generated is card 3 (default: not now; it is
docs/41's P5, the region as the world, when the budget holds).

### The edges

The river is one edge: the Kagase runs along the valley floor, three to six tiles wide in the
forest district's `water.river`, with fords, and it is a water source as docs/30 says. The
mountains are the other edges: cedar plantation rising steeply from the last row of houses, so
the map ends in trees and retaining walls rather than in a fence. The line and the road enter at
the down-valley edge and leave at the up-valley edge through tunnel portals, which read as the
only two ways out.

## 4. Building types

A template is a tile grid, one tile per metre (`SimTileMap.TILE_METRES`), with `tiles`,
`surfaces`, `indoors`, at least one door, tags the district pool selects on, a weight, and a
`look` of `{roof, wall}` drawn from the enum in `godot/content/schemas/building.schema.json`
(roof: `shingle`, `tin`, `tar`; wall: `timber`, `brick`, `render`, `block`), resolved through
`godot/content/dressing/street.json`. Every footprint below fits the existing range (5 x 5 to
22 x 14) and the low-rise rule: one walkable floor, no stairs (docs/23 "Deferred: z-levels").
Two-storey buildings have a two-storey exterior and a ground-floor interior; the stair is a
blocked tile (card 9).

Two `look` values are worth adding so the templates can say what they are: roof **`kawara`**
(grey ceramic tile) and wall **`siding`** (painted sheet-metal siding over timber). Both are a
schema enum change plus a `street.json` table row plus the art lead's material;
`check_roof_look.gd`'s LOOK lane holds the enum, so the change is gated. Until they exist,
`shingle` stands in for kawara and `timber` or `render` for siding, and nothing is blocked.
`brick` should disappear from the templates: brick is rare in the valley.

### The 22 templates

| Template | Size | Becomes | Look | Props it wants |
|---|---|---|---|---|
| `building.arcade.retail`, "Retail Arcade" | 18 x 13 | **Shotengai row**: four shuttered shopfronts under one canopy, stockrooms behind | tin / siding | roll shutters, awnings, signboard fronts, display cases, a vending machine, bicycles |
| `building.bungalow.flat`, "Flat-Roofed Bungalow" | 11 x 8 | **Apāto ground floor**: two small flats off an open stair | tar / render | external stair (blocked), unit doors, washing machines outside, mailboxes |
| `building.cabin.long`, "Long Cabin" | 11 x 5 | **Forestry bunkhouse** | tin / timber | bunks, a kerosene stove, chainsaw rack, boots |
| `building.cabin.small`, "Timber Cabin" | 7 x 5 | **Mountain hut** (tool hut or trail shelter) | tin / timber | tool wall, a tarp, a water drum |
| `building.clinic.storefront`, "Storefront Clinic" | 12 x 8 | **Town clinic** (a doctor's iin) | tar / render | waiting bench, reception counter, pharmacy drawer, examination bed |
| `building.gatehouse.yard`, "Yard Gatehouse" | 8 x 6 | **Yard office** (prefab works office) | tin / render | desk, timecard rack, a kettle, a guard window |
| `building.hall.civic`, "Community Hall" | 15 x 11 | **Community centre** (kōminkan) | tar / render | stacked chairs, a stage edge, a kitchen, notice boards, a tatami room |
| `building.house.corner`, "Corner House" | 12 x 10 | **Corner shop-house** (shop below, home behind) | kawara / timber | shop counter, noren, household genkan, shoe cabinet |
| `building.house.gable`, "Gabled House" | 11 x 8 | **Tiled-roof house**, the ordinary two-storey wooden house. First piece. | kawara / siding | genkan step, shoe cabinet, kotatsu, tatami, futon closet, kerosene heater, amado shutters, block garden wall |
| `building.house.large`, "Large House" | 14 x 11 | **Farmhouse** (an old minka with engawa) | kawara / timber | engawa veranda, irori hearth, family altar, a kura beside it |
| `building.house.narrow`, "Narrow House" | 8 x 10 | **Narrow townhouse** (machiya type, between shops) | kawara / siding | lattice front, inner court, long corridor |
| `building.house.small`, "Small House" | 9 x 7 | **Small wooden house**. First piece. | kawara / timber | as the tiled-roof house, smaller |
| `building.kiosk.corner`, "Corner Kiosk" | 8 x 7 | **Tobacco kiosk and vending alcove** | tar / render | a serving window, a bank of vending machines, a bench, a public phone |
| `building.shed.garage`, "Single Garage" | 7 x 5 | **Carport garage** | tin / block | a kei car, tyres, a bicycle, a shelf of tins |
| `building.shed.lockup`, "Lock-Up" | 6 x 6 | **Kura storehouse** (white plaster, tiny window, heavy door) | kawara / render | rice sacks, chests, old tools, a ladder |
| `building.shed.tin`, "Tin Shed" | 5 x 5 | **Tin shed**: keep, renamed | tin / block | drums, a hose reel, a tarp |
| `building.shop.corner`, "Corner Shop" | 14 x 10 | **Corner store** (a liquor-and-rice shop with the family behind) | kawara / timber | crates, a cold case, a counter, a back room |
| `building.store.grocery`, "Grocery Store" | 16 x 12 | **Supermarket** (the valley's one small super) | tar / render | checkout lane, display freezers, stockroom shelving, trolleys |
| `building.terrace.pair`, "Pair of Terraces" | 12 x 8 | **Nagaya pair** (two row-houses under one roof) | kawara / timber | two genkan, shared wall, laundry poles |
| `building.unit.industrial`, "Industrial Unit" | 14 x 10 | **Sawmill shed** (open-sided on one face). First piece. | tin / siding | band saw, log carriage, sawdust, log stacks outside, a kei truck |
| `building.warehouse.brick`, "Brick Warehouse" | 22 x 14 | **Works warehouse** (the cement works' store, or a timber warehouse) | tin / block | pallet racks, bagged cement, a forklift, a conveyor stub |
| `building.workshop.unit`, "Workshop Unit" | 12 x 9 | **Machine shop** (a kōba: auto repair and welding) | tin / block | a lift, a welding bench, oil drums, a compressor |

Nothing is retired. Every template has a Japanese building of the same footprint, so the
generator's pools and weights are untouched and `godot:check:buildings` keeps its 22.

### New types worth adding

Each is a new template id, permanent once shipped. Footprints are in metres (tiles). The art
lead's first batch is marked. A template that lands after the first batch waits for the floor-plan
generator only if it is cheaper that way (docs/41 P3); none depends on it.

| New template | Size | Tags | Look | What it is and what it wants |
|---|---|---|---|---|
| `building.station.small` | 12 x 7 | civic, station | tin / timber | A waiting room, a ticket window, a short platform as a strip of Low tiles along one face; bench, timetable board, bike shed, a vending machine. **First batch.** |
| `building.shrine.village` | 14 x 12 | civic, shrine | kawara / timber | A gravel precinct with a 5 x 4 haiden hall on footings; torii at the door tile, stone lanterns, komainu, a water basin (decoration unless card 8 says otherwise), one great cedar as a Tree tile. **First batch.** |
| `building.temple.small` | 16 x 12 | civic, temple | kawara / timber | A 9 x 7 hall, a bell frame, a graveyard of stelae as Low tiles, a priest's house door. |
| `building.konbini.road` | 12 x 9 | commercial | tar / render | Glass front, canopy, two aisles, a counter, a cold case, a back room, vending machines and a small car park outside. **First batch.** |
| `building.shophouse.unit` | 6 x 10 | commercial, residential | kawara / siding | One narrow, deep shotengai unit: shutter front, shop, kitchen, tatami room behind. Tiles into rows. |
| `building.minshuku.inn` | 16 x 11 | commercial, residential | kawara / timber | A family inn: big genkan, office, kitchen, bath, four tatami rooms with futon closets; the shukubo on the mountain is this template with a thatched variant later. |
| `building.lumber.yard` | 14 x 8 | industrial, yard | tin / block | An open drying shed on posts (Low tiles under a roof) with log stacks; pairs with the sawmill shed. **First batch.** |
| `building.koban.box` | 5 x 5 | civic, police | tar / render | One room: desk, lamp, a locker (a firearm source under docs/33's default), a bicycle outside. **First batch.** |
| `building.school.wing` | 20 x 12 | civic, school | tar / render | One ground-floor wing of an elementary school: corridor, three classrooms, a staff room; shoe lockers at the entrance. The gym is a second template later. |
| `building.coop.depot` | 14 x 10 | commercial, industrial | tin / siding | The farm co-op's store and depot: feed, fertiliser, tools, a fuel stand outside, a kei truck. |
| `building.firehouse.shed` | 6 x 6 | civic, shed | tin / block | The volunteer fire brigade's shed: a roll door, a pump cart, hose, helmets, and the siren mast outside (a noise source the sim already understands through items; the mast itself is decoration). |
| `building.bath.public` | 14 x 10 | commercial | tar / render | A sento or small onsen: changing rooms, the bath hall, a boiler room. Later. |
| `building.works.control` | 10 x 8 | industrial | tar / block | The dam's control house or the works' weigh office. Later, a landmark (docs/41 P4). |

Props that are not buildings but belong to the valley, for the dresser (docs/41 P1 and P2):
vending machines (the single most Japanese object; several liveries, no real brand), utility
poles with transformers and wire webs, convex road mirrors, guardrails, concrete-block walls with
tile caps, stepped concrete river revetments, retaining walls, torii, stone lanterns, komainu,
grave stelae, noren, roll shutters, amado storm shutters, sliding doors (the sim's door, drawn as
a slider), genkan steps and shoe cabinets, tatami, futon, kotatsu, kerosene heaters and their red
cans, rice cookers, bath covers, laundry poles, blue tarps, log stacks, drying racks, kei trucks
and kei cars, bicycles with baskets, a cable-car cabin, tunnel portals, level-crossing gates, a
kōban lamp, a fire-siren mast, persimmon and plum trees, bamboo clumps.

## 5. Renames

Proposed names. Ids are unchanged except where a "new id" is given; the rule is section 1's.
The inventory of every Western-named entry being written to the shared folder is the complete
list; this section covers what the brief needs to decide the pattern, and the rename pieces in
section 6 take the inventory as their checklist.

### Districts, region, map

| Id | Name today | Proposed name | New id (only if card 5 picks the id rename) |
|---|---|---|---|
| `district.town_center` | Market Cross | Umezaki Ekimae | `district.ekimae` |
| `district.residential_suburb` | Fairfield Rise | Hinatadai | `district.hillside` |
| `district.industrial_park` | Ordnance Way | Kawahara Yards | `district.yards` |
| `district.forest_edge` | Blackpine Reach | Kaminose Shore | `district.shore` |
| `region.main_area` | Ashgrove | Kagase | unchanged |
| `map.district.alpha` | (no name field) | the timber yard; its prose lives in docs | unchanged |

"Ashgrove" also appears in code comments and in docs/23's record as the name of a measurement;
those are history and stay.

### Building templates

The 22 names in section 4's table. Ids unchanged.

### Items: brands, units and Western things

Only names and descriptions change. Digits in a name remain allowed only for a cartridge
(the owner's amendment in the playbook's "Standing bans"); descriptions carry no digits.

| Id | Name today | Proposed name | Why |
|---|---|---|---|
| `item.ammo.rifle` and its `.match`, `.surplus`, `.handload` | .308 Winchester ... | .308 Rifle Round, .308 Match, .308 Surplus, .308 Hand-load | Winchester is a brand |
| `item.ammo.9mm` and its `.hollow`, `.sub`, `.handload` | 9x19mm Parabellum ... | 9mm Pistol Round, 9mm Hollow Point, 9mm Subsonic, 9mm Hand-load | Parabellum is a maker's name |
| `item.ammo.45` and its `.hollow`, `.handload` | .45 ACP ... | .45 Auto, .45 Auto Hollow Point, .45 Auto Hand-load | ACP is a maker's designation |
| `item.brass.9mm` | 9x19mm Brass | 9mm Brass | as above |
| `item.ammo.38`, `.22`, `.12g` families | .38 Special, .22 Long Rifle, 12 Gauge | keep | generic calibre names |
| `item.food.jerky` | Beef Jerky | Dried Squid | the konbini snack |
| `item.food.crackers` | Crackers | Rice Crackers | senbei |
| `item.food.fruit.tin` | Tin of Peaches | Tin of Mandarins | the tinned fruit here |
| `item.food.beans.tin` | Tin of Beans | Tin of Corn | tinned beans are not a staple |
| `item.food.soup.tin` | Tin of Soup | Retort Curry Pouch | the shelf-stable meal |
| `item.food.fish.tin` | Tin of Fish | Tin of Mackerel | saba |
| `item.food.pickles.jar` | Jar of Pickles | Jar of Pickled Plums | the lower town is plum country |
| `item.food.pasta.dry` | Dried Pasta | Dried Noodles | soba and udon |
| `item.food.oats` | Porridge Oats | Pressed Barley | mugi |
| `item.food.apples` | Apples | Persimmons | the tree by every house |
| `item.drink.tea` | Box of Tea | Box of Green Tea | |
| `item.drink.cordial` | Bottle of Cordial | Bottle of Plum Syrup | |
| `item.spirits.bottle` | Bottle of Spirits | Bottle of Shochu | |
| `item.pot.camp` | Billy Can | Camp Pot | an Australian word |
| `item.machete.rusted` | Rusted Machete | Rusted Nata | the forester's brush blade |
| `item.sabre.cavalry` | Cavalry Sabre | Old Army Sword | a grandfather's gunto in a closet |
| `item.pitchfork.barn` | Pitchfork | Hay Fork | |
| `item.rosary.wooden` | Wooden Rosary | Prayer Beads | juzu |
| `item.chess.travel` | Travelling Chess Set | Travelling Shogi Set | |
| `item.cards.deck` | Deck of Playing Cards | Hanafuda Deck | |
| `item.bell.wind` | Wind Bell | Wind Chime | furin |
| `item.named.deer_rifle` | Grandfather's Deer Rifle | keep | the valley's hunters cull deer and boar |
| `item.blastcap.quarry` | Quarry Blasting Cap | keep | the Hikage Works' quarry |
| `item.siren.handcrank` | Hand-Crank Siren | keep | the fire brigade's |
| everything else in `items/` | | keep; descriptions reviewed against the inventory | bats, golf clubs, hard hats, instant noodles and rice are already right |

Vehicles: `vehicle.sedan` "Sedan" becomes **Kei Car**; `vehicle.truck` "Flatbed truck" becomes
**Kei Truck**; `vehicle.van` "Panel van", the bicycle, the e-bike, the scooters and the
skateboard keep their names. Containers keep their kinds ("car boot" is prose a player reads once;
"delivery van", "display freezer", "ammo crate" are right as they are).

### Firearms, under docs/33's default

Guns are rare in Japan. docs/33's card ("How common are firearms in a Japanese setting?",
default: rare, from police, hunters and the self-defence force, and the weapon work already built
stays) is the owner's to decide; this brief does not. What it does is say where each existing
gun comes from in the valley, so loot and raider kits can follow the default when it is taken.

| Item | Source in the valley | How rare, under the default |
|---|---|---|
| `item.revolver.snub`, Snub Revolver | The kōban's locker: the police sidearm is a revolver | The commonest gun, and still rare |
| `item.shotgun.pump`, Pump Shotgun; `item.shotgun.sawnoff` | The hunting association: a shotgun is the civilian gun; a sawn-off is one a raider shortened | Rare |
| `item.rifle.hunting`, Hunting Rifle | A long-licensed hunter who culls deer and boar | Very rare |
| `item.rifle.rimfire`, Rimfire Rifle | A grandfathered relic from before the rimfire ban, or a shooting club | Very rare |
| `item.carbine.lever`, Lever Carbine | An imported hunting gun | Very rare |
| `item.pistol.service`, Service Pistol; `item.smg.compact` | The self-defence force or a police tactical unit, far down the line | Nearly absent; not in raider kits |
| `item.pistol.target`, Target Pistol | A licensed sport shooter | Nearly absent |
| `item.bow.recurve`, `item.bow.hunting` | The school's archery club and a kyudo hall | As common as a club has them |
| `item.crossbow.hunting`, `.repeating` | Licensed since the crossbow law; a few in closets | Rare |

Melee stays the main way to fight, as the card says. The raider `raider.gunhand`'s kit
(`item.pistol.service`) would become the police revolver under the default; that is a kit change
listed in section 6 and taken only when the card is answered.

### People

The generator's lists in `godot/content/colony/generator.json` (12 given names, 12 surnames) are
mixed and Western-leaning. The colony is a Japanese valley's survivors and should read that way,
and a mixed colony is fine: the real valley has technical trainees, care workers, a few foreign
residents, and the two authored uniques, **Mara Sato** and **Ellis Okafor**, both stay as they
are. Proposed lists, in the same shape (24 each):

Given: Haruto, Yui, Sora, Ren, Aoi, Kaito, Mio, Riku, Hina, Daichi, Sakura, Takumi, Nanami, Shun,
Ayaka, Kenji, Satoshi, Yumi, Tomoko, Masaru, Noriko, Hideo, Keiko, Hiro, and non-Japanese: Minh,
Maria, Lucas, Sunita, Asha, Dmitri, Farid, Imani.

Surnames: Sato, Suzuki, Takahashi, Tanaka, Watanabe, Ito, Yamamoto, Nakamura, Kobayashi, Kato,
Yoshida, Yamada, Sasaki, Yamaguchi, Matsumoto, Inoue, Kimura, Hayashi, Shimizu, Mori, Ikeda,
Hashimoto, Abe, Ishikawa, and non-Japanese: Nguyen, Santos, Okafor, Chen, Khan, Novak, Diaz,
Adeyemi.

If the counts must stay at 12 for a gate's sake, take the first twelve of each with two
non-Japanese in each list. Names are rendered given-name first in English prose, as the game
speaks English (card 7).

Backstories (`backstories` in the same file) are all plausible here; worth adding in the same
shape, kit and nudge included: a forestry worker (`item.hatchet.camp`, str), a works hand
(`item.scrap.metal`, con), a konbini clerk (`item.food.noodles.instant`), a shrine attendant,
a hunting-association member (`item.ammo.12g.bird`, dex; a licence, not a gun), station staff
(`item.torch.handheld`), a minshuku keeper (`item.blanket.wool`), a trout-farm hand
(`item.fishing.line`), a retired schoolteacher (`item.book.firstaid`). Raider names (Gunhand,
Watcher, Bagman, Scavenger) are roles and stay.

Speech lines stay English and idiomatic. No romaji is sprinkled into dialogue; a Japanese word
appears in game text only where English has no word for the thing (konbini, tatami, torii,
kotatsu, kura, genkan, kōban).

### Signage

Painted signboards, shutters and posters are art, not text the sim reads. They may carry Japanese
script, and should, because a street of English signs would break the setting; every shop name
on them is invented, and no real brand or logo is drawn (card 7).

## 6. The order of work

1. **This brief merges.** Gate: `npm run check:routing` ends `ROUTING_OK`; the docs/23 planned
   piece and the playbook's docs map point here.
2. **The art lead's first batch**, in Blender with a `--check` each, through the independent art
   review (docs/41 D): the two new materials (kawara roof, siding wall) in the building-finishes
   kit so the enum can grow; the small wooden house and the tiled-roof house as whole houses on
   the existing `house_small` and `house_gable` footprints; the shotengai shutter fronts; the
   sawmill shed; the station; the konbini; the kōban; the village shrine; and prop kit A: vending
   machine, utility pole, road mirror, block wall with tile cap, roll shutter, noren, genkan step
   and shoe cabinet, tatami, futon, kotatsu, kerosene heater, log stack, kei truck, torii, stone
   lantern. Gate: `blender --background --factory-startup --python
   tools/blender/first_person_buildings/build_finishes.py -- --check` prints `BUILDINGS_CHECK_OK`
   (its template count moves with each new template), `npm run godot:check:fp_geometry`.
3. **Content renames**, each a one-step piece for a workhorse, with the shared inventory as the
   checklist. Each piece changes names and descriptions only, keeps ids, and ends green:

   | Piece | What | Gate |
   |---|---|---|
   | R1 | The four district names and the region name | `npm run godot:validate`, `npm test`, `npm run godot:m2:district` |
   | R2 | Re-order the region's cells so x runs up-valley | `npm run godot:check:worldgen`, `npm run godot:m2:region` |
   | R3 | The 22 building template names | `npm run godot:validate`, `npm run godot:check:buildings`, `npm run godot:check:roof` |
   | R4 | After batch 2 lands: the `kawara` and `siding` look values in the schema enum, `street.json` and `check_roof_look.gd`; retag the templates per section 4 and drop `brick` | `npm run godot:check:roof`, `npm run godot:check:buildings`, `npm run godot:check:worldgen`, the finishes `--check` |
   | R5 | Food and drink names and descriptions | `npm run godot:validate`, `npm test`, `npm run godot:check:inventory`, `npm run godot:check:hud` |
   | R6 | Cartridge and brass names (the brand words) | the R5 gates, `npm run godot:check:loot`, `npm run godot:m2:ammo`, `npm run godot:m2:bench` |
   | R7 | Tools, comfort items, melee names | the R5 gates, `npm run godot:m2:comfort`, `npm run godot:m2:noise` |
   | R8 | Vehicle names | `npm run godot:validate`, `npm run godot:check:wrecks`, `npm run godot:m2:vehicles` |
   | R9 | The generator's given names, surnames and added backstories | `npm run godot:validate`, `npm test`, `npm run godot:m2:settlers`, `npm run godot:m2:people` |
   | R10 | Descriptions across `items/` and `containers/` that the inventory lists as Western things | `npm run godot:validate`, `npm test`, `npm run godot:check:inventory` |
   | R11 | The playbook's "What the project is" setting paragraph and `README.md`'s player text name the Kagase valley | `npm run check:routing` |

4. **New templates**, one piece each, in this order: station, konbini, kōban, shrine, lumber
   yard, shophouse unit, minshuku, fire-brigade shed, school wing, co-op depot, small temple,
   public bath, works control house. Each adds the JSON under `godot/content/buildings/`, a pool
   entry in its district, and its finishes manifest. Gate: `npm run godot:validate`,
   `npm run godot:check:buildings`, `npm run godot:check:worldgen`, `npm run godot:check:roof`,
   the finishes `--check`.
5. **The start map** re-authored as the timber yard, same anchors (two gates, well, player
   start). Gate: `npm run godot:m2:district`, `npm run godot:check:fp_expedition`.
6. **Owner cards** (section 7) answered as they come; the raider kit change and any new water
   source wait on theirs.

## 7. Owner cards

Each with one recommended default. The default is built unless the owner picks otherwise.

1. **The valley's name.** Default: **Kagase** (valley, river, line, region). Alternatives:
   Kurose, Minase. The towns' names in section 3 follow whichever is chosen only for the terminus
   (Oku-Kagase).
2. **The premise line and the one real name.** Default: keep "The last stop on the line out of
   Tokyo" verbatim as the title screen's line, and allow **Tokyo** as the one real place name in
   game text; everything up the line is fictional. Alternative: name no real place at all and say
   "out of the city".
3. **Is the city expedition a new district?** Default: **no**. The first expedition goes down the
   valley to Umezaki Ekimae, the existing town centre; the city stays off the map. A city-fringe
   district is docs/41's P5 when the frame and tick budgets hold.
4. **Where the colony starts.** Default: the walled **timber yard** on the Kawahara flat near the
   terminus, keeping `map.district.alpha`'s anchors. Alternatives: the school wing (walls, water,
   a kitchen) or the shrine precinct (a wall, a basin, high ground).
5. **Rename ids too?** Default: **no**; names change, ids stay (saves, kits, loot tables, parity
   fixtures and gates all key on them). If yes, the new ids are in section 5's first table and
   the save version bumps (`godot/sim/kernel/serialize.gd`'s `SAVE_VERSION`).
6. **Firearms.** Already docs/33's card, default rare. This brief adds only the source table in
   section 5 and the raider kit change that follows the default. Nothing new to decide.
7. **Language.** Default: game text is English; a Japanese word appears only where English has
   none; names are given-name first; signage art carries invented Japanese script and no real
   brand.
8. **A shrine water basin as a water source.** A new water source is a mechanic (the playbook's
   examples under "Who decides what" include one). Default: **no**; the basin is decoration, and
   the river and the yard's well remain the water.
9. **Two-storey exteriors with one floor.** Default: **yes**. Houses and shop-houses read as two
   storeys outside; the interior is the ground floor; the stair is a blocked tile with a drawn
   stair. This keeps docs/23's z-level deferral intact and the street honest.
10. **The climate's words.** Default: keep `climate.temperate`'s numbers and the seven weather
    kinds; rename nothing in their ids; rewrite their descriptions for the valley (the rainy
    season's mist, typhoon rain in autumn, clear cold winters, snow on the ridges). A start season
    other than the current `spring` is a rule change and is not proposed.

## 8. Sources

- https://en.wikipedia.org/wiki/Ome_Line
- https://en.wikipedia.org/wiki/%C5%8Cme,_Tokyo
- https://en.wikipedia.org/wiki/Okutama,_Tokyo
- https://en.wikipedia.org/wiki/Lake_Okutama
- https://en.japantravel.com/tokyo/ome-showa-retro-town/65267
- https://www.sangyo-rodo1.metro.tokyo.lg.jp/tourism/accessible/en/course31.html
- https://www.timeout.com/tokyo/things-to-do/sawanoi-ozawa-brewery
- https://tokyogrown.jp/en/e_mark/detail?id=571438
- https://tokyocheapo.com/lifestyle/outdoors/mount-mitake
- https://at-tama.tokyo/lang_en/tourismtopics/mount-mitakes/
- https://www.tokyoupdates.metro.tokyo.lg.jp/en/post-1450/
- https://chillnn.com/en/1890a281aad58/info/
- https://ippei-janine.com/tokyo-day-trips/nature/hatonosu-gorge-tokyo/
- https://en.japantravel.com/tokyo/okutamas-ootama-walking-course/17613
- https://www.alltrails.com/parks/japan/tokyo/chichibu-tama-kai-national-park
- https://en.japantravel.com/tokyo/okutama-town-history-landmarks/68851
- https://tokyopast3.com/okutama-industrial-hikawa-plant
- https://ridgelineimages.com/haikyo/okutama-ropeway/
- https://ridgelineimages.com/musings/postcards-of-lake-okutama-1950s/
- https://www.japan-experience.com/all-about-japan/tokyo/outdoor-activities/nippara-limestone-cave
- https://www.mlit.go.jp/tagengo-db/common/001551343.docx
- https://www.jstage.jst.go.jp/browse/jjhg/7/5/_contents/-char/ja
