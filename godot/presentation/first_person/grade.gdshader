shader_type canvas_item;
render_mode blend_mul, unshaded;
// The grade's lens (docs/46, "Grade"): a light vignette and fine grain, as one full-screen quad multiplied
// over the 3D picture and under the HUD. It multiplies by one or less everywhere, so it can only darken:
// the night is never lifted by it. The tonemap and the saturation are the Environment's, in `sky_view.gd`.
//
// Renderer: Compatibility (GLES3, WebGL2). No screen read, no texture: one hash per pixel.

uniform float vignette_strength = 0.2;
// The vignette starts at `vignette_inner` and is full at `vignette_outer`, in half-heights from the centre.
uniform float vignette_inner = 0.62;
uniform float vignette_outer = 1.18;
uniform float grain_strength = 0.035;
// Moves the grain; `sky_view.gd` feeds it the sim's tick, so a paused sim holds its grain still.
uniform vec2 grain_seed = vec2(0.0);

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec2 from_centre = (UV - 0.5) * 2.0;
	// An ellipse a little wider than the screen is tall, so the corners darken before the sides do.
	float radius = length(from_centre * vec2(0.82, 1.0));
	float vignette = 1.0 - vignette_strength * smoothstep(vignette_inner, vignette_outer, radius);
	float grain = 1.0 - grain_strength * hash12(floor(FRAGCOORD.xy) + grain_seed);
	COLOR = vec4(vec3(vignette * grain), 1.0);
}
