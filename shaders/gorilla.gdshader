shader_type spatial;
// Cartoon gorilla fur with an animated jungle camouflage layer.
#include "res://shaders/noise.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.42, 0.29, 0.21, 1.0);
uniform float camo = 0.0;        // 0 = normal, 1 = fully camouflaged
uniform float visibility = 1.0;  // screen-door opacity
uniform float flash = 0.0;       // white flash when tagged
uniform float tint_strength = 1.0;        // 1 for fur, lower for skin parts
uniform vec4 part_color : source_color = vec4(1.0);
uniform float fur_noise = 1.0;

varying vec3 local_pos;
varying vec3 world_normal;

void vertex() {
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 camo_pattern(vec3 p) {
	vec3 dark_green = vec3(0.10, 0.28, 0.08);
	vec3 leaf_green = vec3(0.28, 0.55, 0.16);
	vec3 olive = vec3(0.42, 0.45, 0.18);
	vec3 brown = vec3(0.30, 0.20, 0.10);
	vec2 cell = jt_cell3(p * 3.2);
	float blotch = jt_fbm3(p * 2.2);
	vec3 col = mix(dark_green, leaf_green, smoothstep(0.35, 0.6, blotch));
	col = mix(col, brown, smoothstep(0.62, 0.7, jt_fbm3(p * 1.7 + 11.0)));
	// leaf-shaped cells with a lighter vein
	float leaf = 1.0 - smoothstep(0.25, 0.45, cell.x);
	col = mix(col, mix(leaf_green, olive, cell.y), leaf * 0.65);
	col *= 0.85 + 0.3 * cell.y;
	return col;
}

void fragment() {
	vec3 base = mix(part_color.rgb, base_color.rgb * part_color.rgb, tint_strength);
	float n = jt_noise3(local_pos * 38.0);
	base *= mix(1.0, 0.85 + 0.3 * n, fur_noise);
	// camouflage spreads over the body like growing leaves
	float spread = jt_fbm3(local_pos * 4.0 + 3.0);
	float t = camo * 1.25 - 0.1;
	float mask = smoothstep(spread - 0.06, spread + 0.06, t);
	float edge = smoothstep(0.08, 0.0, abs(spread - t)) * step(0.01, camo) * step(camo, 0.99);
	vec3 col = mix(base, camo_pattern(local_pos), mask);
	col += vec3(0.4, 1.0, 0.3) * edge * 0.8;
	col = mix(col, vec3(1.0), flash);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// cartoon rim light
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = col * rim * 0.25 * (1.0 - mask * 0.7) + vec3(0.4, 1.0, 0.3) * edge * 0.6;
	if (visibility < 0.999 && visibility < jt_bayer4(FRAGCOORD.xy)) {
		discard;
	}
}
