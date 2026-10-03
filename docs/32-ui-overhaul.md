# 32 — UI overhaul design brief

This is the proposed interface design, based on the owner's 2026-10-03 brief and a live
review of merged main `bf6b41a`. It does not describe shipped features. The implementation
order and remaining work live only in [the roadmap](23-roadmap.md#ui-overhaul).
The owner's actual choices are recorded in [the decision record](30-decisions.md#the-whole-interface-2026-10-03).

## Direction

**Project Zomboid practicality first; Tarkov and Zero Sievert for tactical detail; Dungeon
Settlers for visual cohesion with the world.** Ordinary management should be easy to read
and fast to operate while the survival decisions remain demanding.

The survivor screen uses **a stylized anatomical diagram with equipment arranged around it**.
The diagram is a purpose-made illustration, distinct from the small world sprite. Equipment
is recognizable through actual item pictures, readable names and fit information.

The current interface has useful underlying actions, but repeated heavy frames give empty
slots, instructions and important conditions similar weight. Navigation and survivor identity
are inconsistent. The live audit also found skill-web and bench clipping at 720p, learning
prose overflow at both sizes, and vehicle instruments covering quick slots.
[The audit and native-size captures](../.hermes/plans/2026-10-03_ui-overhaul/audit/README.md)
document those findings. Earlier inventory, title, pause and settings captures are in
[the layout review](../.hermes/plans/2026-10-03_ui-layout/).

## Visual language

Use flatter surfaces, deliberate spacing and a small number of strong borders. Reserve
canvas or painted-metal texture for the outer frame and illustration backing; reading
surfaces stay quiet. Item art, small stamped labels and the anatomical drawing provide
identity. The world keeps its existing pixel-art scale and treatment.

| Role | Proposed starting treatment |
| --- | --- |
| Background | Olive charcoal, `#171B18` |
| Panels | Slightly lighter charcoal, `#222720` |
| Primary text | Warm bone, `#E4DFCF` |
| Secondary text | Readable grey khaki, `#B0AE9D` |
| Selection and available action | Muted amber, `#CBA45A`, plus outline/focus shape |
| Grouping | Desaturated moss |
| Urgent condition | Restrained rust, accompanied by words and a distinct mark |

These are prototype colours, subject to native-size contrast review. Prefer a readable
body face such as Source Sans 3 or IBM Plex Sans, with restrained condensed headings if
useful. Bundle and verify the chosen font's license before adoption. Mixed case serves
item names and prose; uppercase is limited to short section labels. Pixel art does not
require small pixel lettering everywhere. Reduced motion remains supported.

[The illustrative concept](../.hermes/plans/2026-10-03_ui-overhaul/anatomical-concept.png)
explores this mood, not final proportions or gameplay. Its diagram and inspector are too
large for an efficient loot screen. The playable layout must devote visible space to bags
and the opened container. Its finer wound label, incomplete equipment set and five illustrated
quick slots are not specifications: production needs ten semantic body regions, all twelve
equipment slots and all six existing quick slots.

## Navigation and layout

One shared navigation frame exposes **Survivor**, **Colony** and the existing event/history
information where it is available. Keep Tab, J, K and contextual E as direct routes. Do not
add an empty Journal page merely because the concept illustrates a label.

The survivor's name is persistent across Loadout, Condition and Skills. Clearly distinguish
the controlled survivor from the person being viewed. A compact roster opens each known
colonist's dossier; returning to a sheet restores its selection and scroll position where
the subject and contents remain valid. An action names its target when it could be ambiguous.

At 1920×1080, Loadout supports three working regions: anatomy/equipment, carried and opened
storage, and item/condition detail. At 1280×720, use purposeful Loadout/Storage/Condition
sections and a contextual detail drawer. Source and destination remain visible together
during transfer; the diagram can recede while packing. Never shrink the entire desktop
layout until the text becomes tiny. All twelve equipment slots remain reachable.

The field HUD becomes compact: immediate self-condition prose, outside context, a clear
interaction prompt, six quick slots and a colony entry point. Detailed anatomy belongs in
the survivor screen. Vehicle instruments have reserved space rather than stacking over
quick access. Preserve the current run/pause behavior and make its actual state clear.

## Inventory and loot

**Recommendation awaiting preference:** retain physical grid packing and add a synchronized
fast list for finding, filtering and selecting items. The grid remains the capacity authority.
If grid-only is preferred, the navigation, item detail and transfer improvements still apply.
A list-only replacement would need an explicit capacity/placement design before implementation.

An opened container and carried storage show their names and owners. Item selection exposes
the most useful facts first: what it is, known condition, where it fits, and available actions.
Flavour prose comes after the task information. Equipment cards show the real item's picture
and name; empty slots use a quieter treatment.

Provide a visible transfer action and an optional shortcut. Use existing legal placement
and transfer commands; if destination is ambiguous, let the player choose. Failed movement
explains the actual reason, such as no fitting space or lost reach. Preserve drag, rotation,
split, equip, unequip, use, drop and nested-container navigation. Filtered views must never
turn a hidden occupied cell into an apparently empty drop target.

Search only contents the current read model legitimately exposes. This work does not grant
knowledge of unopened containers, remote access, unlimited capacity, automatic repacking or
new colony loadout rules. Counted objects and shortcut labels keep their existing exceptions;
hidden condition/stat measurements do not become item-comparison numbers.

## Anatomy, equipment and care

Author a restrained illustrated figure with ten stable, selectable semantic regions: head,
torso, left/right arms, hands, legs and feet. Anatomy detail supports recognition at the
smallest layout. Region shapes, condition overlays and hit regions share the same authored
coordinates. State words and marks remain readable without colour.

Arrange the twelve real equipment slots around it: head, eyes, face, gloves, belt, primary,
vest, torso, legs, feet, back and secondary. Highlight connections on selection rather than
covering the figure with permanent crossing lines. Selecting equipment opens its item detail;
selecting a body region opens known condition and available care information.

Read categorical state, wound, bleeding, dressing, infection and protection information from
the existing condition view. A region-level wound is not a precise wound coordinate; boolean
protection is not a garment drawing. Do not reconstruct health fractions or expose diagnostic
certainty. New anatomy art must not imply smaller damage regions than the simulation knows.

Link to existing treatment actions only when their actor, patient and supply requirements
are satisfied. Viewing a colonist is not permission for the controlled survivor's item-use
action to apply to that colonist. New treatment mechanics are separate work.

The first flow needs small read-model additions for legal action availability and refusal
reasons: current transfer handlers can reject silently, and the existing response view is
limited to self-antibiotics. Derive these words and actions from simulation preconditions
shared with command validation, rather than duplicating eligibility rules in the interface.
Selecting a region must not suggest that every treatment can target it manually today.

## All-screen coverage

This matrix defines the coverage required for the overhaul, not a second status list.

| Surface | Result to deliver |
| --- | --- |
| Field HUD, six quick slots, interaction hints | Compact hierarchy; clear acting person; contextual actions; no collisions with long prose or instruments |
| Survivor loadout, carried bags, opened loot | Anatomical diagram and gear; usable source/destination workspace; consistent inspect, drag and transfer feedback |
| Condition and treatment | Selectable regions linked to truthful condition prose and legal care actions |
| Colony roster and work | Persistent identity, readable job groups, explicit priority controls and Focus choices; details open from the selected person |
| Skills | The same survivor context; legible web navigation, separate selected-node detail and learn action; clear manual/automatic learning |
| Gunsmith bench | Recognizable weapon assembly, installed slots, compatible candidates and existing categorical comparisons; footer reachable at 720p |
| Car, handlebar and board dashboards | Existing distinct instruments composed with the field HUD; mount/exit and six quick slots remain reachable |
| Item and world context menus | Consistent target, action hierarchy, unavailable-action explanation where supported, keyboard focus and dismissal |
| Building and other contextual actions | Existing placement/action feedback uses the same interaction grammar; no new building mechanics implied |
| Help and onboarding hints | Scannable key reference plus contextual prompts; retained keyboard routes remain discoverable |
| Title, pause, save/load, end of run | Distinct game identity, clear selection and feedback, truthful run context and continuity |
| Settings | Coherent treatment of existing opacity, volume and reduced-motion controls; no claim that an advanced screen exists |
| Speech, events, saved/pickup/busy feedback, cursors | Shared visual language, readable timing and priority, no information about unseen actors or hidden duration |
| Developer sheet, spawn menu, attention overlays | Remain distinct developer tools; preserve routes and visibility boundaries during shared-input changes |

Work currently exposes eighteen priority columns but six named jobs lack consumers:
Firefight, Hunt, Farm, Craft, Modify and Butcher. Do not present them as working capabilities.
Keep current activity prose tied to actual read models. Camp assignment, new storage rules,
bulk scheduling and automatic loadout logic are not secretly included in this UI work.

## Integration contracts

Agree these seams before parallel implementation:

- **Subject and authority:** each view identifies the viewed survivor; each command identifies
  actor, item owner and target. Make a small action/target matrix from the current command
  handlers. Preserve reach, ownership, supply, fit and simulation validation; extend only
  the necessary action/reason read models to expose existing rules truthfully.
- **One input owner:** a shared UI controller owns active screens, focus and dismissal order,
  integrating with the current Session states. Escape closes the top interaction once. Opening
  a screen releases held movement. Typing digits in search cannot use a quick-slot item;
  text editing and drag gestures consume their keys before global game input.
- **One theme boundary:** share colour, spacing, type, focus, hover, pressed and selected
  treatments, plus supported read-only/unavailable states. Preserve truthful action availability.
  Use native Godot controls for lists/forms/menus and custom drawing where anatomy/grid
  geometry warrants it. Keep headless resource loading and export behavior valid.
- **Bounded refresh:** cache view snapshots by world, tick, subject and relevant UI state;
  invalidate on load, commands, selection and container changes. Do not rebuild every view
  on every paused frame. Avoid a wholesale controller rewrite before the first flow works.

The coordinator owns `presentation/main.gd`, input/session integration, shared contracts and
documentation. After those seams are fixed, separate worktrees can own theme/components,
inventory/loot, diagram/art, colony/skills, and context/shell files. Assign actual disjoint
paths before each slice; only the coordinator integrates shared files. Read-only design and
runtime audits can proceed alongside those workers.

## Acceptance

Judge actual running screens at **1280×720 and 1920×1080**, using empty and crowded states,
long names/descriptions, multiple injuries, nested bags and a larger roster. Capture the
same representative fixtures before and after. A pretty empty screen is insufficient.

The first playable journey is cupboard → nearly full pack → refused and successful transfer
→ equip → inspect → select an injured region → available care → return to the world. Later
journeys cover a colonist's work/learning choices, fitting a weapon part, mounting/exiting each
vehicle type, help/settings/resume, save/load and the end-of-run screen.

Primary text and actions must remain readable at native size; scroll and clipping regions
must agree with hit testing. Verify keyboard-only navigation for standard controls, visible
focus, cancellation, and clear text/shape cues for conditions. No panel may leave active
children behind when closed or swallow clicks intended for its visible content.

Extend existing inventory, HUD, play, context, response, web and skin gates for behavior and
actual-scene routing. Replace old kit/font/chart-proportion assertions deliberately as the
new design lands; do not remove ownership, health-information, placement or input guarantees.
Run the required full Godot chain for integrated implementation and verify exported resources.

Measure UI refresh and child-control drawing separately on a quiet machine. The existing
world-draw benchmark excludes both, as well as GPU/presentation time. Compare closed HUD,
crowded inventory and colony screens on the same fixture and machine; report actual timing,
not only deterministic runner-contract success. Existing simulation/world rendering overruns
remain visible in [the performance record](22-performance.md#shipped-godot-runtime-measurements).
An interface redesign must not be described as having solved those unrelated overruns.
