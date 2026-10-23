shader_type spatial;
// Procedural leaf shapes on quads (ferns, giant elephant-ear leaves, grass tufts).
render_mode cull_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec4 leaf_a : source_color = vec4(0.14, 0.42, 0.10, 1.0);
uniform vec4 leaf_b : source_color = vec4(0.42, 0.72, 0.20, 1.0);
uniform int shape = 0; // 0 = broad leaf, 1 = grass blades, 2 = fern
uniform float sway = 0.15;

varying float vhash;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vhash = jt_hash12(w.xz);
	float bend = UV.y < 0.5 ? (1.0 - UV.y * 2.0) : 0.0;
	bend = 1.0 - UV.y;
	VERTEX.x += sin(TIME * 1.7 + w.x * 0.3 + w.z * 0.2) * sway * bend;
	VERTEX.z += cos(TIME * 1.3 + w.z * 0.25) * sway * bend * 0.7;
}

void fragment() {
	vec2 uv = UV;
	float alpha = 1.0;
	float vein = 0.0;
	if (shape == 0) {
		// tear-drop leaf: wide at the middle, pointed tip at the top (uv.y = 0)
		float y = 1.0 - uv.y;
		float half_width = sin(clamp(y, 0.0, 1.0) * 3.14159) * 0.48 * (1.0 - y * 0.35);
		alpha = step(abs(uv.x - 0.5), half_width);
		vein = smoothstep(0.03, 0.0, abs(uv.x - 0.5)) + smoothstep(0.02, 0.0, abs(fract((y + abs(uv.x - 0.5)) * 6.0) - 0.5) - 0.47) * 0.4;
	} else if (shape == 1) {
		float blades = abs(fract(uv.x * 5.0) - 0.5) * 2.0;
		alpha = step(blades, (uv.y) * 0.9 + 0.08 * jt_hash12(vec2(floor(uv.x * 5.0), vhash * 10.0)));
	} else {
		float y = 1.0 - uv.y;
		float spine = abs(uv.x - 0.5);
		float leaflet = abs(fract(y * 9.0) - 0.5);
		float width = 0.45 * sin(clamp(y, 0.0, 1.0) * 3.14159);
		alpha = step(spine, width * (1.0 - leaflet * 1.2)) ;
		vein = smoothstep(0.03, 0.0, spine);
	}
	if (alpha < 0.5) {
		discard;
	}
	vec3 col = mix(leaf_a.rgb, leaf_b.rgb, clamp(vhash + uv.y * 0.3 - 0.15, 0.0, 1.0));
	col = mix(col, col * 1.35 + vec3(0.05, 0.08, 0.0), vein * 0.6);
	col *= 0.75 + 0.35 * (1.0 - uv.y);
	ALBEDO = col;
	ROUGHNESS = 0.7;
	BACKLIGHT = col * 0.7;
}
