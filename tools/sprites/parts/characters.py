"""The published pawn skeleton: no bodies are generated here any more.

Every body on the roster is hand-made art now. "The bodies turn and walk" (docs/23, 2026-09-26)
moved every human onto the outpost pack's four-direction survivor and the shambler onto the
pack's own; the zombie pose study of 2026-10-02 drew seven zombie families; and on 2026-10-19 the
screamer and the bloater -- the last two generated, face-on, flipped rigs -- joined those
families as zombie study 02 (`godot/art/simplyzombies/zombie-poses/study-02/`). Their functions,
the `_figure` assembler, the face and the tone pass that drew them went with them, the standing
rule for art the pack replaces (tools/sprites/README.md), and their keys are on build.py's
`RETIRED_KEYS`.

What is left is the skeleton the face-on rigs were authored against -- named rows in pixels above
the soles of a 32x40 canvas -- because it is still published: `guide.py` draws it as the pawn
guide sheet, and `check_authored.gd` carries a hand copy of two rows for the commissioned-rig
bounds an artist would be held to (assets/sprites/README.md). The proportion is the owner's
2026-09-08 call (docs/30, "Overcast or torchlight"): a body about one tile tall, a third of it
head.
"""

from draw import SIZE

PAWN_W = SIZE
PAWN_H = SIZE * 5 // 4  # 40: a one-tile figure with ten rows of headroom, and 1.25 x zoom is an integer

# --- the published skeleton -------------------------------------------------------------
# Every row is in pixels above the soles, which sit on the canvas's bottom row: y counts
# negative upwards, so FEET_Y = 0 is row 39 and HEAD_CY = -21 is row 18. A body is drawn
# against these and never against a canvas row, so the day the canvas grows the figure does
# not have to be re-derived -- only the anchor moves.
#
# The squat proportion, in rows: legs 6 (0..-6, the boots two of them), trunk 10 (-6..-16),
# the head 13 tall centred at -21 with its chin one row *into* the trunk (a squat figure has
# no neck), crown at -27. A figure is 28 px tall against the 41 it was, and the head is 46% of
# it where it was 27% -- the owner's second call of 2026-09-08, "shorter legs and a bigger
# head", on top of the first. Only the rows and the skull moved; the columns (HAND_X,
# SHOULDER_HALF) are unchanged.
FEET_Y = 0
LEG_TOP_Y = -6
TORSO_TOP_Y = -16
SHOULDER_Y = -14
HAND_Y = -8
HAND_X = 8.4
HEAD_CY = -21
HEAD_R = 6.0
SHOULDER_HALF = 8.0
