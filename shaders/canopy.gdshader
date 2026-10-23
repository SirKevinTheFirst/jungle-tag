shader_type spatial;
// Leafy blobs for tree canopies and bushes. Sways in the wind.
render_mode cull_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec4 leaf_a : source_color = vec4(0.16, 0.45, 0.12, 1.0);
uniform vec4 leaf_b : source_color = vec4(0.38, 0.66, 0.18, 1.0);
uniform float sway = 0.25;

varying vec3 wpos;
varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 1.3 + w.x * 0.12 + w.z * 0.09) * sway;
	VERTEX.x += s * (0.5 + 0.5 * NORMAL.y);
	VERTEX.z += cos(TIME * 1.1 + w.z * 0.1) * sway * 0.6;
	// lumpy silhouette
	VERTEX += NORMAL * (jt_noise3(VERTEX * 2.5 + w * 0.05) - 0.5) * 0.35;
	wpos = w;
}

void fragment() {
	vec2 cell = jt_cell3(wpos * 1.6);
	float n = jt_fbm3(wpos * 0.35);
	vec3 col = mix(leaf_a.rgb, leaf_b.rgb, smoothstep(0.3, 0.7, n));
	col *= 0.75 + 0.45 * smoothstep(0.0, 0.6, cell.x) * (0.6 + 0.4 * cell.y);
	ALBEDO = col * tint;
	ROUGHNESS = 0.8;
	BACKLIGHT = col * 0.6;
}
