extends RefCounted
# The first-person art seam. Nothing here is required for the foundation to boot: every path is
# optional, and a missing model falls back to the placeholder box the view builds itself. That is
# deliberate -- the art worker owns `godot/assets/first_person/`, and this branch must not depend on
# files that have not merged yet.
#
# Conventions for whoever lands the models, repeated here so the contract travels with the code:
#   - glTF 2.0 `.glb`, +Y up, Godot forward -Z.
#   - Metres. A tile is one metre (`SimTileMap.TILE_METRES`).
#   - Origin at the floor centre, except the ledger: origin at its bottom centre, so it can stand
#     on the desk without a second offset.
#   - desk height 0.78 m; ledger 0.30 m x 0.22 m (x by z).
#
# The names are the seam: `desk.glb`, `ledger.glb`, `shelf.glb`, `barricade.glb`, `wall_module.glb`.
# Only desk and ledger are read today; the rest are reserved so the art pass can land piecemeal.

const DIR: String = "res://assets/first_person/"
const DESK: String = DIR + "desk.glb"
const LEDGER: String = DIR + "ledger.glb"
const SHELF: String = DIR + "shelf.glb"
const BARRICADE: String = DIR + "barricade.glb"
const WALL_MODULE: String = DIR + "wall_module.glb"

const DESK_HEIGHT_M: float = 0.78
const DESK_WIDTH_M: float = 1.20
const DESK_DEPTH_M: float = 0.62
const LEDGER_WIDTH_M: float = 0.30
const LEDGER_DEPTH_M: float = 0.22
const LEDGER_THICKNESS_M: float = 0.026
const SHELF_SIZE: Vector3 = Vector3(0.90, 1.85, 0.32)
const BARRICADE_SIZE: Vector3 = Vector3(1.20, 1.10, 0.18)
const WALL_MODULE_SIZE: Vector3 = Vector3(1.00, 2.60, 0.12)
# Where the ledger's centre sits above the floor: the desk top plus half its own thickness. The
# ledger's authored origin is its bottom centre, so its node is placed on the desk top instead.
const LEDGER_TOP_M: float = DESK_HEIGHT_M + LEDGER_THICKNESS_M


## The packed scene at `path`, or null when the art has not landed. `ResourceLoader.exists` is the
## one test used, so an empty seam is a normal boot rather than a load error in the log.
static func model(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	return resource as PackedScene
