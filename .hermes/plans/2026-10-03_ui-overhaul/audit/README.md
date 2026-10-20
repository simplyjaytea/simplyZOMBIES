# Current live UI audit for the redesign

Audited merged main `bf6b41a`, Godot 4.7.1 Compatibility, 2026-10-03. The UI review
worktree was fast-forwarded to main and is clean. No production edits or commits.
This is a design audit, not another geometry-fix slice.

Owner direction received during audit: Project Zomboid first for practical usability;
Tarkov / Zero Sievert for tactical feel, fitted to Dungeon Settlers art. The paperdoll
must remain a stylized anatomical diagram with equipment around it. Grid/list preference
was still pending when this report was written.

## Evidence and method

Twenty-eight new PNGs are in this directory: fourteen scenarios at **actual native
1280×720 and 1920×1080**. Both runs used the live main scene and UI code. The temporary
capture driver was deleted afterwards. Existing `after-*` captures under the repository's
`.hermes/plans/2026-10-03_ui-layout/` still represent the merged inventory, damaged body
chart, ordinary HUD, title, pause, settings, and item-menu surfaces.

The scene was stopped from processing after boot. Screens were opened with their real
keyboard routes where possible, and actual sim read models supplied their contents.
Selected colonist, skill earnings, nearby bench/container, carried attachment candidates,
mounted vehicle, and terminal death state were staged for coverage. There was one explicit
simulation tick near the death capture, not a campaign or performance run. Vehicle
positions were temporarily moved to the player to obtain the three real dashboard layouts.
The bench's service pistol was a staged nearby weapon; the inventory still correctly shows
the player's existing Kitchen Knife in its occupied primary slot. Death text is staged
coverage, not evidence of a naturally played run's narrative.

Both engine processes completed with exit zero. The graphics backend logged unsupported
VSync and resource/texture teardown warnings after the captures; no test-suite pass is
claimed. The retained `capture-*.log` files also mention attempted raw-sheet captures that
were discarded: the stopped scene did not refresh the raw developer text. That is outside
this player-facing redesign audit.

Each filename below has both `1280x720-` and `1920x1080-` prefixes:

| Suffix | Caption |
| --- | --- |
| `key-legend.png` | Live two-column first-run / F1 keyboard reference. |
| `selected-colonist-hud.png` | Ellis selected; header still reads YOU despite another survivor's name. |
| `skill-web-colonist-auto.png` | Selected colonist's autonomous learning web. |
| `skill-web-player-learnable.png` | Player web with earned regional learning available; 720p cuts off the lower/right screen. |
| `work-manual-learning.png` | Ellis set to Manual with a long real learnable-node list; prose overflows even at 1080p. |
| `gunsmith-bench.png` | Service Pistol bench and two compatible carried attachment options; footer below 720p. |
| `loot-transfer.png` | Nearby cupboard and pockets in the small live transfer window. |
| `inventory-with-loot.png` | Full sheet with that cupboard, pockets, equipped Frame Pack, diagram and inspect column. |
| `context-colonist.png` | Actual context verbs for the selected colonist: inspect, camp, shout. |
| `vehicle-dashboard-cluster.png` | Sedan gauges; overlaps action bar and quick slots at both sizes. |
| `vehicle-dashboard-handlebar.png` | Electric-bike instruments; overlaps quick slots. |
| `vehicle-dashboard-board.png` | Kick-scooter motion strip; overlaps quick slots. |
| `attention-overlay.png` | Live attention overlay route enabled in the quiet boot scene. |
| `run-over.png` | Real run-over shell reached with a staged terminal colony state. |

## Existing surface and task map

| Surface / route | Current player task and friction |
| --- | --- |
| Field HUD | Two prose cards, YOU and OUTSIDE; persistent large corner diagram; contextual key/action bar; six-slot belt/pocket strip. Large repeated frames compete with the map. Long self/context prose expands underneath the outside card at 720p. No coherent selected-person identity across panels. |
| World targeting and context / click, right-click | Click selects a known colonist or attacks elsewhere; right-click offers only available verbs. Strong useful action model, but important colony operations depend on finding/selecting someone in the world. Context is plain text with little grouping or target explanation. |
| Gear / Tab | Own equipment in twelve slots around the condition diagram, a vertical fixed-order bag column, inspect pane, and persistent quick slots. Native-size bag cells make capacity honest; a large pack requires scrolling. Full sheet has no search, category filter, fast list, comparison workflow, or survivor switcher. |
| Equipment and item actions / drag, right-click, R | Drag placement and rotation, equip/unequip/use/drop/split/open/inspect menus, nested bag columns, valid/invalid drop feedback. Useful underlying commands; heavily dependent on precise pointer gestures and context-menu discovery. Equipment slots largely show text rather than the item's recognizable art. |
| Condition and care / diagram, prose, T | Ten body regions, wound/infection categorical color and marks, armour outline, written condition/treatment responses. Diagram itself is not an interactive body-part inspector. Condition rows and item inspect are separate; there is no unified patient/task context. |
| Nearby loot / E | Small cupboard-to-pockets transfer window, drag between grids, take all that fits. Tab includes the opened container ahead of personal bags. This is a strong practical basis, but the small window only presents pockets as destination, and full-screen looting forces a lot of vertical travel. |
| Colony work / J | Eighteen priority columns, cycling focus, compressed identity text, manual learnable words. No persistent roster, row-to-survivor dossier navigation, clear current-task column, grouping/filtering, or bulk editing. Headers abbreviate even at 1080p, and long learning prose escapes the panel. |
| Learning / K | Radial six-region web for selected survivor or player. Automatic focus is configured in Work; manual learning can happen here or in Work's prose. This cross-screen dependency is not discoverable. Footer legend is long/truncated; fixed panel spills off 720p. |
| Gunsmith / E near bench | Installed attachment slots versus carried compatible parts, categorical better/worse tradeoffs, click to detach/fit. Good real depth exists but the screen expresses it as two textual lists, with no weapon picture or clear assembly relationships. Fixed position/size clips footer at 720p. |
| Vehicle operation | Distinct car, handlebar and board instruments with existing diegetic gauges/prose. Their placement ignores the permanent field controls, causing overlap. Long mount/exit hints also overrun the HUD's available width. |
| F1 help | Full reference grouped into Move, Act, Look, Run. Most discoverability is concentrated here; the E entry is a paragraph describing many contexts. The new design needs contextual learning alongside this reference. |
| Title / pause / death | Centered framed action lists, keyboard and mouse focus, save feedback, run-over chronicle excerpt. Functional but the same visual hierarchy as every ordinary sheet, little game identity, and limited run context. |
| Settings | Only panel opacity, master volume and reduced motion. **There is no advanced-settings screen**. UI scale, display options and rebinding would be new features, not a reskin of existing controls. |
| Feedback and world presentation | Saved stamp, pickup ping, focus pulse, busy motion, cursors/drag verdict, own condition text near pawn, focal speech bubbles, remembered map/afterimages, noise/scent/sight/light overlays. These need the same design grammar without revealing unseen actors or hidden certainty. |
| Developer tools | M raw sheet and F8 spawn menu. These are separate dev surfaces, not an advanced player settings menu; preserve their separation. |

## Navigation and interaction consequences

The current focus stack is shell → legend → settings → web → bench → sheet → work →
street. Escape closes the relevant layer; routes are allowlisted per focus. Movement is
released when entering a panel. Keep these input guarantees and existing shortcuts while
adding visible navigation.

Selection currently splits three ways: street-selected survivor drives HUD and K; Tab,
quick slots and the corner condition chart remain the player; J lists colonists but does
not provide a direct dossier route. The selected-colonist screenshot makes the confusing
YOU/Ellis heading visible. A persistent, explicit subject identity is more valuable than
new frame decoration.

Inventory and management panels do not inherently promise a paused world. The new layout
must make the actual run/pause/speed state visible and keep context-specific actions from
obscuring one another. Do not quietly introduce automatic pause or remote colony-equipment
commands during a presentation redesign; those are behavior changes to decide explicitly.

## Anatomical diagram and art constraints

The current diagram is a 64×160 authored mask canvas, ten parts, three poses, drawn at
integer scale (2× compact/corner, 3× wide inventory). It uses simple geometric silhouettes,
categorical tint/marks and an armour outline. There is no detailed anatomical line drawing
or gear-rendering layer. Twelve surrounding equipment frames mostly contain names and
small slot symbols. The world body's 32×40 directional sprite and limited wearable layers
are not an appropriate source for detailed UI anatomy or large inventory item pictures.

Recommended art direction is **a purpose-made stylized anatomical diagram**, still distinct
body regions and readable at the smallest supported size, with restrained clinical marks
and a linked selected-part treatment detail. Surround it with clearer actual-item cards:
recognizable equipment art, names, discrete condition prose, slots and compatibility. Avoid
turning the diagram into a dressed avatar: that contradicts the owner's latest direction.
Retain categorical condition semantics; no health fractions, infection-certainty meter or
hidden-stat reconstruction is needed for tactical detail.

## Recommended design groups

1. **Shared navigation, subject and hierarchy.** Establish one screen frame with visible
   routes for field, survivor gear/condition, colony work and learning, plus unambiguous
   selected-person identity and return context. Keep the existing shortcuts. Use shared
   spacing, type hierarchy, hover/focus, scrolling, panels and accessible contrast, rather
   than the same thick frame at every nesting level. Draw from Dungeon Settlers material
   and pixel discipline while giving long practical prose enough legibility.
2. **Field and colony awareness.** Compact field chrome, actionable context in one place,
   explicit paused/running state, consistent quick slots, and a reserved vehicle-instrument
   region. Add a compact colony roster entry point with allowed status prose and a direct
   path to each person's work/learning detail. Keep the playable world prominent.
3. **Survivor, equipment and care.** Diagram plus surrounding loadout as the stable anchor;
   connect selected body part, equipment protection and available treatment information.
   Make gear readable from actual pictures and clean inspect/compare sections. Preserve
   player-versus-selected-colonist authority and target identity when dispatching commands.
4. **Practical inventory and looting.** Put source/destination ownership, transfer and item
   actions within reach. If the owner chooses grid plus fast list, both views must expose
   the same real container membership and placement constraints: a list is not unlimited
   storage. Search/filter/grouping and deliberate quick transfer can improve ordinary
   looting without removing spatial packing. Avoid changing the sim to fake convenience.
5. **Colony management and learning.** A usable work table with pinned survivor identity,
   readable job groups, clear priority editing and selected-row detail. Place focus and
   learning together in that survivor's context; the radial web can be a detailed learning
   view rather than the only way to understand progression. Bulk actions and new current-job
   readouts must be explicitly scoped as capabilities beyond today's table.
6. **Weapon/vehicle detail and supporting screens.** Weapon assembly art plus attachment
   relationships, eligible candidates and prose comparisons; vehicle instruments that
   compose with field controls; coherent context/item menus, title/pause/death/help/settings
   and transient feedback. No screen should be left wearing the old chrome merely because
   inventory got the first visual pass.

Prototype and acceptance journeys should include: loot a cupboard into a nearly full pack;
find/use a dressing for a named injured part; change one colonist's role and learning path;
compare/fit a weapon part; enter/exit a vehicle; open help/settings and resume; and end a run.
Judge them at both supported sizes with crowded/long-content states, not only empty boot UI.

Implementation should retain the existing sim read models and command queues. Extend the
current inventory/HUD/play/web/context/vehicles/UI-skin gates to exercise those journeys,
including overflow and correct target dispatch. No broad test redesign is implied by this
audit. At capture time, `godot/ui/README.md` and the UI-kit README were stale about what was
already live. The proposal's documentation patch corrects those descriptions; this audit
describes the earlier baseline and is not an implementation record for the redesign.
