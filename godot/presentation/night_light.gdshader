shader_type canvas_item;
// The night, per pixel (presentation/light_map.gd, plan item A10). One screen-sized rect drawn over
// the bodies and multiplied into them: white where the survivor sees in full daylight, the night's
// colour where they see nothing, and a source's own tint where its light lands. It only ever
// darkens -- `blend_mul` cannot make a pixel brighter than the picture under it -- so nothing this
// shader does can show what the world under it did not already draw.
//
// What a pixel's light is, is the simulation's own rule evaluated at that pixel instead of at the
// survivor's feet (SimLight.sight_metres: min(range, max(ambient, lit)), lit the max -- never the
// sum -- of each source's remaining reach). The per-source "does this source reach this tile, and
// does the survivor see it" answer arrives as bits in `light_tex`, built on the CPU from the sim's
// own shadowcasts (light_look.gd's light_texels), so a wall stops light here exactly where it
// stops it in the sim. The shader adds only geometry: distance measured to the pixel rather than
// to the tile centre, and a feather that fades each answer out over the inner half of the last
// tile it holds on -- inward only, so light and sight never bleed onto a tile they do not reach.
//
// Pixel-crisp: everything is evaluated at the centre of the art pixel the fragment lies in, and
// the darkness is cut into LEVELS steps with an ordered dither on that same grid, so the pools
// read as pixel art rather than as a smooth airbrush over it.

render_mode blend_mul, unshaded;

const int MAX_LIGHTS = 24;

// One texel per tile of the view window. R: the survivor sees this tile (255) or not (0). G, B, A:
// bits 0-7, 8-15 and 16-23 -- source i reaches this tile *and* the survivor sees it.
uniform sampler2D light_tex : filter_nearest, repeat_disable;
uniform ivec2 view_origin = ivec2(0, 0);
uniform ivec2 view_size = ivec2(1, 1);

// Screen pixels per tile, and where world (0, 0) lands on screen.
uniform float zoom = 64.0;
uniform vec2 origin_px = vec2(0.0);
// Screen pixels per art pixel: the grid the light is evaluated and dithered on.
uniform float art_px = 2.0;

// The observer's daylight reach and the sky's share of it, in metres.
uniform float range_m = 48.0;
uniform float ambient = 1.0;
// Where the survivor's eyes are, in tiles. The sky's light reaches the survivor's own sight radius
// (ambient x range) and fades out over its outer part, so by night the unlit ground they can see
// is a soft disc around them instead of the shadowcast's square-cornered tiles. Only ever darker.
uniform vec2 eye = vec2(0.0);
uniform float eye_fade = 1.0;
// How lit the survivor's own little disc of night is at least: enough to make out their own body
// and the ground at their feet, which the sim already says they see.
uniform float eye_floor = 0.3;

// Sources, in bit order: xy their position in tiles, z their reach in metres, w how much a flame
// flickers (0 for a bulb). Tints in the same order.
uniform int light_count = 0;
uniform vec4 light_pos[MAX_LIGHTS];
uniform vec4 light_tint[MAX_LIGHTS];
// A beam, for a light whose content has one: xy the way its carrier faces, z the cosine of its
// half-angle (0 means a round pool), w unused. Outside the beam the cast is still the halo.
uniform vec4 light_dir[MAX_LIGHTS];
// How far a beam's bright core reaches, as a fraction of the source's reach: a torch throws its
// light further forward than a lamp throws it all round.
uniform float beam_scale = 0.55;

// The look: the colour of full dark, how much of the way to it a lightless pixel goes, the curve
// a fraction of sight is shown through, how much a pool takes its source's hue, how much darker
// the edge of sight is than the dark inside it, and how many steps the darkness is cut into.
uniform vec4 night_colour : source_color = vec4(0.03, 0.035, 0.07, 1.0);
uniform float night_wash = 0.9;
uniform float curve = 3.0;
uniform float tint_strength = 0.85;
uniform float edge_dark_day = 0.25;
uniform float edge_dark_night = 0.8;
uniform float levels = 14.0;
// The pool: the sim lights a campfire's whole twenty metres, which at the boot zoom is more than
// the screen, so a pool drawn at the sim's reach is no pool at all. The bright core is drawn out
// to pool_scale of a source's reach and the rest of its cast is a halo at halo of that light --
// both only ever *less* than the sim's own number, never more.
uniform float pool_scale = 0.3;
uniform float pool_min_m = 1.5;
uniform float halo = 0.35;
// How bright a pool's core is at least, whatever its source: the pool is where a body is worth
// looking at, and it reads as light only if it is close to daylight.
uniform float core_bright = 0.95;

varying vec2 screen_px;

void vertex() {
	screen_px = VERTEX;
}

// One tile's four bytes, fetched once; a tile outside the view window is all zero (unseen).
ivec4 texel(ivec2 tile) {
	ivec2 cell = tile - view_origin;
	if (cell.x < 0 || cell.y < 0 || cell.x >= view_size.x || cell.y >= view_size.y) {
		return ivec4(0);
	}
	return ivec4(texelFetch(light_tex, cell, 0) * 255.0 + 0.5);
}

// The 4x4 ordered-dither threshold, 0..1, for an art pixel (the Bayer matrix by bit interleave).
float bayer(ivec2 p) {
	int x = p.x & 3;
	int y = p.y & 3;
	int xy = x ^ y;
	int v = ((xy & 1) << 3) | ((x & 1) << 2) | ((xy & 2)) | ((x & 2) >> 1);
	return (float(v) + 0.5) / 16.0;
}

// The fraction of daylight sight shown, through the curve: 0 stays 0, 1 stays 1, and the dim end
// is lifted so a campfire's pool reads as a pool rather than as a slightly less dark patch.
float shown(float fraction) {
	return 1.0 - pow(1.0 - clamp(fraction, 0.0, 1.0), curve);
}

// A per-tile answer softened over the inner half of the tiles that hold it: the four tile centres
// around the pixel, bilinear, then cut at one half so the fade ends exactly at the tile's edge and
// never crosses it. A tile that does not hold the answer is 0 everywhere inside it.
float feather(int b00, int b10, int b01, int b11, int own, vec2 f) {
	if (own == 0) {
		return 0.0;
	}
	float s = mix(mix(float(b00), float(b10), f.x), mix(float(b01), float(b11), f.x), f.y);
	return smoothstep(0.5, 1.0, s);
}

void fragment() {
	ivec2 art = ivec2(floor(screen_px / art_px));
	vec2 centre_px = (vec2(art) + 0.5) * art_px;
	vec2 at = (centre_px - origin_px) / zoom;
	vec2 corner = at - 0.5;
	ivec2 c0 = ivec2(floor(corner));
	vec2 f = corner - vec2(c0);

	ivec4 t00 = texel(c0);
	ivec4 t10 = texel(c0 + ivec2(1, 0));
	ivec4 t01 = texel(c0 + ivec2(0, 1));
	ivec4 t11 = texel(c0 + ivec2(1, 1));
	// The pixel's own tile is one of the four corners: the one its fraction rounds toward.
	ivec4 to = f.y < 0.5 ? (f.x < 0.5 ? t00 : t10) : (f.x < 0.5 ? t01 : t11);
	int own_r = to.r;
	float seen = feather(t00.r > 127 ? 1 : 0, t10.r > 127 ? 1 : 0, t01.r > 127 ? 1 : 0, t11.r > 127 ? 1 : 0, own_r > 127 ? 1 : 0, f);

	// The brightest source here -- max, never sum, as the sim keeps it.
	float best = 0.0;
	vec3 hue = vec3(1.0);
	if (light_count > 0 && own_r > 127) {
		ivec3 b00 = t00.gba;
		ivec3 b10 = t10.gba;
		ivec3 b01 = t01.gba;
		ivec3 b11 = t11.gba;
		ivec3 bo = to.gba;
		for (int i = 0; i < MAX_LIGHTS; i++) {
			if (i >= light_count) {
				break;
			}
			int ch = i / 8;
			int bit = i - ch * 8;
			int own = (bo[ch] >> bit) & 1;
			if (own == 0) {
				continue;
			}
			float mask = feather((b00[ch] >> bit) & 1, (b10[ch] >> bit) & 1, (b01[ch] >> bit) & 1, (b11[ch] >> bit) & 1, own, f);
			vec4 src = light_pos[i];
			float flick = 1.0 - src.w * (0.5 + 0.5 * sin(TIME * 9.0 + float(i) * 1.7) * sin(TIME * 4.3 + float(i) * 0.9));
			float d = distance(at, src.xy);
			float reach = clamp(src.z * flick - d, 0.0, range_m);
			float core_m = max(pool_min_m, src.z * pool_scale) * flick;
			float core = 1.0 - smoothstep(core_m * 0.35, core_m, d);
			vec4 beam = light_dir[i];
			if (beam.z > 0.0) {
				// The wedge: full inside the half-angle, softened over a few degrees past it, and
				// a small disc at the hand so the carrier stands in their own light.
				vec2 to = at - src.xy;
				float along = d > 0.0001 ? dot(to / d, beam.xy) : 1.0;
				float edge = beam.z - 0.06;
				float wedge = smoothstep(edge, beam.z, along);
				float beam_m = max(pool_min_m, src.z * beam_scale) * flick;
				float throw_core = wedge * (1.0 - smoothstep(beam_m * 0.5, beam_m, d));
				float hand = 1.0 - smoothstep(0.6, 1.6, d);
				core = max(throw_core, hand * 0.8);
			}
			float lift = shown(reach / range_m);
			float b = mix(halo * lift, max(lift, core_bright * step(0.0001, reach)), core) * mask;
			if (b > best) {
				best = b;
				hue = light_tint[i].rgb;
			}
		}
	}

	// The sky is shown as it is -- dusk is half dark -- and only a source's light goes through the
	// curve, so the pools carry the night rather than the whole street brightening with them.
	float shown_sky = ambient;
	float sky_r = max(0.5, ambient * range_m);
	float near_eye = 1.0 - eye_fade * smoothstep(sky_r * 0.45, sky_r + 0.75, distance(at, eye));
	float sky_here = max(ambient, eye_floor * eye_fade) * near_eye;
	float shown_here = max(sky_here, best);
	float dark = (1.0 - shown_here) * night_wash;
	// Off the edge of sight: the sky's dark, and a little more, so what is only remembered sits
	// back from what is seen. The feather walks a seen pixel toward it over the last half tile.
	float dark_sky = (1.0 - shown_sky) * night_wash;
	float edge_dark = mix(edge_dark_night, edge_dark_day, shown_sky);
	float dark_unseen = dark_sky + edge_dark * (1.0 - dark_sky);
	dark = mix(dark_unseen, dark, seen);

	// Pixel-crisp steps, dithered on the art grid.
	dark = clamp(floor(dark * levels + bayer(art)) / levels, 0.0, 1.0);

	// A pool takes its source's hue in proportion to how much it out-lights the sky.
	float pool = clamp((shown_here - sky_here) / max(0.0001, 1.0 - sky_here), 0.0, 1.0) * seen;
	vec3 light = mix(vec3(1.0), hue, tint_strength * pool);
	COLOR = vec4(mix(light, night_colour.rgb, dark), 1.0);
}
