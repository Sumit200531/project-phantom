shader_type spatial;
// Wind-swayed grass cards. Original shader for Project Phantom.
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float sway = 0.09;
uniform float card_height = 0.55;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / card_height, 0.0, 1.0);
	h *= h;
	float w = sin(TIME * 1.6 + wp.x * 0.45 + wp.z * 0.3) + 0.45 * sin(TIME * 3.3 + wp.z * 1.1);
	VERTEX.x += w * sway * h;
	VERTEX.z += w * sway * 0.55 * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * tint.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.35, 0.1);
}
