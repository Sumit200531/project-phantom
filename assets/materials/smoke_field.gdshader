shader_type spatial;
// Billowing obscuring field. Opaque at the core, softer at the silhouette.
render_mode cull_disabled, depth_draw_never, diffuse_lambert_wrap, specular_disabled;

uniform vec4 color : source_color = vec4(0.8, 0.8, 0.86, 1.0);
uniform float density = 0.97;
uniform float fade = 1.0;
uniform float seed = 0.0;

void vertex() {
	float t = TIME * 0.6 + seed;
	float n = sin(VERTEX.x * 3.1 + t) * 0.045 + sin(VERTEX.y * 4.3 + t * 1.3) * 0.04 + sin(VERTEX.z * 3.7 - t * 0.8) * 0.045;
	VERTEX += NORMAL * n;
}

void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = smoothstep(0.0, 0.5, f);
	float swirl = 0.5 + 0.5 * sin(UV.x * 18.0 + UV.y * 9.0 + TIME * 0.4 + seed);
	ALBEDO = color.rgb * (0.92 + 0.08 * swirl);
	ALPHA = density * mix(0.4, 1.0, edge) * fade;
	ROUGHNESS = 1.0;
}
