class_name MenuBackground
extends ColorRect
## Animated jungle backdrop for menus (layered leaf silhouettes and light rays).


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float leaf_layer(vec2 uv, float scale, float t, float seed){
	uv *= scale;
	uv.x += t * 0.05 * (1.0 + seed);
	uv.y += sin(uv.x * 0.7 + t * 0.6 + seed) * 0.15;
	vec2 id = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float r = h(id + seed);
	float a = r * 6.2831 + sin(t + r * 6.0) * 0.3;
	mat2 m = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	vec2 p = m * (f - (vec2(h(id + 3.1), h(id + 7.7)) - 0.5) * 0.4);
	float leaf = length(p * vec2(2.2, 1.0)) - 0.35;
	return step(leaf, 0.0) * step(0.35, r);
}
void fragment(){
	vec2 uv = UV;
	float t = TIME;
	vec3 top = vec3(0.32, 0.62, 0.42);
	vec3 bottom = vec3(0.04, 0.16, 0.07);
	vec3 col = mix(top, bottom, uv.y);
	// god rays
	float ray = sin(uv.x * 18.0 - uv.y * 6.0 + sin(t * 0.3) * 2.0) * 0.5 + 0.5;
	col += vec3(0.9, 1.0, 0.6) * pow(ray, 8.0) * (1.0 - uv.y) * 0.12;
	vec2 auv = uv * vec2(1.78, 1.0);
	float l1 = leaf_layer(auv, 4.0, t, 1.0);
	float l2 = leaf_layer(auv, 7.0, t, 2.0);
	float l3 = leaf_layer(auv, 12.0, t, 3.0);
	col = mix(col, vec3(0.05, 0.22, 0.07), l3 * 0.6);
	col = mix(col, vec3(0.08, 0.3, 0.1), l2 * 0.75);
	col = mix(col, vec3(0.03, 0.14, 0.05), l1 * 0.9 * smoothstep(0.2, 1.0, abs(uv.x - 0.5) * 2.0 + uv.y * 0.3));
	float vig = smoothstep(1.2, 0.3, length((uv - 0.5) * vec2(1.4, 1.0)));
	COLOR = vec4(col * (0.55 + 0.45 * vig), 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	material = m
