shader_type spatial;
// Falling water sheet with scrolling streaks.
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform float speed = 1.6;

void fragment() {
	vec2 uv = UV;
	float streak = jt_noise2(vec2(uv.x * 40.0, uv.y * 3.0 - TIME * speed * 3.0));
	float streak2 = jt_noise2(vec2(uv.x * 90.0, uv.y * 6.0 - TIME * speed * 5.0));
	float s = smoothstep(0.35, 0.9, streak * 0.6 + streak2 * 0.5);
	vec3 col = mix(vec3(0.45, 0.78, 0.9), vec3(0.95, 1.0, 1.0), s);
	float edge = smoothstep(0.0, 0.08, uv.x) * smoothstep(1.0, 0.92, uv.x);
	ALBEDO = col;
	EMISSION = col * 0.15;
	ALPHA = (0.55 + s * 0.4) * edge;
	ROUGHNESS = 0.2;
}
