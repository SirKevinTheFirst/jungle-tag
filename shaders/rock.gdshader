shader_type spatial;
// Triplanar stylised rock with moss on upward faces.
#include "res://shaders/noise.gdshaderinc"

uniform vec4 rock_color : source_color = vec4(0.45, 0.42, 0.38, 1.0);
uniform vec4 moss_color : source_color = vec4(0.22, 0.42, 0.12, 1.0);
uniform float moss_amount = 0.55;

varying vec3 wpos;
varying vec3 tint;
varying vec3 wnorm;

void vertex() {
	tint = COLOR.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 bw = abs(wnorm);
	bw /= (bw.x + bw.y + bw.z);
	float nx = jt_fbm2(wpos.zy * 0.6);
	float ny = jt_fbm2(wpos.xz * 0.6);
	float nz = jt_fbm2(wpos.xy * 0.6);
	float n = nx * bw.x + ny * bw.y + nz * bw.z;
	float strata = 0.5 + 0.5 * sin(wpos.y * 2.2 + n * 6.0);
	vec3 col = rock_color.rgb * (0.7 + 0.45 * n) * (0.9 + 0.12 * strata);
	float moss = smoothstep(0.55, 0.85, wnorm.y + n * 0.4) * moss_amount;
	col = mix(col, moss_color.rgb * (0.8 + 0.4 * n), moss);
	ALBEDO = col * tint;
	ROUGHNESS = 0.9;
}
