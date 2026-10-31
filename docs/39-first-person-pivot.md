# First-person survival colony pivot

Owner direction, 2026-11-01. This is a conversion plan, not a claim that its
features have shipped. The roadmap in docs/23 owns completion evidence.

## The game we are making

A first-person survival colony sim. The player explores, scavenges and fights
as one vulnerable survivor, then returns to a settlement whose people continue
working through their own skills, needs and priorities. Unique authored people,
generated survivors, recruitment, the planned captive arc, progression,
permanent loss and succession remain in scope.

Colony management has a physical access point. Approach a ledger, interact,
play a short opening/writing animation, and use an efficient management menu.
Assignments and standing instructions persist. Conversations provide reports,
recruitment and delegation; a foreman is a planned role, not a prerequisite for
managing the starting colony. Routine work must not become repeated errands.

The visual reference is Project Zomboid's Project Viewpoint interpretation of
ordinary places in 3D, with Zero Sievert-inspired pixel textures, restrained
colour and wear. Inventory takes its equipment/container presentation cues
from Escape from Tarkov and STALKER. These are references for original assets
and interaction design, not dependencies or assets to copy.

## Preserved baseline

The clean top-down game at `4995ca6ff94b6259f6ed4dc2bcfe55884e750218` is
preserved on GitHub by a branch, annotated tag and source release named
`archive/topdown-colony-pre-first-person-2026-11-01`.

[Source archive and release](https://github.com/simplyjaytea/simplyZOMBIES/releases/tag/archive/topdown-colony-pre-first-person-2026-11-01).

This preserves all tracked assets, code, content and history. Ignored caches,
generated exports and files outside Git are not part of that source backup.
The repository remains active. No existing sprite needs to be deleted to begin.

## What changes and what survives

Keep Godot 4.7.1 and the deterministic 20 Hz simulation. Reuse colony jobs,
skills, needs, inventory rules, injury, infection, item generation, weapon
assembly, recruitment, director and save infrastructure where their contracts
still fit. Existing gates continue to judge those rules.

Build a new 3D presentation and first-person input path. Adapt interaction,
combat geometry, visibility, building placement and inventory UI deliberately.
The old movement, tile sight and cone hit tests are planar; a 3D camera does
not make them correct for elevated sights, windows or cover.

Input remains commands. The sim owns position, collision outcomes, damage,
work and inventory mutations. Presentation reads state and interpolates
between ticks; camera look and animation render smoothly. Do not introduce
an independently moving physics player and synchronize competing positions.

Use a single documented spatial contract: metres; sim x/y maps to Godot x/z;
Godot +Y is height. Start on one walkable floor. The first-person decision
does not silently approve stairs, roofs to walk on, jumping or multilevel
pathfinding. Those require a later spatial design and measured migration.

No health bar or numerical injury fraction. Information remains uncertain,
and the HUD speaks in words under the existing contract. A different camera
does not widen information access or expose unseen people through walls.

## Delivery sequence

### First-person foundation and physical ledger

Deliver an opt-in scene booting the real sim, initially on a small district.
Mouse look, camera-relative movement and visible NPCs must follow sim state.
Walls block movement through the existing authority. A nearby physical ledger
opens functional work management, dispatches actual job-priority commands,
captures input, and closes cleanly. Placeholder bodies are explicit.

Proof: a headless scene gate exercises movement, collision, camera-relative
directions, sim stepping, ledger reach and aim rejection, accepted access,
priority mutation and menu input capture/release. Register the gate in the
runner, npm scripts, chain, shard and routing table. Standard boot remains
available during the experiment; it is not yet the new default game.

### Blender starter kit and integration

In parallel, author a desk, open ledger, shelf, timber barricade and modular
wall. Retain editable Blender source, a reproducible builder, original pixel
texture atlas and exported GLBs. A runtime build must not require Blender.
Use metres, applied transforms and coherent texel density, initially about
64 texels per metre. Origins are floor-centred; the ledger is bottom-centred
for placement on a desk. Export path: `godot/assets/first_person/`.

Integrate the kit into the actual foundation scene. Prove the scene consumes
the exports, inspect headed screenshots, and check dimensions, nearest
filtering, scale, readability and collision agreement. A Blender beauty
render alone does not pass in-game art review. The coordinator commissions
an independent review of the final art head before any art PR merges.

### Scavenging and personal equipment

Connect world-facing container selection to actual search, take, stow and
equip commands. Adapt the existing grid inventory into equipment, pockets,
bags and world containers with substantial item illustrations. Carrying,
searching and reload rules remain sim-owned. Include skills and condition
access with the existing information restrictions.

Proof: a player can retrieve, carry, equip, save and restore real items;
inaccessible containers and invalid moves are refused. Decide inventory
time/pause behaviour explicitly before shipping this slice.

### Spatial combat and perception

Specify and implement one authority for collision, shot obstruction, melee
reach, body-part hits and NPC perception. Camera geometry and simulation
must agree on doors, windows and low cover. Retain weapon handling, skills,
ammunition, wear, wounds and commitment while adapting aiming and impact.
Any new height state or command field includes save and replay implications.

Proof: paired hit/miss and blocked/open scenarios, stance and cover cases,
NPC perception, reproducibility and full shared-sim gates. Do not ship a
visual hit that the sim rejects or a sim hit through visible solid cover.

### People and settlement operation

Add ledger animations, reports and conversations, delegation, and first-person
construction access. Preserve authored/generated identities and skills. Build
the captive arc as separately named slices; it is planned work, not recovered
functionality. Emergency reports and standing orders keep administration usable
while the player is away. Menus still need keyboard and mouse accessibility.

Proof: assign work, leave, observe real progress and consequences, return to
reports reflecting events; recruitment and captivity have their own gates.

### End-to-end conversion and default switch

Complete a playable expedition: prepare at the ledger, search a house, attract
danger, fight or retreat, return supplies, treat an injury, save and reload.
Include death and succession, then resume the measured ten-seed balance work
and human ten-day playtest. Measure sim and render budgets separately on a
quiet machine, including the intended NPC population and horde size.

Only switch the default scene and exports after these paths are usable and
verified. Reassess web performance with actual measurements; no browser,
multiplayer, multilevel-world or whole-campaign performance claim is implied
by the foundation scene. Windows is the initial interactive review target.

## Work ownership and review

One branch and worktree per piece, based on main. The coordinator owns the
pivot plan and design records. The code worker owns the foundation and gate
wiring. The art worker owns the original Blender kit. They coordinate on the
asset path, scale, origin and interaction locations rather than editing each
other's files. Integration is an explicitly named piece.

Keep model identifiers out of everything pushed. Each worker reports files,
checks, remaining limitations and a precise commit. The coordinator reviews
and integrates. An independent read-only art reviewer makes its own shots.
Follow the existing green-CI and separate-author merge rules. No gate is
disabled merely because it encodes the old presentation: retain it for the
baseline, or replace it with an explicit new contract when that slice lands.

## Open design details

The owner has approved the first-person direction, physical management access,
colony systems, art references and Blender workflow. Remaining details include
inventory/ledger pause policy, how urgent reports reach the player, the scope
of a foreman's authority, and the eventual vertical-world rules. The initial
prototype may use reversible defaults if it labels them; none constitutes a
new permanent design decision.
