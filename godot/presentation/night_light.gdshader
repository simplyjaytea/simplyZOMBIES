shader_type canvas_item;
// The night, per pixel (presentation/light_map.gd, plan item A10). One screen-sized rect drawn over
// the bodies and multiplied into them: white where the survivor sees in full daylight, the night's
// colour where they see nothing, and a source's own tint where its light lands. It only ever
// darkens -- `blend_mul` cannot make a pixel brighter than the picture under it -- so nothing this
// shader does can show what the world under it did not already draw.
//
// Where light may land is the simulation's: the per-source "does this source reach this tile, and
// does the survivor see it" answer arrives as bits in `light_tex`, built on the CPU from the sim's
// own shadowcasts (light_look.gd's light_texels), so a wall stops light here exactly where it stops
// it in the sim, and a source's light is feathered inward only, never onto a tile the survivor does
// not see. How much light lands there is the look: each source draws a pool out to its own radius
// (pool_scale of its sim reach) and nothing past it, at a brightness capped by how strong the
// source is (LightLook.source_cap) -- less light than the sim's, never more, so outside a pool the
// night holds at its floor however far the sim says the cast goes.
//
// Pixel art, not airbrush: everything is evaluated at the centre of the art pixel the fragment lies
// in, every light is snapped to `pool_levels` flat rings with an ordered dither only in the band
// where one ring gives way to the next, and the darkness is rounded to `levels` steps -- dithered
// only where seen gives way to unseen or the known map to the void, the other places the picture
// changes.

render_mode blend_mul, unshaded;

const int MAX_LIGHTS = 24;

// One texel per tile of the view window. R: the survivor sees this tile (255) or not (0). G, B, A:
// bits 0-7, 8-15 and 16-23 -- source i reaches this tile *and* the survivor sees it.
uniform sampler2D light_tex : filter_nearest, repeat_disable;
uniform ivec2 view_origin = ivec2(0, 0);
uniform ivec2 view_size = ivec2(1, 1);

// Screen pixels per tile, and where world (0, 0) lands on screen.
uniform float zoom = 64.0;
uniform float art_px = 2.0;
uniform vec2 origin_px = vec2(0.0);

// The sky's share of a survivor's daylight sight: 1 at noon, the night's ambient at midnight; and
// that daylight sight, in metres. The sky lights the ground out to ambient x range_m around them.
uniform float ambient = 1.0;
uniform float range_m = 48.0;
// Where the survivor's eyes are, in tiles, and how far they see from there (LightLook.eye_disc_metres:
// their own sight at their feet, held under EYE_DISC_MAX_M). By night the ground they can make out
// with no light at all is a small disc around them at eye_floor of daylight, in rings like a pool's.
uniform vec2 eye = vec2(0.0);
uniform float eye_fade = 1.0;
uniform float eye_reach = 2.0;
uniform float eye_floor = 0.55;

// Sources, in bit order: xy their position in tiles, z their reach in metres, w how much a flame
// flickers (0 for a bulb). Tints in the same order, w the brightest the pool gets (source_cap).
uniform int light_count = 0;
uniform vec4 light_pos[MAX_LIGHTS];
uniform vec4 light_tint[MAX_LIGHTS];
// A beam, for a light the sim casts as one: xy the way its carrier faces, z the cosine of its
// half-angle (0 means a round pool), w the cosine a little inside it, where the light is full.
// Outside the beam there is only the spill's disc at the hand.
uniform vec4 light_dir[MAX_LIGHTS];
// How far a beam reaches, as a fraction of the source's reach: a torch throws its light further
// forward than a lamp throws it all round.
uniform float beam_scale = 0.55;
// The disc a beam draws at the hand, in metres: the sim's spill (SimLight.SPILL_M), the ground a
// torch lights whichever way it points.
uniform float spill_m = 1.5;

// The look: the colour of full dark, how much of the way to it a lightless pixel goes at dusk (all
// of it at midnight), how much a
// pool takes its source's hue, how much darker the edge of sight is than the dark inside it (by day
// and by night), the darkness's steps, and a pool's rings and the width of the dither between two.
uniform vec4 night_colour : source_color = vec4(0.03, 0.035, 0.07, 1.0);
uniform float night_wash = 0.94;
uniform float tint_strength = 0.85;
uniform float edge_dark_day = 0.0;
uniform float edge_dark_night = 0.95;
uniform float levels = 20.0;
// How much of the night's colour is left at midnight (LightLook.NIGHT_FLOOR), and how dark the
// known map's edge beside the void goes.
uniform float night_floor = 0.24;
uniform float void_dark = 0.9;
uniform float pool_levels = 5.0;
uniform float band = 0.35;
// A pool's radius: pool_scale of the source's sim reach, never under pool_min_m. The sim lights a
// campfire's whole twenty metres, which at the boot zoom is more than the screen; a pool drawn at
// the sim's reach would be no pool at all.
uniform float pool_scale = 0.3;
uniform float pool_min_m = 1.5;

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

// A 0..1 falloff snapped to pool_levels flat rings. The last `band` of each ring is an ordered
// dither toward the next one up, so a ring's edge reads as pixel art; a flat ring has no dither in
// it at all. 0 stays 0 and 1 stays 1.
float rings(float v, float threshold) {
	float x = clamp(v, 0.0, 1.0) * pool_levels;
	float k = floor(x);
	float t = clamp((x - k - (1.0 - band)) / band, 0.0, 1.0);
	return min(pool_levels, k + step(threshold, t - 0.0001)) / pool_levels;
}

// How far inside its own tile an answer holds, 0 at the edge of a neighbour that does not hold it
// and 1 half a tile in: the tile's own answer, its neighbour across the nearer vertical edge (h),
// across the nearer horizontal edge (v) and across the nearer corner (d), and the pixel's distance
// to those edges in tiles (0 to 0.5). Each missing neighbour fades it toward its own edge or corner,
// so the fade always reaches 0 exactly at the tile boundary, corners included, and never crosses
// it -- a bilinear blend of the four tile centres would leave a corner half-lit and step there.
float inside(int own, int h, int v, int d, vec2 dist) {
	if (own == 0) {
		return 0.0;
	}
	float m = 1.0;
	if (h == 0) {
		m *= smoothstep(0.0, 0.5, dist.x);
	}
	if (v == 0) {
		m *= smoothstep(0.0, 0.5, dist.y);
	}
	if (d == 0 && h != 0 && v != 0) {
		m *= smoothstep(0.0, 0.5, length(dist));
	}
	return m;
}

// The same answer centred on the tile boundary instead: 1 half a tile inside the tiles that hold
// it, 0 half a tile inside the ones that do not, one half on the boundary itself.
float across(int own, int h, int v, int d, vec2 dist) {
	if (own != 0) {
		return 0.5 + 0.5 * inside(own, h, v, d, dist);
	}
	return 0.5 - 0.5 * inside(1, 1 - h, 1 - v, 1 - d, dist);
}

void fragment() {
	ivec2 art = ivec2(floor(screen_px / art_px));
	float threshold = bayer(art);
	vec2 centre_px = (vec2(art) + 0.5) * art_px;
	vec2 at = (centre_px - origin_px) / zoom;
	vec2 corner = at - 0.5;
	ivec2 c0 = ivec2(floor(corner));
	vec2 f = corner - vec2(c0);

	ivec4 t00 = texel(c0);
	ivec4 t10 = texel(c0 + ivec2(1, 0));
	ivec4 t01 = texel(c0 + ivec2(0, 1));
	ivec4 t11 = texel(c0 + ivec2(1, 1));
	// The pixel's own tile is one of the four corners, the one its fraction rounds toward; the
	// other three are its neighbours across the nearer vertical edge, horizontal edge and corner.
	bool right = f.x >= 0.5;
	bool below = f.y >= 0.5;
	ivec4 to = below ? (right ? t11 : t01) : (right ? t10 : t00);
	ivec4 th = below ? (right ? t01 : t11) : (right ? t00 : t10);
	ivec4 tv = below ? (right ? t10 : t00) : (right ? t11 : t01);
	ivec4 td = below ? (right ? t00 : t10) : (right ? t01 : t11);
	vec2 dist = abs(f - 0.5);
	int own_r = to.r;
	// Seen (R 255) and known (R 128 or 255: seen now, or remembered), as the darkness reads them.
	// The edge of sight is centred on the tile boundary, half a tile into each side, so a lone seen
	// tile is a rounded patch rather than a hard square. Only the sky and the survivor's own disc
	// cross into the unseen side; no source's light does.
	float seen = across(int(to.r > 191), int(th.r > 191), int(tv.r > 191), int(td.r > 191), dist);
	// The void -- tiles never seen, which no layer draws -- cannot be lit or faded by a multiply, so
	// the known side does all the fading: its last half tile walks down to the void's own dark.
	float known = inside(int(to.r > 63), int(th.r > 63), int(tv.r > 63), int(td.r > 63), dist);

	// The brightest light here -- max, never sum, as the sim keeps it. Round pools and beams are kept
	// apart so a beam crossing a pool can lay its light over the pool's colour instead of replacing it.
	float best = 0.0;
	vec3 hue = vec3(1.0);
	float best_beam = 0.0;
	vec3 hue_beam = vec3(1.0);
	if (light_count > 0 && own_r > 191) {
		ivec3 bo = to.gba;
		ivec3 bh = th.gba;
		ivec3 bv = tv.gba;
		ivec3 bd = td.gba;
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
			float mask = inside(own, (bh[ch] >> bit) & 1, (bv[ch] >> bit) & 1, (bd[ch] >> bit) & 1, dist);
			vec4 src = light_pos[i];
			vec4 tint = light_tint[i];
			float flick = 1.0 - src.w * (0.5 + 0.5 * sin(TIME * 9.0 + float(i) * 1.7) * sin(TIME * 4.3 + float(i) * 0.9));
			float d = distance(at, src.xy);
			float radius = max(pool_min_m, src.z * pool_scale) * flick;
			// A round pool: full to a fifth of its radius, gone at the radius, and nothing past it.
			float fall = 1.0 - smoothstep(radius * 0.2, radius, d);
			vec4 beam = light_dir[i];
			if (beam.z > 0.0) {
				// The wedge, from the hand: full a little inside the half-angle and gone at it, so it
				// ends inside the tiles the sim's own wedge lights (the bits), and the spill at the
				// hand, so the carrier stands in their own light.
				vec2 ray = at - src.xy;
				float along = d > 0.0001 ? dot(ray / d, beam.xy) : 1.0;
				float wedge = smoothstep(beam.z, beam.w, along);
				float reach_m = max(pool_min_m, src.z * beam_scale) * flick;
				float thrown = wedge * (1.0 - smoothstep(reach_m * 0.45, reach_m, d));
				float hand = 1.0 - smoothstep(spill_m * 0.4, spill_m, d);
				fall = max(thrown, hand * 0.7);
			}
			float b = tint.w * rings(fall * mask, threshold);
			if (beam.z > 0.0) {
				if (b > best_beam) {
					best_beam = b;
					hue_beam = tint.rgb;
				}
			} else if (b > best) {
				best = b;
				hue = tint.rgb;
			}
		}
	}
	// Where a beam crosses a pool the brighter of the two sets the level, and the colour is the two
	// tints weighed by how bright each is here: a torch over a campfire's ground stays warm under the
	// white. A pixel only one of them reaches keeps that one's tint exactly. No channel of the blend,
	// at the brighter level, comes out above what the brighter of the two lights gives it alone.
	if (best_beam > 0.0) {
		if (best > 0.0) {
			vec3 cap = max(hue * best, hue_beam * best_beam) / max(best, best_beam);
			hue = min(mix(hue, hue_beam, best_beam / (best + best_beam)), cap);
		} else {
			hue = hue_beam;
		}
		best = max(best, best_beam);
	}

	// The sky is shown as it is -- dusk is half dark -- out to half a tile inside the survivor's
	// own sight radius (the sky's share of their range). By night their own little disc is lifted
	// toward eye_floor, in rings like any other light, and less as the sky brightens, so it never
	// shows at dusk. The disc ends half a tile inside their sight radius too: the sim sees a tile by
	// its centre, so every point that close lies in a seen tile, and the disc stays round rather
	// than cut into the plus-shaped set of tiles a small radius sees.
	float d_eye = distance(at, eye);
	float sky_r = max(0.5, ambient * range_m - 0.5);
	float sky = ambient * (1.0 - eye_fade * smoothstep(sky_r * 0.5, sky_r, d_eye));
	float disc_r = max(0.5, eye_reach - 0.5);
	float disc = eye_floor * (1.0 - ambient) * eye_fade * rings(1.0 - smoothstep(disc_r * 0.45, disc_r, d_eye), threshold);
	float shown = max(sky, max(disc, best));
	// How far a lightless pixel goes toward the night's colour: night_wash at dusk, all the way at
	// midnight, so outside the pools and the survivor's disc the night holds at the same floor the
	// unseen dark does.
	float wash = mix(1.0, night_wash, ambient);
	float dark_seen = (1.0 - shown) * wash;
	// Off the edge of sight: the sky's dark, and a little more by night, so what is only remembered
	// sits back from what is seen. By day nothing: the remembered map draws its own dimming.
	float dark_sky = (1.0 - ambient) * wash;
	float edge_dark = mix(edge_dark_night, edge_dark_day, ambient);
	float dark_unseen = dark_sky + edge_dark * (1.0 - dark_sky);
	float dark = mix(dark_unseen, dark_seen, seen);
	// Beside the void, the known side's last half tile goes most of the way to full dark, which is
	// about where the void's own unlit background sits under the same night.
	dark = mix(max(dark_unseen, void_dark), dark, known);

	// Rounded to `levels` steps where the picture is flat; dithered between two steps only where
	// seen gives way to unseen or the known map to the void. The rings carry their own dither.
	float edge = max(step(0.001, seen) * step(seen, 0.999), step(0.001, known) * step(known, 0.999));
	dark = mix(floor(dark * levels + 0.5), floor(dark * levels + threshold), edge) / levels;
	dark = clamp(dark, 0.0, 1.0);

	// A pool takes its source's hue in proportion to how much it out-lights the sky.
	float pool = clamp((best - sky) / max(0.0001, 1.0 - sky), 0.0, 1.0) * seen;
	vec3 light = mix(vec3(1.0), hue, tint_strength * pool);
	// Full dark is the night's colour, and at midnight a fraction of it (night_floor), so the floor
	// outside every light is near black with only a little blue in it; from dusk on up it is the
	// night's colour itself, so dusk keeps its tone.
	vec3 floor_colour = night_colour.rgb * mix(night_floor, 1.0, smoothstep(0.04, 0.3, ambient));
	COLOR = vec4(mix(light, floor_colour, dark), 1.0);
}
