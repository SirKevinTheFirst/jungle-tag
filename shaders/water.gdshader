shader_type spatial;
// Stylised river water with flowing ripples.
render_mode blend_mix, depth_draw_opaque, cull_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec4 shallow : source_color = vec4(0.25, 0.70, 0.70, 1.0);
uniform vec4 deep : source_color = vec4(0.06, 0.32, 0.38, 1.0);
uniform vec2 flow = vec2(0.0, 0.6);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.5 + wpos.x * 0.4 + wpos.z * 0.3) * 0.04;
}

void fragment() {
	vec2 p = wpos.xz * 0.35 + flow * TIME;
	float n = jt_fbm2(p);
	float n2 = jt_fbm2(p * 2.3 - flow * TIME * 0.7);
	vec3 nrm = normalize(vec3((n - 0.5) * 0.6, 1.0, (n2 - 0.5) * 0.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep.rgb, shallow.rgb, n * 0.7 + 0.15);
	float foam = smoothstep(0.72, 0.78, n2) * 0.6;
	ALBEDO = mix(col, vec3(0.9, 0.97, 1.0), foam);
	ALPHA = clamp(0.72 + fres * 0.25 + foam, 0.0, 1.0);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
