# simplyZOMBIES

Hardcore colony survival: attention (noise/scent/light) ties survival to tower-defense pressure. One attention system, no wave timer.

## Language

**Need**:
A survival pressure every survivor carries — hunger, thirst, rest, mood, temperature, or hygiene. Six in parallel, including the controlled character. Not one collapsed bar.
_Avoid_: Stat (reserved for STR/CON/DEX), attribute, meter (too vague — pools, bands, and mood are different shapes)

**Need pool**:
A 0–100 depleting store for hunger, thirst, or rest. 100 is full.
_Avoid_: Bar, health bar, hunger meter (when you mean the pool itself)

**Need band**:
A discrete grade for temperature or hygiene, not a depleting store. Temperature runs comfortable through three cold and three hot degrees; hygiene runs clean through three dirty degrees.
_Avoid_: Flag, temperature meter, hygiene meter

**Soft cascade**:
The early failure mode of a Need — performance and mood degrade before a hard crisis.
_Avoid_: Soft fail, soft death

**Hard crisis**:
The late failure mode after a soft cascade — collapse, leaving, illness, or an equivalent lethal or immobilizing outcome.
_Avoid_: Instant death (unless a specific Need truly kills immediately)

**Need hold**:
A sandbox freeze that keeps Need pools full and bands at comfortable/clean without unregistering the systems.
_Avoid_: Disable needs, god mode, cheat (those mean turning the module off)

**Need crisis**:
The hard-crisis state on a survivor: none, starving, dehydrating, or passed_out. Not a stance and not an injury.
_Avoid_: Stance, downed, starvation injury

**Need seek**:
An NPC interrupt to eat, drink, sleep, wash, or stand at a lit Campfire. Not a Job and not pathfinding inside a Need module.
_Avoid_: Job, chore, needs AI

**Job**:
An NPC work type in the slice: Haul, Construct, Cook, Doctor, or Rest. Guard exists only on Mara’s leftover row.
_Avoid_: Task (wayfinder decision tickets), chore, Need seek

**Stockpile**:
Colony items sitting on the exam-room indoor floor. Personal grids stay personal.
_Avoid_: Colony inventory, shared pool, warehouse, stash UI

**Campfire**:
The authored exam-room station that is heat, Cook, and light. Starts unlit. The player douses it.
_Avoid_: Stove, heater, firepit, light source (when you mean this object)

**Survivor generator**:
The content pool that rolls ordinary survivors (name, trait, backstory) for the slice — distinct from unique authored survivors like Mara.
_Avoid_: RNG recruit, random NPC
