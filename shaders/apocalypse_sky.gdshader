shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.055, 0.032, 0.04);
uniform vec3 horizon_color : source_color = vec3(0.95, 0.42, 0.16);
uniform vec3 ground_color : source_color = vec3(0.07, 0.04, 0.035);
uniform vec3 sun_color : source_color = vec3(1.0, 0.72, 0.38);
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.62;
uniform float cloud_scale = 2.0;

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
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dir.y;
	float t = smoothstep(-0.02, 0.6, y);
	vec3 col = mix(horizon_color, zenith_color, pow(t, 0.72));
	col = mix(ground_color, col, smoothstep(-0.16, 0.0, y));

	float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
	col += sun_color * pow(sd, 1400.0) * 7.0;
	col += sun_color * pow(sd, 10.0) * 0.2;

	if (y > 0.0) {
		vec2 uv = dir.xz / (y + 0.16);
		uv = uv * cloud_scale;
		float warp = fbm(uv * 0.55);
		float c = fbm(uv + warp * 0.9);
		float cover = smoothstep(1.02 - cloud_amount, 1.22 - cloud_amount, c);
		vec3 cloud_col = mix(vec3(0.17, 0.09, 0.07), vec3(0.045, 0.026, 0.026), clamp(c * 1.3, 0.0, 1.0));
		float rim = smoothstep(0.35, 0.0, y) * smoothstep(0.4, 0.85, c);
		cloud_col += sun_color * rim * 0.55;
		col = mix(col, cloud_col, cover * 0.9);
	}
	COLOR = col;
}
