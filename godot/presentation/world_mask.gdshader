shader_type canvas_item;
// The baked world's sight mask (presentation/world_layers.gd). Every baked layer draws in world
// pixels -- tile (tx, ty) covers [tx * zoom, (tx + 1) * zoom) -- so the fragment's own local
// position says which tile it is on, and that tile's state says whether this layer shows there.
// One shader, five materials: each layer passes the bits it needs set and the bits it needs
// clear. Nothing here decides *what* a tile looks like; that was baked. This only decides which
// of the baked looks the screen shows, which is the per-frame question the old tile loop asked
// with `has_tile` and `continue`.
//
// Inputs, all sampled with texelFetch so no filtering can blur one tile into the next:
//   live_cells  the player's shadowcast, size x size, 1 where a sightline reaches (VisibleTiles)
//   flags       one byte per map tile: EXPLORED (the remembered map, unpacked from the sim's
//               bitset), ROOF (the roof rule chose it), A2 (a wall module stands there), and
//               LIVE itself when the sight set is not the sim's own VisibleTiles

const int LIVE = 1;
const int EXPLORED = 2;
const int ROOF = 4;
const int A2 = 8;

uniform sampler2D live_cells : filter_nearest;
uniform sampler2D flags : filter_nearest;
uniform float zoom = 64.0;
uniform ivec2 map_size = ivec2(1, 1);
uniform ivec3 live_origin = ivec3(0, 0, 0); // x, y of cell (0, 0) in tiles, and the cast's size
// Where LIVE comes from: 0 the flags byte (a duck-typed sight set, written tile by tile), 1 the
// shadowcast's own cells, 2 every tile (no observer view at all: everything draws as seen).
uniform int live_source = 0;
uniform int want = 1;
uniform int deny = 0;

varying vec2 world_px;

void vertex() {
	world_px = VERTEX;
}

int byte_at(sampler2D tex, ivec2 at) {
	return int(texelFetch(tex, at, 0).r * 255.0 + 0.5);
}

int state_of(ivec2 tile) {
	int bits = byte_at(flags, tile);
	if (live_source == 2) {
		bits |= LIVE;
	} else if (live_source == 1) {
		ivec2 cell = tile - live_origin.xy;
		if (cell.x >= 0 && cell.y >= 0 && cell.x < live_origin.z && cell.y < live_origin.z && byte_at(live_cells, cell) == 1) {
			bits |= LIVE;
		}
	}
	return bits;
}

void fragment() {
	ivec2 tile = ivec2(floor(world_px / zoom));
	if (tile.x < 0 || tile.y < 0 || tile.x >= map_size.x || tile.y >= map_size.y) {
		discard;
	}
	int state = state_of(tile);
	if ((state & want) != want || (state & deny) != 0) {
		discard;
	}
}
