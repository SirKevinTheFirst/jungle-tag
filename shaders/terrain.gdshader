shader_type spatial;
// Jungle floor: vertex colour picks grass / mud / sand, noise adds detail.
#include "res://shaders/noise.gdshaderinc"

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n1 = jt_fbm2(wpos.xz * 0.08);
	float n2 = jt_noise2(wpos.xz * 1.3);
	vec3 grass_a = vec3(0.20, 0.45, 0.12);
	vec3 grass_b = vec3(0.33, 0.58, 0.16);
	vec3 mud = vec3(0.32, 0.22, 0.13);
	vec3 sand = vec3(0.70, 0.62, 0.42);
	vec3 rock = vec3(0.40, 0.38, 0.34);
	vec3 grass = mix(grass_a, grass_b, n1);
	grass *= 0.85 + 0.25 * n2;
	vec3 col = grass * COLOR.r + mud * COLOR.g + sand * COLOR.b;
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	col = mix(col, rock * (0.8 + 0.3 * n2), smoothstep(0.35, 0.6, slope));
	// little leaf litter speckles
	float litter = step(0.86, jt_noise2(wpos.xz * 4.0)) * COLOR.r;
	col = mix(col, vec3(0.45, 0.32, 0.12), litter * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
