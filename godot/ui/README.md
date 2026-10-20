# Godot UI boundary

Godot `Control` scenes belong here. They render simulation state and submit commands, but
must not own authoritative health, inventory, combat, attention, or AI state. This directory
contains the live HUD, inventory/loot, condition chart, work/skills, bench, vehicles, context
menus and system screens. `presentation/main.gd` currently composes them; `chrome.gd` and
`kit.gd` provide the shared Field Kit treatment.

The owner's October 3 whole-interface redesign is described in
[the UI brief](../../docs/32-ui-overhaul.md), with implementation order only in
[the roadmap](../../docs/23-roadmap.md#ui-overhaul). It is proposed work, not a completed
migration. The new design may replace the old kit, font and panel/chart composition while
preserving information constraints, command validation and run-state/input guarantees.
