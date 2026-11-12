shader_type spatial;
// The ground (docs/46, "The ground"): one continuous surface in the valley's materials. Every value
// here is set by ground_look.gd, which also explains the two maps. Nothing is lit by this shader
// but what the scene's own lights reach: no emission, default shading, shadows received.
//
// Near the eye a fragment picks its material from the per-tile map, looked up at a coordinate pushed
// about by noise so two materials meet along a ragged line, then reads that material's tile at 64
// texels a metre. Far from the eye, where a tile is a pixel or less, it reads the tile's mean colour
// from a filtered map instead, so distance blurs and does not shimmer.
//
// Target: the Compatibility renderer (GLES3, and WebGL2 on the web). At most five texture reads a
// fragment near the eye and three far from it; the branches are there to skip reads, which is what
// a software rasteriser pays for. Every read inside a branch passes its own gradients.
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

const int LAYERS = 9;
const int LAYER_ASPHALT = 0;
const int LAYER_FORD = 6;
const int LAYER_WATER = 7;
const int FLAG_FIRM = 1;
const int FLAG_SEALED = 2;

// One texel a tile. R: the material. G: flags (firm, sealed). B: road paint (0 none, else
// 1 + variant + 4 for a line running east-west).
uniform sampler2D tile_map : filter_nearest, repeat_disable;
// One texel a tile: the tile's mean colour, and in A how far a damp patch darkens it.
uniform sampler2D far_map : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2DArray surfaces : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
// R: paint. G: paint gone grey.
uniform sampler2DArray paint : filter_nearest_mipmap_anisotropic, repeat_enable;
// R, G: the push of a boundary. B: the slow field of damp patches and the macro tint.
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

uniform vec2 map_size = vec2(256.0, 256.0);
uniform float texels_per_metre = 64.0;
uniform float surface_period_m = 4.0;
uniform vec2 noise_offset = vec2(0.0, 0.0);
uniform float edge_wander_m = 0.38;
uniform float edge_period_m = 13.0;
uniform float patch_period_m = 47.0;
uniform float patch_threshold = 0.60;
uniform float patch_breakup = 0.45;
uniform float patch_step = 0.06;
uniform float patch_grit = 0.03;
uniform float edge_grit_m = 0.06;
uniform float patch_roughness = 0.6;
uniform float macro_period_m = 211.0;
uniform float macro_strength = 0.07;
uniform float far_start_m = 0.15;
uniform float far_end_m = 0.60;
uniform float patch_tint[9];
uniform float roughness_of[9];
uniform float season_weight[9];
// The season's grass over spring's, in linear light.
uniform vec3 season_tint = vec3(1.0, 1.0, 1.0);
uniform vec3 paint_colour : source_color = vec3(0.79, 0.78, 0.72);
uniform vec3 paint_worn_colour : source_color = vec3(0.70, 0.70, 0.64);
uniform float paint_strength = 0.9;
uniform float water_drift_m = 0.05;
uniform float bank_shade = 0.55;

varying vec3 world_pos;
varying float steep;


// A number in 0..1 for one world texel: the grit that ends an edge in single texels.
float grit(vec2 cell) {
	uvec2 q = uvec2(ivec2(cell));
	uint h = q.x * 0x9E3779B1u + q.y * 0x85EBCA77u;
	h ^= h >> 15u;
	h *= 0x2C1B3C6Du;
	h ^= h >> 12u;
	return float(h >> 8u) / 16777216.0;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// A bank face under a water tile stands upright; it reads the tile behind it.
	steep = 1.0 - abs(n.y);
	world_pos.xz -= n.xz * 0.02 * steep;
}


void fragment() {
	vec2 p = world_pos.xz;
	vec2 ddx = dFdx(p);
	vec2 ddy = dFdy(p);
	float footprint = max(length(ddx), length(ddy));
	bool bank = steep > 0.5;
	// The world's own texel grid: every choice below is made per texel, so an edge is pixel-crisp.
	vec2 cell = floor(p * texels_per_metre);
	vec2 ps = (cell + 0.5) / texels_per_metre;
	// Grit is for the eye up close: once a pixel holds a few texels it would only sparkle.
	float speck = (grit(cell) - 0.5) * (1.0 - smoothstep(0.8, 3.0, footprint * texels_per_metre));
	ivec2 last = ivec2(map_size) - ivec2(1);
	vec4 here = texelFetch(tile_map, clamp(ivec2(floor(p)), ivec2(0), last), 0);
	vec4 tile = here;
	vec3 edge = textureGrad(noise, ps / edge_period_m + noise_offset, ddx / edge_period_m, ddy / edge_period_m).rgb;
	if (!bank) {
		vec2 pushed = ps + (edge.rg - 0.5) * 2.0 * edge_wander_m + vec2(speck, -speck) * edge_grit_m;
		vec4 there = texelFetch(tile_map, clamp(ivec2(floor(pushed)), ivec2(0), last), 0);
		int f0 = int(here.g * 255.0 + 0.5);
		int f1 = int(there.g * 255.0 + 0.5);
		// A sealed tile (a room, a wall's footing) keeps its square; two firm tiles (asphalt against
		// concrete) meet along a straight line; anything soft frays.
		bool sealed = ((f0 | f1) & FLAG_SEALED) != 0;
		bool firm = ((f0 & f1) & FLAG_FIRM) != 0;
		if (!sealed && !firm) {
			tile = there;
		}
	}
	int layer = clamp(int(tile.r * 255.0 + 0.5), 0, LAYERS - 1);

	float far = smoothstep(far_start_m, far_end_m, footprint);
	vec3 colour = vec3(0.0);
	float patch_mul = patch_tint[layer];
	if (far < 1.0) {
		vec2 uv = p / surface_period_m;
		if (layer == LAYER_FORD || layer == LAYER_WATER) {
			// Water drifts a texel at a time.
			uv.x += floor(TIME * water_drift_m * texels_per_metre) / (texels_per_metre * surface_period_m);
		}
		colour = textureGrad(surfaces, vec3(uv, float(layer)), ddx / surface_period_m, ddy / surface_period_m).rgb;
		int code = int(here.b * 255.0 + 0.5);
		if (code > 0 && layer == LAYER_ASPHALT) {
			int c = code - 1;
			bool east_west = c >= 4;
			vec2 puv = east_west ? p.yx : p;
			vec2 pdx = east_west ? ddx.yx : ddx;
			vec2 pdy = east_west ? ddy.yx : ddy;
			vec4 line = textureGrad(paint, vec3(puv, float(c & 3)), pdx, pdy);
			colour = mix(colour, mix(paint_colour, paint_worn_colour, line.g), line.r * paint_strength);
		}
		colour *= mix(vec3(1.0), season_tint, season_weight[layer]);
	}
	if (far > 0.0) {
		// The far map carries the season and the paint already.
		vec4 mean = textureGrad(far_map, p / map_size, ddx / map_size, ddy / map_size);
		colour = mix(colour, mean.rgb, far);
		patch_mul = mix(patch_mul, mean.a, far);
	}

	// Damp patches: a slow field broken up by the middle one, so a patch has a ragged shore. Far
	// off the shore softens with the pixel.
	float slow = textureGrad(noise, ps / patch_period_m + noise_offset.yx, ddx / patch_period_m, ddy / patch_period_m).b;
	float patch_field = mix(slow, edge.b, patch_breakup) + speck * patch_grit;
	float soft = 0.012 + footprint * 0.2;
	// Two steps: damp, then wet.
	float damp = 0.5 * smoothstep(patch_threshold, patch_threshold + soft, patch_field)
		+ 0.5 * smoothstep(patch_threshold + patch_step, patch_threshold + patch_step + soft, patch_field);
	colour *= mix(1.0, patch_mul, damp);
	float macro = texture(noise, p / macro_period_m + noise_offset * 0.37).b;
	colour *= 1.0 + (macro - 0.5) * 2.0 * macro_strength;
	if (bank) {
		colour *= bank_shade;
	}
	ALBEDO = colour;
	ROUGHNESS = roughness_of[layer] * mix(1.0, patch_roughness, damp);
	SPECULAR = 0.5;
}
