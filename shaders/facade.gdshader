shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.34, 0.315, 0.29);
uniform vec3 trim_color : source_color = vec3(0.2, 0.185, 0.175);
uniform vec3 window_color : source_color = vec3(0.035, 0.05, 0.065);
uniform vec3 roof_color : source_color = vec3(0.115, 0.11, 0.105);
uniform vec3 lit_color : source_color = vec3(1.0, 0.66, 0.33);
uniform float bay_w = 3.4;
uniform float floor_h = 3.8;
uniform float lit_amount = 0.13;
uniform float grime = 0.4;

instance uniform vec3 tint;
instance uniform float seed;

varying vec3 wpos;
varying vec3 wnorm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 an = abs(normalize(wnorm));
	if (an.y > 0.75) {
		ALBEDO = roof_color;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		return;
	}
	vec2 uv = (an.x > an.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
	vec2 g = uv / vec2(bay_w, floor_h);
	vec2 cell = fract(g);
	vec2 id = floor(g);
	float wx = step(0.16, cell.x) * step(cell.x, 0.84);
	float wy = step(0.36, cell.y) * step(cell.y, 0.86);
	float win = wx * wy;
	float h = hash21(id + vec2(seed, seed * 1.7));
	float lit = step(1.0 - lit_amount, h) * win;
	float band = smoothstep(0.1, 0.0, cell.y);
	vec3 col = base_color * mix(vec3(1.0), tint, 0.7);
	col = mix(col, trim_color, band);
	float grunge = 1.0 - grime * hash21(id * 0.37 + vec2(seed * 2.1, 3.0));
	col *= mix(1.0, grunge, 0.65);
	ALBEDO = mix(col, window_color, win);
	EMISSION = lit_color * lit * 1.7;
	ROUGHNESS = mix(0.95, 0.24, win);
	METALLIC = win * 0.15;
}
