# Native asset audit

Status: **PASS**. 187 assets, 279 unique native sprite PNGs, 22 multi-frame animation states.

| Group | Assets | Animated assets | Animation states | Frame entries |
|---|---:|---:|---:|---:|
| characters | 2 | 2 | 16 | 40 |
| effects | 20 | 12 | 12 | 48 |
| environment | 33 | 0 | 0 | 0 |
| items | 60 | 0 | 0 | 0 |
| props | 33 | 0 | 0 | 0 |
| utility | 35 | 2 | 2 | 8 |
| wearables | 4 | 0 | 16 | 16 |

Errors: 0. Review notes: 0. The JSON report contains exact IDs and details. Reused frames are flagged for review rather than silently counted as distinct drawings. Single-frame facing states are not counted as animated assets.

Checks metadata, PNG decoding, native size, alpha presence, coordinates and pixel uniqueness. Does not validate Godot import, collisions, autotile rules, visual style, animation timing quality or anatomy.
