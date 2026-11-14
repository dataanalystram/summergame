shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 hot_color : source_color = vec3(1.0, 0.33, 0.03);
uniform vec3 dark_color : source_color = vec3(0.05, 0.016, 0.01);
uniform float patch_scale = 0.3;
uniform float drift = 0.012;
uniform float emission_strength = 6.5;
uniform float vein_bias = 0.5;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wp.xz * patch_scale;
	float t = TIME * drift;
	float n = fbm(uv + vec2(t, t * 0.7) + fbm(uv * 0.6) * 0.9);
	float veins = smoothstep(vein_bias, vein_bias + 0.22, n);
	float glow = smoothstep(0.3, 0.8, n) * 0.55;
	vec3 col = mix(dark_color, hot_color, veins);
	ALBEDO = col;
	EMISSION = hot_color * (veins * emission_strength + glow);
}
