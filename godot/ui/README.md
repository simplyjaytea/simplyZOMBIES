# Godot UI boundary

Godot `Control` scenes belong here. They may render simulation state and submit commands, but they
must not own authoritative health, inventory, combat, attention, or AI state. The first parity UI
arrives in R4; this boundary exists now so presentation code does not absorb it in the meantime.
