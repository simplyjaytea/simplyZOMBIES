shader_type canvas_item;
// The overcast day (presentation/day_grade.gd, slice B5 of the three-features plan). One
// screen-sized rect drawn over everything main draws and under the night's multiply, reading the
// picture under it and handing it back graded: its colour pulled toward its own grey, cooled, and
// veiled toward the overcast sky's grey, by `weight` -- 1 under a full day's sky, 0 at night. At 0
// the rect is not drawn at all, so the night frame is the picture the night already drew.
//
// It only ever moves a pixel along the three steps below, in this order; DayGrade.grade in
// day_grade.gd is the same arithmetic on a Color, which is what check_grade_look.gd judges the
// palette with. The HUD is a CanvasLayer over main's canvas item and is never in this picture.

render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
// How much of the grade this frame takes: DayGrade.weight_of(ambient).
uniform float weight = 0.0;
// The share of a pixel's colour, away from its own grey, the day keeps: `saturation` in the lit
// middle and top, `shadow_saturation` in the darks, eased between over luma 0 to `shadow_luma`.
uniform float saturation = 1.0;
uniform float shadow_saturation = 1.0;
uniform float shadow_luma = 0.25;
// The cool cast, a gain per channel.
uniform vec3 cool = vec3(1.0);
// The sky's grey, and how far toward it every pixel is veiled.
uniform vec3 haze = vec3(0.5);
uniform float haze_amount = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	float keep = mix(shadow_saturation, saturation, smoothstep(0.0, shadow_luma, luma));
	vec3 g = mix(vec3(luma), c, keep);
	g = clamp(g * cool, 0.0, 1.0);
	g = mix(g, haze, haze_amount);
	COLOR = vec4(mix(c, g, weight), 1.0);
}
