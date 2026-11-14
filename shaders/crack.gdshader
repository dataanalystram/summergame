shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float intensity = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.48, 0.12);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 uv = UV;
	float wobble = sin(uv.y * 13.0) * 0.13 + sin(uv.y * 41.0) * 0.035;
	float line_a = abs(uv.x - (0.36 + wobble));
	float wobble_b = sin(uv.x * 11.0 + 2.0) * 0.12 + sin(uv.x * 29.0) * 0.03;
	float line_b = abs(uv.y - (0.62 + wobble_b));
	float m = min(line_a, line_b);
	float core = smoothstep(0.07, 0.0, m);
	float halo = smoothstep(0.22, 0.0, m) * 0.5;
	float flicker = 0.75 + 0.25 * sin(TIME * 9.0 + uv.x * 20.0 + uv.y * 17.0);
	ALBEDO = tint;
	ALPHA = (core + halo) * intensity * flicker;
}
