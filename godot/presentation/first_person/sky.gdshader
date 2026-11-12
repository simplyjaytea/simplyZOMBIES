shader_type sky;
// The drawn sky of the first-person scene (docs/46, "Light and air"): a three-stop gradient from the horizon
// to the zenith, one slow cloud layer, a soft sun where the sim's clock puts it, sparse stars, and the far
// ridges of the valley with mist at their feet. Every number arrives as a uniform from `sky_view.gd`, which
// reads the sim; nothing here keeps time or draws a random number, so two frames of one tick are one picture.
//
// Renderer: Compatibility (GLES3, WebGL2), as the Environment's sky. Cost per sky pixel: two reads of one
// small noise, a handful of mixes and, under 23 degrees of elevation, three ridge crests of four sines each.

uniform vec3 zenith_colour : source_color = vec3(0.44, 0.56, 0.71);
uniform vec3 middle_colour : source_color = vec3(0.6, 0.69, 0.77);
uniform vec3 horizon_colour : source_color = vec3(0.76, 0.81, 0.83);
uniform vec3 below_colour : source_color = vec3(0.6, 0.64, 0.64);
// Where the middle stop sits, as the sine of the elevation.
uniform float middle_height = 0.3;

// Unit vector towards the sun, in world axes.
uniform vec3 sun_direction = vec3(0.0, 0.7, 0.7);
uniform vec3 sun_colour : source_color = vec3(1.0, 0.95, 0.86);
uniform float sun_disc = 1.0;
uniform float sun_glow = 0.25;
// A warm band along the horizon on the sun's side (dusk and dawn).
uniform float horizon_glow = 0.0;

// One tiling noise, read twice. `cloud_cover` is the share of the sky the layer covers, `cloud_amount` its
// opacity, `cloud_mottle` how far the layer's noise lightens and darkens the whole deck.
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 cloud_offset = vec2(0.0);
uniform vec2 cloud_offset_fine = vec2(0.0);
uniform float cloud_scale = 0.35;
uniform float cloud_cover = 0.3;
uniform float cloud_amount = 0.6;
uniform float cloud_mottle = 0.04;
uniform vec3 cloud_light : source_color = vec3(0.9, 0.92, 0.93);
uniform vec3 cloud_dark : source_color = vec3(0.6, 0.63, 0.65);

uniform float star_amount = 0.0;

// The far ridges: three silhouettes, nearest first, each paler than the one before it.
uniform float ridge_amount = 1.0;
uniform vec3 ridge_near : source_color = vec3(0.45, 0.52, 0.5);
uniform vec3 ridge_mid : source_color = vec3(0.58, 0.64, 0.63);
uniform vec3 ridge_far : source_color = vec3(0.68, 0.73, 0.73);
uniform float ridge_mist = 0.7;

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// The crest of one ridge at azimuth `a`, as an elevation in radians: a long swell, shoulders, and the
// small teeth of a tree line.
float crest(float a, float base, float swing, float phase) {
	return base
		+ swing * sin(a * 2.0 + phase)
		+ swing * 0.60 * sin(a * 5.0 + phase * 2.3)
		+ swing * 0.34 * sin(a * 11.0 + phase * 4.1)
		+ swing * 0.16 * sin(a * 23.0 + phase * 7.7)
		+ swing * 0.07 * sin(a * 53.0 + phase * 3.3);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	float lift = clamp(up, 0.0, 1.0);

	// The gradient.
	vec3 colour = mix(horizon_colour, middle_colour, smoothstep(0.0, middle_height, lift));
	colour = mix(colour, zenith_colour, smoothstep(middle_height, 1.0, lift));

	// The sun's side of the horizon, and the sun's own glow.
	float toward = dot(dir, sun_direction);
	vec2 flat_dir = normalize(dir.xz + vec2(1e-5));
	vec2 flat_sun = normalize(sun_direction.xz + vec2(1e-5));
	float side = max(dot(flat_dir, flat_sun), 0.0);
	float band = (1.0 - smoothstep(0.0, 0.45, lift)) * side * side * side;
	colour = mix(colour, sun_colour, clamp(horizon_glow * band, 0.0, 1.0));
	float glow = pow(max(toward, 0.0), 6.0) * 0.5 + pow(max(toward, 0.0), 48.0);
	colour += sun_colour * sun_glow * glow;

	// The cloud layer, on a flattened dome so it gathers towards the horizon.
	vec2 uv = dir.xz / (lift + 0.22) * cloud_scale;
	float n = texture(cloud_noise, uv + cloud_offset).r * 0.65 + texture(cloud_noise, uv * 2.63 + cloud_offset_fine).r * 0.35;
	float near_horizon = smoothstep(0.0, 0.2, lift);
	colour *= 1.0 + cloud_mottle * (n - 0.5) * 2.0 * near_horizon;
	float density = smoothstep(1.0 - cloud_cover - 0.14, 1.0 - cloud_cover + 0.14, n) * cloud_amount * near_horizon;
	vec3 cloud = mix(cloud_light, cloud_dark, smoothstep(0.45, 0.9, n));
	cloud += sun_colour * sun_glow * glow * 0.6;
	colour = mix(colour, cloud, density);

	// The disc, behind the cloud.
	float disc = smoothstep(0.99985, 0.99993, toward);
	colour += sun_colour * sun_disc * disc * (1.0 - density) * 2.0;

	// Sparse stars: one in a cell now and then, a pixel or two wide, lost towards the horizon and behind cloud.
	if (star_amount > 0.0 && up > 0.02) {
		vec2 grid = dir.xz / (up + 0.4) * 90.0;
		vec2 cell = floor(grid);
		float pick = hash21(cell);
		if (pick > 0.93) {
			vec2 centre = vec2(hash21(cell + 17.0), hash21(cell + 43.0)) * 0.7 + 0.15;
			float spot = 1.0 - smoothstep(0.04, 0.13, length(fract(grid) - centre));
			float bright = 0.35 + 0.65 * hash21(cell + 71.0);
			colour += vec3(0.82, 0.88, 1.0) * spot * bright * star_amount * smoothstep(0.02, 0.3, up) * (1.0 - density);
		}
	}

	// The far ridges, drawn back to front, each fading to mist at its foot.
	if (ridge_amount > 0.0 && up < 0.4) {
		float elevation = asin(clamp(up, -1.0, 1.0));
		float azimuth = atan(dir.x, dir.z);
		float edge = 0.0016;
		float far_top = crest(azimuth, 0.128, 0.020, 0.4);
		float mid_top = crest(azimuth, 0.088, 0.017, 2.1);
		float near_top = crest(azimuth, 0.050, 0.014, 4.4);
		float far_in = (1.0 - smoothstep(far_top - edge, far_top + edge, elevation)) * ridge_amount;
		vec3 far_colour = mix(ridge_far, horizon_colour, ridge_mist * (1.0 - smoothstep(mid_top - 0.01, far_top, elevation)));
		colour = mix(colour, far_colour, far_in);
		float mid_in = (1.0 - smoothstep(mid_top - edge, mid_top + edge, elevation)) * ridge_amount;
		vec3 mid_colour = mix(ridge_mid, horizon_colour, ridge_mist * (1.0 - smoothstep(near_top - 0.01, mid_top, elevation)));
		colour = mix(colour, mid_colour, mid_in);
		float near_in = (1.0 - smoothstep(near_top - edge, near_top + edge, elevation)) * ridge_amount;
		vec3 near_colour = mix(ridge_near, horizon_colour, ridge_mist * (1.0 - smoothstep(-0.01, near_top, elevation)));
		colour = mix(colour, near_colour, near_in);
	}

	// Under the horizon there is only the valley floor's haze.
	colour = mix(colour, below_colour, smoothstep(0.0, -0.03, up));

	COLOR = colour;
}
