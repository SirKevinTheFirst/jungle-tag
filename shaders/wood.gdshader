shader_type spatial;
// Bark (vertical ridges) or planks depending on 'planks'.
#include "res://shaders/noise.gdshaderinc"

uniform vec4 wood_color : source_color = vec4(0.40, 0.27, 0.16, 1.0);
uniform float planks = 0.0;
uniform float moss_amount = 0.25;

varying vec3 lpos;
varying vec3 wpos;
varying vec3 tint;
varying vec3 wnorm;

void vertex() {
	tint = COLOR.rgb;
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col;
	if (planks > 0.5) {
		float board = floor(wpos.x * 2.2 + wpos.z * 2.2);
		float grain = jt_noise2(vec2(board * 7.0, (wpos.x + wpos.z) * 0.6) + wpos.y);
		col = wood_color.rgb * (0.75 + 0.35 * jt_hash12(vec2(board, 3.0))) * (0.85 + 0.2 * grain);
		float seam = smoothstep(0.04, 0.0, abs(fract(wpos.x * 2.2 + wpos.z * 2.2) - 0.5) - 0.46);
		col *= 1.0 - seam * 0.5;
	} else {
		float ang = atan(lpos.x, lpos.z);
		float ridge = jt_noise2(vec2(ang * 6.0, wpos.y * 0.35 + lpos.y * 0.2));
		float fine = jt_noise3(wpos * 3.0);
		col = wood_color.rgb * (0.6 + 0.55 * ridge) * (0.9 + 0.2 * fine);
		float moss = smoothstep(0.55, 0.8, jt_fbm3(wpos * 0.5)) * moss_amount;
		col = mix(col, vec3(0.2, 0.4, 0.12), moss);
	}
	ALBEDO = col * tint;
	ROUGHNESS = 0.9;
}
