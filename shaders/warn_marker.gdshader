shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float intensity = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.36, 0.07);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.055, 0.0, abs(r - 0.74));
	float inner = smoothstep(0.8, 0.1, r) * 0.09;
	ALBEDO = tint;
	ALPHA = (ring * 0.75 + inner) * intensity;
}
