// Shared hash / value-noise helpers for Jungle Tag shaders.
float jt_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float jt_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float jt_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = jt_hash13(i);
	float n100 = jt_hash13(i + vec3(1, 0, 0));
	float n010 = jt_hash13(i + vec3(0, 1, 0));
	float n110 = jt_hash13(i + vec3(1, 1, 0));
	float n001 = jt_hash13(i + vec3(0, 0, 1));
	float n101 = jt_hash13(i + vec3(1, 0, 1));
	float n011 = jt_hash13(i + vec3(0, 1, 1));
	float n111 = jt_hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float jt_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(jt_hash12(i), jt_hash12(i + vec2(1, 0)), f.x),
		mix(jt_hash12(i + vec2(0, 1)), jt_hash12(i + vec2(1, 1)), f.x), f.y);
}

float jt_fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * jt_noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

float jt_fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * jt_noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Cellular (Voronoi) distance: x = nearest distance, y = cell id hash.
vec2 jt_cell3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 c = i + o;
		vec3 r = o + vec3(jt_hash13(c), jt_hash13(c + 17.0), jt_hash13(c + 41.0)) - f;
		float d = dot(r, r);
		if (d < best) { best = d; id = jt_hash13(c + 5.0); }
	}
	return vec2(sqrt(best), id);
}

// Ordered 4x4 dither threshold for screen-door transparency.
float jt_bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int idx = p.x + p.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}
