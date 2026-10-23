shader_type spatial;
// A vine tube bent along two segments (anchor -> p1 -> p2) supplied per instance.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 vine_p1 = vec3(0.0, -5.0, 0.0);
uniform vec3 vine_p2 = vec3(0.0, -10.0, 0.0);
uniform float vine_split = 0.5;
uniform vec4 vine_color : source_color = vec4(0.25, 0.42, 0.12, 1.0);

varying float along;

void vertex() {
	// mesh runs from y = 0 (anchor) to y = -1 (tip)
	float t = clamp(-VERTEX.y, 0.0, 1.0);
	vec3 p;
	vec3 dir;
	if (t <= vine_split) {
		float k = t / max(vine_split, 0.001);
		p = mix(vec3(0.0), vine_p1, k);
		dir = vine_p1;
	} else {
		float k = (t - vine_split) / max(1.0 - vine_split, 0.001);
		p = mix(vine_p1, vine_p2, k);
		dir = vine_p2 - vine_p1;
	}
	vec3 radial = vec3(VERTEX.x, 0.0, VERTEX.z);
	// small leaf bumps along the vine
	float bump = step(0.8, jt_noise2(vec2(t * 40.0, atan(VERTEX.x, VERTEX.z) * 2.0))) * 2.2;
	VERTEX = p + radial * (1.0 + bump);
	along = t;
}

void fragment() {
	float n = jt_noise2(vec2(along * 60.0, UV.x * 8.0));
	vec3 col = vine_color.rgb * (0.7 + 0.5 * n);
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
