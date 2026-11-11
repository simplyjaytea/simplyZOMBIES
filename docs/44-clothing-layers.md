# 44 — Clothing layers on the first-person bodies: the design note

Draft, 2026-11-04. A design note, not a record: nothing here has shipped, and docs/23 owns the
evidence when it does. It answers one question for docs/41's pieces C2 and C3 and art piece 12
("modular survivors and clothing that follows the worn slots"): in first person, with 3D bodies
from the Blender character kit, how do worn things (clothing, armour, the plate, gloves, boots,
packs) show on the survivor, on colonists and on raiders, and what does the sim already know that
the picture must follow? It keeps docs/41's three rules. The picture is the sim; anything that
can be taken is sim; words, not numbers.

Every claim about the code below was read on `main` at `f9cd5ce2`. Two pieces of art it builds on
are not on `main` yet and are named as such where they are used: the organic survivor (the
character kit's second survivor, in independent review) and the view-model arms kit with its
`arms_view.gd` (on their own branches, paused mid-round).

## What exists today

**The slots.** `SimInventory.EQUIP_SLOTS` (`godot/sim/modules/inventory.gd`) has twelve: `back`,
`vest`, `belt`, `primary`, `secondary`, `head`, `face`, `eyes`, `torso`, `gloves`, `legs`, `feet`.
Ten of them are worn; `primary` and `secondary` are what the hands hold, which is the weapon plan's
(docs/41 W1 to W5) and not this note's. Each slot holds **one item**. The file's own header says
why: "Layering is basic on purpose: slots are independent, no layered armour resolution." So the
sim has no idea of a shirt under a coat. It has a torso slot, a vest slot over or under it (it
does not say which), and a pack. That fact shapes everything below: the picture's layers are per
slot, and the order they draw in is a presentation rule, because the sim has none.

**The worn items.** Sixty-three content entries carry a worn `equipSlot`: 14 torso, 7 vest, 7 head,
7 face, 3 eyes, 5 gloves, 5 legs, 4 feet, 7 back and 4 belt, across `armor.json`, `clothing.json`,
`masks.json`, `containers.json`, `lights.json` and `named.json` under `godot/content/items/`.

**What reads them.** No worn item is cosmetic. The slot cut of 2026-08-19 kept only slots that a
system reads, and every worn item today feeds at least one reader:

- **Armour.** 32 items declare an `armor` map per body part. `SimInfection.armor_coverage_of`
  composes it, max per part and never a sum, and folds in fitted parts through
  `SimAttachments.armor_coverage`: a plate multiplies the vest's torso, and a lining multiplies
  its arms. The same coverage softens damage in `SimHealth.damage_part`, wears the garment that
  stopped the blow (`SimHealth.wear_struck_armor`; "The plate wears", docs/30), and becomes the
  condition view's `armored` boolean (`godot/sim/condition.gd`). `SimNeeds.wearing_armor` reads
  it again for the heat wave.
- **Warmth.** 21 items declare a `warmth` map per body part. `SimNeeds.warmth_of`,
  `warmth_points` and `warmth_bands` turn it into bands on the temperature ladder. Being wet
  halves the bands above the first (`WET_WARMTH_MUL`), so a soaked coat is half a coat. Three
  items (`item.poncho.rain`, `item.raincoat.hooded`, `item.poncho.tarp`) declare `shedsRain`,
  which `SimNeeds.sheds_rain` reads to keep the body dry. Wetness itself is one integer on the
  needs component, `wetUntilTick`, read through `SimNeeds.is_wet`.
- **Filter.** 13 items declare a `filter`, which `SimInfection.filter_of` reads at a bloater's
  cloud.
- **Capacity.** 13 items (every back and belt item, the chest rig and the bandolier) carry a
  `container`. Equipping one is what grants its grid (docs/10).
- **Light.** The two headlamps and the clip-light glasses are read by `godot/sim/modules/light.gd`,
  whose `LIGHT_SLOTS` include `head` and `eyes`.

**Who wears what.** Colonists start with no clothes. The owner chose "armour reaches people by
being found, not by being issued" (docs/30, 2026-09-12), and the Dress job puts found gear on
(`SimJobs.WEAR_FOUND_ARMOR`). Every raider archetype's kit rolls a canvas cap at one in two and a
school pack at two in five, and `SimRaiders._hold_it` puts anything with an equip slot on the
body, so those two are worn rather than carried. No archetype carries a vest. There is no
gunhand's vest in content. The gunhand's tell is the pistol in its hand. Of the zombie kinds, only
`zombie.armored` wears anything: its `worn` list is the scrap vest and the bike helmet, equipped
by `SimRoster._wear_the_kit` and dropped as loot when it dies. A colonist who turns becomes a
default shambler, and `SimRecruits._turn_with_kit` **stows** what they wore in the new body's
pack rather than wearing it.

**What the screen draws.** Nothing worn. `body_view.gd` draws every person (colonists, raiders,
settlers) with `survivor.glb` and every zombie with `shambler.glb`, whatever is in their slots.
`own_body.gd`, the third-person testing view, does the same for the player. The only equipment
the first-person screen draws on a body is the held weapon (`held_weapon.gd`). So, today, **every
one of the ten worn slots has no picture in first person.**

**The art that will carry it.** The organic survivor is one closed, smooth-skinned body of 7,810
triangles (the kit's survivor budget is 1,000 to 8,000) under one single-sided `SurvivorAtlas`
material. Its 512 x 512 atlas holds the body at 128 px/m and the head and neck at 256 px/m, and
every island's rectangle is frozen (`organic_survivor.FROZEN`). Its 18-bone named rig carries
blended weights, and it wears "a fitted base layer (long-sleeve top, work trousers, boots) close
to the body so clothing can sit over it later". The arms kit is 3,712 triangles against a budget
of 4,000, on a 256 x 256 atlas at 128 px/m, with a 43-bone rig whose arm bones "match the survivor
rig, so a clothing layer weights by the same names". Its sleeve mesh is the base top's sleeve.
The owner's answers that bind the arms are bare hands on the base and **gloves only when worn**.
Those answers are recorded in the arms task brief, because the contract file they were first
written into is lost.

**The legacy answer.** The top-down painter (`godot/art/simplyzombies/clothing/README.md`) painted
each garment into every frame of the body picture, so a shirt could never step out of time with
the legs. That only worked because a sprite is a picture. On 2026-09-25 the owner accepted a
named gap: the pack's four wearables drew, and "an equipped jacket shows nothing on the body
until then". The top-down game is legacy now. What carries over is the principle, not the method:
what you wear shows on your body, and a body whose clothes cannot come off is art this project
cannot use.

## The layering model

Three ways to put a worn item on a 3D body:

- **Mesh layers.** Each item, or each family of items, is its own skinned mesh bound to the body's
  skeleton by bone name. It is shown when the slot holds it and hidden when it does not. A layer
  can change the silhouette (a hood, a pack, a carrier), and it costs triangles and a draw per
  body.
- **Texture swaps.** The item is a paint page over the body's own atlas islands: a shirt over the
  base top, jeans over the base trousers, gloves over the hands. It costs no triangles and changes
  no silhouette. With one material and one atlas per body, two swapped slots mean a composite
  texture per distinct outfit.
- **A mix.** Shape is mesh and surface is paint.

**The recommended default is the mix, with one sentence as its rule: an item that changes the
outline is a mesh layer, and an item that lies on the base layer is paint.** The kit's convention
allows it as written. "One single-sided material per model" holds per GLB: the body keeps
`SurvivorAtlas`, and every layer GLB uses one shared `ClothingAtlas` material, single-sided and
nearest-filtered. A dressed body is then two materials, however many layers it wears. It is never
one per garment.

How the 63 items split under that rule:

- **Paint (no triangles).** The inner tops (linen shirt, thermal undershirt, cloth wrap) over the
  base top's islands. All five legs items over the base trousers: the shorts paint skin onto the
  shins, and the insulated trousers paint a quilt. The thin face coverings (cloth, dust and
  surgical masks, the bandana) over the lower-face islands at the head's 256 px/m. The five gloves
  over the hand islands. The sandals over the base footwear.
- **Mesh layers.** The outer torso garments (both coats, the parka, the leather jacket, the
  raincoat, the two ponchos, the blanket, both aprons, the paper coverall, the hazmat suit). All
  seven vest-slot items. Every head item. The respirator and the gas mask. The scarf. The three
  eyes items. Every back and belt item. The three boots, because a boot shaft and a steel toe
  change the outline at the ankle.

**Layer order is a presentation rule.** The sim has none, so the clothing manifest gives each
torso item a `layer` of `inner` (paint, under everything), `mid` (coats, jackets, aprons, the
coverall and the hazmat suit) or `over` (the two ponchos, the raincoat and the blanket: the rain
gear and the thing you wrap yourself in). The vest slot draws between `mid` and `over`. A carrier
over a winter coat therefore shows, and the same carrier under a poncho does not. That ordering is
the owner's call (docs/33, card 28) because it decides what a stranger's armour tells you; the
recommended default is the one just given.

**The hair.** The survivor's hair, with its high bun, is part of the one body mesh, and no hat can
sit over the bun without clipping. The kit exports the hair as its own mesh object under the same
material, plus a tucked variant for under a hat. That is still one material, so the convention
holds. A head item names which hair it wants.

**The resolver.** A single presentation module, proposed as
`godot/presentation/first_person/outfit.gd`, turns a body's `equipment` component into its
picture. It returns the layer meshes to show, the paint pages to compose, the hair variant, the
sleeve family and the hand page. It reads only the base id in each slot and the presence of a
part in a vest's `plate` and `pocket` slots (`SimAttachments.in_slot`). It never reads tier,
condition, affixes or what a container holds. `body_view.gd`, `own_body.gd` and `arms_view.gd` all
call it, and nothing else decides what a body wears. The manifest it reads lives beside the GLBs
as `godot/assets/first_person/clothing/clothing.json`, keyed by item id. It is deliberately not a
`*.manifest.json`, for the reason the arms gave for `arms/arms.json`: `Models.manifests()` would
take its entries for loot.

**The cost.**

- **Triangles.** The base body is 7,810. The proposed per-layer caps are 2,000 for a `mid` coat
  (torso, sleeves and collar; the parka and raincoat hood add up to 200), 1,000 for an `over`
  drape, 900 for a vest with its loaded variant, 700 for a pack, 400 for a hat or helmet, 300 for a
  mask or respirator, 150 for the scarf or the eyes items, 300 for a belt item and 250 for a boot
  pair. The heaviest legal stack is a body in a parka, a carrier, a poncho, a frame pack, a hard
  hat, a gas mask, goggles, a belt pouch, a scarf and boots: about 14,200 triangles. The proposed
  dressed-body cap is 14,500. People are few (a colony, a raid band), and the horde is zombies,
  which this note keeps baked (below), so the dressed cap does not multiply by the horde. The
  first-person bodies piece (C1) measured about 0.5 ms a frame in the mean and 2 ms at p95 for 40
  skinned bodies. Dressed people are re-measured the same way before the cap is trusted.
- **Atlas space.** One `ClothingAtlas` at 1,024 x 1,024 and 128 px/m holds 64 m² of surface. The
  full layer set is about 20 families at under a square metre each. Laying it out once at full
  size and freezing every rectangle (the `FROZEN` precedent) means a later family never moves an
  earlier one. That is about 4 MiB of texture, shared by every dressed body. Paint pages are
  patches registered to the survivor's frozen islands. A body whose outfit has paint draws a
  composite of the 512 x 512 body atlas (1 MiB each), built once per distinct paint set and shared
  by every body that wears the same set. A cache of 32 composites bounds the worst case at 32 MiB;
  colonists and a raid band come nowhere near it.
- **Blender kit work.** A new kit, `tools/blender/first_person_clothing/`, with a reproducible
  builder and a `--check`, the house shape. It shares the survivor's rig and frozen islands by
  reading `survivor.glb`, never by copying numbers. The survivor itself changes in two places: the
  hair split above, and the base footwear (card 29). The arms kit gains sleeve families and glove
  pages (below). In the docs/41 measure of one session per art piece, plus review rounds, the
  first cut is about three art sessions and the full set about six more.
- **Gate work.** One kit check with its plants, and one new lane in `godot:check:first_person`
  (see "The gate"). That is about two code sessions, beside the resolver.

## What the picture must agree with

**Coverage is drawn where it is declared.** For every worn item, the body parts its layer or paint
covers must equal the union of the keys in its `armor` and `warmth` maps. The parka's `head`
warmth is its hood. The scrap vest's arm coverage reaches the shoulders. The welding apron
declares arm armour, so it is drawn with sleeves. The down vest and the mesh vest declare the
torso alone, so they are drawn sleeveless. A picture that covers less than the sim tells the
player a part is bare when it is armoured. A picture that covers more says a part is protected
when it is not. That is the clause-4 failure in its most dangerous form, false confidence about a
bite. Drawing beyond the declared parts is allowed only through a named `drawnBeyond` list in the
manifest, each entry with its reason, so that every such case is a decision someone read.

**Two content facts the first-cut gate will raise at once.** The hazmat suit and the paper coverall
are whole-body garments by name, but they declare coverage for the torso and arms only. Either the
content gains leg keys, which moves bite odds and warmth and so is a balance change with its own
measurement, or the picture draws them with a `drawnBeyond` entry for the legs and the reason. The
note recommends the content fix, measured, because a suit that leaves your legs bare is a lie in
either direction. The butcher's apron declares only the torso, and draws as a bib and skirt whose
skirt goes in `drawnBeyond`.

**What the picture must not show**, under hardcore contract clause 4:

- **A plate under an `over` layer.** A plate in a carrier that a poncho covers draws nothing. A
  carrier that is the outermost torso layer shows whether its plate pockets are filled: the loaded
  variant stands proud of the chest, front and back, and an empty carrier lies flat. That is
  information, and it is information a person standing there would have. When a plate wears
  through and detaches (`_wear_one`), the carrier goes flat on that tick. Card 28 asks whether
  that is the owner's intent.
- **A lining**, under any layer. It is inside the vest.
- **Quality, condition and affixes.** Two scrap vests at different tiers, or at different
  condition words, draw the same. Condition becomes worn looks only through a later pass with
  the bench's words (docs/41 W6 is the weapons' version), never through a number.
- **What a container holds.** A pack is drawn the same full or empty, because the grid is the only
  place capacity is shown (docs/10's "a grid is the same information rendered as shape").
- **Filter strength.** A cloth mask and a gas mask look different because they are different
  things, but nothing on the picture grades how well either works.

**What the picture should follow beyond the slots.** Wet is a sim fact (`SimNeeds.is_wet`), it is
visible in the world, and it is cheap: a darkened cloth ramp on the body's material while the sim
says wet. It belongs to the art pass, and the rain gear (`shedsRain`) keeps the body under it dry,
because that is what the sim says. Its look goes to the art review with the rest of that pass.

## Silhouette: what reads at 2 m and at 10 m

The first-person lens is 75 degrees vertical. At a 1280 x 720 frame that is about 235 screen pixels
per metre at 2 m and 47 at 10 m. A body texel at 128 px/m is 7.8 mm: at 2 m it is about two screen
pixels, and at 10 m one screen pixel is close to three texels. So paint detail is a 2 m read, and
only shape and large value blocks survive to 10 m. The rule for the kit:

- **At 10 m** a stranger's head top (hair, a soft hat or a hard helmet), their back (pack or no
  pack), their outermost torso shape (coat bulk, a hood, a poncho's drape, a hazmat suit), a
  carrier when it is outermost, and the held weapon's class must each read. These are the things
  that change what you do next: whether to shoot, whether they can carry your stores away, whether
  a torso shot is worth taking.
- **At 2 m** everything else must read: gloves, a mask or respirator, goggles or glasses, the
  shirt and trousers' paint, boots against the base footwear, a belt pouch, a loaded carrier
  against an empty one, the scarf.
- **Nothing reads through what is over it.** The outer layer is the read, as in the plate rule
  above.

Each item's manifest entry names its read distance, and the kit check measures it (below). An item
whose 10 m read does not survive the measurement is moved to 2 m in the manifest. The item is not
made louder than it is.

## The view-model arms

The owner's answers stand: **bare hands on the base, gloves only when worn.** The rest follows from
the resolver:

- **Hands** are the hand page `outfit.gd` returns: bare, or one of the five gloves painted over the
  arms atlas's hand islands. The chemical gloves add a gauntlet cuff ring (about 100 triangles a
  hand), because the long cuff is what tells them apart at 0.4 m.
- **Sleeves follow the worn torso layer**, and only the torso layer: the vest slot has no sleeves.
  The arms kit exports a small set of sleeve families as separate meshes on the same skeleton and
  atlas. `knit` is the base top's sleeve as it is today, and every `inner` top paints over it.
  `smooth` covers the leather jacket, the raincoat, the coverall and the welding apron. `padded`
  covers the two coats and the parka. `rubber` is the hazmat suit. An `over` drape adds an upper-arm
  fold mesh over whichever sleeve is under it. One family shows at a time, so the shown arms stay
  inside a budget of 4,500 triangles, and every family is held to the kit's existing `cuff`,
  `stump`, `body-match` and `density` checks.
- **One answer.** `arms_view.gd` asks `outfit.gd` for the player, as `body_view.gd` asks it for
  every other body and `own_body.gd` asks it for the player in the testing view. The gate asserts
  that the sleeve family and hand page the arms draw are the ones the resolver gives for the
  player's slots, and that they change on the tick the equip does. A coat put on in the inventory
  sheet is on the arms when the sheet closes.

## Zombies and raiders

**Raiders reuse the layer system without exception.** A raider is a person wearing items, and what
they wear is their kit, the same items a colonist wears. The gunhand's tell is the pistol and
whatever the kit rolled, never a baked archetype outfit. That is what keeps `check_m2_raiders`'
NO-TELL lane true in 3D: two archetypes in the same items draw the same. What a raider *does*
wear is fair to read. A raider with a school pack can carry your stores away, and you can see it.
How a raider reads as a raider at all, when everyone is the same body, is the owner's (card 30).
The recommended default carries over the owner's one-raider-tint call of 2026-09-25 as one shared
paint on the base layer, the same for every archetype.

**Zombies have their own rags baked, and wear only what the sim says they wear.** A zombie kind's
torn remains of clothing are paint on its own body atlas, as the shambler's are now. They are
never an item, they are never takeable, and they must never look like gear: no intact helmet, pack
or vest on a zombie that has no `worn` entry. Real worn items use the same layer meshes as people,
which needs the kinds on the shared rig (docs/41 C3: "each a variant of the shared rig"). Until
then, the armored kind is a baked model whose manifest names the items it shows, and the gate
holds that list equal to the kind's `worn`. So, in both phases, **what you see on a zombie is what
you can take off it.** A turned colonist is the open case. The sim stows their clothes rather than
wearing them, so today they would draw as a default shambler in rags. Whether they keep wearing
their coat, so that you know who they were, is a small sim change and an owner call (card 31).

## The gate

Two halves, the house shape: the kit proves the art, and the scene proves the picture follows the
sim. Every assertion has a planted failure that turns it red (CLAUDE.md, "A gate that cannot
fail").

**The kit**, `blender --background --factory-startup --python
tools/blender/first_person_clothing/build_clothing.py -- --check`, printing `CLOTHING_CHECK_OK`:

- **Coverage of content.** It reads `godot/content/items/*.json` directly, as the weapon kit reads
  content slots. Every item with a worn `equipSlot` has a manifest entry, either a picture or an
  explicit `none` with a reason; an entry for an id content does not have is refused. Plant:
  `missing-entry`.
- **Declared parts.** Each entry's drawn parts equal its `armor` and `warmth` keys, plus its named
  `drawnBeyond`. The drawn parts are measured from the layer's own weights (the bones its vertices
  follow) or the islands its paint covers, and never taken from the entry's say-so. Plant: a coat
  exported without sleeves (`undeclared-cover`).
- **Never clips.** For every layer, at every sampled frame of every survivor clip (idle, walk,
  crouch_idle and the death fall through its held pose), no body vertex in the covered region
  stands proud of the layer. Every legal pair of stacked layers (`mid` under a vest, a vest under
  `over`, a pack over each) is checked the same way. That is pairs, not the full product, so the
  cost stays linear. Sleeve families are checked against every arms clip. Plant: a layer shrunk by
  1 cm (`clip`).
- **Density.** Every layer island's area-weighted median is within 128 px/m ±10%, the survivor's
  own rule. Paint pages register to the survivor's frozen islands texel for texel. Plants:
  `layer-density` (0.35x) and `paint-shift` (one texel off).
- **Rig and material.** Layers weight only to bone names the survivor (or, for sleeves, the arms)
  rig has, with at most four influences. Each layer is one single-sided material on the shared
  atlas, with nearest filtering. Plants: `bone-rename`, `second-material`.
- **Budget.** Per-layer caps, and the heaviest legal stack under the dressed-body cap. Plant:
  `budget`.
- **Far read.** Each 10 m item's outline, rasterised in the builder at 47 px/m against the empty
  slot's, differs by at least a dozen pixels. Each 2 m item is held to the same test at 235 px/m.
  The rasteriser is in the builder, not a render, so it needs no display. Plant: a pack scaled to
  a sliver (`far-read`).
- **Bytes.** GLBs, atlas and manifest rebuild byte-identical. Plant: `flip-byte`.

**The scene**, a new OUTFIT lane in `npm run godot:check:first_person`, in a fresh scene as the
BODIES lane is:

- **Equip and unequip.** It equips each worn item on a colonist in turn. The body's shown layers,
  paint set and hair are the resolver's for those slots. They go when the item is unequipped (a
  stale layer is the planted failure), and the corpse draws whatever the corpse still wears.
- **The arms.** The arms' sleeve family and hand page equal the resolver's for the player, and they
  change on the tick the equip does.
- **Hidden information.** A carrier under an `over` layer shows no carrier node. A loaded and an
  empty carrier under a poncho draw identical node sets. Two items of one base at different tiers
  and condition words draw identically. The planted failure is a resolver that reads condition.
- **Raiders.** A raider's drawn set equals its equipped kit, and two archetypes in identical items
  draw identically, which is NO-TELL carried to 3D.
- **Zombies.** Each kind's drawn gear equals its content `worn` list, and a kind with none shows
  none.
- **Budget.** A fully dressed body's triangle count is under the cap. The frame cost of 40 dressed
  bodies is measured headed and recorded, as C1's was; it is not gated, because CI has no display.

## Phasing

**First, the minimum that makes worn items visible.** The resolver, the clothing manifest with an
entry for all 63 worn items, the kit check and the OUTFIT lane. Five layer families cover the 10 m
read: one pack (the three backpacks), one carrier with its loaded variant (the three plate vests,
also used for the chest rig), one hard helmet (the bike helmet and the hard hat), one soft cap (the
canvas cap and the wool hat), and one padded coat (the winter coat and the parka, the parka with
its hood). The hair split rides with the caps. On the arms, the `padded` sleeve family and the
glove pages, because the owner's gloves answer is about the view model and it costs paint, not
geometry. Every other item is an explicit `none` with the reason "first cut", and the inventory
and inspect text still say it is worn, as with the 2026-09-25 gap. That is about 4,600 triangles of
layers, under a tenth of the clothing atlas, three art sessions and two code sessions. It waits
for the organic survivor and the arms kit to land, since it binds to both of their rigs and
islands.
Whether to ship with that named gap is card 32.

**Then the art pass.** The rest of the layer families (the `over` drapes, the hazmat suit, the
aprons, the remaining hats, masks, eyes items, scarf, belt items and boots); the paint pages for
the inner tops, the legs, the footwear and the thin masks; the base footwear change (card 29); the
`smooth` and `rubber` sleeves; wet cloth; the raider mark (card 30); the armored zombie baked to its
`worn` list; and the pocket pouch on a carrier or jacket when one is fitted.

**Later, with the pieces that own them.** Generated faces and hair pools (C2). Zombie kinds on the
shared rig, and with them real layers on zombies and the turned colonist (C3, card 31). Wear looks
by condition word, and torn or bloodied cloth where a wound is (C3's "wounds read on the body").
Merging a body's layers into one mesh per outfit, if the dressed-body measurement asks for it.

## For the owner

Five cards, filed in docs/33 under "Waiting on the owner" as items 28 to 32. Each has a recommended
default, and none blocks work: the default is what gets built.

- **28. What hides armour?** Default: rain gear and the blanket draw over the vest and hide it, and
  every other torso garment draws under it. A loaded carrier looks fuller than an empty one only
  when nothing covers it.
- **29. What does a body wear with nothing in a slot?** Default: the survivor's base layer (top,
  trousers) stays as the clothes everyone has, worth nothing to the sim. Its boots are repainted as
  plain soft shoes, so boots in the feet slot read as boots.
- **30. How does a raider read as a raider in first person?** Default: one shared raider paint on
  the base layer, the same for every archetype, carrying over the one-tint call of 2026-09-25.
- **31. Does a turned colonist keep wearing their clothes?** Default: yes, once zombie kinds are on
  the shared rig. What fits goes on the body, the rest stays in the pack, and the loot is the same.
- **32. Does the first cut ship with the named gap?** Default: yes. Five layer families and the
  gloves first, and every other worn item shows nothing until the art pass, with the inventory
  still saying it is worn.
