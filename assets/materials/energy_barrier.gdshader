shader_type spatial;
// Hex-lattice energy barrier with scanlines, fresnel rim, hit ripples and dissolve.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.25, 0.9, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float hit_strength = 0.0;
uniform vec2 hit_uv = vec2(0.5, 0.5);
uniform float dissolve = 0.0;
uniform vec2 aspect = vec2(6.0, 3.2);

float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.732))), p.x);
}

float hex_grid(vec2 uv) {
	vec2 r = vec2(1.0, 1.732);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	return 0.5 - hex_dist(g);
}

void fragment() {
	vec2 uv = UV * aspect * 2.4;
	float h = hex_grid(uv);
	float lines = smoothstep(0.06, 0.0, h);
	float scan = 0.5 + 0.5 * sin(UV.y * 70.0 - TIME * 5.0);
	float edge_d = min(min(UV.x, 1.0 - UV.x) * aspect.x, min(UV.y, 1.0 - UV.y) * aspect.y);
	float edge = smoothstep(0.18, 0.0, edge_d);
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float d = distance(UV * aspect, hit_uv * aspect);
	float ripple = hit_strength * smoothstep(0.35, 0.0, abs(d - (1.0 - hit_strength) * 2.2));
	float base_glow = 0.06 + 0.04 * sin(TIME * 3.0 + UV.x * 6.0);
	float a = base_glow + lines * 0.3 + edge * 0.9 + fres * 0.2 + scan * 0.04 + ripple * 1.4;
	float n = fract(sin(dot(floor(uv * 2.0), vec2(12.9898, 78.233))) * 43758.5453);
	if (n < dissolve) {
		a *= 0.0;
	}
	ALBEDO = color.rgb * a * intensity;
}
