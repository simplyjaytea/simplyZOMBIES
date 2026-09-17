# Core items and held weapons

This concrete core set contains 48 distinct 32×32 inventory icons and 12 separate held weapon PNGs for the approved compact character proportions. It does not claim to cover the game's entire catalog.

The native weapon shapes occupy 12–27 pixels across, except the vertical bow. All held sprites point east. Their grips and muzzle/tip coordinates are expressed in texture pixels from the top-left origin. The root manifest links every held weapon to its inventory icon. A renderer can translate to `grip`, rotate toward aim, then attach flashes/projectiles at `muzzle`.

The `weapon.demoCooldownSeconds` and `weapon.demoFxType` values are demonstration metadata. They do not define the game's weapon balancing. These PNGs are static art; separate effect animations and runtime weapon movement provide firing/swing actions. Gear icons are inventory representations and are not fitted character clothing layers.

The inventory atlas is 256×192, arranged in eight columns and six rows of 32×32 cells. Its order follows the first 48 entries in `manifest.json`. `icons/` also includes all individual icons. `held/` contains the world-size weapon artwork. Both contact sheets show native and enlarged nearest-neighbor renderings.

Production used built-in image generation after inspecting the official ZERO Sievert outpost, bunker and combat screenshots and the approved revised character contact sheet. The generated designs are original. No original game's sprite was extracted or reused.

Original PNG sources, prompts and crop/scale metadata are included. `extract-assets.py` reproducibly performs mechanical cropping, nearest-neighbor resizing, padding and contact-sheet composition. Its alpha threshold is only used to measure crop boundaries; the source RGBA is preserved, including some partially transparent edge pixels. The first held source is retained as provenance; `held-weapons.png` is the final source following the transparent-background refinement.

Known limits: the native bow string is very thin; the held bow and crossbow are shown loaded. The hatchet blade points down/right while its handle points left. All held weapons are east-facing sprites intended for aim rotation. There are no baked reload or weapon-condition variants in this item set.
